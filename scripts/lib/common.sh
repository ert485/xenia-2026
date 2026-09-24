#!/usr/bin/env bash
# Shared helpers for kit scripts. Source it; don't execute it.
# shellcheck shell=bash
set -euo pipefail

KIT_ROOT="${KIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
export KIT_ROOT

log() { printf '%s\n' "$*" >&2; }
die() { log "error: $*"; exit 1; }

# mask: replace 12-digit runs (AWS account IDs) on stdin so output is safe to paste.
mask() { sed -E 's/[0-9]{12}/<account-id>/g'; }

require_cmd() {
  local c
  for c in "$@"; do command -v "$c" >/dev/null 2>&1 || die "missing command: $c (see Task 1 of the plan, or 'make tools')"; done
}

# load_env: source kit.local.env (gitignored). KIT_ENV_FILE overrides the path; tests use that.
load_env() {
  local f="${KIT_ENV_FILE:-$KIT_ROOT/kit.local.env}"
  [[ -f "$f" ]] || die "missing $f (copy kit.local.env.example and fill it in)"
  set -a
  # shellcheck disable=SC1090
  source "$f"
  set +a
  : "${MEMBER_ACCOUNT_ID:?set MEMBER_ACCOUNT_ID in $f}"
  : "${MANAGEMENT_ACCOUNT_ID:?set MANAGEMENT_ACCOUNT_ID in $f}"
  : "${ZONE_ID:?set ZONE_ID in $f}"
}

# require_profile <profile> <expected-account-id>: refuse to run against the wrong account.
require_profile() {
  local profile="$1" expected="$2" actual
  actual="$(aws sts get-caller-identity --profile "$profile" --query Account --output text 2>/dev/null)" \
    || die "profile '$profile' is not logged in (run: aws sso login --sso-session personal)"
  [[ "$actual" == "$expected" ]] || die "profile '$profile' resolves to a different account than kit.local.env expects"
}
