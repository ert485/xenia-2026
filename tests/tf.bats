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
  [[ "$output" == *"args=-chdir="*"/infra/platform plan"* ]] || return 1
  [[ "$output" == *"acct=<account-id>"* ]]
}

@test "tf.sh uses personal-admin for org and refuses a mismatched account" {
  FAKE_ACCOUNT="$MEMBER_ID" run scripts/tf.sh org plan
  [ "$status" -eq 1 ]
  [[ "$output" == *"different account"* ]]
}

@test "tf.sh exports cohack credentials for org (backend is member-account) and never echoes the secret" {
  # org's own guard checks personal-admin against MANAGEMENT_ACCOUNT_ID, and now also checks
  # cohack against MEMBER_ACCOUNT_ID; the fake aws shim answers get-caller-identity the same way
  # regardless of --profile, so give both accounts the same fake value to satisfy both guards.
  printf 'MEMBER_ACCOUNT_ID=%s\nMANAGEMENT_ACCOUNT_ID=%s\nZONE_ID=ZFAKEZONE\n' "$MANAGEMENT_ID" "$MANAGEMENT_ID" > "$TMP/kit-org-ok.env"
  KIT_ENV_FILE="$TMP/kit-org-ok.env" FAKE_ACCOUNT="$MANAGEMENT_ID" run scripts/tf.sh org plan
  [ "$status" -eq 0 ]
  [[ "$output" == *"key=FAKEKEY-configure export-credentials --profile cohack --format env"* ]] || return 1
  [[ "$output" != *"FAKESECRET"* ]]
}

@test "tf.sh refuses org when the cohack identity doesn't match the member account" {
  # personal-admin matches MANAGEMENT_ACCOUNT_ID, but the fake identity is the same for every
  # profile, so the added cohack-vs-MEMBER_ACCOUNT_ID guard now catches the mismatch.
  FAKE_ACCOUNT="$MANAGEMENT_ID" run scripts/tf.sh org plan
  [ "$status" -eq 1 ]
  [[ "$output" == *"different account"* ]]
}

@test "tf.sh requests the cohack profile for a non-org stack" {
  FAKE_ACCOUNT="$MEMBER_ID" run scripts/tf.sh platform plan
  [ "$status" -eq 0 ]
  [[ "$output" == *"key=FAKEKEY-configure export-credentials --profile cohack --format env"* ]]
}

@test "tf.sh dies if credential export fails, and never invokes terraform" {
  FAKE_ACCOUNT="$MEMBER_ID" FAKE_EXPORT_CREDS_FAIL=1 run scripts/tf.sh platform plan
  [ "$status" -ne 0 ]
  [[ "$output" == *"could not export credentials for profile cohack"* ]] || return 1
  [[ "$output" != *"cwd="* ]] || return 1
  [[ "$output" != *"args="* ]]
}
