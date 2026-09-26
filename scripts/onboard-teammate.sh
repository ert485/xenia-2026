#!/usr/bin/env bash
# Usage: scripts/onboard-teammate.sh <email> <first> <last> [--budget 30]
# Creates the teammate's Identity Center user (the invitation email carries a one-time code), adds
# them to the hackathon group, issues their gateway key, and prints one block for Erik to send by
# direct message. Idempotent: a second run for the same email creates nothing and issues no key.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
load_env
require_cmd aws jq

email="${1:?usage: onboard-teammate.sh <email> <first> <last> [--budget 30]}"
first="${2:?usage: onboard-teammate.sh <email> <first> <last> [--budget 30]}"
last="${3:?usage: onboard-teammate.sh <email> <first> <last> [--budget 30]}"
shift 3
budget=30
while [[ $# -gt 0 ]]; do
  case "$1" in
    --budget) budget="${2:?--budget needs a number of USD}"; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done
[[ "$email" == *@*.* ]] || die "not an email address: $email"
[[ "$budget" =~ ^[0-9]+$ ]] || die "--budget must be whole USD"

require_profile personal-admin "$MANAGEMENT_ACCOUNT_ID"
require_profile cohack "$MEMBER_ACCOUNT_ID"

ledger="${XENIA_LEDGER:-$HOME/.xenia/teammates.tsv}"
mkdir -p "$(dirname "$ledger")"
touch "$ledger"
chmod 600 "$ledger"

ids="$(TF_NO_MASK=1 "$KIT_ROOT/scripts/tf.sh" org output -raw identity_store_id)"
group="$(TF_NO_MASK=1 "$KIT_ROOT/scripts/tf.sh" org output -raw hackathon_group_id)"
idc() { aws identitystore "$@" --identity-store-id "$ids" --profile personal-admin --region ca-central-1; }

user_id="$(idc list-users --filters "AttributePath=UserName,AttributeValue=$email" --query 'Users[0].UserId' --output text)"
if [[ -z "$user_id" || "$user_id" == "None" ]]; then
  user_id="$(idc create-user --user-name "$email" --display-name "$first $last" \
    --name "$(jq -nc --arg g "$first" --arg f "$last" '{GivenName: $g, FamilyName: $f}')" \
    --emails "$(jq -nc --arg e "$email" '[{Value: $e, Type: "work", Primary: true}]')" \
    --query UserId --output text)"
  log "created the Identity Center user; AWS sends the invitation email with a one-time code now"
else
  log "Identity Center user already exists"
fi

if idc get-group-membership-id --group-id "$group" --member-id "UserId=$user_id" >/dev/null 2>&1; then
  log "already in the hackathon group"
else
  idc create-group-membership --group-id "$group" --member-id "UserId=$user_id" >/dev/null
  log "added to the hackathon group (permission set hackathon-dev on the member account)"
fi

alias="$(awk -F'\t' -v e="$email" 'tolower($1) == tolower(e) {print $2}' "$ledger" | head -1)"
key=""
if [[ -n "$alias" ]]; then
  echo "already onboarded; use scripts/rotate-key.sh $alias for a new key"
else
  alias="$(printf '%s' "$first" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')"
  [[ -n "$alias" ]] || alias="teammate"
  if cut -f2 "$ledger" | grep -qx -- "$alias"; then
    alias="$alias-$(printf '%s' "$last" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9' | cut -c1)"
  fi
  key="$("$KIT_ROOT/scripts/gateway-key.sh" generate "$alias" "$budget")"
  printf '%s\t%s\t%s\n' "$email" "$alias" "$(date -u +%F)" >> "$ledger"
fi

portal="https://${ids}.awsapps.com/start"
cat <<EOF

Erik: this block holds the member account ID and a key. Send it to $first by direct message, never in a channel.
----------------------------------------------------------------------------------------------------
Teammate: two things for the weekend.

1. Your gateway key (alias "$alias", budget \$$budget). Paste it into .devcontainer/ai.local.env as
   ANTHROPIC_AUTH_TOKEN=<key>, or add it as the Codespaces user secret GATEWAY_KEY. Keep it private;
   if it ever leaks, say so in Discord and it gets rotated. No blame.
   ${key:-(no new key: you were already onboarded; ask Erik for scripts/rotate-key.sh $alias)}

2. AWS access, optional (the console, or a CLI loop on your own machine). Accept the AWS invitation
   email (it has a one-time code), set a password and MFA, then add this to ~/.aws/config:

[sso-session cohack]
sso_start_url = $portal
sso_region = ca-central-1
sso_registration_scopes = sso:account:access

[profile cohack-dev]
sso_session = cohack
sso_account_id = $MEMBER_ACCOUNT_ID
sso_role_name = hackathon-dev
region = ca-central-1

   Then: aws sso login --sso-session cohack. Any agent you run with that session inherits near-admin
   reach, which is why agents in the dev container get no AWS credentials by default.
----------------------------------------------------------------------------------------------------
EOF