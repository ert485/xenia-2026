#!/usr/bin/env bash
# On the Docker box: render the gateway's runtime env files from SSM into /run/xenia (tmpfs, 0600) and
# (re)start the gateway compose project. Called by box/gateway.sh update|restart and at every boot.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../box/lib.sh"
load_box_env

master="$(ssm_get gateway/master-key 2>/dev/null)" \
  || die "missing /xenia/gateway/master-key; on the laptop: printf 'sk-%s' \"\$(openssl rand -hex 32)\" | scripts/put-secret.sh gateway/master-key"
pgpw="$(ssm_get gateway/postgres-password 2>/dev/null)" \
  || die "missing /xenia/gateway/postgres-password; on the laptop: openssl rand -hex 24 | scripts/put-secret.sh gateway/postgres-password"
api_base="$(ssm_get gpu/api-base 2>/dev/null || echo https://gpu-not-provisioned.invalid/v1)"
vllm_token="$(ssm_get gpu/vllm-token 2>/dev/null || echo unset)"
vllm_cert="$(ssm_get gpu/vllm-cert 2>/dev/null || true)"

umask 077
install -d -m 0700 /run/xenia
install -d -m 0755 /run/xenia/certs
printf 'POSTGRES_PASSWORD=%s\n' "$pgpw" > /run/xenia/postgres.env
{
  printf 'LITELLM_MASTER_KEY=%s\n' "$master"
  printf 'DATABASE_URL=postgresql://litellm:%s@postgres:5432/litellm\n' "$pgpw"
  printf 'VLLM_API_BASE=%s\n' "$api_base"
  printf 'VLLM_API_KEY=%s\n' "$vllm_token"
} > /run/xenia/litellm.env

# Pin the GPU box's self-signed certificate: system CAs (for Bedrock) plus that one certificate.
if [[ -n "$vllm_cert" ]]; then
  cat /etc/ssl/certs/ca-bundle.crt > /run/xenia/certs/bundle.pem
  printf '%s\n' "$vllm_cert" >> /run/xenia/certs/bundle.pem
  chmod 0644 /run/xenia/certs/bundle.pem
  printf 'SSL_CERT_FILE=/certs/bundle.pem\n' >> /run/xenia/litellm.env
  log "vLLM backend: configured (certificate pinned)"
else
  log "vLLM backend: not provisioned yet; requests fail over to Bedrock"
fi

log "docker engine: $(docker version --format '{{.Server.Version}}')"

cd "$here"
docker compose build --quiet caddy
docker compose up -d --remove-orphans
docker compose ps --format 'table {{.Name}}\t{{.Status}}'

# Caddy must default-route via the gateway network's gw0, or its DNS-01/instance-role traffic is
# dropped by the IMDS guard (Task 6 review carry). `gw_priority` needs Docker Engine >= 28 (see the
# comment in compose.yml); the box's AL2023 `docker` package is unpinned, so this is asserted, not
# assumed. A short retry loop covers the gap between `up -d` returning and the container's network
# namespace being fully set up.
gw_addr="$(docker network inspect gateway -f '{{(index .IPAM.Config 0).Gateway}}')"
caddy_route=""
for _ in $(seq 1 15); do
  caddy_route="$(docker exec gateway-caddy-1 ip route 2>/dev/null | head -1 || true)"
  [[ -n "$caddy_route" ]] && break
  sleep 1
done
[[ -n "$caddy_route" ]] || die "gateway-caddy-1 never came up to check its default route"
log "caddy default route: $caddy_route (gateway network gw0 address: $gw_addr)"
case "$caddy_route" in
  "default via $gw_addr "*) : ;;
  *) die "caddy's default route is not via the gateway network ($gw_addr); got '$caddy_route' — its DNS-01/instance-role traffic would be dropped by the IMDS guard. Check gw_priority/priority in compose.yml and the box's Docker Engine version." ;;
esac
