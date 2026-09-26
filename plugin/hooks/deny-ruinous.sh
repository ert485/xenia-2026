#!/usr/bin/env bash
# PreToolUse hook of the kit plugin (matcher Bash|Write|Edit|MultiEdit|NotebookEdit): denies a
# short, fixed list of ruinous commands before they run. Never asks: an allowed call prints
# nothing and exits 0; a denied call prints a PreToolUse deny whose reason starts
# "deny-ruinous <rule>:" and says what to do instead. This is a guardrail against the obvious, not
# a sandbox -- the egress firewall and the absence of deploy credentials in the dev container are
# the real boundary, and everything not listed below is allowed.
#
# A Bash command is judged by tokenizing it the way a shell would (python3's shlex, invoked below),
# never by matching a raw substring: fix-round-1 found that substring matching both missed real
# bypasses (`git  push --force` with two spaces, `git "push" --force`, `git -C dir push --force`)
# and denied things that only *mention* a pattern in quoted text (a commit message, an echo string).
# fix-round-2: the tokenizer alone isn't enough -- a wrapper (sudo/env/nice/timeout/...) that takes
# an option's value as its own token was letting the value be mistaken for the real command, so every
# rule below it was skipped. This hook is still a guardrail, not a sandbox: `bash -c` and `eval`
# (which hide a command from tokenizing entirely) are out of scope, same as the plan calls it.
set -uo pipefail
# Defence in depth: nothing here should ever glob-expand against this process's real cwd.
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

# ---------------------------------------------------------------------------
# Shell tokenizer: python3's shlex, posix mode, with an unquoted newline treated as its own
# separator token too (real shells treat a bare newline like `;`; shlex's default silently
# swallows it as whitespace, which would let a second line hide from every check below).
# ---------------------------------------------------------------------------
TOKENIZE_PY='
import shlex, sys
try:
    lex = shlex.shlex(sys.argv[1], posix=True, punctuation_chars="();<>|&\n")
    lex.whitespace = " \t\r"
    lex.whitespace_split = True
    toks = list(lex)
except ValueError:
    sys.exit(1)
sys.stdout.write("\0".join(toks) + ("\0" if toks else ""))
'

# Tokenizes $1 into the global TOKENS array. Returns 2 if python3 itself is missing, 1 if the
# command could not be safely tokenized (for example unbalanced quotes), 0 on success.
tokenize_bash_command() {
  TOKENS=()
  command -v python3 >/dev/null 2>&1 || return 2
  local tmp rc tok
  tmp="$(mktemp)" || return 2
  python3 -c "$TOKENIZE_PY" "$1" > "$tmp" 2>/dev/null
  rc=$?
  if [ "$rc" -ne 0 ]; then rm -f "$tmp"; return 1; fi
  while IFS= read -r -d '' tok; do
    TOKENS+=("$tok")
  done < "$tmp"
  rm -f "$tmp"
  return 0
}

# ---------------------------------------------------------------------------
# Path helpers, shared by the Bash-command checks below and the Write/Edit/MultiEdit/NotebookEdit
# path checks further down. Matched by path component, not by substring, so "docs/proofs-archive/"
# and ".agent-requests/" are never caught (fix-round-1 minor 4).
# ---------------------------------------------------------------------------
is_docs_proofs_path() {
  [[ "$1" =~ (^|/)docs/proofs(/|$) ]]
}

is_dot_agent_path() {
  [[ "$1" =~ (^|/)\.agent(/|$) ]]
}

is_firewall_path() {
  local p="$1" base="${1##*/}"
  case "$base" in
    init-firewall.sh|refresh-firewall.sh) return 0 ;;
  esac
  case "$p" in
    /etc/sudoers|/etc/sudoers.d/*) return 0 ;;
  esac
  return 1
}

# One candidate write target (a redirection target, or a resolved destination argument): denies
# under whichever rule it matches, or returns 0 (not a match) so the caller keeps looking.
check_one_write_target() {
  local target="$1"
  if is_docs_proofs_path "$target"; then
    deny proofs "proof files are written only from real command output; file a .agent-requests/ request instead"
  fi
  if is_dot_agent_path "$target"; then
    deny verifier-output "the verifier's own verdict is not yours to edit; fix the reasons and let it re-run"
  fi
  if is_firewall_path "$target"; then
    deny firewall "the egress firewall is the boundary between this container and the internet; ask the human, or file a .agent-requests/ request"
  fi
  return 0
}

# rm's own strip: a trailing / or /* or /. is dropped before comparing against the dangerous-target
# list (quotes are already gone -- shlex stripped them during tokenizing).
strip_rm_target() {
  local t="$1"
  case "$t" in
    /) : ;;  # the bare root: stripping the trailing / would leave an empty string
    */\*) t="${t%/\*}" ;;
    */.) t="${t%/.}" ;;
    */) t="${t%/}" ;;
  esac
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

# ---------------------------------------------------------------------------
# Per-verb argument checks. Each receives only the resolved command's own argument tokens (wrappers
# such as sudo/env/command, leading VAR=value assignments, and -- for git -- global options before
# the subcommand, have already been stripped by process_simple_command below).
# ---------------------------------------------------------------------------

# Rule force-push: git push with a force flag, a mirror/delete, or a +/: refspec. Incident: the
# container-first plan's no-force-push rule and a teammate's report on 2026-09-25 of an agent doing
# something destructive despite its settings.
check_force_push_args() {
  local t
  for t in "$@"; do
    case "$t" in
      --force*) deny force-push \
        "a force push rewrites shared history; push a normal commit, or file a .agent-requests/ request if history really needs rewriting" ;;
      --mirror) deny force-push \
        "a mirror push can overwrite or delete remote refs wholesale; push a normal commit, or file a .agent-requests/ request" ;;
      --delete) deny force-push \
        "deleting a remote ref is not allowed from here; ask the human, or file a .agent-requests/ request" ;;
      -f|-fu|-uf) deny force-push \
        "a force push rewrites shared history; push a normal commit, or file a .agent-requests/ request if history really needs rewriting" ;;
      +*) deny force-push \
        "a refspec starting with + forces the update; push a normal commit, or file a .agent-requests/ request" ;;
      :*) deny force-push \
        "a refspec starting with : deletes the remote ref; ask the human, or file a .agent-requests/ request" ;;
    esac
    if [[ "$t" == -* && "$t" != --* && "$t" == *f* ]]; then
      deny force-push \
        "a force push rewrites shared history; push a normal commit, or file a .agent-requests/ request if history really needs rewriting"
    fi
  done
  return 0
}

# Rule delete-workspace (git clean half): a clean that also flushes ignored/untracked files, which
# would destroy the verifier's own output. Incident: same as force-push.
check_git_clean_args() {
  local t combined=""
  for t in "$@"; do
    case "$t" in
      --force) combined+="f" ;;
      --*) continue ;;
      -*) combined+="${t#-}" ;;
    esac
  done
  if [[ "$combined" == *f* && ( "$combined" == *x* || "$combined" == *X* ) ]]; then
    deny delete-workspace \
      "git clean with -f and -x/-X destroys ignored and untracked files, including the verifier's own output; run git clean -n to preview first, or file a .agent-requests/ request"
  fi
  return 0
}

# Rule delete-workspace (rm half): rm -r of the workspace root or something that resolves to it.
check_rm_recursive_args() {
  local cwd="$1"; shift
  local t has_recursive=0 target
  for t in "$@"; do
    [[ "$t" == "--recursive" ]] && has_recursive=1
  done
  if [ "$has_recursive" -eq 0 ]; then
    for t in "$@"; do
      case "$t" in
        --*) continue ;;
        -*) [[ "$t" == *r* || "$t" == *R* ]] && has_recursive=1 ;;
      esac
    done
  fi
  [ "$has_recursive" -eq 1 ] || return 0
  for t in "$@"; do
    case "$t" in -*) continue ;; esac
    target="$(strip_rm_target "$t")"
    if is_dangerous_rm_target "$target" "$cwd"; then
      deny delete-workspace \
        "a recursive delete of the workspace root (or something that resolves to it) is not allowed; delete a specific subpath, or file a .agent-requests/ request"
    fi
  done
  return 0
}

# Rule firewall (iptables/ip6tables/ipset half): a flush/policy/delete verb as its own argument.
check_iptables_args() {
  local t
  for t in "$@"; do
    case "$t" in
      -F|-X|-P|-D|flush|destroy)
        deny firewall \
          "the egress firewall is the boundary between this container and the internet; ask the human, or file a .agent-requests/ request"
        ;;
    esac
  done
  return 0
}

# Rules proofs/verifier-output/firewall (write-target half): every non-option argument is a
# candidate write target (tee can write several files at once; so can touch, rm, truncate, chmod,
# and git rm).
check_write_targets_all() {
  local t
  for t in "$@"; do
    case "$t" in -*) continue ;; esac
    check_one_write_target "$t"
  done
  return 0
}

# Rules proofs/verifier-output/firewall (destination half): cp/mv/install/ln/git-mv only write to
# their destination -- the last non-option argument, or the -t/--target-directory argument if given.
check_write_targets_last() {
  local -a nonflag=()
  local t skip_next=0 dash_t_dir=""
  for t in "$@"; do
    if [ "$skip_next" -eq 1 ]; then
      dash_t_dir="$t"
      skip_next=0
      continue
    fi
    case "$t" in
      -t) skip_next=1; continue ;;
      --target-directory=*) dash_t_dir="${t#--target-directory=}"; continue ;;
      -*) continue ;;
    esac
    nonflag+=("$t")
  done
  if [ -n "$dash_t_dir" ]; then
    check_one_write_target "$dash_t_dir"
    return 0
  fi
  local cnt="${#nonflag[@]}"
  [ "$cnt" -gt 0 ] && check_one_write_target "${nonflag[$((cnt - 1))]}"
  return 0
}

# sed/perl only write in place with -i (or -i<suffix>); otherwise they only read.
check_inplace_edit_args() {
  local t has_i=0
  for t in "$@"; do
    case "$t" in
      -i|-i.*|--in-place|--in-place=*) has_i=1 ;;
    esac
  done
  [ "$has_i" -eq 1 ] || return 0
  check_write_targets_last "$@"
  return 0
}

# git's own global options, skipped before the subcommand: -C <dir>, -c <k=v>, --git-dir[=/ ]...,
# --work-tree[=/ ]..., --no-pager, --bare, -P.
check_git_subcommand() {
  local cwd="$1"; shift
  local -a gargs=("$@")
  local n="${#gargs[@]}" i=0 t
  while [ "$i" -lt "$n" ]; do
    t="${gargs[$i]}"
    case "$t" in
      -C|-c|--git-dir|--work-tree) i=$((i + 2)); continue ;;
      --git-dir=*|--work-tree=*|--no-pager|--bare|-P) i=$((i + 1)); continue ;;
      *) break ;;
    esac
  done
  [ "$i" -lt "$n" ] || return 0
  local sub="${gargs[$i]}"
  local -a sargs=()
  local j
  for ((j = i + 1; j < n; j++)); do
    sargs+=("${gargs[$j]}")
  done
  case "$sub" in
    push) check_force_push_args "${sargs[@]}" ;;
    clean) check_git_clean_args "${sargs[@]}" ;;
    rm) check_write_targets_all "${sargs[@]}" ;;
    mv) check_write_targets_last "${sargs[@]}" ;;
  esac
  return 0
}

# Wrappers stripped before resolving the real command: leading VAR=value assignments, sudo, command,
# env, exec, nohup, time, nice, ionice, timeout (and each one's own flags/assignments).
#
# fix-round-2: a wrapper option that takes its value as a SEPARATE token (`sudo -u root ...`,
# `env -u FOO ...`) was only skipped by "matches -*", which skips the option itself but not its
# value -- so the value (a username, an env var name) was mistaken for the real command and every
# rule below was skipped for it. Each wrapper below now knows which of its own options take a
# separate value and skips that token too, and sudo/env additionally stop at a literal `--`.
resolve_simple_command() {
  # Reads the global SIMPLE array; sets REAL_BASE and the global ARGS array. REAL_BASE is empty if
  # nothing but assignments/wrappers were found (nothing to check).
  REAL_BASE=""
  ARGS=()
  local n="${#SIMPLE[@]}" i=0 t base
  while [ "$i" -lt "$n" ]; do
    t="${SIMPLE[$i]}"
    if [[ "$t" =~ ^[A-Za-z_][A-Za-z0-9_]*=.*$ ]]; then
      i=$((i + 1)); continue
    fi
    base="${t##*/}"
    case "$base" in
      sudo)
        # Options that take a separate value: -u user, -g group, -h host, -p prompt, -C num,
        # -D dir, -r role, -t type, -U user, -T timeout. A `--user=`-style long form carries its
        # value in the same token, so the generic "-*" skip already handles it. `--` ends option
        # parsing (whatever follows is the real command, even if it looks like a flag).
        i=$((i + 1))
        while [ "$i" -lt "$n" ]; do
          t="${SIMPLE[$i]}"
          [[ "$t" == "--" ]] && { i=$((i + 1)); break; }
          case "$t" in
            -*)
              i=$((i + 1))
              case "$t" in
                -u|-g|-h|-p|-C|-D|-r|-t|-U|-T) i=$((i + 1)) ;;
              esac
              continue
              ;;
          esac
          break
        done
        continue
        ;;
      command|exec)
        # exec -a NAME sets argv[0]; NAME is exec's own value, not the real command.
        i=$((i + 1))
        while [ "$i" -lt "$n" ]; do
          t="${SIMPLE[$i]}"
          case "$t" in
            -a) i=$((i + 2)); continue ;;
            -*) i=$((i + 1)); continue ;;
          esac
          break
        done
        continue
        ;;
      nohup|time)
        i=$((i + 1))
        while [ "$i" -lt "$n" ] && [[ "${SIMPLE[$i]}" == -* ]]; do i=$((i + 1)); done
        continue
        ;;
      nice)
        # -n N: the niceness increment.
        i=$((i + 1))
        while [ "$i" -lt "$n" ]; do
          t="${SIMPLE[$i]}"
          case "$t" in
            -n) i=$((i + 2)); continue ;;
            -*) i=$((i + 1)); continue ;;
          esac
          break
        done
        continue
        ;;
      ionice)
        # -c N (class), -n N (level), -p PID: each takes a separate value.
        i=$((i + 1))
        while [ "$i" -lt "$n" ]; do
          t="${SIMPLE[$i]}"
          case "$t" in
            -c|-n|-p) i=$((i + 2)); continue ;;
            -*) i=$((i + 1)); continue ;;
          esac
          break
        done
        continue
        ;;
      timeout)
        # -k DURATION, -s SIGNAL take a separate value; then the DURATION positional (before the
        # real command) is itself skipped, never treated as the command.
        i=$((i + 1))
        while [ "$i" -lt "$n" ]; do
          t="${SIMPLE[$i]}"
          case "$t" in
            -k|-s) i=$((i + 2)); continue ;;
            -*) i=$((i + 1)); continue ;;
          esac
          break
        done
        [ "$i" -lt "$n" ] && i=$((i + 1))
        continue
        ;;
      env)
        # -u NAME (unset), -C DIR (chdir), -S STRING (split) take a separate value; `--` ends
        # option parsing the same as for sudo.
        i=$((i + 1))
        while [ "$i" -lt "$n" ]; do
          t="${SIMPLE[$i]}"
          [[ "$t" == "--" ]] && { i=$((i + 1)); break; }
          case "$t" in
            -u|-C|-S) i=$((i + 2)); continue ;;
            -*) i=$((i + 1)); continue ;;
          esac
          if [[ "$t" =~ ^[A-Za-z_][A-Za-z0-9_]*=.*$ ]]; then
            i=$((i + 1)); continue
          fi
          break
        done
        continue
        ;;
    esac
    break
  done
  [ "$i" -lt "$n" ] || return 0
  REAL_BASE="${SIMPLE[$i]##*/}"
  local j
  for ((j = i + 1; j < n; j++)); do
    ARGS+=("${SIMPLE[$j]}")
  done
  return 0
}

# One simple command (a run of tokens between operators): checks its redirection targets (whatever
# the command turns out to be), then its resolved command's own rule.
process_simple_command() {
  local cwd="$1"
  local n="${#SIMPLE[@]}"
  [ "$n" -eq 0 ] && return 0

  local k
  for ((k = 0; k < n - 1; k++)); do
    case "${SIMPLE[$k]}" in
      '>'|'>>'|'>|'|'&>') check_one_write_target "${SIMPLE[$((k + 1))]}" ;;
    esac
  done

  resolve_simple_command
  [ -n "$REAL_BASE" ] || return 0

  case "$REAL_BASE" in
    git) check_git_subcommand "$cwd" "${ARGS[@]}" ;;
  esac
  case "$REAL_BASE" in
    rm) check_rm_recursive_args "$cwd" "${ARGS[@]}"; check_write_targets_all "${ARGS[@]}" ;;
    tee|touch|truncate|chmod) check_write_targets_all "${ARGS[@]}" ;;
    cp|mv|install|ln) check_write_targets_last "${ARGS[@]}" ;;
    sed|perl) check_inplace_edit_args "${ARGS[@]}" ;;
    iptables|ip6tables|ipset) check_iptables_args "${ARGS[@]}" ;;
  esac
  return 0
}

is_operator_token() {
  case "$1" in
    ';'|'&&'|'||'|'|'|'&'|'('|')'|$'\n') return 0 ;;
  esac
  return 1
}

check_bash() {
  local cmd="$1" cwd="$2" rc
  tokenize_bash_command "$cmd"
  rc=$?
  if [ "$rc" -eq 2 ]; then
    deny bash-parse \
      "python3 is missing, so this Bash command could not be safely parsed; ask a human to check the plugin's dependencies, or file a .agent-requests/ request"
  elif [ "$rc" -eq 1 ]; then
    deny bash-parse \
      "this command's quoting could not be safely parsed (unbalanced quotes); rephrase it, or file a .agent-requests/ request"
  fi

  SIMPLE=()
  local tok
  for tok in "${TOKENS[@]}"; do
    if is_operator_token "$tok"; then
      process_simple_command "$cwd"
      SIMPLE=()
    else
      SIMPLE+=("$tok")
    fi
  done
  process_simple_command "$cwd"
  return 0
}

check_write_path() {
  local p="$1"
  is_firewall_path "$p" && deny firewall \
    "the egress firewall is the boundary between this container and the internet; ask the human, or file a .agent-requests/ request"
  is_docs_proofs_path "$p" && deny proofs \
    "proof files are written only from real command output; file a .agent-requests/ request instead"
  is_dot_agent_path "$p" && deny verifier-output \
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
