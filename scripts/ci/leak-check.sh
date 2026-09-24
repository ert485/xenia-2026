#!/usr/bin/env bash
# Usage: scripts/ci/leak-check.sh [--allow-emails FILE] <path>...
# Exit 1 if any text file under the paths contains something that must never be public
# (P-public/site): a 12-digit number, an awsapps.com URL, a hosted-zone-shaped ID, a public IPv4
# address, a phone number, or an email not in the allow-list. Prints file:line: reason.
# A line containing "leak-check:ignore" is skipped. Exit 2 on usage error.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
allow="${LEAK_ALLOW_EMAILS:-$here/../../site/allowed-emails.txt}"
if [[ "${1:-}" == "--allow-emails" ]]; then allow="${2:?}"; shift 2; fi
[[ $# -gt 0 ]] || { echo "usage: $0 [--allow-emails FILE] <path>..." >&2; exit 2; }

files=()
for p in "$@"; do
  if [[ -d "$p" ]]; then
    while IFS= read -r f; do files+=("$f"); done < <(find "$p" -type f \( -name '*.md' -o -name '*.html' -o -name '*.yml' -o -name '*.yaml' -o -name '*.json' -o -name '*.txt' -o -name '*.sh' -o -name '*.tf' -o -name '*.env' -o -name '*.toml' \) -not -path '*/node_modules/*' -not -path '*/.terraform/*' | sort)
  elif [[ -f "$p" ]]; then
    files+=("$p")
  fi
done
[[ ${#files[@]} -gt 0 ]] || exit 0

status=0
# scan <file> <ERE> <reason> [<exclude-ERE>]
scan() {
  local hits
  hits="$(grep -nE -- "$2" "$1" | grep -v 'leak-check:ignore' || true)"
  if [[ -n "${4:-}" && -n "$hits" ]]; then hits="$(printf '%s\n' "$hits" | grep -vE -- "$4" || true)"; fi
  [[ -z "$hits" ]] && return 0
  printf '%s\n' "$hits" | cut -d: -f1 | while read -r n; do printf '%s:%s: %s\n' "$1" "$n" "$3"; done
  status=1
}

private_ip='(^|[^0-9])(10|127|0)\.[0-9]+\.[0-9]+\.[0-9]+|169\.254\.[0-9]+\.[0-9]+|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]+\.[0-9]+|192\.168\.[0-9]+\.[0-9]+|1\.1\.1\.1|8\.8\.8\.8|9\.9\.9\.9'

for f in "${files[@]}"; do
  scan "$f" '(^|[^0-9A-Za-z])[0-9]{12}([^0-9A-Za-z]|$)' '12-digit number (AWS account ID?)'
  scan "$f" '[A-Za-z0-9-]+\.awsapps\.com' 'awsapps.com URL (Identity Center portal)'
  scan "$f" '(^|[^A-Za-z0-9])Z[0-9A-Z]{13,32}([^A-Za-z0-9]|$)' 'hosted-zone-shaped ID'
  scan "$f" '(^|[^0-9.])([0-9]{1,3}\.){3}[0-9]{1,3}([^0-9.]|$)' 'IPv4 address' "$private_ip"
  scan "$f" '(^|[^0-9])(\+?1[-. ]?)?\(?[0-9]{3}\)?[-. ][0-9]{3}[-. ][0-9]{4}([^0-9]|$)' 'phone number'
  while read -r email; do
    [[ -z "$email" ]] && continue
    if [[ -f "$allow" ]] && grep -qixF -- "$email" "$allow"; then continue; fi
    n="$(grep -nF -- "$email" "$f" | grep -v 'leak-check:ignore' | head -1 | cut -d: -f1 || true)"
    [[ -z "$n" ]] && continue
    printf '%s:%s: email not on the allow-list: %s\n' "$f" "$n" "$email"
    status=1
  done < <(grep -ohE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$f" | sort -u || true)
done
exit "$status"
