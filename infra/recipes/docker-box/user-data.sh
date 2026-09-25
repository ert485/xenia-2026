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

# IMDS guard (deviation 1): only the backend network (bridge gw0) may reach the instance metadata
# service. Installed and started here, right after Docker and before anything that needs GitHub (the
# kit clone below), so a first boot that can't reach GitHub still leaves the DROP rule in place. It
# depends on nothing in the kit checkout; tests/user-data.bats locks this ordering. main.tf ignores
# user_data changes (ignore_changes = [ami, user_data]), so this only applies to boxes created later.
# Docker keeps an existing DOCKER-USER chain's contents across restarts, but the chain itself may
# not exist yet (a fresh dockerd hasn't created it), so the script always ensures the chain first.
cat > /usr/local/sbin/xenia-imds-guard.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
iptables -N DOCKER-USER 2>/dev/null || true
iptables -C DOCKER-USER ! -i gw0 -d 169.254.169.254 -j DROP 2>/dev/null \
  || iptables -I DOCKER-USER ! -i gw0 -d 169.254.169.254 -j DROP
EOF
chmod 0755 /usr/local/sbin/xenia-imds-guard.sh

# Runs BEFORE docker starts, on every boot: dockerd restarts containers with restart policies during
# its own startup, so without this, there is a window on every boot after the first where a container
# can reach 169.254.169.254 before the guard (below) has a chance to run. This unit installs the same
# idempotent rule pre-emptively so the chain is already in place the instant docker creates its bridges.
cat > /etc/systemd/system/xenia-imds-guard-pre.service <<'EOF'
[Unit]
Description=xenia: pre-install the metadata-service drop rule before docker starts
Before=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/xenia-imds-guard.sh

[Install]
WantedBy=docker.service
EOF

# Re-asserts the same rule after docker (re)starts, in case dockerd's own startup replaced or flushed
# the DOCKER-USER chain.
cat > /etc/systemd/system/xenia-imds-guard.service <<'EOF'
[Unit]
Description=xenia: drop container traffic to instance metadata except from the backend network (gw0)
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

systemctl daemon-reload
systemctl enable --now xenia-imds-guard-pre.service
systemctl enable --now xenia-imds-guard.service

mkdir -p /srv/app /srv/previews
# /run/xenia is tmpfs (wiped every boot): a tmpfiles.d rule recreates it with the right mode on every
# boot, including this one via the immediate --create below.
cat > /etc/tmpfiles.d/xenia.conf <<'EOF'
d /run/xenia 0700 root root -
EOF
systemd-tmpfiles --create /etc/tmpfiles.d/xenia.conf

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
systemctl enable --now xenia-backup.timer
systemctl enable xenia-gateway.service

# The kit checkout is cloned here (rather than after network setup) so this script and every later
# boot/update can share ensure_networks() from box/lib.sh instead of duplicating network creation.
# It runs last, after the metadata guard, /etc/xenia.env and every unit are in place, so a failed clone
# stops first boot with only the checkout and networks missing. scripts/box.sh xenia-gateway
# Action=update cannot repair that on its own: the SSM document runs gateway.sh from this checkout.
# Hence the retries, and a recovery hint that re-runs this (idempotent) script instead.
if [ ! -d /srv/kit/.git ]; then
  cloned=""
  for attempt in 1 2 3 4 5; do
    if git clone --depth 1 --branch "${kit_ref}" "https://github.com/${kit_repo}.git" /srv/kit; then
      cloned=yes
      break
    fi
    rm -rf /srv/kit
    echo "kit clone attempt $attempt failed" >&2
    [ "$attempt" = 5 ] || sleep 30
  done
  if [ -z "$cloned" ]; then
    echo "ERROR: kit clone failed; networks and gateway not set up — once GitHub is reachable, re-run first boot on the box (sudo bash /var/lib/cloud/instance/user-data.txt), then scripts/box.sh xenia-gateway Action=update" >&2
    exit 1
  fi
fi
find /srv/kit/infra/recipes/docker-box -name '*.sh' -exec chmod +x {} +

# shellcheck source=infra/recipes/docker-box/box/lib.sh
source /srv/kit/infra/recipes/docker-box/box/lib.sh
ensure_networks

# Task 7 adds gateway/compose.yml; before that this only updates the checkout. A failure here must
# not abort first boot (the rest of provisioning, and later scripts/box.sh update calls, still work),
# but it must not be silent either.
if ! /srv/kit/infra/recipes/docker-box/box/gateway.sh update; then
  echo "WARNING: initial gateway.sh update failed; first boot continues without the gateway started (retry with: scripts/box.sh xenia-gateway Action=update)" >&2
fi
