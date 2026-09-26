#!/usr/bin/env bash
# /doctor: checks a teammate's setup in well under 30 seconds (every network call has a 10 s limit).
# Prints one line per check: "ok", "warn" (works, but something is missing), or "FAIL <check>: <hint>".
# Exit 1 if anything FAILed.
set -uo pipefail
fails=0
ok()   { printf 'ok    %s\n' "$1"; }
warn() { printf 'warn  %s: %s\n' "$1" "$2"; }
fail() { printf 'FAIL  %s: %s\n' "$1" "$2"; fails=$((fails + 1)); }

if gh auth status >/dev/null 2>&1; then ok "gh is logged in"
else fail "gh is logged in" "run gh auth login (Codespaces does this for you)"; fi

if [[ -n "$(git config user.name 2>/dev/null)" && -n "$(git config user.email 2>/dev/null)" ]]; then ok "git identity is set"
else fail "git identity is set" "git config --global user.name '<your name>' and user.email (your GitHub noreply address keeps your email private)"; fi

base="${ANTHROPIC_BASE_URL:-https://llm.26.cohack.tetl.ca}"
if [[ -z "${ANTHROPIC_AUTH_TOKEN:-}" ]]; then
  fail "gateway key" "paste your key into .devcontainer/ai.local.env or set the GATEWAY_KEY Codespaces secret, then open a new terminal"
elif curl -fsS -m 10 -H "Authorization: Bearer $ANTHROPIC_AUTH_TOKEN" "$base/v1/models" 2>/dev/null | jq -e '.data[] | select(.id == "qwen3-coder")' >/dev/null 2>&1; then
  ok "gateway answers with your key ($base)"
else
  fail "gateway answers with your key" "the key was refused or $base is unreachable; if the key leaked or expired, ask Erik for a new one by direct message"
fi

client="$(docker version --format '{{.Client.Version}}' 2>/dev/null | head -1 || true)"
if [[ -n "$client" ]]; then
  ok "docker client $client"
  docker info >/dev/null 2>&1 || warn "docker daemon" "none reachable from here; fine in the dev container (CI builds images, the box runs them)"
else
  fail "docker client" "the Docker CLI is missing; rebuild the dev container"
fi

if [[ -f Makefile ]]; then
  if make -n check >/dev/null 2>&1; then ok "make check is wired"
  else fail "make check is wired" "make -n check fails here; read the Makefile or run make check to see why"; fi
else
  warn "make check" "no Makefile in $(pwd); run /doctor from the repo root"
fi

if [[ -n "${DISCORD_WEBHOOK_URL:-}" ]]; then
  code="$(curl -s -o /dev/null -w '%{http_code}' -m 10 -X GET "$DISCORD_WEBHOOK_URL" || echo 000)"
  if [[ "$code" == "200" ]]; then ok "Discord webhook reachable"
  else fail "Discord webhook reachable" "HTTP $code; check the URL, and that discord.com is in the firewall allow-list"; fi
else
  warn "Discord webhook" "DISCORD_WEBHOOK_URL is not set, so /notify can't post"
fi

if command -v gitleaks >/dev/null 2>&1; then ok "gitleaks $(gitleaks version 2>/dev/null)"
else warn "gitleaks" "push protection covers provider keys; gitleaks missing means the sk- rule runs only in CI"; fi

if (( fails == 0 )); then echo "doctor: all green"; else echo "doctor: $fails problem(s) above"; exit 1; fi
