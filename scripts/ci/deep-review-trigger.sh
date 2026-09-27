#!/usr/bin/env bash
# Usage: SAMPLE=<repo var> LABELS=<pr labels> PR=<pr number> ACTION=<event action>
#        ADDED_LABEL=<label just added, if any> EXISTING_DEEP_REVIEW_COMMENT=<current deep-review
#        comment body, if any> scripts/ci/deep-review-trigger.sh <base-sha> <head-sha>
# Run from the root of the repo being checked (like scripts/ci/shutdown-coverage.sh); in team repos
# the workflow runs the kit's copy from .kit/ the same way the other kit scripts do.
#
# Decides whether a PR gets the deep review (component 7: a slower, wider, Bash-permitted rerun of
# the PR reviewer). Prints exactly one line, "run=true reason=<why>" or "run=false reason=<why>",
# and exits 0 either way. Exits 2 on bad input: missing or malformed arguments, a PR that isn't a
# positive integer when one is needed, or a SAMPLE value that is none of empty/unset, "all", or a
# positive integer.
#
# Rules, first match wins:
#   1. ACTION is "labeled" and ADDED_LABEL isn't
#      "deep-review"                                        -> false (label-mismatch)
#   2. EXISTING_DEEP_REVIEW_COMMENT carries a hidden
#      "xenia-deep-review-sha:<sha>" marker matching head    -> false (already-reviewed): once per
#                                                                head SHA, so a stale label event or
#                                                                a second push to the same head
#                                                                doesn't re-run it
#   3. LABELS contains "deep-review"                        -> true (label)
#   4. a changed path starts with infra/, .github/,
#      templates/ or scripts/ (first such path, in diff
#      order)                                               -> true (risky-path <path>)
#   5. SAMPLE is empty, unset, or "all"                      -> true (sample all)
#   6. SAMPLE is a positive integer N                        -> true when PR % N == 0, else false
#                                                                (sample 1-in-N)
#   7. anything else in SAMPLE                               -> exit 2
set -euo pipefail

usage() { echo "usage: SAMPLE=... LABELS=... PR=... deep-review-trigger.sh <base-sha> <head-sha>" >&2; }

base="${1:-}"
head="${2:-}"
if [[ -z "$base" || -z "$head" ]]; then
  usage
  exit 2
fi

sha_re='^[0-9a-fA-F]{7,40}$'
if ! [[ "$base" =~ $sha_re ]] || ! [[ "$head" =~ $sha_re ]]; then
  echo "deep-review-trigger: base and head must each be 7-40 hex characters" >&2
  exit 2
fi

SAMPLE="${SAMPLE:-}"
LABELS="${LABELS:-}"
PR="${PR:-}"
ACTION="${ACTION:-}"
ADDED_LABEL="${ADDED_LABEL:-}"
EXISTING_DEEP_REVIEW_COMMENT="${EXISTING_DEEP_REVIEW_COMMENT:-}"

# Rule 1: a labeled event for any label other than deep-review is not a trigger by itself. Other
# rules (a sticky deep-review label from earlier, a risky path, sample-all) can still fire below;
# this only stops an unrelated label (e.g. needs-triage) from being treated as one.
if [[ "$ACTION" == "labeled" && "$ADDED_LABEL" != "deep-review" ]]; then
  echo "run=false reason=label-mismatch"
  exit 0
fi

# Rule 2: once per head SHA. A deep-review comment already posted for this exact head sha means
# nothing new to add, regardless of what triggered this run.
existing_sha="$(printf '%s\n' "$EXISTING_DEEP_REVIEW_COMMENT" \
  | sed -nE 's/^<!-- xenia-deep-review-sha:([0-9a-fA-F]{7,40}) -->$/\1/p' | head -n1)"
if [[ -n "$existing_sha" && "$existing_sha" == "$head" ]]; then
  echo "run=false reason=already-reviewed"
  exit 0
fi

# Rule 3: the deep-review label, comma- or newline-separated, trimmed.
labels_normalized="$(printf '%s' "$LABELS" | tr ',' '\n')"
while IFS= read -r label; do
  label="$(printf '%s' "$label" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  if [[ "$label" == "deep-review" ]]; then
    echo "run=true reason=label"
    exit 0
  fi
done <<< "$labels_normalized"

# Rule 4: a risky changed path. git diff --name-only lists paths in tree order; the first one
# under a risky prefix is "the first matching path".
changed="$(git diff --name-only "$base...$head")"
if [[ -n "$changed" ]]; then
  while IFS= read -r path; do
    case "$path" in
      infra/*|.github/*|templates/*|scripts/*)
        echo "run=true reason=risky-path $path"
        exit 0
        ;;
    esac
  done <<< "$changed"
fi

# Rule 5: no sampling configured yet, or explicitly "all".
if [[ -z "$SAMPLE" || "$SAMPLE" == "all" ]]; then
  echo "run=true reason=sample all"
  exit 0
fi

# Rule 6: a positive integer sample rate.
int_re='^[1-9][0-9]*$'
if [[ "$SAMPLE" =~ $int_re ]]; then
  if ! [[ "$PR" =~ $int_re ]]; then
    echo "deep-review-trigger: PR must be a positive integer (got: '$PR')" >&2
    exit 2
  fi
  if (( PR % SAMPLE == 0 )); then
    echo "run=true reason=sample 1-in-$SAMPLE"
  else
    echo "run=false reason=sample 1-in-$SAMPLE"
  fi
  exit 0
fi

# Rule 7: anything else in SAMPLE is bad input.
echo "deep-review-trigger: SAMPLE must be empty, 'all', or a positive integer (got: '$SAMPLE')" >&2
exit 2
