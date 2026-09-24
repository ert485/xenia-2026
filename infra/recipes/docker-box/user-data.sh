#!/usr/bin/env bash
# Docker box first boot (Amazon Linux 2023, arm64). Rendered by templatefile() in main.tf.
# shellcheck disable=SC2154
set -euxo pipefail

hostnamectl set-hostname xenia-docker-box

dnf install -y docker git jq iptables-nft postgresql16 python3-pyyaml
systemctl enable --now docker

# Compose v2 and buildx CLI plugins, checksums verified. Compose >= 2.24 is needed for !reset in the
# kit's overrides; compose build needs buildx >= 0.17.
plugins=/usr/local/lib/docker/cli-plugins
mkdir -p "$plugins"
cd /tmp
curl -fsSLO https://github.com/docker/compose/releases/download/v2.39.2/docker-compose-linux-aarch64
curl -fsSLO https://github.com/docker/compose/releases/download/v2.39.2/docker-compose-linux-aarch64.sha256
sha256sum -c docker-compose-linux-aarch64.sha256
install -m 0755 docker-compose-linux-aarch64 "$plugins/docker-compose"
curl -fsSLo buildx-v0.37.1.linux-arm64 https://github.com/docker/buildx/releases/download/v0.37.1/buildx-v0.37.1.linux-arm64
curl -fsSL https://github.com/docker/buildx/releases/download/v0.37.1/checksums.txt \
  | grep 'buildx-v0.37.1.linux-arm64$' | sha256sum -c
install -m 0755 buildx-v0.37.1.linux-arm64 "$plugins/docker-buildx"

# Container logs go to CloudWatch, one stream per container name (scripts/logs.sh reads them).
cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "awslogs",
  "log-opts": {
    "awslogs-region": "ca-central-1",
    "awslogs-group": "${log_group}",
    "tag": "{{.Name}}",
    "mode": "non-blocking",
    "max-buffer-size": "4m"
  }
}
EOF
systemctl restart docker
docker compose version
docker buildx version

docker network inspect gateway >/dev/null 2>&1 || docker network create --opt com.docker.network.bridge.name=gw0 gateway
docker network inspect edge >/dev/null 2>&1 || docker network create --opt com.docker.network.bridge.name=edge0 edge

# IMDS guard (deviation 1): only the gateway network may reach the instance metadata service.
cat > /usr/local/sbin/xenia-imds-guard.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
iptables -C DOCKER-USER ! -i gw0 -d 169.254.169.254 -j DROP 2>/dev/null \
  || iptables -I DOCKER-USER ! -i gw0 -d 169.254.169.254 -j DROP
EOF
chmod 0755 /usr/local/sbin/xenia-imds-guard.sh
cat > /etc/systemd/system/xenia-imds-guard.service <<'EOF'
[Unit]
Description=xenia: drop container traffic to instance metadata except from the gateway network
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/xenia-imds-guard.sh

[Install]
WantedBy=multi-user.target
EOF

mkdir -p /srv/app /srv/previews /run/xenia
chmod 0700 /run/xenia

if [ ! -d /srv/kit/.git ]; then
  git clone --depth 1 --branch "${kit_ref}" "https://github.com/${kit_repo}.git" /srv/kit
fi
find /srv/kit/infra/recipes/docker-box -name '*.sh' -exec chmod +x {} +

cat > /etc/xenia.env <<'EOF'
ZONE=${zone_name}
APP_PORT=${app_port}
BACKUP_BUCKET=${backup_bucket}
KIT_REPO=${kit_repo}
KIT_REF=${kit_ref}
EOF
chmod 0644 /etc/xenia.env

cat > /etc/systemd/system/xenia-backup.service <<'EOF'
[Unit]
Description=xenia: pg_dumpall every Postgres container to the backup bucket
After=docker.service

[Service]
Type=oneshot
EnvironmentFile=/etc/xenia.env
ExecStart=/srv/kit/infra/recipes/docker-box/box/backup.sh
EOF
cat > /etc/systemd/system/xenia-backup.timer <<'EOF'
[Unit]
Description=xenia: hourly Postgres backups

[Timer]
OnCalendar=hourly
RandomizedDelaySec=300
Persistent=true

[Install]
WantedBy=timers.target
EOF

# /run/xenia is tmpfs: after every boot (scripts/startup.sh), rewrite the runtime env files from SSM
# and bring the gateway up again.
cat > /etc/systemd/system/xenia-gateway.service <<'EOF'
[Unit]
Description=xenia: render gateway secrets from SSM and start the gateway compose project
After=docker.service network-online.target xenia-imds-guard.service
Wants=network-online.target
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/srv/kit/infra/recipes/docker-box/box/gateway.sh restart

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now xenia-imds-guard.service
systemctl enable --now xenia-backup.timer
systemctl enable xenia-gateway.service

# Task 7 adds gateway/compose.yml; before that this only updates the checkout.
/srv/kit/infra/recipes/docker-box/box/gateway.sh update || true
