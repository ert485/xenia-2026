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
  [[ "$output" == *"would stop i-0123456789abcdef0"* ]]
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

@test "gpu.sh model refuses a name that is not in models.yaml, before touching AWS" {
  GPU_PROFILE=cohack run scripts/gpu.sh model no-such-model
  [ "$status" -eq 1 ]
  [[ "$output" == *"no model named no-such-model"* ]]
  ! grep -q 'send-command' "$AWS_CALLS"
}
