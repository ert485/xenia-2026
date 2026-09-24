#!/usr/bin/env bats
setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export TMP="$BATS_TEST_TMPDIR"
  export FAKE_STATE="$TMP/state"; mkdir -p "$FAKE_STATE"
  export AWS_CALLS="$TMP/aws-calls"; : > "$AWS_CALLS"
  cp tests/helpers/aws-shim.sh "$TMP/aws"; chmod +x "$TMP/aws"
  export PATH="$TMP:$PATH"
  printf 'MEMBER_ACCOUNT_ID=111111111\nMANAGEMENT_ACCOUNT_ID=222222222\nZONE_ID=ZFAKEZONE\n' > "$TMP/kit.env"
  export KIT_ENV_FILE="$TMP/kit.env" FAKE_ACCOUNT=111111111
  export KIT_BACKEND_FILE="$TMP/backend.local.hcl"
}

@test "first run creates bucket and table and writes the backend file" {
  run scripts/bootstrap.sh
  [ "$status" -eq 0 ]
  grep -q 's3api create-bucket' "$AWS_CALLS"
  grep -q 'dynamodb create-table' "$AWS_CALLS"
  grep -qE '^bucket += "xenia-tfstate-[0-9a-f]{6}"$' "$KIT_BACKEND_FILE"
  grep -qE 'profile += "cohack"' "$KIT_BACKEND_FILE"
}

@test "second run reuses the bucket name and creates nothing" {
  scripts/bootstrap.sh
  first="$(grep bucket "$KIT_BACKEND_FILE")"
  : > "$AWS_CALLS"
  run scripts/bootstrap.sh
  [ "$status" -eq 0 ]
  [ "$(grep bucket "$KIT_BACKEND_FILE")" = "$first" ]
  ! grep -q 'create-bucket' "$AWS_CALLS"
  ! grep -q 'create-table' "$AWS_CALLS"
}
