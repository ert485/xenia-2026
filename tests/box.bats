#!/usr/bin/env bats
setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export TMP="$BATS_TEST_TMPDIR"
  export AWS_CALLS="$TMP/aws-calls"; : > "$AWS_CALLS"
  cat > "$TMP/aws" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$AWS_CALLS"
case "$*" in
  *"sts get-caller-identity"*)                echo 111111111 ;;
  *"ec2 describe-instances"*)                 echo i-0123456789abcdef0 ;;
  *"ssm send-command"*)                       echo cmd-0001 ;;
  *"get-command-invocation"*"--query Status"*) echo "${FAKE_STATUS:-Success}" ;;
  *"get-command-invocation"*)                 printf 'networks: backend edge\taccount %012d\n' 7 ;;
esac
EOF
  chmod +x "$TMP/aws"
  export PATH="$TMP:$PATH"
  printf 'MEMBER_ACCOUNT_ID=111111111\nMANAGEMENT_ACCOUNT_ID=222222222\nZONE_ID=ZFAKEZONE\n' > "$TMP/kit.env"
  export KIT_ENV_FILE="$TMP/kit.env" BOX_POLL_SECONDS=0
}

@test "box.sh sends the document with Key=Value parameters as SSM JSON and masks the output" {
  run scripts/box.sh xenia-gateway Action=status
  [ "$status" -eq 0 ]
  grep -q -- '--document-name xenia-gateway' "$AWS_CALLS"
  grep -qF '{"Action":["status"]}' "$AWS_CALLS"
  [[ "$output" == *"networks: backend edge"* ]]
  [[ "$output" == *"<account-id>"* ]]
}

@test "box.sh exits non-zero when the command does not succeed" {
  FAKE_STATUS=Failed run scripts/box.sh xenia-gateway Action=status
  [ "$status" -ne 0 ]
  [[ "$output" == *"ended with status Failed"* ]]
}

@test "box.sh rejects a parameter that is not Key=Value" {
  run scripts/box.sh xenia-gateway status
  [ "$status" -eq 1 ]
  [[ "$output" == *"not Key=Value"* ]]
  ! grep -q 'send-command' "$AWS_CALLS"
}
