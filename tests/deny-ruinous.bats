#!/usr/bin/env bats
# Tests for plugin/hooks/deny-ruinous.sh: the PreToolUse hook that denies a short, fixed list of
# ruinous commands (force push, deleting the workspace root, editing the firewall, writing under
# docs/proofs/ or .agent/) and allows everything else.

setup() {
  export KIT="$BATS_TEST_DIRNAME/.."
  export HOOK="$KIT/plugin/hooks/deny-ruinous.sh"
  export CWD="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$CWD"
  git -C "$CWD" init -q -b main
  git -C "$CWD" config user.email "fixture@example.invalid"
  git -C "$CWD" config user.name "Fixture"
  git -C "$CWD" commit -q --allow-empty -m init
}

bash_payload() {
  jq -n --arg cwd "$CWD" --arg cmd "$1" \
    '{hook_event_name:"PreToolUse", tool_name:"Bash", cwd:$cwd, tool_input:{command:$cmd}}'
}

write_payload() {
  jq -n --arg cwd "$CWD" --arg tool "$1" --arg fp "$2" \
    '{hook_event_name:"PreToolUse", tool_name:$tool, cwd:$cwd, tool_input:{file_path:$fp}}'
}

notebook_payload() {
  jq -n --arg cwd "$CWD" --arg np "$1" \
    '{hook_event_name:"PreToolUse", tool_name:"NotebookEdit", cwd:$cwd, tool_input:{notebook_path:$np}}'
}

run_hook_with() {
  run bash -c 'bash "$HOOK" <<< "$1"' _ "$1"
}

# A bare `[[ ... ]]` does not reliably fail a bats test on this platform's default bash (3.2:
# `set -e` does not trigger on a failing `[[ ]]`), so the prefix check below avoids it.
assert_prefix() {
  case "$1" in
    "$2"*) return 0 ;;
  esac
  echo "expected [$1] to start with [$2]" >&2
  return 1
}

assert_deny() {
  local rule="$1" reason
  [ "$status" -eq 0 ]
  jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<< "$output"
  reason="$(jq -r .hookSpecificOutput.permissionDecisionReason <<< "$output")"
  assert_prefix "$reason" "deny-ruinous $rule:"
}

assert_allow() {
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "force-push: denies every force-push shape" {
  for cmd in \
    "git push --force" \
    "git push -f origin x" \
    "git push -fu origin x" \
    "git push origin +main" \
    "git push origin :main" \
    "git push --force-with-lease"
  do
    run_hook_with "$(bash_payload "$cmd")"
    assert_deny force-push
  done
}

@test "force-push: a plain push is allowed" {
  for cmd in "git push -u origin agent/task-11" "git push origin HEAD"; do
    run_hook_with "$(bash_payload "$cmd")"
    assert_allow
  done
}

@test "delete-workspace: rm of the workspace root or something that resolves to it is denied" {
  for cmd in \
    "rm -rf /workspace" \
    'rm -rf "$XENIA_ROOT"/' \
    "rm -fr ." \
    "rm -r -f ~" \
    "rm --recursive --force /" \
    "rm -rf *"
  do
    run_hook_with "$(bash_payload "$cmd")"
    assert_deny delete-workspace
  done
}

@test "delete-workspace: git clean with -f and -x is denied, -n is allowed" {
  run_hook_with "$(bash_payload "git clean -fdx")"
  assert_deny delete-workspace

  run_hook_with "$(bash_payload "git clean -n")"
  assert_allow
}

@test "delete-workspace: an ordinary recursive rm elsewhere is allowed" {
  for cmd in "rm -rf node_modules" "rm -rf ./build" "rm -f a.txt"; do
    run_hook_with "$(bash_payload "$cmd")"
    assert_allow
  done
}

@test "firewall: writing the firewall scripts or sudoers is denied" {
  run_hook_with "$(write_payload Write ".devcontainer/init-firewall.sh")"
  assert_deny firewall
}

@test "firewall: a Bash command that rewrites or flushes the firewall is denied" {
  for cmd in \
    "sudo sed -i s/x/y/ /usr/local/bin/init-firewall.sh" \
    "sudo iptables -F" \
    "sudo iptables -P OUTPUT ACCEPT"
  do
    run_hook_with "$(bash_payload "$cmd")"
    assert_deny firewall
  done
}

@test "firewall: running init-firewall.sh with no write verb is allowed" {
  run_hook_with "$(bash_payload "sudo /usr/local/bin/init-firewall.sh")"
  assert_allow
}

@test "proofs: writing under docs/proofs/ is denied, reading it is allowed" {
  run_hook_with "$(write_payload Write "docs/proofs/x.md")"
  assert_deny proofs

  run_hook_with "$(write_payload Edit "/workspace/docs/proofs/x.md")"
  assert_deny proofs

  run_hook_with "$(bash_payload "echo hi > docs/proofs/x.md")"
  assert_deny proofs

  run_hook_with "$(bash_payload "cp /tmp/a docs/proofs/")"
  assert_deny proofs

  run_hook_with "$(bash_payload "cat docs/proofs/x.md")"
  assert_allow

  run_hook_with "$(bash_payload "grep -r foo docs/proofs")"
  assert_allow
}

@test "verifier-output: writing under .agent/ is denied, reading it is allowed" {
  run_hook_with "$(write_payload Write ".agent/STATUS.json")"
  assert_deny verifier-output

  run_hook_with "$(bash_payload "echo '{}' > .agent/STATUS.json")"
  assert_deny verifier-output

  run_hook_with "$(bash_payload "ls .agent")"
  assert_allow
}

@test "an ordinary Write elsewhere is allowed" {
  run_hook_with "$(write_payload Write "docs/notes.md")"
  assert_allow
}

@test "a malformed payload (a Write with no file_path) is allowed: not ours to judge" {
  run_hook_with "$(jq -n --arg cwd "$CWD" '{hook_event_name:"PreToolUse", tool_name:"Write", cwd:$cwd, tool_input:{}}')"
  assert_allow
}

@test "NotebookEdit on a proof path is denied via notebook_path" {
  run_hook_with "$(notebook_payload "docs/proofs/x.ipynb")"
  assert_deny proofs
}

@test "hooks.json: PreToolUse is wired to deny-ruinous.sh and SessionStart is unchanged" {
  jq -e '.hooks.PreToolUse[0].matcher == "Bash|Write|Edit|MultiEdit|NotebookEdit"' "$KIT/plugin/hooks/hooks.json"
  jq -e '.hooks.PreToolUse[0].hooks[0].command | contains("deny-ruinous.sh")' "$KIT/plugin/hooks/hooks.json"
  jq -e '.hooks.SessionStart[0].matcher == "startup|resume|clear|compact"' "$KIT/plugin/hooks/hooks.json"
  jq -e '.hooks.SessionStart[0].hooks[0].command | contains("inject-principles.sh")' "$KIT/plugin/hooks/hooks.json"
}
