#!/usr/bin/env bash
# Usage: scripts/cost.sh
# Month-to-date and yesterday's spend for the member account, by service, from Cost Explorer
# (management account, profile personal-admin). Cost Explorer lags by up to a day and Budgets by
# several hours (spec section 8): this is a rear-view mirror; scripts/status.sh shows what runs now.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
load_env
require_cmd aws jq python3
require_profile personal-admin "$MANAGEMENT_ACCOUNT_ID"

read -r month_start yesterday today tomorrow < <(python3 -c '
import datetime
d = datetime.datetime.now(datetime.timezone.utc).date()
one = datetime.timedelta(days=1)
print(d.replace(day=1), d - one, d, d + one)')

filter="$(jq -nc --arg a "$MEMBER_ACCOUNT_ID" '{Dimensions: {Key: "LINKED_ACCOUNT", Values: [$a]}}')"
err="$(mktemp)"
trap 'rm -f "$err"' EXIT

ce() { # ce <start> <end> <granularity>
  aws ce get-cost-and-usage --profile personal-admin --region us-east-1 \
    --time-period "Start=$1,End=$2" --granularity "$3" --metrics UnblendedCost \
    --filter "$filter" --group-by Type=DIMENSION,Key=SERVICE --output json 2>"$err"
}

table() {
  jq -r '[.ResultsByTime[].Groups[] | {k: .Keys[0], v: (.Metrics.UnblendedCost.Amount | tonumber)}]
    | group_by(.k) | map({k: .[0].k, v: (map(.v) | add)}) | sort_by(-.v)
    | ((.[] | "\(.k)\t\(.v)"), "TOTAL\t\(map(.v) | add // 0)")' \
    | awk -F'\t' '{printf "  %-50s %10.2f USD\n", $1, $2}'
}

report() { # report <title> <start> <end> <granularity>
  local json
  if ! json="$(ce "$2" "$3" "$4")"; then
    if grep -q DataUnavailableException "$err"; then
      echo "Cost Explorer needs up to 24 hours after first enablement; open the Cost Explorer console once"
      exit 0
    fi
    cat "$err" >&2
    die "Cost Explorer query failed"
  fi
  echo "$1 ($2 to $3, end exclusive)"
  printf '%s' "$json" | table
  echo
}

report "Month to date, member account" "$month_start" "$tomorrow" MONTHLY
report "Yesterday, member account" "$yesterday" "$today" DAILY
echo "Cost Explorer lags by up to 24 hours and budget alerts by several hours; today's row is partial."
echo "Fixed rates of what is running now: SHUTDOWN.md. What is running now: scripts/status.sh."