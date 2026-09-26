#!/usr/bin/env bash
# Usage: scripts/agent-requests.sh watch <workspace-dir>
#        scripts/agent-requests.sh once <workspace-dir>
# Container-first plan, component 5: the credential broker. Runs on the Mac, never inside the dev
# container. Watches <workspace-dir>/.agent-requests for NNN-<slug>.md request files that have no
# matching NNN-<slug>.result.md, shows each one and the exact command it names, asks a human yes
# or no on the terminal, and only then runs it with the human's own credentials. `watch` repeats
# every 5 seconds until stopped; `once` does a single pass and exits (what the tests use).
#
# Request files are untrusted input: this script never `eval`s or `source`s anything from one,
# and refuses (without ever prompting) a request with no command block, more than one, a command
# over 2000 characters, a slug outside [a-z0-9-], or a request file that is a symlink.
# shellcheck disable=SC2016
# (throughout: single-quoted printf formats below contain literal ``` fences, not command
# substitution; shellcheck can't tell backticks are inert inside single quotes)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$here/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: scripts/agent-requests.sh watch <workspace-dir>
       scripts/agent-requests.sh once <workspace-dir>

Runs on the Mac, never in the dev container. <workspace-dir> is the Mac folder the container
mounts. `once` does a single pass over .agent-requests/ and exits; `watch` repeats every 5 seconds
until stopped (ctrl-c).
EOF
}

# mask_secrets: kit `mask` (12-digit numbers) plus a redaction for sk-... style API keys, so
# result and proof files are safe to have committed to a public repo.
mask_secrets() {
  mask | sed -E 's/sk-[A-Za-z0-9_-]{6,}/sk-<redacted>/g'
}

tty_fd_open=0

# ensure_tty: open the confirmation source once, lazily, so a pass with nothing to ask never
# needs a terminal at all. AGENT_REQUESTS_TTY overrides /dev/tty; tests point it at a plain file
# of answers, one per prompt, read in order.
ensure_tty() {
  [ "$tty_fd_open" -eq 1 ] && return 0
  local tty_src="${AGENT_REQUESTS_TTY:-/dev/tty}"
  exec 3<"$tty_src" || die "cannot open $tty_src to ask for confirmation"
  tty_fd_open=1
}

# ask_tty <prompt>: prints the prompt to stderr (so it never pollutes a captured result) and
# reads one line from the confirmation source into ASK_TTY_ANSWER. Deliberately not a
# command-substitution-friendly `printf`-return: capturing it with "$(ask_tty ...)" would fork a
# subshell, and the open fd 3 (plus tty_fd_open) would then vanish with that subshell, reopening
# the confirmation source from the top on the very next prompt. Callers read $ASK_TTY_ANSWER
# right after calling this.
ASK_TTY_ANSWER=""
ask_tty() {
  local prompt="$1"
  ensure_tty
  printf '%s' "$prompt" >&2
  IFS= read -r ASK_TTY_ANSWER <&3 || ASK_TTY_ANSWER=""
}

# extract_section <file> <heading>: prints the lines between a `**<heading>**` line and the next
# `**...**` heading line (or EOF). Display only; never used to decide what to run.
extract_section() {
  local file="$1" name="$2"
  awk -v name="$name" '
    { line = $0; sub(/\r$/, "", line) }
    line ~ /^\*\*[^*]+\*\*[ \t]*$/ {
      h = line
      sub(/^\*\*/, "", h); sub(/\*\*[ \t]*$/, "", h)
      if (h == name) { insec = 1 } else { if (insec) exit; insec = 0 }
      next
    }
    insec { print line }
  ' "$file"
}

# extract_first_fence <file>: prints the lines inside the first ``` ... ``` fenced block. Callers
# must already have confirmed there is exactly one such block (see fence count check below).
extract_first_fence() {
  awk '
    /^```/ { n++; if (n == 1) { next } else { exit } }
    n == 1 { print }
  ' "$1"
}

# extract_proof_path <file>: prints the docs/proofs/<name>.md path named by a `Proof: ...` line in
# the Then section, if it matches the safe-name pattern exactly. <name> can never contain a slash
# or a "..", so this can never point outside docs/proofs/.
extract_proof_path() {
  local file="$1" then_section line
  then_section="$(extract_section "$file" "Then")"
  [ -n "$then_section" ] || return 0
  while IFS= read -r line; do
    if [[ "$line" =~ ^Proof:\ (docs/proofs/[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+\.md)[[:space:]]*$ ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
      return 0
    fi
  done <<EOF_THEN
$then_section
EOF_THEN
  return 0
}

# print_request <file> <command>: shows a request clearly on the terminal before asking anything,
# with the command shown exactly as it will run.
print_request() {
  local file="$1" command="$2"
  printf '\n=== Agent request: %s ===\n' "$(basename "$file")"
  printf 'Command (will run exactly as shown, from the workspace root):\n%s\n\n' "$command"
  printf 'Why:\n%s\n\n' "$(extract_section "$file" "Why")"
  printf 'What it changes:\n%s\n\n' "$(extract_section "$file" "What it changes")"
  printf 'Expected result:\n%s\n\n' "$(extract_section "$file" "Expected result")"
  printf 'Undo:\n%s\n\n' "$(extract_section "$file" "Undo")"
  printf 'Then:\n%s\n' "$(extract_section "$file" "Then")"
  printf '=== end request ===\n'
}

# write_result <result-file> <title> <status> <reason> <command> <exit-code> <output> <proof-path>
# Never overwrites an existing result file: a request without a result is still pending, but once
# a result exists it is the permanent record of what happened.
write_result() {
  local result_file="$1" title="$2" status="$3" reason="$4" command="$5"
  local exit_code="$6" output="$7" proof_path="$8"
  local masked_command=""

  if [ -e "$result_file" ]; then
    log "agent-requests: not overwriting existing result: $result_file"
    return 0
  fi

  [ -n "$command" ] && masked_command="$(printf '%s' "$command" | mask_secrets)"

  {
    printf '# Result: %s\n\n' "$title"
    printf -- '- Status: %s\n' "$status"
    [ -n "$exit_code" ] && printf -- '- Exit code: %s\n' "$exit_code"
    printf -- '- Time (UTC): %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    [ -n "$reason" ] && printf -- '- Reason: %s\n' "$reason"
    printf '\n## Command\n\n```\n%s\n```\n' "${masked_command:-(no command parsed)}"
    if [ -n "$exit_code" ]; then
      printf '\n## Output\n\n```\n%s\n```\n' "$output"
    fi
    if [ -n "$proof_path" ]; then
      printf '\nProof written: %s\n' "$proof_path"
    fi
  } > "$result_file"
}

# write_proof <proof-file> <command> <exit-code> <masked-output>: the only path by which a proof
# enters a workspace. Only called after a successful (exit 0) broker-run command. The command
# itself is masked here too: proofs are committed to a public repo just like results are.
write_proof() {
  local proof_file="$1" command="$2" exit_code="$3" masked_output="$4"
  local proof_title masked_command
  proof_title="$(basename "$proof_file" .md)"
  masked_command="$(printf '%s' "$command" | mask_secrets)"
  mkdir -p "$(dirname "$proof_file")"
  {
    printf '# Proof: %s\n\n' "$proof_title"
    printf -- '- Date: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf -- '- Exit code: %s\n\n' "$exit_code"
    printf '## Command\n\n```\n%s\n```\n\n' "$masked_command"
    printf '## Output\n\n```\n%s\n```\n' "$masked_output"
  } > "$proof_file"
}

# run_command <workspace> <file> <result-file> <title> <command>: runs the confirmed command from
# the workspace root, masks its output, writes the result, and writes a proof file when the
# request's Then section names one and the command exits 0.
run_command() {
  local workspace="$1" file="$2" result_file="$3" title="$4" command="$5"
  local tmp_out exit_code=0 masked_output proof_path=""

  tmp_out="$(mktemp)"
  ( cd "$workspace" && bash -c "$command" ) >"$tmp_out" 2>&1 || exit_code=$?
  masked_output="$(mask_secrets < "$tmp_out")"
  rm -f "$tmp_out"

  if [ "$exit_code" -eq 0 ]; then
    local pp
    pp="$(extract_proof_path "$file")"
    if [ -n "$pp" ]; then
      write_proof "$workspace/$pp" "$command" "$exit_code" "$masked_output"
      proof_path="$pp"
    fi
  fi

  write_result "$result_file" "$title" "ran" "" "$command" "$exit_code" "$masked_output" "$proof_path"
  log "agent-requests: ran $title (exit $exit_code)"
}

# process_request <workspace> <file>: validates untrusted input first (never prompting for a
# refusal), then, for a well-formed request, shows it and asks before running anything.
process_request() {
  local workspace="$1" file="$2"
  local base title result_file slug fences command cmdlen answer reason full_reason

  base="$(basename "$file")"
  title="${base%.md}"
  result_file="${file%.md}.result.md"

  [ -e "$result_file" ] && return 0

  if [ -L "$file" ]; then
    write_result "$result_file" "$title" "declined" "refused: request file is a symlink" "" "" "" ""
    return 0
  fi

  slug="${base#[0-9][0-9][0-9]-}"
  slug="${slug%.md}"
  if [[ ! "$slug" =~ ^[a-z0-9-]+$ ]]; then
    write_result "$result_file" "$title" "declined" "refused: slug is outside [a-z0-9-]" "" "" "" ""
    return 0
  fi

  # ok-to-hide: grep -c exits 1 on a zero count, which is a normal "no fence" result here, not a
  # failure being hidden; the very next check treats that zero explicitly.
  fences="$(grep -c '^```' "$file" || true)"
  if [ "$fences" -eq 0 ]; then
    write_result "$result_file" "$title" "declined" "refused: no Command code block found" "" "" "" ""
    return 0
  fi
  if [ "$fences" -ne 2 ]; then
    write_result "$result_file" "$title" "declined" "refused: more than one command code block" "" "" "" ""
    return 0
  fi

  command="$(extract_first_fence "$file")"
  cmdlen="${#command}"
  if [ "$cmdlen" -gt 2000 ]; then
    write_result "$result_file" "$title" "declined" "refused: command is $cmdlen characters, over the 2000 limit" "" "" "" ""
    return 0
  fi

  print_request "$file" "$command"

  ask_tty 'Run this command? [y/N] '
  answer="$ASK_TTY_ANSWER"
  if [ "$answer" != "y" ]; then
    ask_tty 'Declined; why (optional)? '
    reason="$ASK_TTY_ANSWER"
    full_reason="declined by operator"
    [ -n "$reason" ] && full_reason="$full_reason: $reason"
    write_result "$result_file" "$title" "declined" "$full_reason" "$command" "" "" ""
    return 0
  fi

  run_command "$workspace" "$file" "$result_file" "$title" "$command"
}

# find_pending <requests-dir>: NNN-<slug>.md files with no matching NNN-<slug>.result.md, in order.
find_pending() {
  local dir="$1" f base result
  for f in "$dir"/[0-9][0-9][0-9]-*.md; do
    base="$(basename "$f")"
    case "$base" in
      *.result.md) continue ;;
    esac
    result="${f%.md}.result.md"
    [ -e "$result" ] && continue
    printf '%s\n' "$f"
  done | sort
}

process_all() {
  local workspace="$1" req
  local dir="$workspace/.agent-requests"
  [ -d "$dir" ] || return 0
  shopt -s nullglob
  while IFS= read -r req; do
    [ -n "$req" ] || continue
    process_request "$workspace" "$req"
  done < <(find_pending "$dir")
  shopt -u nullglob
}

main() {
  local mode="${1:-}" workspace="${2:-}"
  case "$mode" in
    watch|once) ;;
    *) usage; exit 2 ;;
  esac
  [ -n "$workspace" ] || { usage; exit 2; }
  [ -d "$workspace" ] || die "workspace directory not found: $workspace"

  if [ "$mode" = "once" ]; then
    process_all "$workspace"
    exit 0
  fi

  log "agent-requests: watching $workspace/.agent-requests every 5s (ctrl-c to stop)"
  while true; do
    process_all "$workspace"
    sleep 5
  done
}

main "$@"
