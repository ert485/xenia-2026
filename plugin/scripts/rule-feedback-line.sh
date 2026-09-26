#!/usr/bin/env bash
# Usage: rule-feedback-line.sh "<P-slug>, <what you did differently and why>" | "none"
# Validates one rule-feedback line against the shared regex (spec section 13)
#   ^Rule-feedback:\s*(P-[a-z-]+|none)(?:,\s*(.+))?$
# and prints it normalized ("Rule-feedback: P-slug, reason"). The "Rule-feedback:" prefix is optional
# in the input. Exit 1 with the reason on stderr when it does not match.
set -euo pipefail
in="${1-}"
in="${in//$'\r'/}"
if [[ "$in" == *$'\n'* ]]; then
  echo "rule-feedback: one line only (one exception per line)" >&2
  exit 1
fi
in="${in#"${in%%[![:space:]]*}"}"
in="${in%"${in##*[![:space:]]}"}"
[[ "$in" == Rule-feedback:* ]] || in="Rule-feedback: $in"

re='^Rule-feedback:[[:space:]]*(P-[a-z-]+|none)(,[[:space:]]*(.+))?$'
if [[ ! "$in" =~ $re ]]; then
  echo "rule-feedback: expected 'P-<slug>, <what you did differently and why>' with a lowercase slug such as P-two-gates, or 'none'" >&2
  exit 1
fi
slug="${BASH_REMATCH[1]}"
reason="${BASH_REMATCH[3]}"
if [[ -n "$reason" ]]; then
  printf 'Rule-feedback: %s, %s\n' "$slug" "$reason"
else
  printf 'Rule-feedback: %s\n' "$slug"
fi
