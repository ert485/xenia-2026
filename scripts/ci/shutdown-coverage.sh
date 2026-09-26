#!/usr/bin/env bash
# Usage: scripts/ci/shutdown-coverage.sh <base-sha> <head-sha> <pr-body-file>
# Run from the root of the repo being checked. The shutdown policy (spec section 8, charter C12):
# a PR whose diff touches infra/, .github/workflows/deploy*, or any compose file must also touch
# shutdown.d/, or carry a line "Shutdown: none needed because <reason>" at column 0 of its body,
# outside code fences (CR stripped). Always also checks every shutdown.d entry with bash -n and
# ShellCheck, then checks headers and lists entries via scripts/shutdown.sh --offline.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
base="${1:?usage: shutdown-coverage.sh <base-sha> <head-sha> <pr-body-file>}"
head="${2:?usage: shutdown-coverage.sh <base-sha> <head-sha> <pr-body-file>}"
body="${3:?usage: shutdown-coverage.sh <base-sha> <head-sha> <pr-body-file>}"
[[ -f "$body" ]] || { echo "no such body file: $body" >&2; exit 2; }

fence="$(printf '\140\140\140')"
# body_lines: the PR body with CR stripped and fenced blocks removed
body_lines() {
  tr -d '\r' < "$body" | awk -v fence="$fence" '
    { line = $0; sub(/^[ \t]+/, "", line) }
    index(line, fence) == 1 { infence = !infence; next }
    !infence { print }'
}

changed="$(git diff --name-only "$base...$head")"
billable="$(printf '%s\n' "$changed" | grep -E '^infra/|^\.github/workflows/deploy|(^|/)(docker-)?compose[^/]*\.ya?ml$' || true)"

# The PR template ships "Shutdown: none needed because <reason>"; an unedited placeholder is no reason.
line="$(body_lines | grep -E '^Shutdown:[[:space:]]*none needed because[[:space:]]+[^[:space:]].*$' | head -1 || true)"
reason="$(printf '%s' "$line" | sed -E 's/^Shutdown:[[:space:]]*none needed because[[:space:]]+//; s/[[:space:]]+$//')"
placeholder='^<.*>$'

status=0
if [[ -z "$billable" ]]; then
  echo "shutdown-coverage: nothing billable changed"
elif printf '%s\n' "$changed" | grep -qE '^shutdown\.d/'; then
  echo "shutdown-coverage: billable change covered by a shutdown.d/ change"
elif [[ -n "$line" ]] && ! [[ "$reason" =~ $placeholder ]]; then
  echo "shutdown-coverage: billable change covered by the Shutdown: line"
else
  if [[ -n "$line" ]]; then echo "shutdown-coverage: fill in the reason on the Shutdown: line (it still reads $reason)"; fi
  echo "shutdown-coverage: this PR changes something that can cost money:"
  printf '%s\n' "$billable" | sed 's/^/  /'
  echo
  echo "Policy (CONTRIBUTING, charter C12): a PR that adds or changes something billable must either touch that repo's shutdown.d/ or contain the line 'Shutdown: none needed because <reason>' in its body."
  echo "Teammate: add an off switch with /shutdown-entry, or put the line in the PR body at the start of a line (not indented, not inside a code block). Editing the body re-runs this check."
  status=1
fi

entries="$(find shutdown.d -maxdepth 1 -type f -name '*.sh' 2>/dev/null | LC_ALL=C sort || true)"
if [[ -n "$entries" ]]; then
  while read -r f; do bash -n "$f" || status=1; done <<< "$entries"
  command -v shellcheck >/dev/null || { echo "shellcheck is not installed" >&2; exit 2; }
  # shellcheck disable=SC2086 # entry paths come from find and contain no spaces
  shellcheck $entries || status=1
fi
SHUTDOWN_D="$PWD/shutdown.d" TEAM_REPO_DIR="" "$here/../shutdown.sh" --offline || status=1
exit "$status"
