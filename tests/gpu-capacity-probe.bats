#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# infra/recipes/docker-box/box/gpu-capacity-probe.sh (Task 7 follow-up problem 2): a create-then-
# cancel capacity reservation check for g6e capacity in us-east-1, run on the always-on Docker box.
setup() {
  export TMP="$BATS_TEST_TMPDIR"
  export SCRIPT="$BATS_TEST_DIRNAME/../infra/recipes/docker-box/box/gpu-capacity-probe.sh"
  export AWS_CALLS="$TMP/aws-calls"; : > "$AWS_CALLS"
  export XENIA_ENV_FILE="$TMP/xenia.env"
  printf 'ZONE=fake\nAPP_PORT=3000\nBACKUP_BUCKET=fake\nKIT_REPO=ert485/xenia-2026\nKIT_REF=main\n' > "$XENIA_ENV_FILE"
  cat > "$TMP/aws" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$AWS_CALLS"
case "$*" in
  *"ec2 describe-capacity-reservations"*)
    printf '%s\n' "${SWEEP_IDS-}"; exit 0 ;;
  *"ec2 describe-instance-type-offerings"*"g6e.xlarge"*)
    printf '%s\n' "${ZONES_XLARGE-us-east-1a}"; exit 0 ;;
  *"ec2 describe-instance-type-offerings"*"g6e.2xlarge"*)
    printf '%s\n' "${ZONES_2XLARGE-us-east-1a}"; exit 0 ;;
  *"ec2 create-capacity-reservation"*)
    if [[ "${AVAILABLE-1}" == "1" ]]; then
      printf 'cr-fake123\tactive\n'; exit 0
    else
      echo "InsufficientInstanceCapacity" >&2; exit 1
    fi
    ;;
  *"ec2 cancel-capacity-reservation"*)
    if [[ "${CANCEL_FAIL-0}" == "1" ]]; then exit 1; else exit 0; fi
    ;;
  *"logs create-log-stream"*) exit 0 ;;
  *"logs put-log-events"*) exit 0 ;;
esac
exit 0
EOF
  chmod +x "$TMP/aws"
  export PATH="$TMP:$PATH"
}

@test "capacity available: creates and cancels a reservation per type/zone, exits 0" {
  AVAILABLE=1 run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"g6e.xlarge us-east-1a: AVAILABLE (reservation cr-fake123, active)"* ]]
  [[ "$output" == *"g6e.2xlarge us-east-1a: AVAILABLE (reservation cr-fake123, active)"* ]]
  grep -q 'cancel-capacity-reservation --capacity-reservation-id cr-fake123' "$AWS_CALLS"
  grep -q -- '--region us-east-1' "$AWS_CALLS"
  grep -q 'logs put-log-events' "$AWS_CALLS"
}

@test "capacity none: no capacity logs NONE for each type/zone, exits 0" {
  AVAILABLE=0 run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"g6e.xlarge us-east-1a: NONE"* ]]
  [[ "$output" == *"g6e.2xlarge us-east-1a: NONE"* ]]
  ! grep -q 'cancel-capacity-reservation' "$AWS_CALLS"
}

@test "cancel failure during a probe: logs ALERT and exits non-zero" {
  AVAILABLE=1 CANCEL_FAIL=1 run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ALERT: failed to cancel reservation cr-fake123 (g6e.xlarge us-east-1a)"* ]]
}

@test "sweep at start: a stale reservation is cancelled before probing" {
  SWEEP_IDS=cr-stale1 AVAILABLE=1 run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"swept stale reservation cr-stale1"* ]]
  grep -q 'cancel-capacity-reservation --capacity-reservation-id cr-stale1' "$AWS_CALLS"
}

@test "sweep cancel failure: logs ALERT and exits non-zero before probing anything" {
  SWEEP_IDS=cr-stale1 CANCEL_FAIL=1 run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ALERT: failed to cancel stale reservation cr-stale1"* ]]
  ! grep -q 'describe-instance-type-offerings' "$AWS_CALLS"
}
