#!/usr/bin/env bash
# Usage: scripts/rotate-key.sh <alias|ci>
# Revokes a gateway key and issues a new one with the same budget, in one step (P-public/leak).
#   ci       the kit's CI key into GATEWAY_CI_KEY on ert485/xenia-2026, and, when TEAM_REPO is set,
#            the team repo's ci-<repo-name> key into that repo's GATEWAY_CI_KEY
#   <alias>  a teammate's key; the new key prints once, for a direct message
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
load_env
require_profile cohack "$MEMBER_ACCOUNT_ID"

target="${1:?usage: rotate-key.sh <alias|ci>}"
keys="$KIT_ROOT/scripts/gateway-key.sh"
budget_of() { "$keys" list | awk -F'\t' -v a="$1" '$1 == a {sub(/^budget=/, "", $3); print $3}' | head -1; }

rotate_ci() { # rotate_ci <alias> <owner/repo>
  local b key
  require_cmd gh
  b="$(budget_of "$1")"
  "$keys" revoke "$1"
  key="$("$keys" generate "$1" "${b:-10}" ci)"
  [[ -n "$key" ]] || die "no key came back for $1"
  printf '%s' "$key" | gh secret set GATEWAY_CI_KEY --repo "$2"
  log "rotated '$1' and updated GATEWAY_CI_KEY on $2"
}

if [[ "$target" == "ci" ]]; then
  rotate_ci ci ert485/xenia-2026
  if [[ -n "${TEAM_REPO:-}" ]]; then rotate_ci "ci-${TEAM_REPO##*/}" "$TEAM_REPO"; fi
else
  b="$(budget_of "$target")"
  [[ -n "$b" ]] || die "no key with alias '$target' (see scripts/gateway-key.sh list)"
  "$keys" revoke "$target"
  key="$("$keys" generate "$target" "$b" member)"
  echo "Erik: send this to the teammate by direct message, never in a channel."
  echo "Teammate: your new gateway key (the old one no longer works): $key"
fi
echo "P-public/leak: if this rotation follows a leak, say so in Discord (no blame), then fix the path that leaked it, once."
