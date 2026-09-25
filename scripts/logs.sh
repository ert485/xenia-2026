#!/usr/bin/env bash
# Usage: scripts/logs.sh [name-substring] [--since 30m] [--follow]
# Container logs from the Docker box (CloudWatch group /xenia/boxes; one stream per container,
# named after it). Examples: scripts/logs.sh litellm; scripts/logs.sh pr-12 --since 2h;
# scripts/logs.sh app-web --follow. XENIA_PROFILE picks the AWS profile (default cohack; teammates
# use cohack-dev). Output goes through mask. Needs no kit.local.env.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
require_cmd aws

profile="${XENIA_PROFILE:-cohack}"
group=/xenia/boxes
since=30m
follow=0
name=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since) since="${2:?--since needs a value like 30m or 2h}"; shift 2 ;;
    --follow|-f) follow=1; shift ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) name="$1"; shift ;;
  esac
done

args=(logs tail "$group" --since "$since" --format short --profile "$profile" --region ca-central-1)
if [[ -n "$name" ]]; then
  streams="$(aws logs describe-log-streams --log-group-name "$group" --order-by LastEventTime --descending \
    --limit 50 --query 'logStreams[].logStreamName' --output text --profile "$profile" --region ca-central-1 | tr '\t' '\n')"
  matches="$(printf '%s\n' "$streams" | grep -F -- "$name" || true)"
  [[ -n "$matches" ]] || die "no recent log stream contains '$name'; recent streams: $(printf '%s\n' "$streams" | head -20 | tr '\n' ' ')"
  args+=(--log-stream-names)
  while read -r s; do args+=("$s"); done <<< "$matches"
fi
[[ "$follow" == 1 ]] && args+=(--follow)
aws "${args[@]}" | mask
