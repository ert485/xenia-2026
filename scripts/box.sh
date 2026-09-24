#!/usr/bin/env bash
# Usage: scripts/box.sh <ssm-document> [Key=Value ...]
#   scripts/box.sh xenia-gateway Action=status
# Sends a kit SSM document to the Docker box (the running instance tagged xenia-role=docker-box),
# waits up to 15 minutes, prints stdout and stderr masked, and exits non-zero unless it succeeded.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
load_env
require_cmd aws jq

doc="${1:?usage: scripts/box.sh <ssm-document> [Key=Value ...]}"; shift
params='{}'
for kv in "$@"; do
  [[ "$kv" == *=* ]] || die "parameter '$kv' is not Key=Value"
  params="$(jq -c --arg k "${kv%%=*}" --arg v "${kv#*=}" '. + {($k): [$v]}' <<< "$params")"
done

require_profile cohack "$MEMBER_ACCOUNT_ID"
aws_() { aws --profile cohack --region ca-central-1 "$@"; }

iid="$(aws_ ec2 describe-instances \
  --filters Name=tag:xenia-role,Values=docker-box Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].InstanceId' --output text)"
[[ -n "$iid" && "$iid" != "None" ]] || die "no running Docker box (tag xenia-role=docker-box); scripts/startup.sh starts it"

cid="$(aws_ ssm send-command --instance-ids "$iid" --document-name "$doc" \
  --parameters "$params" --query Command.CommandId --output text)"
log "sent $doc to the Docker box (command $cid)"

poll="${BOX_POLL_SECONDS:-5}"
tries=180
st=Pending
for ((i = 0; i < tries; i++)); do
  st="$(aws_ ssm get-command-invocation --command-id "$cid" --instance-id "$iid" \
    --query Status --output text 2>/dev/null || echo Pending)"
  case "$st" in
    Pending|InProgress|Delayed) sleep "$poll" ;;
    *) break ;;
  esac
done

aws_ ssm get-command-invocation --command-id "$cid" --instance-id "$iid" \
  --query '[StandardOutputContent,StandardErrorContent]' --output text | mask
[[ "$st" == "Success" ]] || die "$doc ended with status $st"
log "$doc: Success"
