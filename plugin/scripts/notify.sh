#!/usr/bin/env bash
# Usage: notify.sh "<message>"
# Posts one line to the team channel's Discord webhook as the agent (P-comms). Refuses anything that
# looks like a key or an environment dump (P-public/agents). Mentions are disabled.
set -euo pipefail
msg="${1:-}"
[[ -n "$msg" ]] || { echo "notify: usage: notify.sh \"<message>\"" >&2; exit 1; }

key_re='sk-[A-Za-z0-9_-]{20,}'
if [[ "$msg" =~ $key_re ]]; then
  echo "notify: refused: the message contains something that looks like a gateway key (P-public). If a key leaked, rotate it: scripts/rotate-key.sh" >&2
  exit 1
fi
if grep -qE '^[A-Z_]+=' <<< "$msg"; then
  echo "notify: refused: the message looks like an environment dump (NAME=value lines)" >&2
  exit 1
fi
if (( ${#msg} > 1900 )); then
  echo "notify: refused: over 1900 characters; post a summary and link the issue or PR instead" >&2
  exit 1
fi
if [[ -z "${DISCORD_WEBHOOK_URL:-}" ]]; then
  echo "notify: DISCORD_WEBHOOK_URL is not set. Teammate: add it as a Codespaces secret, or as DISCORD_WEBHOOK_URL=... in .devcontainer/ai.local.env, then open a new terminal" >&2
  exit 1
fi

url="$(git remote get-url origin 2>/dev/null || true)"
url="${url%.git}"
repo="${url##*/}"
[[ -n "$repo" ]] || repo="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"
who="$(git config user.name 2>/dev/null || echo unknown)"
body="$(jq -nc --arg c "[agent · $repo · $who] $msg" '{content: $c, allowed_mentions: {parse: []}}')"
curl -fsS -m 10 -H 'Content-Type: application/json' -d "$body" "$DISCORD_WEBHOOK_URL" >/dev/null
echo "notify: posted"
