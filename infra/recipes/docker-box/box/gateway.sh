#!/usr/bin/env bash
# Usage (on the box, via the xenia-gateway SSM document): gateway.sh update|restart|status|logs|app-down|current
#   update    fetch KIT_REF into /srv/kit, then (re)start the gateway compose project if it exists
#   restart   re-read secrets from SSM and (re)start the gateway (gateway/start.sh)
#   status    networks, IMDS guard, compose projects, containers
#   logs      last 200 lines of the gateway project
#   app-down  stop the demo app (volumes kept); Friday evening teardown of the example
set -euo pipefail
source "$(dirname "$0")/lib.sh"
load_box_env
gw="$KIT_ON_BOX/infra/recipes/docker-box/gateway"

start_gateway() {
  if [[ -f "$gw/compose.yml" ]]; then
    "$gw/start.sh"
  else
    log "no gateway compose yet ($gw/compose.yml); nothing to start"
  fi
}

case "${1:-}" in
  update)
    cd "$KIT_ON_BOX"
    git fetch -q --depth 1 origin "$KIT_REF"
    git reset -q --hard FETCH_HEAD
    find "$KIT_ON_BOX/infra/recipes/docker-box" -name '*.sh' -exec chmod +x {} +
    log "kit at $(git rev-parse --short HEAD) ($KIT_REF)"
    start_gateway
    ;;
  restart)
    start_gateway
    ;;
  status)
    echo "networks: $(docker network ls --format '{{.Name}}' | grep -xE 'gateway|edge' | sort | tr '\n' ' ')"
    if iptables -C DOCKER-USER ! -i gw0 -d 169.254.169.254 -j DROP 2>/dev/null; then
      echo "imds guard: on"
    else
      echo "imds guard: MISSING (systemctl restart xenia-imds-guard)"
    fi
    echo "kit: $(git -C "$KIT_ON_BOX" rev-parse --short HEAD) ($KIT_REF)"
    route_msg="$(gateway_route_check gateway-caddy-1 gateway)" && route_rc=0 || route_rc=$?
    case "$route_rc" in
      0) echo "caddy default route: ok ($route_msg)" ;;
      1) echo "caddy default route: cannot check ($route_msg)" ;;
      2) echo "caddy default route: cannot check ($route_msg)" ;;
      3) echo "caddy default route: MISMATCH ($route_msg) — DNS-01/instance-role traffic is being dropped by the IMDS guard" ;;
    esac
    docker compose ls --all
    docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
    ;;
  logs)
    [[ -f "$gw/compose.yml" ]] || die "no gateway compose yet"
    cd "$gw" && docker compose logs --tail 200 --no-color
    ;;
  app-down)
    "$BOX_SCRIPTS/app-down.sh"
    ;;
  current)
    # Rollback bookkeeping written by deploy.sh (Task 9); scripts/rollback.sh reads it (Task 26).
    echo "previous: $(cat /srv/app/previous 2>/dev/null || echo none)"
    echo "current: $(cat /srv/app/current.json 2>/dev/null || echo '{}')"
    ;;
  *)
    die "usage: gateway.sh update|restart|status|logs|app-down|current"
    ;;
esac
