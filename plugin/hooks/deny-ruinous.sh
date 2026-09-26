#!/usr/bin/env bash
# PreToolUse hook of the kit plugin (matcher Bash|Write|Edit|MultiEdit|NotebookEdit): denies a
# short, fixed list of ruinous commands before they run. Never asks: an allowed call prints
# nothing and exits 0; a denied call prints a PreToolUse deny whose reason starts
# "deny-ruinous <rule>:" and says what to do instead. This is a guardrail against the obvious, not
# a sandbox -- the egress firewall and the absence of deploy credentials in the dev container are
# the real boundary, and everything not listed below is allowed.
set -uo pipefail
# Word-splitting on a command string (below) must never also glob-expand it against this
# process's real cwd -- a literal `*` or `?` in a scanned argument must stay literal text.
set -f

payload="$(cat)"

deny() {
  local rule="$1" why="$2"
  jq -n --arg reason "deny-ruinous $rule: $why" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
  exit 0
}

# jq missing: fail closed only for what can still be told apart without it (a raw grep on the
# payload text), per the plugin's hook contract. Everything else is allowed rather than guessed at.
if ! command -v jq >/dev/null 2>&1; then
  if grep -q '"tool_name"[[:space:]]*:[[:space:]]*"Bash"' <<<"$payload" 2>/dev/null \
     || grep -q '"tool_name"[[:space:]]*:[[:space:]]*"Write"' <<<"$payload" 2>/dev/null; then
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"deny-ruinous: jq missing, cannot inspect the call"}}\n'
  fi
  exit 0
fi

tool_name="$(jq -r '.tool_name // empty' <<<"$payload" 2>/dev/null)" || tool_name=""
cwd="$(jq -r '.cwd // empty' <<<"$payload" 2>/dev/null)" || cwd=""

# Rule force-push: a Bash command force-pushing over shared history. Incident: the container-first
# plan's no-force-push rule and a teammate's report on 2026-09-25 of an agent doing something
# destructive despite its settings.
check_force_push() {
  local cmd="$1" tok
  [[ "$cmd" == *"git push"* ]] || return 1
  [[ "$cmd" == *"--force"* ]] && return 0     # covers --force and --force-with-lease
  [[ "$cmd" == *"--mirror"* ]] && return 0
  [[ "$cmd" == *"--delete"* ]] && return 0
  for tok in $cmd; do
    case "$tok" in
      -f|-fu|-uf) return 0 ;;
      +*) return 0 ;;  # a refspec starting with +
      :*) return 0 ;;  # a refspec starting with :
    esac
    if [[ "$tok" == -* && "$tok" != --* && "$tok" == *f* ]]; then
      return 0  # -f inside a short-flag cluster, in any order
    fi
  done
  return 1
}

# Rule delete-workspace: rm -r of the workspace root or something that resolves to it, or a git
# clean that also flushes ignored/untracked files (which would destroy the verifier's own output).
# Incident: same as force-push.
strip_rm_target() {
  local t="$1"
  case "$t" in
    /) : ;;  # the bare root: stripping the trailing / would leave an empty string
    */\*) t="${t%/\*}" ;;
    */.) t="${t%/.}" ;;
    */) t="${t%/}" ;;
  esac
  if [[ "$t" == \"*\" && "${#t}" -ge 2 ]]; then t="${t:1:${#t}-2}"; fi
  if [[ "$t" == \'*\' && "${#t}" -ge 2 ]]; then t="${t:1:${#t}-2}"; fi
  printf '%s' "$t"
}

is_dangerous_rm_target() {
  local target="$1" cwd="$2" worktree
  # These are matched as literal, unexpanded text (the raw command string may contain a token
  # such as "$HOME" or "${XENIA_ROOT}" that was never actually expanded by a real shell).
  # shellcheck disable=SC2016
  case "$target" in
    /|/workspace|'~'|'$HOME'|'${HOME}'|.|..|'*'|'$XENIA_ROOT'|'${XENIA_ROOT}') return 0 ;;
  esac
  if [[ -n "$cwd" ]]; then
    [[ "$target" == "$cwd" ]] && return 0
    worktree="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
    [[ -n "$worktree" && "$target" == "$worktree" ]] && return 0
  fi
  return 1
}

check_recursive_rm() {
  local cmd="$1" cwd="$2" tok has_recursive=0 target
  [[ "$cmd" == *"rm "* ]] || return 1
  for tok in $cmd; do
    [[ "$tok" == "--recursive" ]] && has_recursive=1
  done
  if [[ "$has_recursive" -eq 0 ]]; then
    for tok in $cmd; do
      case "$tok" in
        --*) continue ;;
        -*) [[ "$tok" == *r* || "$tok" == *R* ]] && has_recursive=1 ;;
      esac
    done
  fi
  [[ "$has_recursive" -eq 1 ]] || return 1
  for tok in $cmd; do
    case "$tok" in
      rm|-*) continue ;;
    esac
    target="$(strip_rm_target "$tok")"
    is_dangerous_rm_target "$target" "$cwd" && return 0
  done
  return 1
}

check_git_clean() {
  local cmd="$1" tok combined=""
  [[ "$cmd" == *"git clean"* ]] || return 1
  for tok in $cmd; do
    case "$tok" in
      --force) combined+="f" ;;
      --*) continue ;;
      -*) combined+="${tok#-}" ;;
    esac
  done
  [[ "$combined" == *f* && ( "$combined" == *x* || "$combined" == *X* ) ]]
}

# Rule firewall: editing the egress firewall scripts or sudoers, or a Bash command that rewrites
# or flushes the firewall/iptables rules. Incident: the container's egress firewall is the only
# thing between an agent and the internet.
is_firewall_path() {
  local p="$1" base="${1##*/}"
  case "$base" in
    init-firewall.sh|refresh-firewall.sh) return 0 ;;
  esac
  case "$p" in
    /etc/sudoers.d/*) return 0 ;;
  esac
  return 1
}

check_firewall_bash() {
  local cmd="$1"
  [[ "$cmd" == *"init-firewall.sh"* || "$cmd" == *"refresh-firewall.sh"* || "$cmd" == *"iptables"* \
     || "$cmd" == *"ip6tables"* || "$cmd" == *"ipset"* || "$cmd" == *"/etc/sudoers"* ]] || return 1
  [[ "$cmd" =~ sed[[:space:]]+-i ]] && return 0
  [[ "$cmd" == *">"* ]] && return 0
  [[ "$cmd" == *"tee"* ]] && return 0
  [[ "$cmd" == *"cp"* ]] && return 0
  [[ "$cmd" == *"mv"* ]] && return 0
  [[ "$cmd" == *"rm"* ]] && return 0
  [[ "$cmd" == *"chmod"* ]] && return 0
  [[ "$cmd" == *"-F"* ]] && return 0
  [[ "$cmd" == *"-X"* ]] && return 0
  [[ "$cmd" == *"-P"* ]] && return 0
  [[ "$cmd" == *"flush"* ]] && return 0
  [[ "$cmd" == *"destroy"* ]] && return 0
  [[ "$cmd" == *"-D"* ]] && return 0
  return 1
}

# Shared by rules proofs and verifier-output: is a path under the given directory, resolved
# relative to cwd (a plain relative path) or matched anywhere in an absolute path.
is_under_dir() {
  local p="$1" needle="$2"
  case "$p" in
    "$needle"/*) return 0 ;;
    */"$needle"/*) return 0 ;;
  esac
  return 1
}

# Verbs shared by rules proofs and verifier-output: the ways a Bash command can write or remove a
# path, short of a full shell parse.
has_write_verb() {
  local cmd="$1"
  [[ "$cmd" =~ sed[[:space:]]+-i ]] && return 0
  [[ "$cmd" == *">"* ]] && return 0
  [[ "$cmd" == *"tee"* ]] && return 0
  [[ "$cmd" == *"cp"* ]] && return 0
  [[ "$cmd" == *"mv"* ]] && return 0
  [[ "$cmd" == *"touch"* ]] && return 0
  [[ "$cmd" == *"rm"* ]] && return 0   # also catches "git rm"
  return 1
}

check_bash() {
  local cmd="$1" cwd="$2"
  check_force_push "$cmd" && deny force-push \
    "a force push rewrites shared history; push a normal commit, or file a .agent-requests/ request if history really needs rewriting"
  check_recursive_rm "$cmd" "$cwd" && deny delete-workspace \
    "a recursive delete of the workspace root (or something that resolves to it) is not allowed; delete a specific subpath, or file a .agent-requests/ request"
  check_git_clean "$cmd" && deny delete-workspace \
    "git clean with -f and -x/-X destroys ignored and untracked files, including the verifier's own output; run git clean -n to preview first, or file a .agent-requests/ request"
  check_firewall_bash "$cmd" && deny firewall \
    "the egress firewall is the boundary between this container and the internet; ask the human, or file a .agent-requests/ request"
  # Rule proofs: proof files (docs/proofs/) are written only from real command output. Incident:
  # Task 15's fabricated proof, 2026-09-25.
  if [[ "$cmd" == *"docs/proofs"* ]] && has_write_verb "$cmd"; then
    deny proofs "proof files are written only from real command output; file a .agent-requests/ request instead"
  fi
  # Rule verifier-output: the verifier's own verdict is not the agent's to edit or forge.
  # Incident: an agent that can write .agent/STATUS.json can forge its own pass.
  if [[ "$cmd" == *".agent/"* ]] && has_write_verb "$cmd"; then
    deny verifier-output "the verifier's own verdict is not yours to edit; fix the reasons and let it re-run"
  fi
  return 0
}

check_write_path() {
  local p="$1"
  is_firewall_path "$p" && deny firewall \
    "the egress firewall is the boundary between this container and the internet; ask the human, or file a .agent-requests/ request"
  is_under_dir "$p" "docs/proofs" && deny proofs \
    "proof files are written only from real command output; file a .agent-requests/ request instead"
  is_under_dir "$p" ".agent" && deny verifier-output \
    "the verifier's own verdict is not yours to edit; fix the reasons and let it re-run"
  return 0
}

case "$tool_name" in
  Bash)
    command_str="$(jq -r '.tool_input.command // empty' <<<"$payload" 2>/dev/null)" || command_str=""
    [[ -n "$command_str" ]] || exit 0
    check_bash "$command_str" "$cwd"
    ;;
  Write|Edit|MultiEdit)
    file_path="$(jq -r '.tool_input.file_path // empty' <<<"$payload" 2>/dev/null)" || file_path=""
    [[ -n "$file_path" ]] || exit 0
    check_write_path "$file_path"
    ;;
  NotebookEdit)
    notebook_path="$(jq -r '.tool_input.notebook_path // empty' <<<"$payload" 2>/dev/null)" || notebook_path=""
    [[ -n "$notebook_path" ]] || exit 0
    check_write_path "$notebook_path"
    ;;
esac

exit 0
