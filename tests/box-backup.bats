#!/usr/bin/env bats
# Tests for infra/recipes/docker-box/box/backup.sh's container matching: image name contains
# "postgres" anywhere (case-insensitive), OR the container carries label xenia.backup=true.
# Note: "pgvector/pgvector" does not literally contain the substring "postgres", so a real pgvector
# deployment needs the xenia.backup=true label; this fixture gives it that label to match.
setup() {
  export TMP="$BATS_TEST_TMPDIR"
  export SCRIPT="$BATS_TEST_DIRNAME/../infra/recipes/docker-box/box/backup.sh"
  export BOX_SCRIPTS="$TMP/box"; mkdir -p "$BOX_SCRIPTS"
  cp "$BATS_TEST_DIRNAME/../infra/recipes/docker-box/box/lib.sh" "$BOX_SCRIPTS/lib.sh"
  export XENIA_ENV_FILE="$TMP/xenia.env"
  printf 'BACKUP_BUCKET=fake-bucket\n' > "$XENIA_ENV_FILE"
  export DUMP_CALLS="$TMP/dump-calls"; : > "$DUMP_CALLS"

  # fake docker: ps lists containers; inspect reports existence/env/labels per container name; exec
  # runs the (fake) dump, failing for "pg-fail" to exercise the failure path.
  cat > "$TMP/docker" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  ps)
    cat <<'PS'
pg-plain docker.io/library/postgres:16
pg-caps myregistry/POSTGRES-ha:16
pgvector pgvector/pgvector:pg16
labelled myorg/customdb:1.0
other myorg/redis:7
PS
    [[ -n "${PS_EXTRA:-}" ]] && printf '%s\n' "$PS_EXTRA"
    ;;
  inspect)
    if [[ "$2" != "-f" ]]; then
      # bare existence check (docker inspect <name>): "vanished" is gone by the time it's checked.
      [[ "$2" == "vanished" ]] && exit 1
      echo '[{}]'
      exit 0
    fi
    fmt="$2"; name="${*: -1}"
    if [[ "$fmt" == *'.Config.Env'* ]]; then
      [[ "$name" == "pg-plain" ]] && echo "POSTGRES_USER=alice"
      exit 0
    fi
    # label lookup
    case "$name" in
      labelled|pgvector) echo "true" ;;
      *) echo "" ;;
    esac
    ;;
  exec)
    name="$2"
    [[ "$name" == "pg-fail" ]] && exit 1
    echo "$name" >> "$DUMP_CALLS"
    echo "-- dump for $name --"
    ;;
esac
exit 0
EOF
  # fake aws: only `s3 cp -` (upload) reads stdin, exactly like the real CLI — `s3 mv`/`s3 rm` never
  # touch stdin at all. Draining stdin unconditionally here would (as the real CLI never does) let a
  # plain "aws s3 mv/rm" steal bytes from the `docker ps` process-substitution pipe that the caller's
  # `while read` loop is still reading from, silently truncating the loop after one iteration.
  # Records every call so tests can check the .partial-then-rename / cleanup-on-failure behavior.
  export S3_CALLS="$TMP/s3-calls"; : > "$S3_CALLS"
  cat > "$TMP/aws" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == "s3 cp -"* ]] && cat >/dev/null
printf '%s\n' "$*" >> "$S3_CALLS"
exit 0
EOF
  chmod +x "$TMP/docker" "$TMP/aws"
  export PATH="$TMP:$PATH"
}

@test "backup.sh dumps containers whose image contains postgres anywhere, case-insensitively" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qx 'pg-plain' "$DUMP_CALLS"
  grep -qx 'pg-caps' "$DUMP_CALLS"
}

@test "backup.sh dumps containers carrying label xenia.backup=true even with an unrelated image" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qx 'labelled' "$DUMP_CALLS"
}

@test "backup.sh skips containers that are neither postgres-imaged nor labelled" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -qx 'other' "$DUMP_CALLS"
  [ "$status" -ne 0 ]
}

@test "backup.sh uploads to a .partial key first, then renames it to the final key on success" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qE '^s3 cp - s3://fake-bucket/[^ ]+/pg-plain/[^ ]+\.sql\.gz\.partial ' "$S3_CALLS"
  grep -qE '^s3 mv s3://fake-bucket/[^ ]+/pg-plain/[^ ]+\.sql\.gz\.partial s3://fake-bucket/[^ ]+/pg-plain/[^ ]+\.sql\.gz ' "$S3_CALLS"
}

@test "backup.sh skips a container that vanishes between ps and inspect, without aborting the run" {
  PS_EXTRA="vanished docker.io/library/postgres:16" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"backup skipped: vanished (vanished before inspect)"* ]]
  # every other container in the base fixture is still backed up despite the vanished one
  grep -qx 'pg-plain' "$DUMP_CALLS"
  grep -qx 'labelled' "$DUMP_CALLS"
  run grep -qx 'vanished' "$DUMP_CALLS"
  [ "$status" -ne 0 ]
}

@test "backup.sh: one container's exec fails, the others still get dumped, exit status 1" {
  PS_EXTRA="pg-fail docker.io/library/postgres:16" run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"backup FAILED: pg-fail"* ]]
  grep -qx 'pg-plain' "$DUMP_CALLS"
  grep -qx 'pg-caps' "$DUMP_CALLS"
  grep -qx 'labelled' "$DUMP_CALLS"
  run grep -qx 'pg-fail' "$DUMP_CALLS"
  [ "$status" -ne 0 ]
  # the failed dump's .partial object is cleaned up, never left behind or renamed to the final key
  grep -qE '^s3 rm s3://fake-bucket/[^ ]+/pg-fail/[^ ]+\.sql\.gz\.partial ' "$S3_CALLS"
  run grep -E '^s3 mv .*/pg-fail/' "$S3_CALLS"
  [ "$status" -ne 0 ]
}
