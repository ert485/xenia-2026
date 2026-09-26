#!/usr/bin/env bash
# Usage (on the Docker box, via the xenia-preview-up SSM document):
#   box/preview-up.sh <pr> <owner/repo> <sha> <app-dir>
# Builds the PR head on the box (deviation 3) and runs it as compose project pr-<pr>, reachable at
# https://pr-<pr>.box.<ZONE> through Caddy. A resync (the PR already has a preview) redeploys in
# place: it counts once toward the three-preview cap (D24) and is never evicted by itself.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$here/lib.sh"
# shellcheck source=compose-contract.sh
source "$here/compose-contract.sh"
env_file="${XENIA_ENV_FILE:-/etc/xenia.env}"
if [[ -f "$env_file" ]]; then
  # shellcheck disable=SC1090
  source "$env_file"
fi
: "${ZONE:?ZONE missing from $env_file}"
APP_PORT="${APP_PORT:-3000}"
previews_root="${PREVIEWS_ROOT:-/srv/previews}"

pr="${1:?usage: preview-up.sh <pr> <owner/repo> <sha> <app-dir>}"
repo="${2:?usage: preview-up.sh <pr> <owner/repo> <sha> <app-dir>}"
sha="${3:?usage: preview-up.sh <pr> <owner/repo> <sha> <app-dir>}"
appdir="${4:-.}"
# The SSM document validates these too; the box checks again because it is the last line.
[[ "$pr" =~ ^[0-9]{1,6}$ ]] || die "PR number must be digits: $pr"
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "not an owner/repo: $repo"
[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || die "not a 40-hex commit SHA: $sha"
[[ "$appdir" =~ ^[A-Za-z0-9._/-]+$ && "$appdir" != *..* ]] || die "app dir must be a plain relative path: $appdir"

project="pr-$pr"
dir="$previews_root/$project"
mkdir -p "$dir"
rm -rf "$dir/src"
git clone -q "https://github.com/$repo.git" "$dir/src"
git -C "$dir/src" checkout -q "$sha"

app="$dir/src/$appdir"
compose=""
for c in compose.yml compose.yaml docker-compose.yml docker-compose.yaml; do
  if [[ -f "$app/$c" ]]; then compose="$app/$c"; break; fi
done
[[ -n "$compose" ]] || die "no compose.yml or docker-compose.yml in '$appdir' (see templates/team-repo/compose.example.yml)"
check_compose_contract "$compose"
check_preview_isolation "$compose" "$app"
printf '%s\n' "$compose" > "$dir/compose-file"

cap="$(preview_cap_for "$project")"
log "$project: evicting down to $cap other previews before starting"
evict_oldest_previews "$cap" "$project"

override="$here/../app/compose.preview.yml"
# Each preview tags its own image, so two PRs never share web:local.
export PR="$pr" APP_PORT GIT_SHA="$sha" IMAGE="xenia-preview/$project:${sha:0:12}"
dc() { docker compose -p "$project" --project-directory "$app" -f "$compose" -f "$override" "$@"; }
dc build --quiet
dc up -d --remove-orphans

deadline=$((SECONDS + 90))
while (( SECONDS < deadline )); do
  if docker run --rm --network edge curlimages/curl:8.10.1 -fsS -m 3 -o /dev/null "http://$project-web:$APP_PORT/"; then
    echo "preview: https://$project.box.$ZONE"
    exit 0
  fi
  sleep 3
done
die "$project did not answer on port $APP_PORT within 90 s; check 'docker logs $project-web' (scripts/logs.sh $project from a laptop)"
