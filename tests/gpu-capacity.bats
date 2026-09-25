#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# scripts/gpu.sh capacity/capacity-log (Task 7 follow-up problem 2): the human on-demand probe and
# the CloudWatch log reader.
setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export TMP="$BATS_TEST_TMPDIR"
  export AWS_CALLS="$TMP/aws-calls"; : > "$AWS_CALLS"
  cat > "$TMP/aws" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$AWS_CALLS"
case "$*" in
  *"ec2 describe-capacity-reservations"*)
    printf '%s\n' "${SWEEP_IDS-}"; exit 0 ;;
  *"ec2 describe-instance-type-offerings"*)
    printf '%s\n' "${ZONES-us-east-1a}"; exit 0 ;;
  *"ec2 create-capacity-reservation"*)
    if [[ "${AVAILABLE-1}" == "1" ]]; then printf 'cr-fake123\tactive\n'; exit 0; else exit 1; fi ;;
  *"ec2 cancel-capacity-reservation"*) exit 0 ;;
  *"logs filter-log-events"*)
    printf '%s\n' "${FAKE_LOG_LINES-}"; exit "${FILTER_EXIT-0}" ;;
esac
exit 0
EOF
  chmod +x "$TMP/aws"
  export PATH="$TMP:$PATH"
}

@test "capacity: probes both g6e types in the default region (us-east-1) with profile cohack" {
  run scripts/gpu.sh capacity
  [ "$status" -eq 0 ]
  [[ "$output" == *"g6e.xlarge us-east-1a: AVAILABLE"* ]]
  [[ "$output" == *"g6e.2xlarge us-east-1a: AVAILABLE"* ]]
  grep -q -- '--profile cohack' "$AWS_CALLS"
  grep -q -- '--region us-east-1' "$AWS_CALLS"
}

@test "capacity: an explicit region and a single type narrow the probe" {
  run scripts/gpu.sh capacity us-west-2 g6e.xlarge
  [ "$status" -eq 0 ]
  [[ "$output" == *"g6e.xlarge us-east-1a: AVAILABLE"* ]]
  [[ "$output" != *"g6e.2xlarge"* ]]
  grep -q -- '--region us-west-2' "$AWS_CALLS"
}

@test "capacity-log: prints the last n lines and a per-type/zone availability summary" {
  export FAKE_LOG_LINES=$'[2026-09-24T00:00:00Z] g6e.xlarge us-east-1a: AVAILABLE (reservation cr-1, active)\n[2026-09-24T00:10:00Z] g6e.xlarge us-east-1a: NONE (InsufficientInstanceCapacity)\n[2026-09-24T00:20:00Z] g6e.2xlarge us-east-1b: NONE (InsufficientInstanceCapacity)'
  run scripts/gpu.sh capacity-log
  [ "$status" -eq 0 ]
  [[ "$output" == *"g6e.xlarge us-east-1a: AVAILABLE"* ]]
  # The summary's column padding is cosmetic (printf %-24s); match the counts without pinning the
  # exact number of spaces, which is not portable to check character-by-character across awk builds.
  [[ "$output" == *"g6e.xlarge us-east-1a"*"1/2"* ]]
  [[ "$output" == *"g6e.2xlarge us-east-1b"*"0/1"* ]]
  grep -q 'xenia-gpu-capacity-probe' "$AWS_CALLS"
  # /xenia/boxes lives in ca-central-1 (infra/platform), not the us-east-1 EC2 capacity region
  grep -q -- '--profile cohack --region ca-central-1 logs filter-log-events' "$AWS_CALLS"
}

@test "capacity-log: no log lines yet is a clear error, not a silent empty summary" {
  FAKE_LOG_LINES="" run scripts/gpu.sh capacity-log
  [ "$status" -ne 0 ]
  [[ "$output" == *"no xenia-gpu-capacity-probe log lines found"* ]]
}
