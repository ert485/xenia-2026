#!/usr/bin/env bats
setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export TMP="$BATS_TEST_TMPDIR"
  export AWS_CALLS="$TMP/aws-calls"; : > "$AWS_CALLS"
  cat > "$TMP/aws" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$AWS_CALLS"
case "$*" in
  *"sts get-caller-identity"*) echo 111111111 ;;
  *"ec2 describe-instances"*)  printf '%s\n' "${FAKE_IDS-i-0123456789abcdef0}" ;;
esac
exit 0
EOF
  chmod +x "$TMP/aws"
  export PATH="$TMP:$PATH"
  PY="$PWD/.venv/bin/python"; [ -x "$PY" ] || PY=python3
  export PY
}

@test "models.yaml: default exists and every model has the required fields" {
  run "$PY" -c '
import sys, yaml
d = yaml.safe_load(open("infra/recipes/gpu-box/models.yaml"))
assert d["default"] in d["models"], "default not in models"
for name, m in d["models"].items():
    for k in ("repo", "served_name", "tool_parser", "max_num_seqs", "extra_args"):
        assert k in m, f"{name} lacks {k}"
    assert m["served_name"] == "qwen3-coder", f"{name}: clients only know qwen3-coder"
    assert isinstance(m["max_num_seqs"], int), f"{name}: max_num_seqs must be an integer"
print("ok")'
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}

@test "shutdown entry: dry run names the instance and stops nothing" {
  DRY_RUN=1 run shutdown.d/10-gpu-box.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"would stop i-0123456789abcdef0"* ]] || return 1
  ! grep -q 'stop-instances' "$AWS_CALLS"
}

@test "shutdown entry: a real run stops the running instance in us-east-1" {
  run shutdown.d/10-gpu-box.sh
  [ "$status" -eq 0 ]
  grep -q 'stop-instances --instance-ids i-0123456789abcdef0' "$AWS_CALLS"
  grep -q -- '--region us-east-1' "$AWS_CALLS"
}

@test "shutdown entry: nothing running exits 0" {
  FAKE_IDS="" run shutdown.d/10-gpu-box.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing running"* ]]
}

@test "M11: gpu.sh start polls SSM until the box is online before the health-check send-command" {
  printf 'MEMBER_ACCOUNT_ID=111111111\nMANAGEMENT_ACCOUNT_ID=222222222\nZONE_ID=ZFAKEZONE\n' > "$TMP/kit.env"
  export KIT_ENV_FILE="$TMP/kit.env" BOX_POLL_SECONDS=0
  cat > "$TMP/aws" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$AWS_CALLS"
case "$*" in
  *"sts get-caller-identity"*) echo 111111111 ;;
  *"ec2 describe-instances"*"gpu-box"*)    echo i-0123456789abcdef0 ;;
  *"ec2 describe-instances"*"docker-box"*) echo i-0fedcba9876543210 ;;
  *"ssm describe-instance-information"*) echo Online ;;
  *"ssm send-command --instance-ids i-0123456789abcdef0"*) echo cmd-vllm-wait ;;
  *"ssm send-command --instance-ids i-0fedcba9876543210"*) echo cmd-gateway ;;
  *"get-command-invocation --command-id cmd-vllm-wait"*"--query Status"*) echo Success ;;
  *"get-command-invocation --command-id cmd-gateway"*"--query Status"*)   echo Success ;;
  *"get-command-invocation --command-id cmd-vllm-wait"*) printf 'healthy\t\n' ;;
  *"get-command-invocation --command-id cmd-gateway"*)   printf 'gateway updated\t\n' ;;
esac
exit 0
EOF
  chmod +x "$TMP/aws"
  GPU_PROFILE=cohack run scripts/gpu.sh start
  [ "$status" -eq 0 ]
  ping_line="$(grep -n 'ssm describe-instance-information' "$AWS_CALLS" | head -1 | cut -d: -f1)"
  send_line="$(grep -n 'ssm send-command --instance-ids i-0123456789abcdef0' "$AWS_CALLS" | head -1 | cut -d: -f1)"
  [ -n "$ping_line" ] || return 1
  [ -n "$send_line" ] || return 1
  [ "$ping_line" -lt "$send_line" ] || return 1
}

@test "M11: gpu.sh start fails fast when send-command returns no command id, instead of polling" {
  printf 'MEMBER_ACCOUNT_ID=111111111\nMANAGEMENT_ACCOUNT_ID=222222222\nZONE_ID=ZFAKEZONE\n' > "$TMP/kit.env"
  export KIT_ENV_FILE="$TMP/kit.env" BOX_POLL_SECONDS=0
  cat > "$TMP/aws" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$AWS_CALLS"
case "$*" in
  *"sts get-caller-identity"*) echo 111111111 ;;
  *"ec2 describe-instances"*"gpu-box"*) echo i-0123456789abcdef0 ;;
  *"ssm describe-instance-information"*) echo Online ;;
  *"ssm send-command --instance-ids i-0123456789abcdef0"*) echo "" ;;
esac
exit 0
EOF
  chmod +x "$TMP/aws"
  GPU_PROFILE=cohack run scripts/gpu.sh start
  [ "$status" -eq 1 ]
  [[ "$output" == *"no command id"* ]] || return 1
  [ "$(grep -c 'get-command-invocation' "$AWS_CALLS")" -eq 0 ]
}

@test "gpu.sh model refuses a name that is not in models.yaml, before touching AWS" {
  GPU_PROFILE=cohack run scripts/gpu.sh model no-such-model
  [ "$status" -eq 1 ]
  [[ "$output" == *"no model named no-such-model"* ]] || return 1
  ! grep -q 'send-command' "$AWS_CALLS"
}
