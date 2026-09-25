#!/usr/bin/env bash
# Probes On-Demand g6e.xlarge/g6e.2xlarge capacity in every us-east-1 AZ that offers them, without a
# human SSO session: it runs on the always-on Docker box, using the box's own instance role.
#
# EC2 only accepts a create-capacity-reservation request if it can actually place the instance, so
# create-a-1-instance-reservation-then-immediately-cancel-it is a truthful, side-effect-free capacity
# check that needs no running GPU instance. Every reservation this script creates is tagged
# kit=true, purpose=capacity-probe (iam.tf scopes Cancel and the tag-on-create to exactly that tag).
#
# Runs every 10 minutes as xenia-gpu-capacity-probe.timer (installed by install_capacity_probe in
# lib.sh, called from both user-data.sh and box/gateway.sh update). Logs one line per probe to
# stdout, which systemd captures in the journal, and also ships those same lines to the box's
# existing CloudWatch log group (/xenia/boxes): this is a plain systemd service, not a container, so
# it can't ride the box's default `awslogs` Docker log driver (user-data.sh's /etc/docker/daemon.json
# applies only to containers) — instead it calls `aws logs put-log-events` directly against the same
# log group, reusing the box role's existing ContainerLogs grant (iam.tf) rather than needing a
# CloudWatch agent. scripts/gpu.sh capacity-log reads it back.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/lib.sh"
load_box_env

region=us-east-1
# The capacity reservations this script probes only exist in us-east-1, but the CloudWatch log
# group it ships lines to (/xenia/boxes) lives in ca-central-1 (infra/platform, the kit's platform
# region) — a separate region from the EC2 calls above, so `logs` calls get their own region var
# instead of reusing $region.
log_region="${LOG_REGION:-ca-central-1}"
log_group=/xenia/boxes
log_stream=xenia-gpu-capacity-probe
types=(g6e.xlarge g6e.2xlarge)

aws_() { aws --region "$region" "$@"; }
logs_() { aws --region "$log_region" logs "$@"; }

declare -a log_buf=()

# probe_log <line>: stdout now (journald picks it up); buffered for a single CloudWatch shipment
# at exit, so one probe run's lines land as one small batch instead of one API call each.
probe_log() {
  local line
  line="[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"
  printf '%s\n' "$line"
  log_buf+=("$line")
}

ship_logs() {
  [[ ${#log_buf[@]} -gt 0 ]] || return 0
  # create-log-stream fails with ResourceAlreadyExistsException on every run after the first, which
  # is expected and not worth reporting; any other failure (permissions, wrong region, etc.) is
  # reported below instead of being swallowed into /dev/null.
  local create_out create_rc=0
  create_out="$(logs_ create-log-stream --log-group-name "$log_group" --log-stream-name "$log_stream" 2>&1)" || create_rc=$?
  if [[ "$create_rc" -ne 0 && "$create_out" != *ResourceAlreadyExistsException* ]]; then
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ALERT: could not create CloudWatch log stream ($log_group/$log_stream): $create_out" >&2
  fi
  local events="[]" now line
  now="$(($(date +%s) * 1000))"
  for line in "${log_buf[@]}"; do
    events="$(jq -c --arg m "$line" --argjson t "$now" '. + [{timestamp: $t, message: $m}]' <<< "$events")"
  done
  logs_ put-log-events --log-group-name "$log_group" --log-stream-name "$log_stream" \
    --log-events "$events" >/dev/null \
    || echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ALERT: could not ship probe log lines to CloudWatch ($log_group/$log_stream)" >&2
}
trap ship_logs EXIT

# sweep_existing: cancel any reservation this probe left behind (a prior run that crashed between
# create and cancel). If a cancel fails here, that is exactly the "cancel failed" ALERT case below.
sweep_existing() {
  local ids id
  ids="$(aws_ ec2 describe-capacity-reservations \
    --filters Name=tag:purpose,Values=capacity-probe Name=state,Values=active,pending \
    --query 'CapacityReservations[].CapacityReservationId' --output text)"
  [[ -n "$ids" && "$ids" != "None" ]] || return 0
  for id in $ids; do
    if aws_ ec2 cancel-capacity-reservation --capacity-reservation-id "$id" >/dev/null; then
      probe_log "swept stale reservation $id"
    else
      probe_log "ALERT: failed to cancel stale reservation $id"
      exit 1
    fi
  done
}

# probe_one <type> <az>: create a 1-instance reservation and cancel it right away. Logs AVAILABLE or
# NONE either way; a failed *cancel* (as opposed to a failed create, which just means no capacity)
# is the one failure this script treats as urgent.
probe_one() {
  local type="$1" az="$2" out id state
  if out="$(aws_ ec2 create-capacity-reservation \
        --instance-type "$type" --instance-platform "Linux/UNIX" --availability-zone "$az" \
        --instance-count 1 \
        --tag-specifications 'ResourceType=capacity-reservation,Tags=[{Key=kit,Value=true},{Key=purpose,Value=capacity-probe}]' \
        --query 'CapacityReservation.[CapacityReservationId,State]' --output text 2>&1)"; then
    read -r id state <<< "$out"
    probe_log "$type $az: AVAILABLE (reservation $id, $state)"
    if ! aws_ ec2 cancel-capacity-reservation --capacity-reservation-id "$id" >/dev/null; then
      probe_log "ALERT: failed to cancel reservation $id ($type $az)"
      exit 1
    fi
  else
    probe_log "$type $az: NONE ($(tr '\n' ' ' <<< "$out"))"
  fi
}

sweep_existing

for type in "${types[@]}"; do
  zones="$(aws_ ec2 describe-instance-type-offerings --location-type availability-zone \
    --filters Name=instance-type,Values="$type" --query 'InstanceTypeOfferings[].Location' --output text)"
  if [[ -z "$zones" || "$zones" == "None" ]]; then
    probe_log "$type: no zone in $region offers this type"
    continue
  fi
  for az in $zones; do
    probe_one "$type" "$az"
  done
done
