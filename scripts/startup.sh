#!/usr/bin/env bash
# Usage: scripts/startup.sh [--no-gpu]
# Reverses scripts/shutdown.sh for the reversible entries: starts the Docker box, rewrites the
# gateway's runtime env (it lives on tmpfs under /run/xenia and is gone after a stop), removes any
# previews that restarted with the box (previews are ephemeral: a push to the PR rebuilds one), then
# starts the GPU box with scripts/gpu.sh start unless --no-gpu.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
load_env
require_cmd aws
require_profile cohack "$MEMBER_ACCOUNT_ID"

no_gpu=0
for arg in "$@"; do
  case "$arg" in
    --no-gpu) no_gpu=1 ;;
    *) die "unknown argument: $arg (use --no-gpu)" ;;
  esac
done

aws_box() { aws "$@" --profile cohack --region ca-central-1; }

stopped="$(aws_box ec2 describe-instances \
  --filters Name=tag:xenia-role,Values=docker-box Name=instance-state-name,Values=stopped,stopping \
  --query 'Reservations[].Instances[].InstanceId' --output text)"
if [[ -n "$stopped" && "$stopped" != "None" ]]; then
  log "starting the Docker box"
  # shellcheck disable=SC2086 # instance IDs never contain spaces
  aws_box ec2 wait instance-stopped --instance-ids $stopped
  # shellcheck disable=SC2086
  aws_box ec2 start-instances --instance-ids $stopped >/dev/null
  # shellcheck disable=SC2086
  aws_box ec2 wait instance-running --instance-ids $stopped
  first="${stopped%%[[:space:]]*}"
  for _ in $(seq 1 60); do
    ping="$(aws_box ssm describe-instance-information --filters "Key=InstanceIds,Values=$first" \
      --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null || true)"
    [[ "$ping" == "Online" ]] && break
    sleep 5
  done
  [[ "$ping" == "Online" ]] || die "the Docker box is running but not online in SSM after five minutes; check scripts/status.sh"
  "$KIT_ROOT/scripts/box.sh" xenia-gateway Action=restart
  "$KIT_ROOT/scripts/box.sh" xenia-preview-down Pr=all
else
  log "Docker box: already running (or not created)"
fi

if [[ "$no_gpu" == 0 ]]; then
  "$KIT_ROOT/scripts/gpu.sh" start
fi
echo "run scripts/status.sh in five minutes"
