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
  # The container can vanish between `docker ps` above and here (stopped/removed mid-loop); under
  # set -e, a failing docker inspect inside a plain assignment would abort the whole run, so check
  # first and skip with a log line instead of losing every remaining container's backup.
  if ! docker inspect "$name" >/dev/null 2>&1; then
    log "backup skipped: $name (vanished before inspect)"
    continue
  fi
  user="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$name" 2>/dev/null | sed -n 's/^POSTGRES_USER=//p' | head -1)" || true
  user="${user:-postgres}"
  key="$host/$name/$stamp.sql.gz"
  tmp_key="$key.partial"
  # Upload to a .partial key first and only rename it to the real key on success, so a failed or
  # truncated dump never leaves a normal-looking (but incomplete) backup object at $key.
  if docker exec "$name" pg_dumpall -U "$user" | gzip | aws s3 cp - "s3://$BACKUP_BUCKET/$tmp_key" --region ca-central-1 --only-show-errors; then
    aws s3 mv "s3://$BACKUP_BUCKET/$tmp_key" "s3://$BACKUP_BUCKET/$key" --region ca-central-1 --only-show-errors
    log "backup ok: $name -> $key"
  else
    aws s3 rm "s3://$BACKUP_BUCKET/$tmp_key" --region ca-central-1 --only-show-errors 2>/dev/null || true
    log "backup FAILED: $name"
    failed=1
  fi
done < <(docker ps --format '{{.Names}} {{.Image}}')
exit "$failed"
