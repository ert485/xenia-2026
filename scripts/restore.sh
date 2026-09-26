#!/usr/bin/env bash
# Usage: scripts/restore.sh --list [container]
#        scripts/restore.sh <s3-key> <container> [--yes]
# Should tier: the box side is tested with fakes; not proven end to end unless
# docs/proofs/2026-09-25-rollback-restore.md exists.
#
# --list shows the 20 newest backups (optionally for one container, such as app-db-1).
# Otherwise replays one backup into a running Postgres container on the Docker box through the
# xenia-restore document (box/restore.sh). Destructive: it drops and recreates every database in the dump,
# so it asks for the container name unless --yes. The box saves a pre-restore dump first.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
require_cmd aws

usage() { sed -n '2,3p' "$0" | sed 's/^# //' >&2; exit 2; }
bucket() { TF_NO_MASK=1 "$KIT_ROOT/scripts/tf.sh" platform output -raw backup_bucket; }

case "${1:-}" in
  ""|-h|--help) usage ;;
  --list)
    b="$(bucket)"
    aws s3 ls "s3://$b/" --recursive --profile cohack --region ca-central-1 \
      | { if [[ -n "${2:-}" ]]; then grep -F "/$2/" || true; else cat; fi; } \
      | sort | tail -n 20 | awk '{print $1, $2, $4}' | mask
    exit 0 ;;
esac

key="$1"
container="${2:-}"
[[ -n "$container" ]] || usage
[[ "$key" =~ ^[A-Za-z0-9._/-]+\.sql\.gz$ ]] || die "not a backup key (expected <host>/<container>/<stamp>.sql.gz; see --list)"
[[ "$container" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || die "not a container name: $container"

log "restore: $key into $container on the Docker box."
log "This drops and recreates every database in the dump, recreates its roles, and disconnects the app"
log "from them while it runs. The box first saves a pre-restore dump, so a second restore can undo it."
if [[ "${3:-}" != "--yes" ]]; then
  read -r -p "Type the container name to continue: " answer
  [[ "$answer" == "$container" ]] || die "not confirmed; nothing changed"
fi
"$KIT_ROOT/scripts/box.sh" xenia-restore "Key=$key" "Container=$container"