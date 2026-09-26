#!/usr/bin/env bats
# Tests for plugin/hooks/stop-verify.sh: the Stop hook that runs the verifier (Task 32's
# plugin/scripts/agent-verify.sh) and blocks the stop until it passes, up to three attempts per
# session. Each test builds a fresh fixture repository, same shape as tests/agent-verify.bats'.

setup() {
  export GIT_CONFIG_GLOBAL=/dev/null
  export GIT_CONFIG_SYSTEM=/dev/null
  export KIT="$BATS_TEST_DIRNAME/.."
  export CLAUDE_PLUGIN_ROOT="$KIT/plugin"
  export HOOK="$KIT/plugin/hooks/stop-verify.sh"
  export REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q -b main
  git -C "$REPO" config user.email "fixture@example.invalid"
  git -C "$REPO" config user.name "Fixture"
  cat > "$REPO/.gitignore" <<'EOF'
.agent/
.agent-requests/
EOF
  printf 'check:\n\t@true\n' > "$REPO/Makefile"
  mkdir -p "$REPO/scripts" "$REPO/tests" "$REPO/docs/proofs"
  cat > "$REPO/scripts/hello.sh" <<'EOF'
#!/usr/bin/env bash
echo hello
EOF
  chmod +x "$REPO/scripts/hello.sh"
  # Built at runtime, not spelled out here, for the same reason as tests/agent-verify.bats: some
  # bats versions scan a file's raw text for this tag to plan the outer file's own test count.
  test_tag="@$(printf test)"
  printf '#!/usr/bin/env bats\n%s "hello" {\n  run true\n  [ "$status" -eq 0 ]\n}\n' "$test_tag" > "$REPO/tests/hello.bats"
  touch "$REPO/docs/proofs/.gitkeep"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "init"
  git -C "$REPO" switch -q -c agent/x
}

payload() {
  jq -n --arg cwd "$REPO" '{hook_event_name: "Stop", cwd: $cwd, session_id: "sess-1", transcript_path: "/tmp/none", stop_hook_active: false}'
}

run_hook() {
  run bash -c 'bash "$HOOK" <<< "$1"' _ "$(payload)"
}

counter_file() {
  printf '%s/.agent/stop-attempts-sess-1' "$REPO"
}

# A bare `[[ ... ]]` does not reliably fail a bats test on this platform's default bash (3.2:
# `set -e` does not trigger on a failing `[[ ]]`), so substring/prefix checks use these instead.
assert_contains() {
  case "$1" in
    *"$2"*) return 0 ;;
  esac
  echo "expected to find [$2] in: $1" >&2
  return 1
}

assert_prefix() {
  case "$1" in
    "$2"*) return 0 ;;
  esac
  echo "expected [$1] to start with [$2]" >&2
  return 1
}

@test "a passing fixture: no output, exit 0, no counter file" {
  run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$(counter_file)" ]
}

@test "a fixture with a 0-byte committed file blocks three times with the attempt count, then ends BLOCKED on the fourth" {
  : > "$REPO/docs/notes.md"
  git -C "$REPO" add -A
  git -C "$REPO" commit -qm "empty file"

  run_hook
  [ "$status" -eq 0 ]
  jq -e '.decision == "block"' <<< "$output"
  reason="$(jq -r .reason <<< "$output")"
  assert_contains "$reason" "attempt 1 of 3"
  assert_contains "$reason" "empty-files"
  [ -e "$(counter_file)" ]

  run_hook
  [ "$status" -eq 0 ]
  jq -e '.decision == "block"' <<< "$output"
  reason="$(jq -r .reason <<< "$output")"
  assert_contains "$reason" "attempt 2 of 3"

  run_hook
  [ "$status" -eq 0 ]
  jq -e '.decision == "block"' <<< "$output"
  reason="$(jq -r .reason <<< "$output")"
  assert_contains "$reason" "attempt 3 of 3"

  run_hook
  [ "$status" -eq 0 ]
  hook_output="$output"
  run jq -e '.decision' <<< "$hook_output"
  [ "$status" -ne 0 ]
  sysmsg="$(jq -r .systemMessage <<< "$hook_output")"
  assert_prefix "$sysmsg" "BLOCKED"
  [ -e "$(counter_file)" ]
}

@test "fixing the file after two blocks then stopping is allowed and the counter file is gone" {
  : > "$REPO/docs/notes.md"
  git -C "$REPO" add -A
  git -C "$REPO" commit -qm "empty file"

  run_hook
  run_hook
  [ -e "$(counter_file)" ]

  echo "now has content" > "$REPO/docs/notes.md"
  git -C "$REPO" commit -aqm "fix the file"

  run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$(counter_file)" ]
}

@test "a payload whose cwd is not a git repo: exit 0, no output" {
  export GIT_CEILING_DIRECTORIES="$BATS_TEST_TMPDIR"
  mkdir -p "$BATS_TEST_TMPDIR/plain"
  run bash -c 'bash "$HOOK" <<< "$1"' _ \
    "$(jq -n --arg cwd "$BATS_TEST_TMPDIR/plain" '{hook_event_name:"Stop", cwd:$cwd, session_id:"sess-1"}')"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "XENIA_VERIFY_ARGS can demote the empty-files check to a warning so the fixture passes" {
  : > "$REPO/docs/notes.md"
  git -C "$REPO" add -A
  git -C "$REPO" commit -qm "empty file"

  run bash -c 'XENIA_VERIFY_ARGS="--warn empty-files" bash "$HOOK" <<< "$1"' _ "$(payload)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$(counter_file)" ]
}

@test "the verifier missing: exit 0 with a systemMessage and no decision" {
  export CLAUDE_PLUGIN_ROOT="$BATS_TEST_TMPDIR/empty-plugin"
  mkdir -p "$CLAUDE_PLUGIN_ROOT"
  run_hook
  [ "$status" -eq 0 ]
  hook_output="$output"
  run jq -e '.decision' <<< "$hook_output"
  [ "$status" -ne 0 ]
  jq -e '.systemMessage | length > 0' <<< "$hook_output"
}

@test "hooks.json: the Stop hook is wired to stop-verify.sh" {
  jq -e '.hooks.Stop[0].hooks[0].command | contains("stop-verify.sh")' "$KIT/plugin/hooks/hooks.json"
}
