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

  # fake docker: ps lists four containers; inspect reports env/labels per container name.
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
    ;;
  inspect)
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
    echo "$name" >> "$DUMP_CALLS"
    echo "-- dump for $name --"
    ;;
esac
exit 0
EOF
  # fake aws: drains stdin like the real `aws s3 cp -` would (upload), so gzip never gets SIGPIPE.
  cat > "$TMP/aws" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
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
