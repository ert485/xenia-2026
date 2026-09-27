#!/usr/bin/env bash
# Wrapper so the kit's scripts/ directory has every command; the renderer lives in the plugin.
exec "$(cd "$(dirname "$0")/.." && pwd)/plugin/scripts/render-shutdown-md.sh" "$@"
