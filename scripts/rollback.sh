#!/usr/bin/env bash
# Usage: scripts/rollback.sh [--app-dir DIR] [--dry-run]
# Should tier: tested with fakes; not proven end to end unless docs/proofs/2026-09-25-rollback-restore.md exists.
#
# Puts the image that ran before the last deploy back on app.26.cohack.tetl.ca in one command (spec section 9).
# Reads /srv/app/previous and /srv/app/current.json on the Docker box through the xenia-gateway document
# (Action=current), then re-sends xenia-deploy with the previous image and the commit it was built from
# (its sha-<commit> tag), so the compose file matches the image. deploy.sh records the image it replaces,
# so running this twice swaps back. The next push to main deploys over it as usual.
# AppDir: --app-dir, else the repo variable APP_DIR, else ".".
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
require_cmd jq

app_dir="" dry=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-dir) app_dir="${2:?--app-dir needs a directory}"; shift 2 ;;
    --dry-run) dry=1; shift ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "usage: scripts/rollback.sh [--app-dir DIR] [--dry-run]" >&2; exit 2 ;;
  esac
done

state="$("$KIT_ROOT/scripts/box.sh" xenia-gateway Action=current)" || die "could not read the deploy state from the box"
# box.sh prints stdout and stderr joined by a tab; keep what precedes the tab on each line.
field() { printf '%s\n' "$state" | cut -f1 | sed -n "s/^$1=//p" | tail -1; }
previous="$(field previous)"
repo="$(field repo)"
sha="$(field sha)"
[[ -n "$previous" && "$previous" != none ]] || die "nothing to roll back to: the box has no previous image (one deploy so far)"
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ && "$sha" =~ ^[0-9a-f]{40}$ ]] || die "the box has no usable deploy record in /srv/app/current.json"

prev_sha="$sha"
if [[ "$previous" =~ :sha-([0-9a-f]{40})$ ]]; then prev_sha="${BASH_REMATCH[1]}"; fi

if [[ -z "$app_dir" ]]; then
  app_dir="$(gh variable get APP_DIR --repo "$repo" 2>/dev/null || true)"
  app_dir="${app_dir:-.}"
fi

registry="$(TF_NO_MASK=1 "$KIT_ROOT/scripts/tf.sh" platform output -json ecr_repository_urls \
  | jq -r --arg r "$repo" '.[$r] // empty' | sed 's|/.*||')"
[[ -n "$registry" ]] || die "no ECR repository for $repo in the platform outputs (is it on the allow-list?)"
image="$registry/$previous"

log "rollback: $repo back to $previous (commit ${prev_sha:0:12}), app dir $app_dir"
if (( dry )); then
  printf 'would send xenia-deploy Repo=%s Sha=%s Image=%s AppDir=%s\n' "$repo" "$prev_sha" "$image" "$app_dir" | mask
  exit 0
fi
"$KIT_ROOT/scripts/box.sh" xenia-deploy "Repo=$repo" "Sha=$prev_sha" "Image=$image" "AppDir=$app_dir"
"$KIT_ROOT/scripts/box.sh" xenia-gateway Action=current
log "rolled back. The image must still be in ECR (the lifecycle policy keeps the last 20)."
