#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Tests for vllm_probe() in infra/recipes/docker-box/box/lib.sh: gateway/start.sh calls it so a
# stale (or stopped) /xenia/gpu/api-base never leaves LiteLLM's vLLM deployment pointed at an
# address that drops packets — see Task 7 follow-up problem 1.
setup() {
  export LIB="$BATS_TEST_DIRNAME/../infra/recipes/docker-box/box/lib.sh"
  export TMP="$BATS_TEST_TMPDIR"
  export CURL_CALLS="$TMP/curl-calls"; : > "$CURL_CALLS"
  cat > "$TMP/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_CALLS"
[[ "${CURL_REACHABLE:-1}" == "1" ]]
EOF
  chmod +x "$TMP/curl"
  export PATH="$TMP:$PATH"
}

@test "reachable backend: prints the real api_base and logs reachable" {
  CURL_REACHABLE=1 run bash -c 'source "$LIB"; vllm_probe "https://1.2.3.4:8443/v1" tok "https://gpu-not-provisioned.invalid/v1"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"vLLM backend: reachable (https://1.2.3.4:8443/v1)"* ]]
  [[ "$output" == *"https://1.2.3.4:8443/v1"* ]]
  grep -qF -- '-H Authorization: Bearer tok https://1.2.3.4:8443/health' "$CURL_CALLS"
}

@test "unreachable backend: prints the placeholder and logs why" {
  CURL_REACHABLE=0 run bash -c 'source "$LIB"; vllm_probe "https://1.2.3.4:8443/v1" tok "https://gpu-not-provisioned.invalid/v1"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"vLLM backend not reachable; using the instant-fail placeholder, requests go to Bedrock"* ]]
  last="$(tail -n1 <<< "$output")"
  [ "$last" = "https://gpu-not-provisioned.invalid/v1" ]
}

@test "already the placeholder: never probes, just prints it back" {
  run bash -c 'source "$LIB"; vllm_probe "https://gpu-not-provisioned.invalid/v1" tok "https://gpu-not-provisioned.invalid/v1"'
  [ "$status" -eq 0 ]
  [ "$output" = "https://gpu-not-provisioned.invalid/v1" ]
  [ ! -s "$CURL_CALLS" ]
}
