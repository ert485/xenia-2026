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
# shellcheck disable=SC2086
aws ec2 stop-instances --instance-ids $ids --profile "$profile" --region us-east-1 >/dev/null
echo "stopped $ids (gpu box); the gateway serves from Bedrock until scripts/gpu.sh start"
