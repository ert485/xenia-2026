#!/usr/bin/env bash
# Usage: shutdown-entry.sh <name> "<what it stops>" "<restore command>" "<cost when running>" "<stop command>"
# Writes shutdown.d/NN-<name>.sh in the kit's entry format (Appendix B), with NN the next free tens
# number from 40 up (10 to 30 are the kit's own). The stop command must succeed when the thing is
# already stopped. SHUTDOWN_DIR overrides the directory (tests).
set -euo pipefail
[[ $# -eq 5 ]] || { echo "usage: shutdown-entry.sh <name> \"<stops>\" \"<restore>\" \"<cost>\" \"<stop command>\"" >&2; exit 1; }
name="$1" stops="$2" restore="$3" cost="$4" stop_cmd="$5"
[[ "$name" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { echo "shutdown-entry: name must be lowercase letters, digits and dashes" >&2; exit 1; }
for v in "$stops" "$restore" "$cost" "$stop_cmd"; do
  [[ -n "$v" && "$v" != *$'\n'* ]] || { echo "shutdown-entry: every field is one non-empty line" >&2; exit 1; }
done

dir="${SHUTDOWN_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)/shutdown.d}"
mkdir -p "$dir"
max=30
for f in "$dir"/[0-9][0-9]-*.sh; do
  [[ -e "$f" ]] || continue
  n="$(basename "$f")"; n="${n%%-*}"; n=$((10#$n))
  (( n > max )) && max=$n
done
nn=$(( (max / 10 + 1) * 10 ))
out="$dir/$nn-$name.sh"
who="$(git config user.name 2>/dev/null || echo unknown)"

{
  printf '%s\n' '#!/usr/bin/env bash' '# xenia-shutdown'
  printf '# stops: %s\n# added-by: %s\n# restore: %s\n# cost-when-running: %s\n' "$stops" "$who" "$restore" "$cost"
  printf '%s\n' 'set -euo pipefail' ''
  # Written literally into the generated entry, not expanded here.
  # shellcheck disable=SC2016
  printf '%s\n' 'if [[ "${DRY_RUN:-0}" == "1" ]]; then'
  printf '  echo "would stop %s (see the stops: line above)"\n' "$name"
  printf '%s\n' '  exit 0' 'fi'
  printf '%s\n' "$stop_cmd"
  printf 'echo "stopped %s"\n' "$name"
} > "$out"
chmod +x "$out"
bash -n "$out"
echo "wrote $out"
echo "Teammate: commit it in the same PR as the billable change; the Shutdown: line is then not needed."
