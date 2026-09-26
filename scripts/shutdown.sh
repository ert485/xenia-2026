#!/usr/bin/env bash
# Usage: scripts/shutdown.sh [--dry-run] [--offline]
#   Runs every shutdown.d/*.sh entry in the kit in file-name order, then the team repo's
#   ($TEAM_REPO_DIR/shutdown.d). Keeps going past failures; exits 1 at the end if any failed.
#   --dry-run  entries print what they would stop and change nothing (DRY_RUN=1)
#   --offline  CI mode: check headers and syntax and list what would run; runs nothing, no env file
#   SHUTDOWN_D overrides the kit directory (tests, and CI in a team repo).
# It stops only what has an entry. Check the billing console too; the AWS bill is yours.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

dry=0
offline=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry=1 ;;
    --offline) offline=1 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) die "unknown argument: $arg (use --dry-run or --offline)" ;;
  esac
done

kit_d="${SHUTDOWN_D:-$KIT_ROOT/shutdown.d}"
team_from_env="${TEAM_REPO_DIR:-}"
[[ "$offline" == 1 ]] || load_env
team_dir="${team_from_env:-${TEAM_REPO_DIR:-}}"

entries() { [[ -d "$1" ]] || return 0; find "$1" -maxdepth 1 -type f -name '*.sh' | LC_ALL=C sort; }

failures=""
nfail=0
count=0

check_dir() { # offline: headers (via the renderer), syntax, and the list
  local d="$1" f
  [[ -d "$d" ]] || return 0
  if ! "$KIT_ROOT/scripts/render-shutdown-md.sh" "$d" >/dev/null; then
    failures="$failures headers-in-$d"; nfail=$((nfail + 1))
  fi
  while read -r f; do
    [[ -n "$f" ]] || continue
    count=$((count + 1))
    if bash -n "$f"; then echo "would run: $f"; else failures="$failures $(basename "$f")"; nfail=$((nfail + 1)); fi
  done < <(entries "$d")
}

run_dir() { # online: run each entry, never stop early
  local d="$1" label="$2" f rc
  while read -r f; do
    [[ -n "$f" ]] || continue
    count=$((count + 1))
    echo "== $label/$(basename "$f")"
    set +e
    DRY_RUN="$dry" bash "$f" < /dev/null
    rc=$?
    set -e
    if [[ "$rc" == 0 ]]; then
      echo "ok"
    else
      echo "FAILED (exit $rc)"
      failures="$failures $label/$(basename "$f")"; nfail=$((nfail + 1))
    fi
  done < <(entries "$d")
}

if [[ "$offline" == 1 ]]; then check_dir "$kit_d"; else run_dir "$kit_d" kit; fi

if [[ -z "$team_dir" ]]; then
  echo "team repo skipped: TEAM_REPO_DIR unset"
elif [[ ! -d "$team_dir/shutdown.d" ]]; then
  echo "team repo skipped: $team_dir/shutdown.d not found"
elif [[ "$offline" == 1 ]]; then
  check_dir "$team_dir/shutdown.d"
else
  run_dir "$team_dir/shutdown.d" team
fi

mode="ran"; [[ "$offline" == 1 ]] && mode="checked"
if [[ "$nfail" -gt 0 ]]; then
  echo "shutdown: $count entries $mode, $nfail failed:$failures"
  exit 1
fi
echo "shutdown: $count entries $mode, 0 failed"
