#!/usr/bin/env bash
# Usage: scripts/put-secret.sh <name-under-/xenia/> [value]
#   printf 'sk-%s' "$(openssl rand -hex 32)" | scripts/put-secret.sh gateway/master-key
#   scripts/put-secret.sh app/STRIPE_KEY          # reads the value from stdin
# Writes an SSM SecureString in the member account (ca-central-1). The value never appears on a
# command line: it goes through a 0600 temp file.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
load_env
require_cmd aws

name="${1:?usage: scripts/put-secret.sh <name-under-/xenia/> [value]}"
[[ "$name" =~ ^(gateway|gpu|app)/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*$ ]] \
  || die "name must look like gateway/<x>, gpu/<x>, or app/<x> (the Docker box reads only those)"
# app/<NAME>: deploy.sh (infra/recipes/docker-box/box/lib.sh's apply_ssm_app_params) exports the
# part after the last "/" as an environment variable, so it must already be shaped like one, and
# must not be one deploy.sh, compose, or the shell already uses. Reject those here, before the
# value is ever written to SSM, instead of letting deploy.sh discover it at deploy time. Keep this
# deny-list in sync with lib.sh's _app_secret_reserved by hand — this script can't source a
# box-only file from the laptop.
if [[ "$name" == app/* ]]; then
  app_last="${name##*/}"
  [[ "$app_last" =~ ^[A-Z_][A-Z0-9_]*$ ]] \
    || die "app/$app_last: the part after the last '/' must be A-Z, 0-9, _ only, and not start with a digit — deploy.sh exports it as that name and can't otherwise"
  case "$app_last" in
    PATH|HOME|IFS|SHELL|BASH_ENV|ENV|PS4|PROMPT_COMMAND|IMAGE|GIT_SHA|ZONE) \
      die "app/$app_last: reserved — deploy.sh or the compose stack already uses that name; pick another" ;;
    LD_*|APP_*|HEALTH_*|KIT_*|BOX_*|XENIA_*|DOCKER_*|COMPOSE_*|AWS_*) \
      die "app/$app_last: reserved — deploy.sh or the compose stack already uses that name; pick another" ;;
  esac
fi
if [[ $# -ge 2 ]]; then value="$2"; else value="$(cat)"; fi
[[ -n "$value" ]] || die "empty value"
require_profile cohack "$MEMBER_ACCOUNT_ID"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
chmod 0600 "$tmp"
printf '%s' "$value" > "$tmp"
aws ssm put-parameter --profile cohack --region ca-central-1 --name "/xenia/$name" \
  --type SecureString --overwrite --value "file://$tmp" >/dev/null
log "stored /xenia/$name (SecureString)"
