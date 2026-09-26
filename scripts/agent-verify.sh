#!/usr/bin/env bash
# Thin wrapper so `scripts/agent-verify.sh` works from the repo root; the real script lives
# under plugin/ so the dev container's seeded plugin carries it too.
exec "$(cd "$(dirname "$0")/.." && pwd)/plugin/scripts/agent-verify.sh" "$@"
