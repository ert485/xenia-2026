#!/usr/bin/env bash
# Usage (on the Docker box, through the xenia-restore document): box/restore.sh <s3-key> <container>
# Replays a pg_dumpall backup written by box/backup.sh into a running Postgres container:
#   1. uploads a pre-restore dump of the container next to its backups, so the restore can be undone;
#   2. drops, with FORCE, every database the dump creates: backup.sh dumps without --clean, so without this
#      the replay would fail on existing tables and duplicate keys;
#   3. replays the dump with psql as the container's POSTGRES_USER. "already exists" errors (roles) are
#      expected; any other error fails the run and is printed.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$here/lib.sh"
env_file="${XENIA_ENV_FILE:-/etc/xenia.env}"
# shellcheck disable=SC1090
[[ -f "$env_file" ]] && source "$env_file"
: "${BACKUP_BUCKET:?BACKUP_BUCKET missing from $env_file}"

key="${1:?usage: restore.sh <s3-key> <container>}"
c="${2:?usage: restore.sh <s3-key> <container>}"
[[ "$key" =~ ^[A-Za-z0-9._/-]+\.sql\.gz$ && "$key" != *..* ]] || die "not a backup key: $key"
image="$(docker inspect -f '{{.Config.Image}}' "$c" 2>/dev/null)" || die "no such container: $c"
[[ "$image" == postgres* ]] || die "$c runs $image, not postgres"
user="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$c" | sed -n 's/^POSTGRES_USER=//p' | head -1)"
user="${user:-postgres}"

work="$(mktemp -d "${TMPDIR:-/var/tmp}/xenia-restore.XXXXXX")"
trap 'rm -rf "$work"' EXIT

pre="$(hostname)/$c/pre-restore-$(date -u +%Y%m%dT%H%M%SZ).sql.gz"
docker exec "$c" pg_dumpall -U "$user" | gzip | aws s3 cp - "s3://$BACKUP_BUCKET/$pre" --only-show-errors
log "saved the current state as $pre (restore that key to undo this)"

aws s3 cp "s3://$BACKUP_BUCKET/$key" "$work/dump.sql.gz" --only-show-errors
gunzip "$work/dump.sql.gz"
dbs=()
while IFS= read -r db; do dbs+=("$db"); done < <(
  sed -nE 's/^CREATE DATABASE "?([A-Za-z0-9_]+)"?( .*)?;$/\1/p' "$work/dump.sql" | grep -vxE 'postgres|template0|template1' || true)
for db in "${dbs[@]}"; do
  log "dropping database $db"
  docker exec "$c" psql -q -U "$user" -d postgres -c "DROP DATABASE IF EXISTS \"$db\" WITH (FORCE);"
done

docker exec -i "$c" psql -q -U "$user" -d postgres < "$work/dump.sql" > "$work/psql.log" 2>&1 || true
unexpected="$(grep 'ERROR' "$work/psql.log" | grep -v 'already exists' || true)"
if [[ -n "$unexpected" ]]; then
  printf '%s\n' "$unexpected" | head -20 >&2
  die "the replay reported errors; the pre-restore state is $pre"
fi
log "restored $key into $c (${#dbs[@]} databases recreated)"
