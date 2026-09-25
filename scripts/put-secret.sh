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
