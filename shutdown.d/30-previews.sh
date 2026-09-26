#!/usr/bin/env bash
# xenia-shutdown
# stops: all per-PR preview environments on the Docker box (ca-central-1)
# added-by: erik
# restore: reopen or push to the PR (preview-up.yml rebuilds it)
# cost-when-running: shares the Docker box (no extra cost)
set -euo pipefail
kit="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
profile="${KIT_PROFILE:-cohack}"

running="$(aws ec2 describe-instances --profile "$profile" --region ca-central-1 \
  --filters Name=tag:xenia-role,Values=docker-box Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].InstanceId' --output text)"
if [[ -z "$running" || "$running" == "None" ]]; then
  # 20-docker-box.sh runs first, so on a full shutdown the box is already stopped; the previews
  # stopped with it, and scripts/startup.sh removes them when the box comes back.
  echo "nothing running: the Docker box is stopped"
  exit 0
fi
if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "would stop all previews on $running (scripts/box.sh xenia-preview-down Pr=all)"
  exit 0
fi
"$kit/scripts/box.sh" xenia-preview-down Pr=all
