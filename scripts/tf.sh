#!/usr/bin/env bash
# Usage: scripts/tf.sh <stack> <terraform args...>
#   <stack> is a directory under infra/: org | platform | recipes/docker-box | recipes/gpu-box | recipes/static-site | examples/kit-site
# Runs terraform in that directory with the shared backend config (infra/backend.local.hcl) and
# TF_VAR_* values from kit.local.env. Output is masked (12-digit numbers) unless TF_NO_MASK=1 or the
# command is interactive (apply, destroy, import, console).
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
load_env
require_cmd terraform aws

stack="${1:?usage: scripts/tf.sh <stack> <terraform args>}"; shift
dir="$KIT_ROOT/infra/$stack"
[[ -d "$dir" ]] || die "no such stack directory: $dir"
backend="$KIT_ROOT/infra/backend.local.hcl"

export TF_VAR_member_account_id="$MEMBER_ACCOUNT_ID"
export TF_VAR_management_account_id="$MANAGEMENT_ACCOUNT_ID"
export TF_VAR_zone_id="$ZONE_ID"
export TF_VAR_alert_email="${ALERT_EMAIL:-}"
export TF_VAR_alert_sms="${ALERT_SMS:-}"
export TF_VAR_team_repo="${TEAM_REPO:-}"
if [[ -f "$backend" ]]; then
  TF_VAR_state_bucket="$(awk -F'"' '/^bucket/ {print $2}' "$backend")"
  export TF_VAR_state_bucket
fi

case "$stack" in
  org) require_profile personal-admin "$MANAGEMENT_ACCOUNT_ID"; tf_profile=personal-admin ;;
  *)   require_profile cohack "$MEMBER_ACCOUNT_ID"; tf_profile=cohack ;;
esac

# Terraform 1.5.7's S3 backend uses the old AWS SDK, which can't read sso-session-style profiles
# (only the aws provider, v6, handles those); export short-lived credentials instead so the
# backend can authenticate. Never echoed: creds is only ever eval'd, not printed. Captured into a
# variable first (not `eval "$(...)"` directly) because under set -e, eval of a failed command
# substitution still returns 0 — that would fail open and run terraform with ambient credentials
# on an expired SSO session.
creds="$(aws configure export-credentials --profile "$tf_profile" --format env)" \
  || die "could not export credentials for profile $tf_profile (run: aws sso login --sso-session personal)"
[[ -n "$creds" ]] || die "could not export credentials for profile $tf_profile (run: aws sso login --sso-session personal)"
eval "$creds"

cmd="${1:-}"
args=("$@")
if [[ "$cmd" == "init" ]]; then
  [[ -f "$backend" ]] || die "no $backend: run scripts/bootstrap.sh first"
  key="$(printf '%s' "$stack" | tr '/' '-').tfstate"
  args=(init -backend-config="$backend" -backend-config="key=$key" "${@:2}")
fi

case "$cmd" in
  apply|destroy|import|console) terraform -chdir="$dir" "${args[@]}" ;;
  *)
    if [[ "${TF_NO_MASK:-0}" == "1" ]]; then
      terraform -chdir="$dir" "${args[@]}"
    else
      terraform -chdir="$dir" "${args[@]}" 2>&1 | mask
      exit "${PIPESTATUS[0]}"
    fi ;;
esac
