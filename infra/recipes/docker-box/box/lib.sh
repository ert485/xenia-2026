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
