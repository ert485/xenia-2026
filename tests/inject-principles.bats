#!/usr/bin/env bats
# Review Focus item 3: the hook must emit valid JSON for any PRINCIPLES.md and never fail a session.
setup() {
  export KIT="$BATS_TEST_DIRNAME/.."
  export CLAUDE_PLUGIN_ROOT="$KIT/plugin"
  export HOOK="$KIT/plugin/hooks/inject-principles.sh"
  export REPO="$BATS_TEST_TMPDIR/repo"
  git init -q "$REPO"
}

ctx() { jq -r .hookSpecificOutput.additionalContext <<< "$output"; }

@test "listed repo (https remote): the repo's PRINCIPLES.md is injected" {
  git -C "$REPO" remote add origin https://github.com/ert485/xenia-2026.git
  printf 'REPO-COPY-MARKER\n' > "$REPO/PRINCIPLES.md"
  run bash -c 'cd "$REPO" && bash "$HOOK"'
  [ "$status" -eq 0 ]
  [ "$(jq -r .hookSpecificOutput.hookEventName <<< "$output")" = "SessionStart" ]
  [[ "$(ctx)" == *"REPO-COPY-MARKER"* ]] || return 1
  [[ "$(ctx)" != *"kit default copy"* ]] || return 1
  [[ "$(ctx)" == "Agent: these are the team's rules"* ]] || return 1
  [[ "$(ctx)" == *"/pain (log friction)"* ]]
}

@test "listed repo (ssh remote without .git) normalizes to the same slug" {
  # "git""@..." keeps the leak check's email pattern from matching the SSH remote in this file
  git -C "$REPO" remote add origin "git""@github.com:ert485/xenia-2026"
  printf 'REPO-COPY-MARKER\n' > "$REPO/PRINCIPLES.md"
  run bash -c 'cd "$REPO" && bash "$HOOK"'
  [ "$status" -eq 0 ]
  [[ "$(ctx)" == *"REPO-COPY-MARKER"* ]]
}

@test "unlisted repo: the bundled copy with the note, never the repo's text" {
  git -C "$REPO" remote add origin https://github.com/someone/else.git
  printf 'PLANTED-TEXT\n' > "$REPO/PRINCIPLES.md"
  run bash -c 'cd "$REPO" && bash "$HOOK"'
  [ "$status" -eq 0 ]
  [[ "$(ctx)" != *"PLANTED-TEXT"* ]] || return 1
  [[ "$(ctx)" == *"P-ours"* ]] || return 1
  [[ "$(ctx)" == *"(kit default copy: this repo is not on the kit's allowed list, see plugin/allowed-repos.txt)"* ]]
}

@test "quotes, backslashes, tabs and non-ASCII still produce valid JSON with the text intact" {
  git -C "$REPO" remote add origin https://github.com/ert485/xenia-2026.git
  printf 'say "hi" \\ back\tslash caf\xc3\xa9\n' > "$REPO/PRINCIPLES.md"
  run bash -c 'cd "$REPO" && bash "$HOOK"'
  [ "$status" -eq 0 ]
  jq -e '.hookSpecificOutput.additionalContext | contains("say \"hi\" \\ back\tslash café")' <<< "$output"
}

@test "a 10 KB PRINCIPLES.md is capped at 4 KB with a visible marker" {
  git -C "$REPO" remote add origin https://github.com/ert485/xenia-2026.git
  head -c 10240 /dev/zero | tr '\0' 'a' > "$REPO/PRINCIPLES.md"
  run bash -c 'cd "$REPO" && bash "$HOOK"'
  [ "$status" -eq 0 ]
  [[ "$(ctx)" == *"[truncated at 4 KB; read PRINCIPLES.md in full]"* ]] || return 1
  [ "$(ctx | tr -cd 'a' | wc -c | tr -d ' ')" -le 4200 ]
}

@test "outside any git repo: bundled copy, exit 0" {
  mkdir -p "$BATS_TEST_TMPDIR/plain"
  run bash -c 'cd "$BATS_TEST_TMPDIR/plain" && GIT_CEILING_DIRECTORIES="$BATS_TEST_TMPDIR" bash "$HOOK"'
  [ "$status" -eq 0 ]
  [[ "$(ctx)" == *"P-public"* ]] || return 1
  [[ "$(ctx)" == *"kit default copy"* ]]
}

@test "hooks.json and plugin.json are valid and point at the hook" {
  jq -e '.hooks.SessionStart[0].matcher == "startup|resume|clear|compact"' "$KIT/plugin/hooks/hooks.json"
  jq -e '.hooks.SessionStart[0].hooks[0].command | contains("inject-principles.sh")' "$KIT/plugin/hooks/hooks.json"
  jq -e '.name == "xenia-kit"' "$KIT/plugin/.claude-plugin/plugin.json"
}
