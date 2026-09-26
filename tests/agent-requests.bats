#!/usr/bin/env bats
# Tests for scripts/agent-requests.sh (Task 34): the credential broker. Every test builds a fresh
# fixture workspace with its own .agent-requests/ dir and drives the script with `once`, feeding
# confirmation answers through AGENT_REQUESTS_TTY instead of a real terminal.

setup() {
  export KIT="$BATS_TEST_DIRNAME/.."
  export SCRIPT="$KIT/scripts/agent-requests.sh"
  export WS="$BATS_TEST_TMPDIR/workspace"
  mkdir -p "$WS/.agent-requests"
  export TTY="$BATS_TEST_TMPDIR/tty-answers"
  : > "$TTY"
}

# write_request <file> <command> <why> <what-it-changes> <expected> <undo> <then>
write_request() {
  local file="$1" command="$2" why="$3" changes="$4" expected="$5" undo="$6" then="$7"
  {
    printf '**Command**\n\n```bash\n%s\n```\n\n' "$command"
    printf '**Why**\n\n%s\n\n' "$why"
    printf '**What it changes**\n\n%s\n\n' "$changes"
    printf '**Expected result**\n\n%s\n\n' "$expected"
    printf '**Undo**\n\n%s\n\n' "$undo"
    printf '**Then**\n\n%s\n' "$then"
  } > "$file"
}

@test "y runs the command and writes a result with exit code and output" {
  write_request "$WS/.agent-requests/001-echo.md" 'echo hello-world' \
    "smoke test" "read-only" "prints hello-world" "not needed" "nothing else"
  printf 'y\n' > "$TTY"

  AGENT_REQUESTS_TTY="$TTY" run "$SCRIPT" once "$WS"
  [ "$status" -eq 0 ]
  [ -f "$WS/.agent-requests/001-echo.result.md" ]
  grep -qF -- '- Status: ran' "$WS/.agent-requests/001-echo.result.md" || return 1
  grep -qF -- '- Exit code: 0' "$WS/.agent-requests/001-echo.result.md" || return 1
  grep -qF -- 'hello-world' "$WS/.agent-requests/001-echo.result.md"
}

@test "n writes a declined result and runs nothing" {
  write_request "$WS/.agent-requests/002-marker.md" 'touch marker' \
    "smoke test" "creates marker" "a marker file" "rm marker" "nothing else"
  printf 'n\nnot ready yet\n' > "$TTY"

  AGENT_REQUESTS_TTY="$TTY" run "$SCRIPT" once "$WS"
  [ "$status" -eq 0 ]
  [ ! -e "$WS/marker" ]
  grep -qF -- '- Status: declined' "$WS/.agent-requests/002-marker.result.md" || return 1
  grep -qF -- 'not ready yet' "$WS/.agent-requests/002-marker.result.md"
}

@test "a request with no Command block is refused without prompting" {
  printf '**Why**\n\nno command here\n' > "$WS/.agent-requests/003-nocmd.md"

  AGENT_REQUESTS_TTY="$TTY" run "$SCRIPT" once "$WS"
  [ "$status" -eq 0 ]
  [[ "$output" != *'Run this command?'* ]] || return 1
  grep -qF -- '- Status: declined' "$WS/.agent-requests/003-nocmd.result.md" || return 1
  grep -qF -- 'no Command code block found' "$WS/.agent-requests/003-nocmd.result.md"
}

@test "a request with two command blocks is refused without prompting" {
  {
    printf '**Command**\n\n```bash\necho one\n```\n\n```bash\necho two\n```\n\n'
    printf '**Why**\n\ntwo blocks\n'
  } > "$WS/.agent-requests/004-twocmd.md"

  AGENT_REQUESTS_TTY="$TTY" run "$SCRIPT" once "$WS"
  [ "$status" -eq 0 ]
  [[ "$output" != *'Run this command?'* ]] || return 1
  grep -qF -- 'unbalanced or extra code fences' "$WS/.agent-requests/004-twocmd.result.md"
}

@test "a request with a slug outside [a-z0-9-] is refused without prompting" {
  write_request "$WS/.agent-requests/005-Bad_Slug.md" 'echo hi' "t" "read-only" "t" "t" "t"

  AGENT_REQUESTS_TTY="$TTY" run "$SCRIPT" once "$WS"
  [ "$status" -eq 0 ]
  [[ "$output" != *'Run this command?'* ]] || return 1
  grep -qF -- 'outside [a-z0-9-]' "$WS/.agent-requests/005-Bad_Slug.result.md"
}

@test "a symlinked request file is refused without prompting" {
  echo "not a real request" > "$BATS_TEST_TMPDIR/elsewhere.md"
  ln -s "$BATS_TEST_TMPDIR/elsewhere.md" "$WS/.agent-requests/006-linked.md"

  AGENT_REQUESTS_TTY="$TTY" run "$SCRIPT" once "$WS"
  [ "$status" -eq 0 ]
  [[ "$output" != *'Run this command?'* ]] || return 1
  grep -qF -- 'request file is a symlink' "$WS/.agent-requests/006-linked.result.md"
}

@test "a command longer than 2000 characters is refused without prompting" {
  local long_cmd
  long_cmd="echo $(printf 'a%.0s' $(seq 1 2000))"
  write_request "$WS/.agent-requests/007-toolong.md" "$long_cmd" "t" "read-only" "t" "t" "t"

  AGENT_REQUESTS_TTY="$TTY" run "$SCRIPT" once "$WS"
  [ "$status" -eq 0 ]
  [[ "$output" != *'Run this command?'* ]] || return 1
  grep -qF -- 'over the 2000 limit' "$WS/.agent-requests/007-toolong.result.md"
}

@test "a 12-digit number and an sk- key in the output are masked in the result" {
  write_request "$WS/.agent-requests/008-secrets.md" \
    'echo "account 123456789012 key sk-abcdefghijklmnop"' \
    "t" "read-only" "t" "t" "t"
  printf 'y\n' > "$TTY"

  AGENT_REQUESTS_TTY="$TTY" run "$SCRIPT" once "$WS"
  [ "$status" -eq 0 ]
  result="$WS/.agent-requests/008-secrets.result.md"
  grep -qF -- '123456789012' "$result" && return 1
  grep -qF -- 'sk-abcdefghijklmnop' "$result" && return 1
  grep -qF -- '<account-id>' "$result" || return 1
  grep -qF -- 'sk-<redacted>' "$result"
}

@test "a Proof line writes the proof file and the result names its path" {
  write_request "$WS/.agent-requests/009-proof.md" 'echo "proof output line"' \
    "t" "read-only" "t" "t" "Proof: docs/proofs/2026-09-26-broker-test.md"
  printf 'y\n' > "$TTY"

  AGENT_REQUESTS_TTY="$TTY" run "$SCRIPT" once "$WS"
  [ "$status" -eq 0 ]
  [ -f "$WS/docs/proofs/2026-09-26-broker-test.md" ]
  grep -qF -- 'proof output line' "$WS/docs/proofs/2026-09-26-broker-test.md" || return 1
  grep -qF -- 'docs/proofs/2026-09-26-broker-test.md' "$WS/.agent-requests/009-proof.result.md"
}

@test "the kit verifier's proofs-unbacked check passes for a broker-written proof" {
  write_request "$WS/.agent-requests/010-proof2.md" 'echo "verified output"' \
    "t" "read-only" "t" "t" "Proof: docs/proofs/2026-09-26-verify-test.md"
  printf 'y\n' > "$TTY"

  AGENT_REQUESTS_TTY="$TTY" run "$SCRIPT" once "$WS"
  [ "$status" -eq 0 ]
  [ -f "$WS/docs/proofs/2026-09-26-verify-test.md" ]

  export GIT_CONFIG_GLOBAL=/dev/null
  export GIT_CONFIG_SYSTEM=/dev/null
  git -C "$WS" init -q -b main
  git -C "$WS" config user.email "fixture@example.invalid"
  git -C "$WS" config user.name "Fixture"
  printf '.agent/\n' > "$WS/.gitignore"
  git -C "$WS" add -A
  git -C "$WS" commit -q -m "init"

  run "$KIT/plugin/scripts/agent-verify.sh" --worktree "$WS" --skip make-check
  [ "$status" -eq 0 ]
  [[ "$output" == *"agent-verify: pass"* ]]
}

@test "an existing .result.md is never overwritten" {
  write_request "$WS/.agent-requests/011-old.md" 'echo should-not-run' "t" "t" "t" "t" "t"
  printf '# Result: 011-old\n\n- Status: declined\n- Reason: already handled by a human\n' \
    > "$WS/.agent-requests/011-old.result.md"

  AGENT_REQUESTS_TTY="$TTY" run "$SCRIPT" once "$WS"
  [ "$status" -eq 0 ]
  [[ "$output" != *'Run this command?'* ]] || return 1
  grep -qF -- 'already handled by a human' "$WS/.agent-requests/011-old.result.md"
}

@test "once with no pending requests does nothing and exits 0" {
  AGENT_REQUESTS_TTY="$TTY" run "$SCRIPT" once "$WS"
  [ "$status" -eq 0 ]
}

@test "usage: missing arguments exit 2" {
  run "$SCRIPT"
  [ "$status" -eq 2 ]
  run "$SCRIPT" once
  [ "$status" -eq 2 ]
}

# --- Fix round 1: TOCTOU, symlink-escape, and display-spoofing hardening ---

@test "a non-regular request file (a fifo) is refused without prompting" {
  mkfifo "$WS/.agent-requests/017-fifo.md"

  AGENT_REQUESTS_TTY="$TTY" run timeout 10 "$SCRIPT" once "$WS"
  [ "$status" -eq 0 ]
  [[ "$output" != *'Run this command?'* ]] || return 1
  grep -qF -- 'not a regular file' "$WS/.agent-requests/017-fifo.result.md"
}

@test "a symlinked docs/proofs writes no file outside the workspace, and no proof is claimed" {
  mkdir -p "$BATS_TEST_TMPDIR/outside"
  mkdir -p "$WS/docs"
  ln -s "$BATS_TEST_TMPDIR/outside" "$WS/docs/proofs"
  write_request "$WS/.agent-requests/014-escape.md" 'echo "should not leave the workspace"' \
    "t" "read-only" "t" "t" "Proof: docs/proofs/2026-09-26-escape-test.md"
  printf 'y\n' > "$TTY"

  AGENT_REQUESTS_TTY="$TTY" run "$SCRIPT" once "$WS"
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/outside/2026-09-26-escape-test.md" ]
  result="$WS/.agent-requests/014-escape.result.md"
  grep -qF -- '- Status: ran' "$result" || return 1
  grep -qF -- 'proof not written' "$result" || return 1
  grep -qF -- 'Proof written:' "$result" && return 1
  true
}

@test "an ESC sequence in Why is shown escaped, not raw" {
  local esc
  esc=$'\x1b'
  write_request "$WS/.agent-requests/012-esc-why.md" 'echo hi' \
    "before${esc}[31mred${esc}[0mafter" "read-only" "t" "t" "t"
  printf 'n\n\n' > "$TTY"

  AGENT_REQUESTS_TTY="$TTY" run "$SCRIPT" once "$WS"
  [ "$status" -eq 0 ]
  [[ "$output" == *'^[[31mred^[[0m'* ]]
}

@test "a Command block containing a raw ESC byte is refused without prompting" {
  local esc file
  esc=$'\x1b'
  file="$WS/.agent-requests/013-esc-cmd.md"
  {
    printf '**Command**\n\n```bash\necho hi%s\n```\n\n' "$esc"
    printf '**Why**\n\nt\n'
  } > "$file"

  AGENT_REQUESTS_TTY="$TTY" run "$SCRIPT" once "$WS"
  [ "$status" -eq 0 ]
  [[ "$output" != *'Run this command?'* ]] || return 1
  grep -qF -- 'control character' "$WS/.agent-requests/013-esc-cmd.result.md"
}

@test "the prompt shows where the proof will be written, before asking y/N" {
  write_request "$WS/.agent-requests/015-proofprompt.md" 'echo hi' \
    "t" "read-only" "t" "t" "Proof: docs/proofs/2026-09-26-prompt-test.md"
  printf 'n\n\n' > "$TTY"

  AGENT_REQUESTS_TTY="$TTY" run "$SCRIPT" once "$WS"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Proof will be written to: docs/proofs/2026-09-26-prompt-test.md'* ]]
}

@test "the prompt says no proof when the request names none" {
  write_request "$WS/.agent-requests/016-noproof.md" 'echo hi' "t" "read-only" "t" "t" "nothing else"
  printf 'n\n\n' > "$TTY"

  AGENT_REQUESTS_TTY="$TTY" run "$SCRIPT" once "$WS"
  [ "$status" -eq 0 ]
  [[ "$output" == *'this request writes no proof'* ]]
}

@test "structural: the request is read once into memory; parsers work from text, not the path" {
  # A real TOCTOU race (the agent swapping the request file for a symlink mid-run) isn't
  # practical to trigger deterministically in bats, so this asserts the shape of the fix instead:
  # exactly one read of the path, and every extractor taking in-memory text afterward.
  grep -qF 'read_request_once() {' "$SCRIPT" || return 1
  [ "$(grep -c 'read_request_once "\$file"' "$SCRIPT")" -eq 1 ] || return 1
  ! grep -qE 'extract_(section|first_fence|proof_path)_from_text[^)]*"\$file"' "$SCRIPT"
}
