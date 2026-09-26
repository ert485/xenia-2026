#!/usr/bin/env bash
# Usage: scripts/lockdown.sh [--undo] [--dry-run]
# The access kill switch (spec D40). Attaches the break-glass SCP xenia-lockdown to the member account:
# every identity there is denied everything, sessions already issued included (teammates' 12-hour
# hackathon-dev sessions, agents running with them, and the deploy, preview, plan, and infra CI roles),
# except Erik's admin Identity Center role, OrganizationAccountAccessRole, and the kit box roles, so the
# gateway keeps answering.
# --undo detaches it. Idempotent. Runs as personal-admin: SCPs never apply to the management account,
# so the undo always works. Deliberately separate from shutdown.sh, which stops spend, not access.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
load_env
require_cmd aws jq

undo=0
dry=0
for a in "$@"; do
  case "$a" in
    --undo) undo=1 ;;
    --dry-run) dry=1 ;;
    *) die "unknown argument: $a (usage: scripts/lockdown.sh [--undo] [--dry-run])" ;;
  esac
done
require_profile personal-admin "$MANAGEMENT_ACCOUNT_ID"

org() { aws organizations "$@" --profile personal-admin --output json; }

policy_id="$(org list-policies --filter SERVICE_CONTROL_POLICY | jq -r '.Policies[] | select(.Name == "xenia-lockdown") | .Id')"
[[ -n "$policy_id" ]] || die "no SCP named xenia-lockdown yet: run scripts/tf.sh org apply first"
attached="$(org list-targets-for-policy --policy-id "$policy_id" \
  | jq -r --arg t "$MEMBER_ACCOUNT_ID" '[.Targets[] | select(.TargetId == $t)] | length')"

if [[ "$undo" == 0 ]]; then
  if [[ "$attached" != 0 ]]; then log "lockdown: already on (xenia-lockdown is attached to the member account)"; exit 0; fi
  if [[ "$dry" == 1 ]]; then log "lockdown: dry run: would attach xenia-lockdown to the member account"; exit 0; fi
  org attach-policy --policy-id "$policy_id" --target-id "$MEMBER_ACCOUNT_ID" >/dev/null
  log "lockdown: ON. Every identity in the member account is denied, live sessions included, except Erik's admin role, OrganizationAccountAccessRole, and the kit box roles. The gateway keeps serving. Undo: scripts/lockdown.sh --undo"
else
  if [[ "$attached" == 0 ]]; then log "lockdown: already off (xenia-lockdown is not attached)"; exit 0; fi
  if [[ "$dry" == 1 ]]; then log "lockdown: dry run: would detach xenia-lockdown from the member account"; exit 0; fi
  org detach-policy --policy-id "$policy_id" --target-id "$MEMBER_ACCOUNT_ID" >/dev/null
  log "lockdown: OFF. xenia-lockdown is detached; FullAWSAccess still applies, so access is as it was."
fi
