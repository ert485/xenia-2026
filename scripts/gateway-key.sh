#!/usr/bin/env bash
# Usage:
#   scripts/gateway-key.sh generate <alias> <max_budget_usd> [member|ci]   prints the new key, once
#   scripts/gateway-key.sh revoke <alias>
#   scripts/gateway-key.sh list
# Talks to LiteLLM's key API on the Docker box's loopback port 4000 through an SSM port-forward
# (deviation 8), never through the public hostname. Needs session-manager-plugin.
# Test overrides: GATEWAY_API_BASE skips the tunnel, GATEWAY_MASTER_KEY skips the SSM read.
set -euo pipefail
# Monitor mode (job control) gives the background port-forward its own process group, so cleanup
# can kill session-manager-plugin along with the aws ssm start-session wrapper, instead of leaking it.
set -m
source "$(dirname "$0")/lib/common.sh"
require_cmd curl jq

usage() { die "usage: gateway-key.sh generate <alias> <max_budget_usd> [member|ci] | revoke <alias> | list"; }
action="${1:-}"; [[ -n "$action" ]] || usage; shift

alias_ok() { [[ "$1" =~ ^[a-z0-9][a-z0-9_-]{0,40}$ ]] || die "alias must be lowercase letters, digits, - or _ (got '$1')"; }
case "$action" in
  generate)
    [[ $# -ge 2 ]] || usage
    alias_ok "$1"
    [[ "$2" =~ ^[0-9]+(\.[0-9]+)?$ ]] || die "budget must be a number of USD (got '$2')"
    kind="${3:-member}"
    [[ "$kind" == member || "$kind" == ci ]] || die "kind must be member or ci"
    ;;
  revoke) [[ $# -ge 1 ]] || usage; alias_ok "$1" ;;
  list) ;;
  *) usage ;;
esac

tunnel=""
hdr="$(mktemp)"
cleanup() {
  rm -f "$hdr"
  if [[ -n "$tunnel" ]]; then
    # Negative pid signals the whole process group (set -m above put the tunnel in its own), so
    # session-manager-plugin (spawned by aws ssm start-session) dies too, not just the wrapper.
    kill -TERM -- "-$tunnel" 2>/dev/null || kill "$tunnel" 2>/dev/null || true
  fi
}
trap cleanup EXIT

api="${GATEWAY_API_BASE:-}"
key="${GATEWAY_MASTER_KEY:-}"
if [[ -z "$api" || -z "$key" ]]; then
  load_env
  require_cmd aws session-manager-plugin
  require_profile cohack "$MEMBER_ACCOUNT_ID"
fi
if [[ -z "$api" ]]; then
  port="${GATEWAY_LOCAL_PORT:-14000}"
  # Refuse to reuse a port something else is already listening on: the master key would otherwise be
  # sent straight to a foreign listener instead of the tunnel we think we opened.
  if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
    exec 3>&- 3<&-
    die "local port $port is already in use; refusing to open the tunnel there (set GATEWAY_LOCAL_PORT to another port)"
  fi
  iid="$(aws ec2 describe-instances --profile cohack --region ca-central-1 \
    --filters Name=tag:xenia-role,Values=docker-box Name=instance-state-name,Values=running \
    --query 'Reservations[].Instances[].InstanceId' --output text)"
  [[ -n "$iid" && "$iid" != "None" ]] || die "no running Docker box"
  aws ssm start-session --profile cohack --region ca-central-1 --target "$iid" \
    --document-name AWS-StartPortForwardingSession \
    --parameters "{\"portNumber\":[\"4000\"],\"localPortNumber\":[\"$port\"]}" >/dev/null 2>&1 &
  tunnel=$!
  api="http://127.0.0.1:$port"
  for i in $(seq 1 30); do
    curl -fsS -m 2 "$api/health/liveliness" >/dev/null 2>&1 && break
    [[ "$i" -eq 30 ]] && die "port-forward to the gateway did not come up (is session-manager-plugin installed?)"
    sleep 1
  done
fi
if [[ -z "$key" ]]; then
  key="$(aws ssm get-parameter --profile cohack --region ca-central-1 --name /xenia/gateway/master-key \
    --with-decryption --query Parameter.Value --output text)"
fi
chmod 0600 "$hdr"
printf 'Authorization: Bearer %s\n' "$key" > "$hdr"

call() { curl -fsS -m 30 -H @"$hdr" -H 'Content-Type: application/json' "$@"; }

case "$action" in
  generate)
    body="$(jq -nc --arg a "$1" --argjson b "$2" --arg k "$kind" '{
      key_alias: $a, max_budget: $b, budget_duration: "30d",
      rpm_limit: 120, tpm_limit: 400000, max_parallel_requests: 8,
      models: ["qwen3-coder", "qwen3-coder-bedrock"], metadata: {kind: $k}}')"
    call -X POST "$api/key/generate" -d "$body" | jq -er .key
    log "issued a key for '$1' (budget \$$2 per 30 days); send it by direct message, never in a channel"
    ;;
  revoke)
    tokens="$(call "$api/key/list?key_alias=$1&return_full_object=true" \
      | jq -c --arg a "$1" '[.keys[] | select(.key_alias == $a) | .token]')"
    [[ "$tokens" != "[]" ]] || die "no key with alias $1"
    call -X POST "$api/key/delete" -d "{\"keys\":$tokens}" >/dev/null
    log "revoked every key with alias $1"
    ;;
  list)
    # size=100: one page is enough for a hackathon-sized team; add pagination if that ever changes.
    call "$api/key/list?return_full_object=true&size=100" \
      | jq -r '.keys[] | "\(.key_alias)\tspend=\(.spend)\tbudget=\(.max_budget)"'
    ;;
esac
