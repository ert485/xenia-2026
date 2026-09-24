#!/usr/bin/env bash
# Stops the demo app compose project (project name "app"). Volumes are kept, so the next deploy finds
# its database again. Used Friday evening to tear down the example (spec section 15).
set -euo pipefail
source "$(dirname "$0")/lib.sh"
if docker compose ls --all --format json | jq -e '.[] | select(.Name == "app")' >/dev/null; then
  docker compose -p app down --remove-orphans
  log "app: stopped (volumes kept)"
else
  log "app: not running"
fi
