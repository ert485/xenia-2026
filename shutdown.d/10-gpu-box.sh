#!/usr/bin/env bash
# xenia-shutdown
# stops: the GPU box (vLLM, g6e.xlarge) in us-east-1; the gateway fails over to Bedrock
# added-by: erik
# restore: scripts/gpu.sh start (weights stay on the volume)
# cost-when-running: about $1.86/hour
set -euo pipefail

profile="${GPU_PROFILE:-cohack}"
ids="$(aws ec2 describe-instances --profile "$profile" --region us-east-1 \
  --filters Name=tag:xenia-role,Values=gpu-box Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].InstanceId' --output text)"
if [[ -z "$ids" || "$ids" == "None" ]]; then
  echo "gpu box: nothing running"
  exit 0
fi
if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "would stop $ids (gpu box)"
  exit 0
fi
# I6 of the final review: the metrics-missing alarm treats a stopped box as breaching, so every run
# of this entry (from scripts/shutdown.sh, runbook 99, or scripts/teardown.sh) paged Erik and the
# night-shift phone about 10 minutes later unless scripts/gpu.sh stop (which disables these actions
# first) was used instead. Mirrors gpu.sh's own gpu_alarm_actions; never fatal — the off switch must
# still work even if this call fails, so only a warning naming the reason, never a die.
reason=""
if ! reason="$(aws cloudwatch disable-alarm-actions --region us-east-1 --profile "$profile" \
    --alarm-names xenia-gpu-box-unhealthy xenia-gpu-box-metrics-missing 2>&1)"; then
  echo "warning: could not disable the GPU alarms: $reason"
fi
# shellcheck disable=SC2086
aws ec2 stop-instances --instance-ids $ids --profile "$profile" --region us-east-1 >/dev/null
echo "stopped $ids (gpu box); the gateway serves from Bedrock until scripts/gpu.sh start"
