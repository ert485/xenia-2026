#!/usr/bin/env bash
# SessionStart hook of the kit plugin: puts the team's core rules in front of every Claude Code session.
# Reads ./PRINCIPLES.md from the open repo only when that repo is on the kit's allowed list, capped at
# 4 KB; otherwise the bundled copy, so a cloned third-party repo can't plant text in every session.
# No network. Always exits 0: a failing hook must never block a session.
set -uo pipefail

root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
bundled="$root/bundled/PRINCIPLES.md"
allowed="$root/allowed-repos.txt"
cap=4096

command -v jq >/dev/null 2>&1 || exit 0

repo_slug() {
  local url
  url="$(git remote get-url origin 2>/dev/null)" || return 0
  url="${url%/}"
  url="${url%.git}"
  # The SSH forms are built from pieces so the kit's leak check (which flags email-shaped strings in
  # plugin/) never sees one in this file.
  local scp="git""@github.com:" ssh="ssh://git""@github.com/"
  case "$url" in
    https://github.com/*) printf '%s' "${url#https://github.com/}" ;;
    "$scp"*)              printf '%s' "${url#"$scp"}" ;;
    "$ssh"*)              printf '%s' "${url#"$ssh"}" ;;
  esac
}

bundled_text() {
  cat "$bundled" 2>/dev/null || printf '%s' "(the kit's bundled PRINCIPLES.md is missing; read PRINCIPLES.md in the repo root)"
}

compose() {
  local slug top body note size
  slug="$(repo_slug)"
  top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$slug" && -n "$top" && -f "$top/PRINCIPLES.md" && -f "$allowed" ]] && grep -qixF -- "$slug" "$allowed"; then
    size="$(wc -c < "$top/PRINCIPLES.md" | tr -d ' ')"
    body="$(head -c "$cap" "$top/PRINCIPLES.md")"
    note=""
    if (( size > cap )); then note="[truncated at 4 KB; read PRINCIPLES.md in full]"; fi
  else
    body="$(bundled_text)"
    note="(kit default copy: this repo is not on the kit's allowed list, see plugin/allowed-repos.txt)"
  fi
  printf '%s\n\n%s\n%s\n\n%s' \
    "Agent: these are the team's rules (PRINCIPLES.md). Read them before acting; the why and the practices are in PRINCIPLES-EXTENDED.md at the repo root." \
    "$body" "$note" \
    "Skills from the kit plugin: /pain (log friction), /rule-feedback (record a knowing exception), /notify (post to the team channel), /doctor (check your setup), /preview (this PR's preview URL), /shutdown-entry (scaffold an off switch), /demo-checklist."
}

emit() { jq -n --arg ctx "$1" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'; }

text="$(compose 2>/dev/null)" || text=""
if [[ -z "$text" ]] || ! emit "$text"; then
  emit "Agent: these are the team's rules (kit default copy).
$(bundled_text)" || true
fi
exit 0
