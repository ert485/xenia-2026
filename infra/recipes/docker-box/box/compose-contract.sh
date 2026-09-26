#!/usr/bin/env bash
# shellcheck shell=bash
# Compose checks shared by deploy.sh and preview-up.sh. Source it; don't execute it.

# check_compose_contract <compose-file>: the kit routes app. and pr-<n>.box. to a service named web
# (the team compose convention), so a compose file without a top-level web service can't be deployed.
check_compose_contract() {
  local f="${1:?usage: check_compose_contract <compose-file>}"
  [[ -f "$f" ]] || { echo "compose file not found: $f" >&2; return 1; }
  if awk -v q="'" '
    /^services:[[:space:]]*(#.*)?$/ { ins = 1; ind = 0; next }
    ins && /^[^[:space:]#]/ { ins = 0 }
    ins && /^[[:space:]]+[^[:space:]#]/ {
      match($0, /^[[:space:]]+/); w = RLENGTH
      if (ind == 0) ind = w
      if (w == ind) {
        name = substr($0, w + 1); sub(/:.*/, "", name); gsub(/"/, "", name); gsub(q, "", name)
        if (name == "web") found = 1
      }
    }
    END { exit found ? 0 : 1 }
  ' "$f"; then
    return 0
  fi
  echo "$f: needs a service named web (the kit routes app. and pr-<n>.box. to it; see templates/team-repo/compose.example.yml)" >&2
  return 1
}

# check_preview_isolation <compose-file> <project-dir>: refuse compose files that would escape the
# project or share a host namespace (spec section 9, D36). Reasons print one per line.
check_preview_isolation() {
  local compose="$1" project_dir="$2" checker
  checker="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/compose-check.py"
  python3 "$checker" "$compose" "$project_dir" \
    || die "preview refused: the compose file breaks the preview isolation rules listed above (spec section 9)"
}
