#!/usr/bin/env bats
setup() {
  export KIT_ROOT="$BATS_TEST_DIRNAME/.."
  export TMP="$BATS_TEST_TMPDIR"
  cp "$BATS_TEST_DIRNAME/helpers/aws-shim.sh" "$TMP/aws"; chmod +x "$TMP/aws"
  # fake terraform that prints its cwd and args
  printf '#!/usr/bin/env bash\necho "cwd=$PWD"; echo "args=$*"; echo "acct=$TF_VAR_member_account_id"; echo "key=$AWS_ACCESS_KEY_ID"\n' > "$TMP/terraform"; chmod +x "$TMP/terraform"
  export PATH="$TMP:$PATH"
  # 12-digit fake account IDs, built at runtime (never literal in this file) so no
  # 12-digit number ever appears in tests/, matching the convention in common.bats.
  MEMBER_ID="$(printf '%012d' 111111111)"
  MANAGEMENT_ID="$(printf '%012d' 222222222)"
  export MEMBER_ID MANAGEMENT_ID
  printf 'MEMBER_ACCOUNT_ID=%s\nMANAGEMENT_ACCOUNT_ID=%s\nZONE_ID=ZFAKEZONE\n' "$MEMBER_ID" "$MANAGEMENT_ID" > "$TMP/kit.env"
  export KIT_ENV_FILE="$TMP/kit.env"
}

@test "tf.sh refuses an unknown stack" {
  FAKE_ACCOUNT="$MEMBER_ID" run scripts/tf.sh nope plan
  [ "$status" -eq 1 ]
  [[ "$output" == *"no such stack"* ]]
}

@test "tf.sh exports TF_VAR_member_account_id and masks output" {
  FAKE_ACCOUNT="$MEMBER_ID" run scripts/tf.sh platform plan
  [ "$status" -eq 0 ]
  [[ "$output" == *"args=-chdir="*"/infra/platform plan"* ]]
  [[ "$output" == *"acct=<account-id>"* ]]
}

@test "tf.sh uses personal-admin for org and refuses a mismatched account" {
  FAKE_ACCOUNT="$MEMBER_ID" run scripts/tf.sh org plan
  [ "$status" -eq 1 ]
  [[ "$output" == *"different account"* ]]
}

@test "tf.sh exports short-lived credentials for the stack's profile and never echoes the secret" {
  FAKE_ACCOUNT="$MANAGEMENT_ID" run scripts/tf.sh org plan
  [ "$status" -eq 0 ]
  [[ "$output" == *"key=FAKEKEY-configure export-credentials --profile personal-admin --format env"* ]]
  [[ "$output" != *"FAKESECRET"* ]]
}
