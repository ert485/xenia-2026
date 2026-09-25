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
