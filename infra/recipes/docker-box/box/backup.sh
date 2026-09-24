#!/usr/bin/env bash
# Hourly (xenia-backup.timer): pg_dumpall of every running Postgres container to the backup bucket at
# s3://$BACKUP_BUCKET/<hostname>/<container>/<UTC stamp>.sql.gz. A container matches when its image
# name contains "postgres" anywhere, case-insensitively (covers docker.io/library/postgres, a custom
# registry's postgres-ha, etc.), or it carries the label xenia.backup=true (needed for images like
# pgvector/pgvector, whose name does not literally contain "postgres"). One failure never stops the
# others; the exit code is 1 if any container failed, so the systemd journal shows it.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
load_box_env

is_postgres() {
  local name="$1" image="$2" image_lc
  image_lc="$(tr '[:upper:]' '[:lower:]' <<< "$image")"
  [[ "$image_lc" == *postgres* ]] && return 0
  [[ "$(docker inspect -f '{{index .Config.Labels "xenia.backup"}}' "$name" 2>/dev/null)" == "true" ]]
}

host="$(hostname -s)"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
failed=0
while read -r name image; do
  is_postgres "$name" "$image" || continue
  user="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$name" | sed -n 's/^POSTGRES_USER=//p' | head -1)"
  user="${user:-postgres}"
  key="$host/$name/$stamp.sql.gz"
  if docker exec "$name" pg_dumpall -U "$user" | gzip | aws s3 cp - "s3://$BACKUP_BUCKET/$key" --region ca-central-1 --only-show-errors; then
    log "backup ok: $name -> $key"
  else
    log "backup FAILED: $name"
    failed=1
  fi
done < <(docker ps --format '{{.Names}} {{.Image}}')
exit "$failed"
