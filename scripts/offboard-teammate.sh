#!/usr/bin/env bash
# Usage: scripts/offboard-teammate.sh <email> [--github <handle>]
# Reverses onboard-teammate.sh: removes the hackathon membership and the Identity Center user,
# revokes the gateway key, drops the ledger line, and with --github removes the handle's access to
# $TEAM_REPO. A code owner's CODEOWNERS line changes only by PR, approved by another owner.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
load_env
require_cmd aws

email="${1:?usage: offboard-teammate.sh <email> [--github <handle>]}"
shift
handle=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --github) handle="${2:?--github needs a handle}"; handle="${handle#@}"; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done
[[ -z "$handle" || "$handle" =~ ^[A-Za-z0-9-]+$ ]] || die "not a GitHub handle: $handle"

require_profile personal-admin "$MANAGEMENT_ACCOUNT_ID"
require_profile cohack "$MEMBER_ACCOUNT_ID"
ledger="${XENIA_LEDGER:-$HOME/.xenia/teammates.tsv}"
ids="$(TF_NO_MASK=1 "$KIT_ROOT/scripts/tf.sh" org output -raw identity_store_id)"
group="$(TF_NO_MASK=1 "$KIT_ROOT/scripts/tf.sh" org output -raw hackathon_group_id)"
idc() { aws identitystore "$@" --identity-store-id "$ids" --profile personal-admin --region ca-central-1; }

user_id="$(idc list-users --filters "AttributePath=UserName,AttributeValue=$email" --query 'Users[0].UserId' --output text)"
if [[ -n "$user_id" && "$user_id" != "None" ]]; then
  # Check if user is in the group, ignore errors if not found
  membership=$(idc get-group-membership-id --group-id "$group" --member-id "UserId=$user_id" --query MembershipId --output text 2>/dev/null) || :
  if [[ -n "$membership" ]]; then
    idc delete-group-membership --membership-id "$membership"
    log "removed from the hackathon group"
  fi
  idc delete-user --user-id "$user_id"
  log "deleted the Identity Center user (active sessions end within the hour)"
else
  log "no Identity Center user for that email"
fi

alias=""
[[ -f "$ledger" ]] && alias="$(awk -F'\t' -v e="$email" 'tolower($1) == tolower(e) {print $2}' "$ledger" | head -1)"
if [[ -n "$alias" ]]; then
  "$KIT_ROOT/scripts/gateway-key.sh" revoke "$alias"
  awk -F'\t' -v e="$email" 'tolower($1) != tolower(e)' "$ledger" > "$ledger.tmp" && mv "$ledger.tmp" "$ledger"
  log "revoked gateway key '$alias' and dropped the ledger line"
else
  log "no ledger line for that email: revoke the key by hand with scripts/gateway-key.sh list and revoke"
fi

if [[ -n "$handle" ]]; then
  require_cmd gh
  [[ -n "${TEAM_REPO:-}" ]] || die "set TEAM_REPO in kit.local.env to remove GitHub access"
  gh api -X DELETE "repos/$TEAM_REPO/collaborators/$handle"
  for inv in $(gh api "repos/$TEAM_REPO/invitations" --jq ".[] | select(.invitee.login == \"$handle\") | .id"); do
    gh api -X DELETE "repos/$TEAM_REPO/invitations/$inv"
  done
  log "removed $handle's access to $TEAM_REPO (and any pending invitation)"
  # Get CODEOWNERS file, ignore errors if it doesn't exist or can't be accessed
  owners="$(gh api "repos/$TEAM_REPO/contents/CODEOWNERS" --jq .content 2>/dev/null | base64 --decode 2>/dev/null || :) || :"
  if printf '%s\n' "$owners" | grep -qE "(^|[[:space:]])@$handle([[:space:]]|$)"; then
    echo "$handle is a code owner. The CODEOWNERS edit goes through a PR approved by another owner:"
    echo "  perl -pi -e 's/\\s\\@$handle(?=\\s|\$)//g' CODEOWNERS && git switch -c offboard-$handle && git commit -am 'Remove $handle from CODEOWNERS'"
  fi
fi