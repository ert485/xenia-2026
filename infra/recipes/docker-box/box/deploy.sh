#!/usr/bin/env bash
# Usage (on the Docker box, via the xenia-deploy SSM document):
#   deploy.sh <owner/repo> <sha> <image> <app-dir>
# Clones the repo at <sha>, checks the compose contract, pulls <image> (built by the deploy workflow)
# and runs it as project "app" with the kit override (container app-web on the edge network).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/lib.sh"
source "$here/compose-contract.sh"

repo="${1:-}" sha="${2:-}" image="${3:-}" appdir="${4:-.}"
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "repo must be owner/name (got '$repo')"
[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || die "sha must be 40 hex characters"
[[ "$image" =~ ^[A-Za-z0-9._/:-]+$ && "$image" == */* ]] || die "image must be <registry>/<name>:<tag>"
[[ "$appdir" =~ ^[A-Za-z0-9._/-]+$ && "$appdir" != *..* && "$appdir" != /* ]] || die "app dir must be a relative path inside the repo"

# Health-check revert (component 8 of the container-first plan): how long to wait for the app to
# come up, and how often to poll while waiting. Both from the environment so the window can be
# corrected by use; both validated so a typo fails fast instead of turning into a silent 0 s timeout.
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-90}"
HEALTH_POLL_INTERVAL="${HEALTH_POLL_INTERVAL:-5}"
[[ "$HEALTH_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || die "HEALTH_TIMEOUT must be a positive integer of seconds (got '$HEALTH_TIMEOUT')"
[[ "$HEALTH_POLL_INTERVAL" =~ ^[1-9][0-9]*$ ]] || die "HEALTH_POLL_INTERVAL must be a positive integer of seconds (got '$HEALTH_POLL_INTERVAL')"

load_box_env
# Where Caddy routes the app (see gateway/Caddyfile); overridable for a box with a different zone,
# and superseded outright by HEALTH_URL below for tests.
APP_HOST="${APP_HOST:-app.$ZONE}"

src="$APP_STATE_DIR/src"
rm -rf "$src"
git clone -q "https://github.com/$repo.git" "$src"
git -C "$src" checkout -q "$sha"
dir="$src/$appdir"
compose=""
for c in compose.yml compose.yaml docker-compose.yml docker-compose.yaml; do
  if [[ -f "$dir/$c" ]]; then compose="$dir/$c"; break; fi
done
[[ -n "$compose" ]] || die "no compose.yml or docker-compose.yml in $appdir"
check_compose_contract "$compose" || die "compose contract failed"

registry="${image%%/*}"
aws ecr get-login-password --region ca-central-1 | docker login --username AWS --password-stdin "$registry" >/dev/null

dc() { docker compose -p app --project-directory "$dir" -f "$compose" -f "$here/../app/compose.app.yml" "$@"; }

# deploy_image <image>: pull and bring <image> up as app-web. Just the compose steps, no bookkeeping
# side effects — this same function runs for both the primary deploy below and, on a failed health
# check, the revert. If it also decided what "previous" means, the revert's own call would capture
# the just-failed image as "the image running before this deploy" and stamp that into
# $APP_STATE_DIR/previous, corrupting the one file scripts/rollback.sh trusts.
deploy_image() {
  local img="$1"
  export IMAGE="$img" APP_PORT GIT_SHA="$sha"
  dc pull --quiet web
  dc up -d --no-build --remove-orphans
}

# app_healthy: true on an HTTP 2xx/3xx. Reached the way the box already reaches it for real
# traffic — through Caddy, not the container network directly — so a pass also proves TLS and
# routing, not just that app-web's process answers. HEALTH_URL overrides the whole URL for tests.
app_healthy() {
  if [[ -n "${HEALTH_URL:-}" ]]; then
    curl -fsS -o /dev/null --max-time 5 "$HEALTH_URL"
  else
    curl -fsS -o /dev/null --max-time 5 --resolve "$APP_HOST:443:127.0.0.1" "https://$APP_HOST/"
  fi
}

# wait_for_health <timeout>: poll app_healthy every $HEALTH_POLL_INTERVAL seconds until it succeeds
# or <timeout> seconds pass. 0 healthy, 1 timed out.
wait_for_health() {
  local timeout="$1" deadline
  deadline=$((SECONDS + timeout))
  until app_healthy; do
    (( SECONDS < deadline )) || return 1
    sleep "$HEALTH_POLL_INTERVAL"
  done
}

# Rollback bookkeeping (Task 26, extended for the health-check revert): the image running right
# now, before this deploy changes anything. If the new image below fails its health check, this is
# what gets redeployed. It is written to $APP_STATE_DIR/previous — the pointer scripts/rollback.sh's
# manual path reads — only once THIS deploy's own health check passes, a few lines down; a deploy
# that fails (this one, or the revert redeploying $prev_image) never writes it, so a failed deploy
# can never overwrite the one record of what was last known good.
prev_image="$(docker inspect -f '{{.Config.Image}}' app-web 2>/dev/null || true)"

deploy_image "$image"

log "waiting up to ${HEALTH_TIMEOUT}s for $APP_HOST to answer healthy"
if wait_for_health "$HEALTH_TIMEOUT"; then
  if [[ -n "$prev_image" && "$prev_image" != "$image" ]]; then
    printf '%s\n' "$prev_image" > "$APP_STATE_DIR/previous"
  fi
  jq -n --arg repo "$repo" --arg sha "$sha" --arg image "$image" --arg app_dir "$appdir" \
    '{repo: $repo, sha: $sha, image: $image, app_dir: $app_dir}' > "$APP_STATE_DIR/current.json"
  log "deployed $repo at ${sha:0:7}: https://$APP_HOST"
  exit 0
fi

log "$image did not pass its health check within ${HEALTH_TIMEOUT}s; rolling back"

if [[ -z "$prev_image" ]]; then
  log "no previous image to roll back to; the app is down — run scripts/rollback.sh or investigate"
  exit 2
fi

deploy_image "$prev_image"

log "waiting up to ${HEALTH_TIMEOUT}s for the rollback to $prev_image to answer healthy"
if wait_for_health "$HEALTH_TIMEOUT"; then
  log "rolled back to $prev_image; it is healthy again ($image's deploy failed — investigate before retrying)"
  exit 1
fi

log "rollback to $prev_image also failed its health check; the app is down — run scripts/rollback.sh or investigate"
exit 2
