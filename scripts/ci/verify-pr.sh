#!/usr/bin/env bash
# Usage: scripts/ci/verify-pr.sh <base-sha>
# Run from the root of the repo being checked (after actions/checkout with fetch-depth: 0), so the
# verifier judges that checkout. Resolves plugin/scripts/agent-verify.sh relative to this script,
# not to the working directory: in the kit itself that is this repo's own copy; in a team repo,
# where the workflow fetches the kit into .kit/, this script runs from .kit/scripts/ci/ and finds
# .kit/plugin/scripts/agent-verify.sh.
#
# make-check and uncommitted-changes are skipped: the check job already runs make check, and a
# fresh CI checkout is never dirty. proofs-unbacked is downgraded to a warning: CI has no
# .agent-requests/ (that only exists on the credential broker's Mac), so a human reviewing the PR
# reads the warning instead of the job blocking on it.
#
# VERIFY_EXTRA_ARGS, if set, is split on whitespace and appended after the flags above, so a
# caller can loosen a check further (e.g. team repos pass `--warn root-files`: they own their root
# layout) without this script hardcoding who gets which flags.
#
# Prints the verifier's stdout, then turns each blocked reason into a `::error` and each warning
# into a `::warning` workflow command (path = the message up to its first colon), and exits with
# the verifier's own exit code (0 pass, 1 blocked, 2 error) so the job fails on 1 or 2.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
kit_root="$(cd "$here/../.." && pwd)"
verifier="$kit_root/plugin/scripts/agent-verify.sh"
base="${1:?usage: verify-pr.sh <base-sha>}"

if [[ "$base" =~ ^0+$ ]]; then
  echo "verify-pr: base is the all-zeros SHA (a new branch's first push, or a push event with no prior commit); skipping"
  exit 0
fi

[[ -x "$verifier" ]] || { echo "verify-pr: no verifier at $verifier" >&2; exit 2; }

extra_args=()
if [[ -n "${VERIFY_EXTRA_ARGS:-}" ]]; then
  # shellcheck disable=SC2206 # intentional word-splitting of a space-separated flag string
  extra_args=(${VERIFY_EXTRA_ARGS})
fi

set +e
if [ "${#extra_args[@]}" -gt 0 ]; then
  out="$("$verifier" --base "$base" --skip make-check --skip uncommitted-changes --warn proofs-unbacked "${extra_args[@]}")"
else
  out="$("$verifier" --base "$base" --skip make-check --skip uncommitted-changes --warn proofs-unbacked)"
fi
rc=$?
set -e

printf '%s\n' "$out"

annotate() { # annotate <verifier-kind> <workflow-command>: e.g. blocked -> error, warning -> warning
  local kind="$1" gh_level="$2" line message path
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    message="$(printf '%s' "$line" | sed -E "s/^  $kind [^:]+: //")"
    path="${message%%:*}"
    printf '::%s file=%s::%s\n' "$gh_level" "$path" "$message"
  done < <(printf '%s\n' "$out" | grep -E "^  $kind ")
}

annotate blocked error
annotate warning warning

exit "$rc"
