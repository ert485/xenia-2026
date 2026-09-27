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

# _check_compose_isolation <project> <project-dir> <compose-file> [secret NAME=value ...]: shared by
# check_preview_isolation and check_deploy_isolation. Checks the RENDERED config
# (`docker compose ... config --format json`), not the raw YAML: Compose resolves ${VAR:-default}
# interpolation, a committed .env file, YAML anchors, extends and merges before using any value, so a
# raw-YAML check can be bypassed by any of those (spec section 9, D36; C2 of the final review). Any
# trailing NAME=value pairs are the app secrets, passed to `docker compose` the same way the real `up`
# gets them, so a compose file with a required variable (kriket's `${BETTER_AUTH_SECRET:?...}`) resolves
# here exactly as it would for the real deploy. Never the kit's own override file: that one is trusted
# and rendering it here would just make its `container_name`/network wiring reject itself.
_check_compose_isolation() {
  local project="$1" project_dir="$2" compose="$3"; shift 3
  local checker rendered rc=0
  checker="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/compose-check.py"
  rendered="$(mktemp "${TMPDIR:-/tmp}/xenia-compose-render.XXXXXX")"
  # Every command below is the condition of an if (not a bare statement followed by `rc=$?`):
  # under this script's `set -e`, a plain failing command exits the whole script immediately,
  # before `rc=$?` ever runs.
  if [[ "$#" -gt 0 ]]; then
    if ! env "$@" docker compose -p "$project" --project-directory "$project_dir" -f "$compose" config --format json >"$rendered"; then
      rm -f "$rendered"
      die "preview refused: the compose file could not be rendered (see compose's error above)"
    fi
  else
    if ! docker compose -p "$project" --project-directory "$project_dir" -f "$compose" config --format json >"$rendered"; then
      rm -f "$rendered"
      die "preview refused: the compose file could not be rendered (see compose's error above)"
    fi
  fi
  python3 "$checker" "$rendered" "$project_dir" || rc=$?
  rm -f "$rendered"
  [[ "$rc" -eq 0 ]] || die "preview refused: the compose file breaks the preview isolation rules listed above (spec section 9)"
}

# check_preview_isolation <project> <project-dir> <compose-file>: refuse compose files that would
# escape the project or share a host namespace (spec section 9, D36). Used by preview-up.sh.
check_preview_isolation() {
  _check_compose_isolation "$1" "$2" "$3"
}

# check_deploy_isolation <project-dir> <compose-file> [secret NAME=value ...]: the same isolation
# check as check_preview_isolation, run for the box's real "app" deploy project. Main self-merges
# once CI is green with no human review, so a real deploy needs the same refusal a preview gets —
# before this, deploy.sh ran no isolation check at all (C2 of the final review).
check_deploy_isolation() {
  local project_dir="$1" compose="$2"; shift 2
  _check_compose_isolation app "$project_dir" "$compose" "$@"
}
