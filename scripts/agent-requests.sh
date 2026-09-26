#!/usr/bin/env bash
# Usage: scripts/agent-requests.sh watch <workspace-dir>
#        scripts/agent-requests.sh once <workspace-dir>
# Container-first plan, component 5: the credential broker. Runs on the Mac, never inside the dev
# container. Watches <workspace-dir>/.agent-requests for NNN-<slug>.md request files that have no
# matching NNN-<slug>.result.md, shows each one and the exact command it names, asks a human yes
# or no on the terminal, and only then runs it with the human's own credentials. `watch` repeats
# every 5 seconds until stopped; `once` does a single pass and exits (what the tests use).
#
# Request files are untrusted input, and the agent that writes them owns this workspace: this
# script never `eval`s or `source`s anything from one, reads each request exactly once into memory
# right after checking it (never reopening the path — the agent could otherwise swap a request for
# a symlink between reads, including during however long an approved command takes to run), and
# refuses (without ever prompting) a request that is a symlink or not a regular file, over 64 KB,
# with no command block or more than one, a command over 2000 characters, a command containing a
# control character other than tab/newline, or a slug outside [a-z0-9-]. Every displayed section is
# shown with control characters (ANSI/terminal escapes included) made visible first, so a request
# can't spoof what's on screen before the yes/no answer. Writes under docs/proofs/ and
# .agent-requests/ are refused rather than followed through a pre-existing symlink anywhere in
# their path.
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

# sanitize_for_display <text>: makes every control character visible (ANSI/terminal escapes
# included) except tab and newline, which `cat -v` leaves untouched on both macOS (BSD) and Linux
# (GNU) cat. Used only for what gets printed to the terminal before the yes/no prompt; never used
# on text that gets executed, masked into a result, or written to a proof.
sanitize_for_display() {
  printf '%s' "$1" | cat -v
}

# has_bad_control_chars <text>: true if <text> contains a control character other than tab. (A
# literal newline can never appear "inside" a line for grep's line-based matching, so it needs no
# explicit allowance here.) Byte-range match under the C locale so this doesn't depend on how the
# terminal's locale treats multibyte UTF-8.
has_bad_control_chars() {
  local text="$1" pattern
  pattern=$'[\x01-\x08\x0B-\x1F\x7F]'
  printf '%s' "$text" | LC_ALL=C grep -qE "$pattern"
}

REQUEST_MAX_BYTES=65536

# read_request_once <file>: reads up to REQUEST_MAX_BYTES+1 bytes from <file> in a single open,
# called immediately after the caller's symlink/regular-file check. Sets REQUEST_CONTENT and
# returns 0 on success. Every parser downstream (fence count, command, display sections, proof
# path) works from that in-memory text and never reopens the path again — this is what closes the
# TOCTOU window a Task 34 fix-round finding pointed out: the agent that owns this workspace could
# otherwise swap the request file for a symlink to something like ~/.aws/credentials between the
# broker's many separate re-reads, including the one that used to happen after an approved command
# had already been running for however long.
# Returns 1 if the file could not be read at all, 2 if it is over the size cap (REQUEST_CONTENT is
# unset in either case).
read_request_once() {
  local file="$1" probe
  REQUEST_CONTENT=""
  # ok-to-hide: stderr is noise here; `|| return 1` right after reports the failure to the caller.
  probe="$(head -c "$((REQUEST_MAX_BYTES + 1))" -- "$file" 2>/dev/null)" || return 1
  if [ "${#probe}" -gt "$REQUEST_MAX_BYTES" ]; then
    return 2
  fi
  REQUEST_CONTENT="$probe"
  return 0
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

# extract_section_from_text <content> <heading>: prints the lines between a `**<heading>**` line
# and the next `**...**` heading line (or EOF), from in-memory text. Display only; never used to
# decide what to run.
extract_section_from_text() {
  local content="$1" name="$2"
  awk -v name="$name" '
    { line = $0; sub(/\r$/, "", line) }
    line ~ /^\*\*[^*]+\*\*[ \t]*$/ {
      h = line
      sub(/^\*\*/, "", h); sub(/\*\*[ \t]*$/, "", h)
      if (h == name) { insec = 1 } else { if (insec) exit; insec = 0 }
      next
    }
    insec { print line }
  ' <<<"$content"
}

# extract_first_fence_from_text <content>: prints the lines inside the first ``` ... ``` fenced
# block, from in-memory text. Callers must already have confirmed there is exactly one such block
# (see the fence count check below).
extract_first_fence_from_text() {
  awk '
    /^```/ { n++; if (n == 1) { next } else { exit } }
    n == 1 { print }
  ' <<<"$1"
}

# extract_proof_path_from_text <content>: prints the docs/proofs/<name>.md path named by a
# `Proof: ...` line in the Then section, if it matches the safe-name pattern exactly. <name> can
# never contain a slash or a "..", so this can never point outside docs/proofs/.
extract_proof_path_from_text() {
  local content="$1" then_section line
  then_section="$(extract_section_from_text "$content" "Then")"
  [ -n "$then_section" ] || return 0
  while IFS= read -r line; do
    if [[ "$line" =~ ^Proof:\ (docs/proofs/[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+\.md)[[:space:]]*$ ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
      return 0
    fi
  done <<<"$then_section"
  return 0
}

# print_request <display-name> <command> <proof-path> <content>: shows a request clearly on the
# terminal before asking anything, with the command shown exactly as it will run and, when the
# request names one, where its proof will be written. Every piece of untrusted text is sanitized
# for display first (control characters, including ANSI/terminal escapes, made visible) so a
# request can't spoof the screen before the yes/no answer.
print_request() {
  local base="$1" command="$2" proof_path="$3" content="$4"

  printf '\n=== Agent request: %s ===\n' "$base"
  printf 'Command (will run exactly as shown, from the workspace root):\n%s\n\n' \
    "$(sanitize_for_display "$command")"
  printf 'Why:\n%s\n\n' "$(sanitize_for_display "$(extract_section_from_text "$content" "Why")")"
  printf 'What it changes:\n%s\n\n' \
    "$(sanitize_for_display "$(extract_section_from_text "$content" "What it changes")")"
  printf 'Expected result:\n%s\n\n' \
    "$(sanitize_for_display "$(extract_section_from_text "$content" "Expected result")")"
  printf 'Undo:\n%s\n\n' "$(sanitize_for_display "$(extract_section_from_text "$content" "Undo")")"
  printf 'Then:\n%s\n\n' "$(sanitize_for_display "$(extract_section_from_text "$content" "Then")")"
  if [ -n "$proof_path" ]; then
    printf 'Proof will be written to: %s\n' "$proof_path"
  else
    printf 'Proof: (none — this request writes no proof)\n'
  fi
  printf '=== end request ===\n'
}

# write_result <result-file> <title> <status> <reason> <command> <exit-code> <output> <proof-path>
# Never overwrites an existing result file, and never writes through a pre-existing symlink at the
# result path: a request without a result is still pending, but once a result exists (or the path
# is already a symlink someone planted) it is left alone.
write_result() {
  local result_file="$1" title="$2" status="$3" reason="$4" command="$5"
  local exit_code="$6" output="$7" proof_path="$8"
  local masked_command=""

  if [ -L "$result_file" ]; then
    log "agent-requests: refusing to write $result_file: it already exists as a symlink"
    return 1
  fi
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

WORKSPACE_PHYSICAL=""

# resolve_workspace_physical <workspace>: caches the physically resolved (symlinks-followed)
# absolute path of the workspace root, once per invocation, so containment checks compare like
# with like.
resolve_workspace_physical() {
  local workspace="$1"
  [ -n "$WORKSPACE_PHYSICAL" ] && return 0
  WORKSPACE_PHYSICAL="$(cd -P -- "$workspace" && pwd -P)" || die "cannot resolve workspace path: $workspace"
}

# contained_dir <workspace> <relative-dir>: ensures <workspace>/<relative-dir> exists and is
# physically inside <workspace>. A pre-existing symlink at any component on the way down (e.g.
# "docs", or "docs/proofs" itself) would otherwise send `mkdir -p` and the write that follows
# outside the workspace entirely — this refuses before ever calling mkdir if it finds one, then,
# as a second, closing check, confirms the physically resolved directory really is
# <workspace-physical>/<relative-dir> (catching a symlink planted in the small window between the
# component check and mkdir too, since resolving through it would land somewhere else). Prints the
# resolved directory and returns 0 on success; prints nothing and returns 1 on refusal.
contained_dir() {
  local workspace="$1" rel_dir="$2" prefix="" part remaining resolved

  resolve_workspace_physical "$workspace"

  remaining="$rel_dir"
  while [ -n "$remaining" ]; do
    part="${remaining%%/*}"
    prefix="$prefix/$part"
    [ -L "$workspace$prefix" ] && return 1
    case "$remaining" in
      */*) remaining="${remaining#*/}" ;;
      *) remaining="" ;;
    esac
  done

  # ok-to-hide: stderr is noise here; `|| return 1` right after reports the failure to the caller.
  mkdir -p -- "$workspace/$rel_dir" 2>/dev/null || return 1
  resolved="$(cd -P -- "$workspace/$rel_dir" && pwd -P)" || return 1
  [ "$resolved" = "$WORKSPACE_PHYSICAL/$rel_dir" ] || return 1
  printf '%s\n' "$resolved"
}

# write_proof <workspace> <rel-proof-path> <command> <exit-code> <masked-output>: the only path by
# which a proof enters a workspace. Only called after a successful (exit 0) broker-run command.
# Refuses (writes nothing, returns 1) if docs/proofs isn't safely contained in the workspace (see
# contained_dir) or if the proof file itself already exists as a symlink; otherwise writes into a
# temp file inside the resolved directory and renames it into place, so the leaf name is never
# opened for writing until it's known not to be a symlink. The command itself is masked here too:
# proofs are committed to a public repo just like results are.
write_proof() {
  local workspace="$1" rel_path="$2" command="$3" exit_code="$4" masked_output="$5"
  local rel_dir leaf resolved_dir final_file proof_title masked_command tmp_file

  rel_dir="$(dirname "$rel_path")"
  leaf="$(basename "$rel_path")"

  resolved_dir="$(contained_dir "$workspace" "$rel_dir")" || {
    log "agent-requests: refusing to write proof $rel_path: $rel_dir is not safely contained in the workspace (symlink?)"
    return 1
  }

  final_file="$resolved_dir/$leaf"
  if [ -L "$final_file" ]; then
    log "agent-requests: refusing to write proof $rel_path: the proof file already exists as a symlink"
    return 1
  fi

  proof_title="$(basename "$leaf" .md)"
  masked_command="$(printf '%s' "$command" | mask_secrets)"

  tmp_file="$(mktemp "$resolved_dir/.proof.XXXXXX")" || return 1
  {
    printf '# Proof: %s\n\n' "$proof_title"
    printf -- '- Date: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf -- '- Exit code: %s\n\n' "$exit_code"
    printf '## Command\n\n```\n%s\n```\n\n' "$masked_command"
    printf '## Output\n\n```\n%s\n```\n' "$masked_output"
  } > "$tmp_file"
  mv -f -- "$tmp_file" "$final_file"
}

# run_command <workspace> <result-file> <title> <command> <proof-path>: runs the confirmed command
# from the workspace root, masks its output, writes the result, and — when a proof path was named
# and the command exits 0 — writes the proof. <proof-path> was already extracted from the
# request's in-memory content before this was called, so nothing here reopens the request file.
run_command() {
  local workspace="$1" result_file="$2" title="$3" command="$4" proof_path="$5"
  local tmp_out exit_code=0 masked_output proof_note=""

  tmp_out="$(mktemp)"
  ( cd "$workspace" && bash -c "$command" ) >"$tmp_out" 2>&1 || exit_code=$?
  masked_output="$(mask_secrets < "$tmp_out")"
  rm -f "$tmp_out"

  if [ -n "$proof_path" ]; then
    if [ "$exit_code" -eq 0 ]; then
      if ! write_proof "$workspace" "$proof_path" "$command" "$exit_code" "$masked_output"; then
        proof_note="proof not written: refused (docs/proofs is not safely contained in the workspace, or the target already exists as a symlink)"
        proof_path=""
      fi
    else
      proof_path=""
    fi
  fi

  write_result "$result_file" "$title" "ran" "$proof_note" "$command" "$exit_code" "$masked_output" "$proof_path"
  log "agent-requests: ran $title (exit $exit_code)"
}

# process_request <workspace> <file>: validates untrusted input first (never prompting for a
# refusal), reads the file exactly once, then, for a well-formed request, shows it and asks before
# running anything.
process_request() {
  local workspace="$1" file="$2"
  local base title result_file slug fences content cmdlen answer reason full_reason
  local command proof_path read_rc

  base="$(basename "$file")"
  title="${base%.md}"
  result_file="${file%.md}.result.md"

  [ -e "$result_file" ] && return 0

  if [ -L "$file" ]; then
    write_result "$result_file" "$title" "declined" "refused: request file is a symlink" "" "" "" ""
    return 0
  fi
  if [ ! -f "$file" ]; then
    write_result "$result_file" "$title" "declined" "refused: request file is not a regular file" "" "" "" ""
    return 0
  fi

  slug="${base#[0-9][0-9][0-9]-}"
  slug="${slug%.md}"
  if [[ ! "$slug" =~ ^[a-z0-9-]+$ ]]; then
    write_result "$result_file" "$title" "declined" "refused: slug is outside [a-z0-9-]" "" "" "" ""
    return 0
  fi

  # Read the request exactly once, right next to the symlink/regular-file check above. Every
  # parser from here on works on this in-memory text and never reopens $file again.
  read_rc=0
  read_request_once "$file" || read_rc=$?
  case "$read_rc" in
    0) : ;;
    2)
      write_result "$result_file" "$title" "declined" "refused: request file is larger than the 64 KB limit" "" "" "" ""
      return 0
      ;;
    *)
      write_result "$result_file" "$title" "declined" "refused: could not read request file" "" "" "" ""
      return 0
      ;;
  esac
  content="$REQUEST_CONTENT"

  # ok-to-hide: grep -c exits 1 on a zero count, a normal result the next check treats explicitly.
  fences="$(grep -c '^```' <<<"$content" || true)"
  if [ "$fences" -eq 0 ]; then
    write_result "$result_file" "$title" "declined" "refused: no Command code block found" "" "" "" ""
    return 0
  fi
  if [ "$fences" -ne 2 ]; then
    write_result "$result_file" "$title" "declined" "refused: unbalanced or extra code fences" "" "" "" ""
    return 0
  fi

  command="$(extract_first_fence_from_text "$content")"

  if has_bad_control_chars "$command"; then
    write_result "$result_file" "$title" "declined" "refused: command contains a control character other than tab or newline" "" "" "" ""
    return 0
  fi

  cmdlen="${#command}"
  if [ "$cmdlen" -gt 2000 ]; then
    write_result "$result_file" "$title" "declined" "refused: command is $cmdlen characters, over the 2000 limit" "" "" "" ""
    return 0
  fi

  proof_path="$(extract_proof_path_from_text "$content")"

  print_request "$base" "$command" "$proof_path" "$content"

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

  run_command "$workspace" "$result_file" "$title" "$command" "$proof_path"
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
  local workspace="$1" req dir resolved_dir
  dir="$workspace/.agent-requests"
  [ -d "$dir" ] || return 0

  # Same containment protection writing a result relies on: refuse the whole pass rather than
  # write anything if .agent-requests itself turns out not to be safely inside the workspace.
  resolved_dir="$(contained_dir "$workspace" ".agent-requests")" || {
    log "agent-requests: refusing to process $dir this pass: not safely contained in the workspace (symlink?)"
    return 0
  }

  shopt -s nullglob
  while IFS= read -r req; do
    [ -n "$req" ] || continue
    process_request "$workspace" "$req"
  done < <(find_pending "$resolved_dir")
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
