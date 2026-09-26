#!/usr/bin/env bash
# Usage: scripts/ci/rule-feedback.sh [--all | --lines] <file|->
# Prints one "<slug><TAB><reason>" line per Rule-feedback line in a PR or issue body, in order.
# The shared regex (spec section 13), matched per line after stripping \r, at column 0 only, and never
# inside a fenced code block (lines between two lines that start with three backticks):
#   ^Rule-feedback:\s*(P-[a-z-]+|none)(?:,\s*(.+))?$
# "none" lines are omitted unless --all. A line that starts with "Rule-feedback:" but does not match is
# reported on stderr and skipped. --lines prints the normalized body instead (CR stripped, fenced blocks
# removed) so other line checks, such as the Shutdown: line in pr-template-check.yml, share the same
# normalization. Used by scripts/pain-review.sh and pr-template-check.yml.
# Exit 0 on readable input, 2 on usage.
# shellcheck disable=SC2016  # the fence pattern contains literal backticks on purpose
set -euo pipefail

mode=pairs
case "${1:-}" in
  --all) mode=all; shift ;;
  --lines) mode=lines; shift ;;
esac
[[ $# -eq 1 ]] || { echo "usage: $0 [--all | --lines] <file|->" >&2; exit 2; }
src="$1"
if [[ "$src" == "-" ]]; then
  src=/dev/stdin
elif [[ ! -r "$src" ]]; then
  echo "cannot read $src" >&2; exit 2
fi

# POSIX ERE form of the shared regex (bash has neither \s nor (?:...)).
re='^Rule-feedback:[[:space:]]*(P-[a-z-]+|none)(,[[:space:]]*(.+))?$'
fence='^[[:space:]]*```'
in_fence=0
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%$'\r'}"
  if [[ "$line" =~ $fence ]]; then in_fence=$((1 - in_fence)); continue; fi
  if (( in_fence )); then continue; fi
  if [[ "$mode" == lines ]]; then printf '%s\n' "$line"; continue; fi
  [[ "$line" == Rule-feedback:* ]] || continue
  if [[ "$line" =~ $re ]]; then
    slug="${BASH_REMATCH[1]}"
    reason="${BASH_REMATCH[3]}"
    reason="${reason%"${reason##*[![:space:]]}"}"
    if [[ "$slug" == none && "$mode" != all ]]; then continue; fi
    printf '%s\t%s\n' "$slug" "$reason"
  else
    printf 'ignored (not the shared format): %s\n' "$line" >&2
  fi
done < "$src"
