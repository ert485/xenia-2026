#!/usr/bin/env bash
# Every minute (xenia-vllm-watchdog.timer): restart vLLM after three consecutive failed /health probes.
# Skips the first 30 minutes after the container starts, so a first-boot weights download is never
# interrupted. docker's restart policy covers crashes; this covers a hung server.
set -euo pipefail
state=/run/xenia/watchdog-fails
mkdir -p /run/xenia
recipe="$(cd "$(dirname "$0")" && pwd)"
container=vllm-vllm-1

started="$(docker inspect -f '{{.State.StartedAt}}' "$container" 2>/dev/null || true)"
if [[ -z "$started" ]]; then
  echo "watchdog: $container not found"
  exit 0
fi
age=$(( $(date +%s) - $(date -d "$started" +%s) ))
if (( age < 1800 )); then
  echo 0 > "$state"
  exit 0
fi
if curl -fsk -m 10 -o /dev/null https://localhost:8443/health; then
  echo 0 > "$state"
  exit 0
fi
fails=$(( $(cat "$state" 2>/dev/null || echo 0) + 1 ))
echo "$fails" > "$state"
echo "watchdog: /health failed ($fails in a row)"
if (( fails >= 3 )); then
  echo "watchdog: restarting vllm"
  (cd "$recipe" && docker compose restart vllm)
  echo 0 > "$state"
fi
