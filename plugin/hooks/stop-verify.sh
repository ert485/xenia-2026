#!/usr/bin/env bash
# Stop hook of the kit plugin: judges "done" by running the verifier (Task 32's
# plugin/scripts/agent-verify.sh), never by the agent's own report -- this hook never reads
# REPORT.md. Blocks the stop until the verifier passes, up to three attempts per session
# (counted in .agent/stop-attempts-<session_id>, gitignored); the fourth stop lets the run end
# with a systemMessage instead, so a human or the harness reads .agent/STATUS.json. Always exits
# 0: this hook itself must never wedge a session.
set -uo pipefail
# XENIA_VERIFY_ARGS is only ever word-split below, never glob-expanded against this process's cwd.
set -f

payload="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  printf '{"systemMessage":"BLOCKED: jq is missing, so the Stop hook could not run the verifier; nothing here has been checked."}\n'
  exit 0
fi

cwd="$(jq -r '.cwd // empty' <<<"$payload" 2>/dev/null)" || cwd=""
session_id="$(jq -r '.session_id // empty' <<<"$payload" 2>/dev/null)" || session_id=""
[[ -n "$cwd" && -d "$cwd" ]] || exit 0
session_id="${session_id:-nosession}"

# Not inside a git worktree, or the worktree has no commits yet: exit 0 silently.
worktree_root="$(cd "$cwd" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[[ -n "$worktree_root" ]] || exit 0
git -C "$worktree_root" rev-parse HEAD >/dev/null 2>&1 || exit 0

root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
verifier="$root/scripts/agent-verify.sh"
counter="$worktree_root/.agent/stop-attempts-$session_id"

if [[ ! -x "$verifier" ]]; then
  jq -n --arg v "$verifier" \
    '{systemMessage: ("Agent: the Stop hook could not find the verifier (" + $v + "); nothing here has been checked. Ask a human to check the plugin install; CI still runs the same checks.")}'
  exit 0
fi

extra_args=()
if [[ -n "${XENIA_VERIFY_ARGS:-}" ]]; then
  # A teammate-provided flag string, meant to be split on whitespace (for example --skip make-check).
  # shellcheck disable=SC2206
  extra_args=( $XENIA_VERIFY_ARGS )
fi

if [ "${#extra_args[@]}" -gt 0 ]; then
  verify_out="$("$verifier" --worktree "$cwd" "${extra_args[@]}" 2>&1)"
else
  verify_out="$("$verifier" --worktree "$cwd" 2>&1)"
fi
verify_status=$?

if [[ "$verify_status" -eq 0 ]]; then
  rm -f "$counter"
  exit 0
fi

mkdir -p "$(dirname "$counter")"
prior=0
if [[ -f "$counter" ]]; then
  prior="$(cat "$counter" 2>/dev/null || echo 0)"
  [[ "$prior" =~ ^[0-9]+$ ]] || prior=0
fi

if [[ "$prior" -ge 3 ]]; then
  printf '{"systemMessage":"BLOCKED: the verifier still fails after 3 attempts; .agent/STATUS.json has the reasons. Nothing here is done."}\n'
  exit 0
fi

attempt=$((prior + 1))
echo "$attempt" > "$counter"
reason="Agent: the verifier says this work is not done (attempt $attempt of 3). Fix every reason below, then finish again. Do not edit .agent/ or docs/proofs/, and do not weaken a check or a test to get past it.
$verify_out"
jq -n --arg reason "$reason" '{decision: "block", reason: $reason}'
exit 0
