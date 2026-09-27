#!/usr/bin/env bash
# Usage (on the Docker box, via the xenia-preview-down SSM document, or from evict_oldest_previews):
#   box/preview-down.sh <pr>|pr-<pr>|all
# Removes a preview's containers, volumes, source checkout, and image. Exit 0 when nothing runs.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$here/lib.sh"
previews_root="${PREVIEWS_ROOT:-/srv/previews}"

down_one() {
  local n="${1#pr-}" project dir compose
  [[ "$n" =~ ^[0-9]{1,6}$ ]] || die "not a PR number: $1"
  project="pr-$n"; dir="$previews_root/$project"
  if ! docker compose -p "$project" down --remove-orphans --volumes; then
    # ok-to-hide: optional read; an absent compose file is handled by the die on the next line.
    compose="$(cat "$dir/compose-file" 2>/dev/null || true)"
    [[ -n "$compose" && -f "$compose" ]] || die "compose down failed for $project and no saved compose file to retry with"
    PR="$n" docker compose -p "$project" -f "$compose" -f "$here/../app/compose.preview.yml" down --remove-orphans --volumes
  fi
  docker images --format '{{.Repository}}:{{.Tag}}' "xenia-preview/$project" | while read -r img; do
    # ok-to-hide: best-effort per-image cleanup; the directory removal below still happens.
    docker image rm "$img" >/dev/null 2>&1 || true
  done
  rm -rf "$dir"
  log "removed preview $project"
}

target="${1:?usage: preview-down.sh <pr>|all}"
if [[ "$target" == "all" ]]; then
  found=0
  while read -r project; do
    [[ -n "$project" ]] || continue
    found=1
    down_one "$project"
  done < <(list_previews)
  [[ "$found" == 1 ]] || log "no previews running"
  # ok-to-hide: best-effort global prune after every preview above was already removed individually.
  docker image prune -f >/dev/null 2>&1 || true
else
  down_one "$target"
fi
