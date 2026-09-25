#!/usr/bin/env bats
# status.sh and cost.sh under fakes: no network, no AWS.

setup() {
  export TMP="$BATS_TEST_TMPDIR"
  REAL="$BATS_TEST_DIRNAME/.."
  mkdir -p "$TMP/kit/scripts/lib" "$TMP/bin" "$TMP/home"
  cp "$REAL/scripts/lib/common.sh" "$TMP/kit/scripts/lib/common.sh"
  cp "$REAL/scripts/status.sh" "$REAL/scripts/cost.sh" "$TMP/kit/scripts/"
  export KIT_ROOT="$TMP/kit"
  printf 'MEMBER_ACCOUNT_ID=111111111\nMANAGEMENT_ACCOUNT_ID=222222222\nZONE_ID=ZFAKEZONE\n' > "$TMP/kit.env"
  export KIT_ENV_FILE="$TMP/kit.env" HOME="$TMP/home"
  printf 'sk-xxxxxxxxxxxxxxxxxxxxxxxx\n' > "$HOME/.xenia-erik-key"
  export FAKE_PREVIEWS="pr-3"
  unset GPU_PROFILE GATEWAY_URL XENIA_KEY_FILE

  cat > "$TMP/kit/scripts/tf.sh" <<'SH'
#!/usr/bin/env bash
case "$*" in
  *backup_bucket*) echo xenia-backups-abc123 ;;
  *host_profile*) echo cohack ;;
esac
SH
  cat > "$TMP/kit/scripts/box.sh" <<'SH'
#!/usr/bin/env bash
printf 'NAME STATUS\ngateway running(3)\napp running(2)\n'
for p in $FAKE_PREVIEWS; do printf '%s running(2)\n%s-web Up 2 hours\n' "$p" "$p"; done
SH
  cat > "$TMP/kit/scripts/gpu.sh" <<'SH'
#!/usr/bin/env bash
echo "instance: running"
SH
  cat > "$TMP/bin/aws" <<'SH'
#!/usr/bin/env bash
case "$*" in
  *"sts get-caller-identity"*"personal-admin"*) echo 222222222 ;;
  *"sts get-caller-identity"*) echo 111111111 ;;
  *"ec2 describe-instances"*"gpu-box"*) : ;;
  *"ec2 describe-instances"*"ca-central-1"*) printf 'xenia-docker-box\tt4g.large\trunning\t2026-09-25T08:00:00+00:00\tdocker-box\n' ;;
  *"ec2 describe-instances"*) printf 'xenia-gpu-box\tg6e.xlarge\tstopped\t2026-09-25T08:00:00+00:00\tgpu-box\n' ;;
  *"s3api list-objects-v2"*) printf 'ip-10-0-0-5/gateway-postgres-1/x.sql.gz\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%S+00:00)" ;;
  *"cloudwatch describe-alarms"*) echo "${FAKE_ALARM:-OK}" ;;
  *"resource-explorer-2"*) exit 254 ;;
  *"ce get-cost-and-usage"*)
    if [ -n "${FAKE_CE_ERROR:-}" ]; then echo "An error occurred (DataUnavailableException) when calling the GetCostAndUsage operation: Data is not available." >&2; exit 254; fi
    printf '%s\n' '{"ResultsByTime":[{"Groups":[' \
      '{"Keys":["Amazon Elastic Compute Cloud - Compute"],"Metrics":{"UnblendedCost":{"Amount":"12.5","Unit":"USD"}}},' \
      '{"Keys":["Amazon Bedrock"],"Metrics":{"UnblendedCost":{"Amount":"0.75","Unit":"USD"}}}]}]}' ;;
esac
exit 0
SH
  cat > "$TMP/bin/curl" <<'SH'
#!/usr/bin/env bash
hdr=""; prev=""; url=""
for a in "$@"; do
  [[ "$prev" == "-D" ]] && hdr="$a"
  [[ "$a" == http* ]] && url="$a"
  prev="$a"
done
case "$url" in
  */health/readiness) printf '%s' "${FAKE_READY:-200}" ;;
  */v1/chat/completions)
    [[ -n "$hdr" ]] && printf 'HTTP/2 200\r\nx-litellm-model-id: qwen3-coder-vllm\r\n\r\n' > "$hdr"
    printf '200' ;;
esac
SH
  chmod +x "$TMP/kit/scripts/"*.sh "$TMP/bin/"*
  export PATH="$TMP/bin:$PATH"
}

@test "every probe succeeds: green, fast" {
  start=$SECONDS
  run "$KIT_ROOT/scripts/status.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok    instances: xenia-docker-box t4g.large running"* ]]
  [[ "$output" == *"ok    gateway: completion served by qwen3-coder-vllm"* ]]
  [[ "$output" == *"ok    previews: pr-3"* ]]
  [[ "$output" == *"ok    backup: newest dump gateway-postgres-1"* ]]
  [[ "$output" == *"ok    alarm: xenia-llm-gateway-down is OK"* ]]
  [[ "$output" == *"ok    gpu: stopped"* ]]
  [[ "$output" != *"WARN"* ]]
  [[ "$output" == *"status: green" ]]
  [ $((SECONDS - start)) -lt 3 ]
}

@test "gateway readiness 503: WARN and the summary says so" {
  FAKE_READY=503 run "$KIT_ROOT/scripts/status.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"WARN  gateway: readiness returned 503"* ]]
  [[ "$output" == *"status: check the WARN lines" ]]
}

@test "more previews than the cap is a WARN" {
  FAKE_PREVIEWS="pr-1 pr-2 pr-3 pr-4" run "$KIT_ROOT/scripts/status.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"WARN  previews: 4 running (cap is 3): pr-1 pr-2 pr-3 pr-4"* ]]
}

@test "alarm in ALARM is a WARN" {
  FAKE_ALARM=ALARM run "$KIT_ROOT/scripts/status.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"WARN  alarm: xenia-llm-gateway-down is ALARM"* ]]
}

@test "--json is valid JSON with the same verdict" {
  run "$KIT_ROOT/scripts/status.sh" --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.status == "green" and (.items | length) >= 6' >/dev/null
}

@test "cost.sh prints services sorted by spend with a total" {
  run "$KIT_ROOT/scripts/cost.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Amazon Elastic Compute Cloud - Compute"*"12.50 USD"*"Amazon Bedrock"*"0.75 USD"*"TOTAL"*"13.25 USD"* ]]
  [[ "$output" != *"111111111"* ]]
}

@test "cost.sh explains the first-day Cost Explorer gap instead of failing" {
  FAKE_CE_ERROR=1 run "$KIT_ROOT/scripts/cost.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cost Explorer needs up to 24 hours after first enablement; open the Cost Explorer console once"* ]]
}
