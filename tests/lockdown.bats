#!/usr/bin/env bats
# scripts/lockdown.sh: attach and detach the break-glass SCP, idempotently, as personal-admin.
setup() {
  export KIT_ROOT="$BATS_TEST_DIRNAME/.."
  export TMP="$BATS_TEST_TMPDIR"
  cp "$BATS_TEST_DIRNAME/helpers/aws-shim.sh" "$TMP/aws"; chmod +x "$TMP/aws"
  export PATH="$TMP:$PATH"
  # 12-digit fake account IDs built at runtime, never literal (leak-check convention, see tf.bats).
  MEMBER_ID="$(printf '%012d' 111111111)"
  MANAGEMENT_ID="$(printf '%012d' 222222222)"
  export MEMBER_ID MANAGEMENT_ID
  printf 'MEMBER_ACCOUNT_ID=%s\nMANAGEMENT_ACCOUNT_ID=%s\nZONE_ID=ZFAKEZONE\n' "$MEMBER_ID" "$MANAGEMENT_ID" > "$TMP/kit.env"
  export KIT_ENV_FILE="$TMP/kit.env" FAKE_ACCOUNT="$MANAGEMENT_ID" FAKE_MEMBER="$MEMBER_ID"
  export FAKE_STATE="$TMP/state" AWS_CALLS="$TMP/calls"
  mkdir -p "$FAKE_STATE"; : > "$AWS_CALLS"
  touch "$FAKE_STATE/scp"
}

attach_calls() { grep -c "organizations attach-policy --policy-id p-lockdown1 --target-id $MEMBER_ID --profile personal-admin" "$AWS_CALLS" || true; }
detach_calls() { grep -c "organizations detach-policy --policy-id p-lockdown1 --target-id $MEMBER_ID --profile personal-admin" "$AWS_CALLS" || true; }

@test "lockdown attaches the SCP to the member account as personal-admin" {
  run scripts/lockdown.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"lockdown: ON"* ]]
  [ "$(attach_calls)" -eq 1 ]
  [ -f "$FAKE_STATE/scp-attached" ]
}

@test "a second lockdown is a no-op that says so" {
  scripts/lockdown.sh
  run scripts/lockdown.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"already on"* ]]
  [ "$(attach_calls)" -eq 1 ]
}

@test "--undo detaches, and a second --undo is a no-op" {
  scripts/lockdown.sh
  run scripts/lockdown.sh --undo
  [ "$status" -eq 0 ]
  [[ "$output" == *"lockdown: OFF"* ]]
  [ "$(detach_calls)" -eq 1 ]
  run scripts/lockdown.sh --undo
  [ "$status" -eq 0 ]
  [[ "$output" == *"already off"* ]]
  [ "$(detach_calls)" -eq 1 ]
}

@test "--dry-run changes nothing in either direction" {
  run scripts/lockdown.sh --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would attach"* ]]
  [ "$(attach_calls)" -eq 0 ]
  touch "$FAKE_STATE/scp-attached"
  run scripts/lockdown.sh --undo --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would detach"* ]]
  [ "$(detach_calls)" -eq 0 ]
}

@test "without the SCP it refuses and points at the org apply" {
  rm -f "$FAKE_STATE/scp"
  run scripts/lockdown.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"scripts/tf.sh org apply"* ]]
  [ "$(attach_calls)" -eq 0 ]
}

@test "it refuses a personal-admin profile that resolves to another account" {
  FAKE_ACCOUNT="$MEMBER_ID" run scripts/lockdown.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"different account"* ]]
  [ "$(attach_calls)" -eq 0 ]
}

@test "it never prints an account ID" {
  run scripts/lockdown.sh
  [[ ! "$output" =~ [0-9]{12} ]]
  run scripts/lockdown.sh --undo
  [[ ! "$output" =~ [0-9]{12} ]]
}

@test "an unknown argument is refused" {
  run scripts/lockdown.sh --now
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown argument"* ]]
}
