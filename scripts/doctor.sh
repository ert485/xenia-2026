#!/usr/bin/env bash
# Wrapper so the kit's scripts/ directory has every command; the checks live in the plugin.
exec "$(cd "$(dirname "$0")/.." && pwd)/plugin/scripts/doctor.sh" "$@"
