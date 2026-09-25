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
load_box_env

src=/srv/app/src
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

# Rollback bookkeeping (Task 26): remember the image that was running, if it is a different one.
prev="$(docker inspect -f '{{.Config.Image}}' app-web 2>/dev/null || true)"
if [[ -n "$prev" && "$prev" != "$image" ]]; then printf '%s\n' "$prev" > /srv/app/previous; fi

export IMAGE="$image" APP_PORT GIT_SHA="$sha"
dc() { docker compose -p app --project-directory "$dir" -f "$compose" -f "$here/../app/compose.app.yml" "$@"; }
dc pull --quiet web
dc up -d --no-build --remove-orphans

log "waiting up to 60 s for app-web:$APP_PORT"
deadline=$((SECONDS + 60))
while (( SECONDS < deadline )); do
  if docker run --rm --network edge curlimages/curl:8.10.1 -fsS -m 3 -o /dev/null "http://app-web:$APP_PORT/"; then
    jq -n --arg repo "$repo" --arg sha "$sha" --arg image "$image" --arg app_dir "$appdir" \
      '{repo: $repo, sha: $sha, image: $image, app_dir: $app_dir}' > /srv/app/current.json
    log "deployed $repo at ${sha:0:7}: https://app.$ZONE"
    exit 0
  fi
  sleep 2
done
die "app-web did not answer on port $APP_PORT within 60 s; look at: docker logs --tail 50 app-web (or scripts/logs.sh app-web from the laptop)"
