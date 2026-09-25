#!/usr/bin/env bash
# xenia-shutdown
# stops: the Docker box (Caddy, LiteLLM gateway, demo app, previews) in ca-central-1
# added-by: erik
# restore: scripts/startup.sh
# cost-when-running: about $1.60/day
set -euo pipefail

profile="${KIT_PROFILE:-cohack}"
ids="$(aws ec2 describe-instances --profile "$profile" --region ca-central-1 \
  --filters Name=tag:xenia-role,Values=docker-box Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].InstanceId' --output text)"
if [[ -z "$ids" || "$ids" == "None" ]]; then
  echo "docker box: nothing running"
  exit 0
fi
if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "would stop $ids (docker box)"
  exit 0
fi
# shellcheck disable=SC2086
aws ec2 stop-instances --profile "$profile" --region ca-central-1 --instance-ids $ids >/dev/null
echo "stopped $ids (docker box); restore with scripts/startup.sh"
