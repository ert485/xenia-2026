#!/usr/bin/env bash
# Usage: scripts/render-shutdown-md.sh [dir ...]
# Prints SHUTDOWN.md: one table row per shutdown.d entry, parsed from the Appendix B header, sorted
# by file name. Default dirs: the kit's shutdown.d, plus $TEAM_REPO_DIR/shutdown.d when set.
# Exits 1 naming the file and the field when a header is incomplete. Runs in CI: no env file needed.
set -euo pipefail
kit="$(cd "$(dirname "$0")/.." && pwd)"
if [[ $# -eq 0 ]]; then
  set -- "$kit/shutdown.d"
  if [[ -n "${TEAM_REPO_DIR:-}" && -d "$TEAM_REPO_DIR/shutdown.d" ]]; then set -- "$@" "$TEAM_REPO_DIR/shutdown.d"; fi
fi

list="$(for d in "$@"; do
  [[ -d "$d" ]] || continue
  find "$d" -maxdepth 1 -type f -name '*.sh' | while read -r f; do printf '%s\t%s\n' "$(basename "$f")" "$f"; done
done | LC_ALL=C sort)"

field() { head -n 8 "$1" | sed -n "s/^# $2:[[:space:]]*//p" | head -1; }
esc() { printf '%s' "$1" | sed 's/|/\\|/g'; }

bad=0
rows=""
while IFS="$(printf '\t')" read -r name path; do
  [[ -n "$name" ]] || continue
  if [[ "$(sed -n 2p "$path")" != "# xenia-shutdown" ]]; then
    echo "$path: line 2 must be '# xenia-shutdown' (see shutdown.d/README.md)" >&2; bad=1; continue
  fi
  row="| \`$name\`"
  for key in stops added-by restore cost-when-running; do
    value="$(field "$path" "$key")"
    if [[ -z "$value" ]]; then echo "$path: missing '# $key:' line (see shutdown.d/README.md)" >&2; bad=1; fi
    row="$row | $(esc "$value")"
  done
  rows="$rows$row |"$'\n'
done <<< "$list"
[[ "$bad" == 0 ]] || exit 1

echo "# Shutdown inventory"
echo
# shellcheck disable=SC2016 # the backticks are markdown, not command substitution
echo 'Rendered by `make shutdown-md`; CI fails a PR when this file is stale. `scripts/shutdown.sh` runs every entry below; `--dry-run` shows what it would do.'
echo
if [[ -z "$rows" ]]; then
  # shellcheck disable=SC2016
  echo 'No entries yet. Add one with `/shutdown-entry` (the header format is in `shutdown.d/README.md`).'
else
  echo "| Entry | Stops | Added by | Restore | Cost when running |"
  echo "|---|---|---|---|---|"
  printf '%s' "$rows"
fi
