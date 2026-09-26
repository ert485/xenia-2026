#!/usr/bin/env bats
setup() {
  export BOX="$BATS_TEST_DIRNAME/../infra/recipes/docker-box/box"
  export FAKE="$BATS_TEST_TMPDIR/fake"; mkdir -p "$FAKE/bin"
  export CALLS="$FAKE/calls"; : > "$CALLS"
  export TMPDIR="$BATS_TEST_TMPDIR"
  export XENIA_ENV_FILE="$FAKE/xenia.env"; echo 'BACKUP_BUCKET=xenia-backups-abc123' > "$XENIA_ENV_FILE"
  export FAKE_IMAGE="postgres:16"
  printf -- '-- dump\nCREATE ROLE app;\nCREATE DATABASE app WITH TEMPLATE = template0 ENCODING = %s;\nCREATE DATABASE analytics WITH TEMPLATE = template0;\n\\connect app\nCOPY public.proof (id, note) FROM stdin;\n' "'UTF8'" | gzip > "$FAKE/dump.sql.gz"
  cat > "$FAKE/bin/docker" <<'SH'
#!/usr/bin/env bash
printf 'docker %s\n' "$*" >> "$CALLS"
case "$*" in
  "inspect -f {{.Config.Image}} missing") exit 1 ;;
  "inspect -f {{.Config.Image}} "*) echo "$FAKE_IMAGE" ;;
  "inspect -f {{range .Config.Env}}{{println .}}{{end}} "*) printf 'POSTGRES_USER=app\nPOSTGRES_DB=app\n' ;;
  *"pg_dumpall"*) echo "-- current state" ;;
  "exec -i "*) cat > "$FAKE/replayed.sql"; echo 'ERROR:  role "app" already exists'; [[ -n "${FAKE_PSQL_ERROR:-}" ]] && echo "ERROR:  $FAKE_PSQL_ERROR"; exit 0 ;;
  *) exit 0 ;;
esac
SH
  cat > "$FAKE/bin/aws" <<'SH'
#!/usr/bin/env bash
printf 'aws %s\n' "$*" >> "$CALLS"
case "$*" in
  "s3 cp - "*) cat > "$FAKE/pre-restore.gz" ;;
  "s3 cp s3://"*) cp "$FAKE/dump.sql.gz" "$4" ;;
esac
SH
  chmod +x "$FAKE/bin/"*
  export PATH="$FAKE/bin:$PATH"
}

@test "rejects a key that is not a backup path" {
  run "$BOX/restore.sh" "../etc/passwd.sql.gz" app-db-1
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a backup key"* ]]
}

@test "refuses a missing or non-postgres container" {
  run "$BOX/restore.sh" "host/app-db-1/20260925T030000Z.sql.gz" missing
  [ "$status" -eq 1 ]
  [[ "$output" == *"no such container"* ]] || return 1
  FAKE_IMAGE=redis:7 run "$BOX/restore.sh" "host/app-db-1/20260925T030000Z.sql.gz" app-db-1
  [ "$status" -eq 1 ]
  [[ "$output" == *"not postgres"* ]]
}

@test "saves a pre-restore dump, drops the dump's databases, replays it" {
  run "$BOX/restore.sh" "host/app-db-1/20260925T030000Z.sql.gz" app-db-1
  [ "$status" -eq 0 ]
  pre="$(grep -n 's3 cp - s3://xenia-backups-abc123/.*/app-db-1/pre-restore-' "$CALLS" | cut -d: -f1)"
  drop="$(grep -n 'DROP DATABASE IF EXISTS "app" WITH (FORCE)' "$CALLS" | cut -d: -f1)"
  [ -n "$pre" ] && [ -n "$drop" ] && [ "$pre" -lt "$drop" ]
  grep -q 'DROP DATABASE IF EXISTS "analytics" WITH (FORCE)' "$CALLS"
  grep -q 'psql -q -U app -d postgres' "$CALLS"
  grep -q 'COPY public.proof' "$FAKE/replayed.sql"
  [[ "$output" == *"restored host/app-db-1/20260925T030000Z.sql.gz into app-db-1 (2 databases recreated)"* ]]
}

@test "an unexpected psql error fails the restore and is printed" {
  FAKE_PSQL_ERROR='relation "proof" does not exist' run "$BOX/restore.sh" "host/app-db-1/20260925T030000Z.sql.gz" app-db-1
  [ "$status" -eq 1 ]
  [[ "$output" == *'relation "proof" does not exist'* ]] || return 1
  [[ "$output" != *'role "app" already exists'* ]]
}
