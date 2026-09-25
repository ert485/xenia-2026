#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# scripts/gpu.sh start/stop, Task 7 follow-up problem 1b: start waits for vLLM health (bounded) then
# updates the gateway; stop updates the gateway right away, so it fails over to Bedrock instead of
# waiting on some future request to notice the box is gone.
setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export TMP="$BATS_TEST_TMPDIR"
  export AWS_CALLS="$TMP/aws-calls"; : > "$AWS_CALLS"
  export HEALTH_STATUS="${HEALTH_STATUS:-Success}"
  cat > "$TMP/aws" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$AWS_CALLS"
case "\$*" in
  *"sts get-caller-identity"*) echo 111111111 ;;
  *"ec2 describe-instances"*"gpu-box"*)    echo i-0123456789abcdef0 ;;
  *"ec2 describe-instances"*"docker-box"*) echo i-0fedcba9876543210 ;;
  *"ssm send-command --instance-ids i-0123456789abcdef0"*) echo cmd-vllm-wait ;;
  *"ssm send-command --instance-ids i-0fedcba9876543210"*) echo cmd-gateway ;;
  *"get-command-invocation --command-id cmd-vllm-wait"*"--query Status"*) echo "\${HEALTH_STATUS}" ;;
  *"get-command-invocation --command-id cmd-gateway"*"--query Status"*)   echo Success ;;
  *"get-command-invocation --command-id cmd-vllm-wait"*) printf 'healthy\t\n' ;;
  *"get-command-invocation --command-id cmd-gateway"*)   printf 'gateway updated\t\n' ;;
esac
exit 0
EOF
  chmod +x "$TMP/aws"
  export PATH="$TMP:$PATH"
  printf 'MEMBER_ACCOUNT_ID=111111111\nMANAGEMENT_ACCOUNT_ID=222222222\nZONE_ID=ZFAKEZONE\n' > "$TMP/kit.env"
  export KIT_ENV_FILE="$TMP/kit.env" BOX_POLL_SECONDS=0
}

@test "gpu.sh start: waits for vLLM health then updates the gateway" {
  GPU_PROFILE=cohack run scripts/gpu.sh start
  [ "$status" -eq 0 ]
  grep -q 'ec2 start-instances --instance-ids i-0123456789abcdef0' "$AWS_CALLS"
  grep -q 'ec2 wait instance-running --instance-ids i-0123456789abcdef0' "$AWS_CALLS"
  grep -q 'ssm send-command --instance-ids i-0123456789abcdef0' "$AWS_CALLS"
  [[ "$output" == *"vLLM healthy"* ]]
  grep -q 'document-name xenia-gateway' "$AWS_CALLS"
  grep -q 'ssm send-command --instance-ids i-0fedcba9876543210 --document-name xenia-gateway' "$AWS_CALLS"
  [[ "$output" == *"Success"* || "$output" == *"gateway updated"* ]]
}

@test "gpu.sh start: health check times out, still updates the gateway (not a hard failure)" {
  HEALTH_STATUS=Failed GPU_PROFILE=cohack run scripts/gpu.sh start
  [ "$status" -eq 0 ]
  [[ "$output" == *"still not healthy after 20 minutes"* ]]
  grep -q 'ssm send-command --instance-ids i-0fedcba9876543210 --document-name xenia-gateway' "$AWS_CALLS"
}

@test "gpu.sh stop: stops the instance and updates the gateway right away" {
  GPU_PROFILE=cohack run scripts/gpu.sh stop
  [ "$status" -eq 0 ]
  grep -q 'ec2 stop-instances --instance-ids i-0123456789abcdef0' "$AWS_CALLS"
  grep -q 'ssm send-command --instance-ids i-0fedcba9876543210 --document-name xenia-gateway' "$AWS_CALLS"
}
