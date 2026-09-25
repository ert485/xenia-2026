#!/usr/bin/env bash
# Usage: scripts/status.sh [--json]
# What is running, in under a minute (spec section 8): kit instances in both regions, gateway health
# and the active backend, open previews, the newest backup, the gateway alarm, and the GPU box.
# One line per item, "ok" or "WARN"; exits 1 when any line is a WARN.
# shellcheck disable=SC2016,SC2329 # JMESPath backticks are literal; probe_* are called by name below
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
load_env
require_cmd aws curl jq python3
require_profile cohack "$MEMBER_ACCOUNT_ID"

json=0
[[ "${1:-}" == "--json" ]] && json=1
gateway="${GATEWAY_URL:-https://llm.26.cohack.tetl.ca}"
key_file="${XENIA_KEY_FILE:-$HOME/.xenia-erik-key}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

say() { printf '%s\t%s\n' "$1" "$2"; }
age() { # age <ISO-8601 time> -> "2d 3h" or "3h 12m"
  python3 -c '
import datetime, sys
t = datetime.datetime.fromisoformat(sys.argv[1].replace("Z", "+00:00"))
m = int((datetime.datetime.now(datetime.timezone.utc) - t).total_seconds()) // 60
h = m // 60
print(f"{h // 24}d {h % 24}h" if h >= 24 else f"{h}h {m % 60}m")' "$1"
}
age_hours() {
  python3 -c '
import datetime, sys
t = datetime.datetime.fromisoformat(sys.argv[1].replace("Z", "+00:00"))
print(int((datetime.datetime.now(datetime.timezone.utc) - t).total_seconds()) // 3600)' "$1"
}

gpu_profile="${GPU_PROFILE:-}"
if [[ -z "$gpu_profile" ]]; then
  gpu_profile="$(TF_NO_MASK=1 "$KIT_ROOT/scripts/tf.sh" recipes/gpu-box output -raw host_profile 2>/dev/null || true)"
  gpu_profile="${gpu_profile:-cohack}"
fi

instances_in() { # instances_in <region> <profile>
  local rows name type state launch role
  rows="$(aws ec2 describe-instances --region "$1" --profile "$2" \
    --filters Name=tag:kit,Values=true Name=instance-state-name,Values=pending,running,stopping,stopped \
    --query 'Reservations[].Instances[].[Tags[?Key==`Name`]|[0].Value,InstanceType,State.Name,LaunchTime,Tags[?Key==`xenia-role`]|[0].Value]' \
    --output text 2>/dev/null)" || { say WARN "instances: could not list $1 with profile $2"; return 0; }
  if [[ -z "$rows" ]]; then
    if [[ "$1" == ca-central-1 ]]; then say WARN "instances: no kit instances in $1"; else say ok "instances: none in $1 ($2)"; fi
    return 0
  fi
  while IFS="$(printf '\t')" read -r name type state launch role; do
    if [[ "$state" == running ]]; then
      say ok "instances: $name $type running, up $(age "$launch") ($1)"
    elif [[ "$role" == docker-box ]]; then
      say WARN "instances: $name $type $state ($1): the gateway, app, and previews are down (scripts/startup.sh)"
    else
      say ok "instances: $name $type $state ($1)"
    fi
  done <<< "$rows"
}

probe_instances() {
  instances_in ca-central-1 cohack
  instances_in us-east-1 cohack
  if [[ "$gpu_profile" != cohack ]]; then instances_in us-east-1 "$gpu_profile"; fi
}

probe_gateway() {
  local code backend
  code="$(curl -s -o /dev/null -w '%{http_code}' -m 10 "$gateway/health/readiness" || true)"
  if [[ "$code" == 200 ]]; then say ok "gateway: ready"; else say WARN "gateway: readiness returned ${code:-no answer}"; fi
  if [[ ! -f "$key_file" ]]; then
    say ok "gateway: no key at $key_file, completion probe skipped"
    return 0
  fi
  printf 'Authorization: Bearer %s\n' "$(tr -d '[:space:]' < "$key_file")" > "$tmp/auth"
  code="$(curl -sS -m 30 -D "$tmp/headers" -o /dev/null -w '%{http_code}' -H @"$tmp/auth" \
    -H 'Content-Type: application/json' "$gateway/v1/chat/completions" \
    -d '{"model":"qwen3-coder","max_tokens":4,"messages":[{"role":"user","content":"Reply with ok."}]}' 2>/dev/null || true)"
  backend="$(tr -d '\r' < "$tmp/headers" 2>/dev/null | awk -F': ' 'tolower($1) == "x-litellm-model-id" {print $2}' | tail -1)"
  if [[ "$code" == 200 ]]; then
    say ok "gateway: completion served by ${backend:-an unnamed backend}"
  else
    say WARN "gateway: 4-token completion returned ${code:-no answer}"
  fi
}

probe_previews() {
  local st names n
  if ! st="$("$KIT_ROOT/scripts/box.sh" xenia-gateway Action=status 2>/dev/null)"; then
    say WARN "previews: could not ask the Docker box over SSM"
    return 0
  fi
  names="$(printf '%s\n' "$st" | grep -oE 'pr-[0-9]+' | sort -u | tr '\n' ' ' | sed 's/ $//' || true)"
  n="$(printf '%s' "$names" | wc -w | tr -d ' ')"
  if [[ "$n" == 0 ]]; then say ok "previews: none"
  elif [[ "$n" -gt 3 ]]; then say WARN "previews: $n running (cap is 3): $names"
  else say ok "previews: $names"; fi
}

probe_backup() {
  local bucket row key stamp hours
  bucket="$(TF_NO_MASK=1 "$KIT_ROOT/scripts/tf.sh" platform output -raw backup_bucket 2>/dev/null || true)"
  [[ -n "$bucket" ]] || { say WARN "backup: no backup_bucket output from the platform stack"; return 0; }
  row="$(aws s3api list-objects-v2 --bucket "$bucket" --profile cohack --region ca-central-1 \
    --query 'sort_by(Contents,&LastModified)[-1].[Key,LastModified]' --output text 2>/dev/null || true)"
  if [[ -z "$row" || "$row" == None* ]]; then say WARN "backup: no dumps in the backup bucket yet"; return 0; fi
  key="${row%%$'\t'*}"; stamp="${row##*$'\t'}"
  hours="$(age_hours "$stamp")"
  key="$(basename "$(dirname "$key")")"
  if [[ "$hours" -ge 2 ]]; then say WARN "backup: newest dump $key is $(age "$stamp") old (hourly expected)"
  else say ok "backup: newest dump $key is $(age "$stamp") old"; fi
}

probe_alarm() {
  local state
  state="$(aws cloudwatch describe-alarms --alarm-names xenia-llm-gateway-down --region us-east-1 --profile cohack \
    --query 'MetricAlarms[0].StateValue' --output text 2>/dev/null || true)"
  if [[ "$state" == OK ]]; then say ok "alarm: xenia-llm-gateway-down is OK"
  else say WARN "alarm: xenia-llm-gateway-down is ${state:-missing}"; fi
}

probe_gpu() {
  local running detail
  running="$(aws ec2 describe-instances --region us-east-1 --profile "$gpu_profile" \
    --filters Name=tag:xenia-role,Values=gpu-box Name=instance-state-name,Values=running \
    --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null || true)"
  if [[ -z "$running" || "$running" == None ]]; then
    say ok "gpu: stopped (the gateway serves from Bedrock)"
    return 0
  fi
  if detail="$("$KIT_ROOT/scripts/gpu.sh" status 2>&1)"; then
    say ok "gpu: $(printf '%s' "$detail" | tr '\n' ';' | sed 's/;$//; s/;/; /g')"
  else
    say WARN "gpu: running but scripts/gpu.sh status failed: $(printf '%s' "$detail" | tail -1)"
  fi
}

probes="instances gateway previews backup alarm gpu"
i=0
for p in $probes; do
  i=$((i + 1))
  "probe_$p" > "$tmp/$i.$p" 2> "$tmp/$i.$p.err" &
done
wait
# Task 28 adds a seventh probe (untagged resources, the click-ops signal) after this line.

lines=""
i=0
for p in $probes; do
  i=$((i + 1))
  if [[ -s "$tmp/$i.$p" ]]; then lines="$lines$(cat "$tmp/$i.$p")"$'\n'
  else lines="$lines$(say WARN "$p: probe failed: $(tail -1 "$tmp/$i.$p.err" 2>/dev/null)")"$'\n'; fi
done

if printf '%s' "$lines" | grep -q '^WARN'; then verdict="check the WARN lines"; rc=1; else verdict="green"; rc=0; fi
if [[ "$json" == 1 ]]; then
  printf '%s' "$lines" | jq -Rn --arg status "$verdict" '[inputs | select(length > 0) | split("\t") | {level: .[0], text: .[1]}] | {items: ., status: $status}' | mask
else
  printf '%s' "$lines" | awk -F'\t' 'length($0) > 0 {printf "%-5s %s\n", $1, $2}' | mask
  echo "status: $verdict"
fi
exit "$rc"