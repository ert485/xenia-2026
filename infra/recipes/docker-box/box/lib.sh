#!/usr/bin/env bash
# shellcheck shell=bash
# Shared helpers for scripts that run ON the Docker box (from the kit checkout at /srv/kit).
# Source it; don't execute it.
set -euo pipefail

KIT_ON_BOX="${KIT_ON_BOX:-/srv/kit}"
BOX_SCRIPTS="${BOX_SCRIPTS:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
export KIT_ON_BOX BOX_SCRIPTS
# SSM Run Command starts scripts with a minimal environment; git and docker want HOME.
export HOME="${HOME:-/root}"

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
die() { log "error: $*"; exit 1; }

# load_box_env: /etc/xenia.env (written by user-data) holds ZONE, APP_PORT, BACKUP_BUCKET, KIT_REPO, KIT_REF.
load_box_env() {
  local f="${XENIA_ENV_FILE:-/etc/xenia.env}"
  [[ -f "$f" ]] || die "missing $f (written by the Docker box user-data)"
  set -a
  # shellcheck disable=SC1090
  source "$f"
  set +a
}

# ssm_get <name-under-/xenia/>: prints a parameter value (decrypted); non-zero if it does not exist.
ssm_get() {
  aws ssm get-parameter --region ca-central-1 --name "/xenia/$1" --with-decryption \
    --query Parameter.Value --output text
}

# list_previews: running or stopped preview projects (pr-<n>), one per line, oldest first, ordered by
# the creation time of the project's pr-<n>-web container.
list_previews() {
  local names n created
  names="$(docker compose ls --all --format json | jq -r '.[].Name' | grep -E '^pr-[0-9]+$' || true)"
  [[ -n "$names" ]] || return 0
  while IFS= read -r n; do
    created="$(docker inspect -f '{{.Created}}' "$n-web" 2>/dev/null || echo 0000)"
    printf '%s %s\n' "$created" "$n"
  done <<< "$names" | sort | cut -d' ' -f2
}

# evict_oldest_previews <max> <keep>: remove the oldest previews until at most <max> remain.
# Never removes <keep> (the preview being deployed right now).
evict_oldest_previews() {
  local max="$1" keep="$2" all count p
  all="$(list_previews)"
  [[ -n "$all" ]] || return 0
  count="$(grep -c . <<< "$all")"
  while IFS= read -r p; do
    (( count <= max )) && break
    [[ "$p" == "$keep" ]] && continue
    log "evicting preview $p (cap $max)"
    "$BOX_SCRIPTS/preview-down.sh" "${p#pr-}"
    count=$((count - 1))
  done <<< "$all"
}

# preview_cap_for <project>: how many OTHER previews may stay before <project> is (re)deployed.
# A resync of a running preview keeps three in total; a new one needs room, so two may stay.
preview_cap_for() {
  local all
  all="$(list_previews)"
  if grep -qx -- "$1" <<< "$all"; then echo 3; else echo 2; fi
}

# ensure_networks: create the box's Docker networks if missing. Idempotent — safe to call on every
# boot and every gateway update, not just once. Also migrates off an old network literally named
# `gateway`: Docker Engine 25 (confirmed on the real box; `gw_priority`/`priority` don't help there)
# picks a multi-network container's default route by whichever attached network's NAME sorts first
# lexicographically, not by connection order — `edge` sorts before `gateway`, so Caddy always routed
# through `edge0` there and the IMDS guard dropped its DNS-01/instance-role traffic. The fix is the
# Docker network name `backend` (`backend` < `edge`, lexically); the bridge name stays `gw0` (the
# IMDS guard's iptables rule keys off the bridge name, not the network's Docker-assigned name). Both
# `gateway` and `backend` want bridge `gw0` and can't share it, so an old `gateway` network has to be
# torn down (bringing the gateway compose project down with it) before `backend` can be created.
ensure_networks() {
  docker network inspect edge >/dev/null 2>&1 \
    || docker network create --opt com.docker.network.bridge.name=edge0 edge

  if docker network inspect gateway >/dev/null 2>&1; then
    log "found the old 'gateway' Docker network; migrating the gateway compose project to 'backend'"
    local gw="$KIT_ON_BOX/infra/recipes/docker-box/gateway"
    if [[ -f "$gw/compose.yml" ]]; then
      ( cd "$gw" && docker compose down --remove-orphans )
    fi
    docker network rm gateway
  fi

  docker network inspect backend >/dev/null 2>&1 \
    || docker network create --opt com.docker.network.bridge.name=gw0 backend
}

# gateway_route_check <container> <network>: does <container>'s default route go via <network>'s
# gateway address? Reads the route from the HOST network namespace with nsenter, never by execing
# `ip` inside the container: the pinned Caddy image (debian bookworm-slim, only
# ca-certificates/libcap2-bin/mailcap) has no `ip`, so a `docker exec ... ip route` always fails
# there, and a swallowed exec error used to be misread as "the route is empty" (a false hard
# failure on every single run). Shared by gateway/start.sh (fails loudly) and box/gateway.sh status
# (reports, doesn't fail).
#
# Prints one line to stdout and returns:
#   0  ok        "<the default route line>"
#   1  not yet running (container hasn't started, or has no PID yet) — caller may retry
#   2  couldn't check (docker/network-inspect/nsenter/ip error) — the message names which
#   3  mismatch  "<actual route>" (the network's gateway address is in the message too)
gateway_route_check() {
  local container="$1" network="$2" state pid want route rc
  state="$(docker inspect -f '{{.State.Running}} {{.State.Pid}}' "$container" 2>/dev/null)" || state=""
  [[ "$state" == "true "* ]] || { echo "$container is not running"; return 1; }
  pid="${state#true }"
  [[ -n "$pid" && "$pid" != "0" ]] || { echo "$container is not running"; return 1; }

  want="$(docker network inspect "$network" -f '{{(index .IPAM.Config 0).Gateway}}' 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 && -n "$want" ]] || { echo "could not read $network's gateway address: $want"; return 2; }

  route="$(nsenter -t "$pid" -n ip -4 route show default 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || { echo "could not read $container's routes: $route"; return 2; }
  [[ -n "$route" ]] || { echo "could not read $container's routes: no default route in its namespace"; return 2; }

  case "$route" in
    "default via $want "*) echo "$route"; return 0 ;;
    *) echo "$route (want via $want, the $network network's gateway)"; return 3 ;;
  esac
}
