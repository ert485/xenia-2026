#!/usr/bin/env bats
setup() {
  export KIT_ROOT="$BATS_TEST_DIRNAME/.."
  export TMP="$BATS_TEST_TMPDIR"
  export FAKE_STATE="$TMP/state"; mkdir -p "$FAKE_STATE"
  export AWS_CALLS="$TMP/aws-calls"
  cp "$BATS_TEST_DIRNAME/helpers/aws-shim.sh" "$TMP/aws"; chmod +x "$TMP/aws"
  export PATH="$TMP:$PATH"
  cat > "$TMP/kit.env" <<EOF
MEMBER_ACCOUNT_ID=111111111
MANAGEMENT_ACCOUNT_ID=222222222
ZONE_ID=ZFAKEZONE
EOF
  export KIT_ENV_FILE="$TMP/kit.env"
}

@test "load_env exports values from KIT_ENV_FILE" {
  run bash -c 'source scripts/lib/common.sh; load_env; echo "$MEMBER_ACCOUNT_ID"'
  [ "$status" -eq 0 ]
  [ "$output" = "111111111" ]
}

@test "load_env dies when the file is missing" {
  export KIT_ENV_FILE="$TMP/nope.env"
  run bash -c 'source scripts/lib/common.sh; load_env'
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing"* ]]
}

@test "require_profile accepts the matching account and rejects another" {
  FAKE_ACCOUNT=111111111 run bash -c 'source scripts/lib/common.sh; require_profile cohack 111111111 && echo ok'
  [ "$output" = "ok" ]
  FAKE_ACCOUNT=999999999 run bash -c 'source scripts/lib/common.sh; require_profile cohack 111111111'
  [ "$status" -eq 1 ]
  [[ "$output" == *"different account"* ]]
}

@test "mask hides 12-digit numbers" {
  run bash -c 'source scripts/lib/common.sh; printf "arn:aws:iam::%012d:role/x\n" 42 | mask'
  [ "$output" = "arn:aws:iam::<account-id>:role/x" ]
}
