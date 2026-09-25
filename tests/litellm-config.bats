#!/usr/bin/env bats
# The pinned LiteLLM looks fallbacks up under the requested (alias) name, so an alias without its own
# fallbacks entry never fails over to Bedrock while the GPU box is down.
setup() {
  CONFIG="$BATS_TEST_DIRNAME/../infra/recipes/docker-box/gateway/litellm.config.yaml"
}

# prints every model_group_alias key with no fallbacks entry; fails if there is one
missing_fallbacks() {
  python3 - "$1" <<'PY'
import sys, yaml
router = yaml.safe_load(open(sys.argv[1]))["router_settings"]
covered = {name for entry in router.get("fallbacks") or [] for name in entry}
missing = [a for a in router.get("model_group_alias") or {} if a not in covered]
print("\n".join(missing))
sys.exit(1 if missing else 0)
PY
}

@test "every model_group_alias key has a fallbacks entry" {
  run missing_fallbacks "$CONFIG"
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "the check fails for an alias with no fallbacks entry" {
  broken="$BATS_TEST_TMPDIR/litellm.config.yaml"
  sed 's/^    opus: qwen3-coder$/&\n    claude-new-model: qwen3-coder/' "$CONFIG" > "$broken"
  grep -q 'claude-new-model' "$broken"
  run missing_fallbacks "$broken"
  [ "$status" -eq 1 ]
  [ "$output" = "claude-new-model" ]
}

# A stopped/dead GPU box's EIP drops packets (no RST): a request just hangs until some timeout
# fires, so the vLLM deployment must fail over fast — a short timeout and zero retries, one attempt
# before Bedrock, not two.
@test "the vLLM deployment has zero retries and a timeout of 30s or less" {
  run python3 - "$CONFIG" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
vllm = next(m["litellm_params"] for m in d["model_list"] if m["model_name"] == "qwen3-coder")
retries = vllm.get("max_retries", vllm.get("num_retries"))
assert retries == 0, f"vLLM deployment retries must be 0, got {retries!r}"
timeout = vllm["timeout"]
assert timeout <= 30, f"vLLM deployment timeout must be <= 30s, got {timeout!r}"
print("ok")
PY
  echo "$output"
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}
