#!/usr/bin/env bats
# Tests for plugin/scripts/agent-verify.sh (Task 32). Each test builds a fresh fixture
# repository and runs the verifier from this kit checkout, never the kit's own `make check`.

setup() {
  export GIT_CONFIG_GLOBAL=/dev/null
  export GIT_CONFIG_SYSTEM=/dev/null
  export KIT="$BATS_TEST_DIRNAME/.."
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
  # The fixture's own test-tag is built at runtime, not spelled out here: some bats versions scan
  # a file's raw text for that tag (heredoc or not) to plan its test count, so a literal one in
  # this outer file's fixture data miscounts the outer file's own tests.
  test_tag="@$(printf test)"
  printf '#!/usr/bin/env bats\n%s "hello" {\n  run true\n  [ "$status" -eq 0 ]\n}\n' "$test_tag" > "$REPO/tests/hello.bats"
  touch "$REPO/docs/proofs/.gitkeep"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "init"
  git -C "$REPO" switch -q -c agent/x
}

verify() {
  run "$KIT/plugin/scripts/agent-verify.sh" --worktree "$REPO" "$@"
}

status_json() { jq -r "$1" "$REPO/.agent/STATUS.json"; }

@test "pass: a clean branch with a script change and a test change" {
  echo "echo again" >> "$REPO/scripts/hello.sh"
  echo "# note" >> "$REPO/tests/hello.bats"
  git -C "$REPO" commit -aqm "tweak"
  base_sha=$(git -C "$REPO" rev-parse main)
  head_sha=$(git -C "$REPO" rev-parse HEAD)

  verify
  [ "$status" -eq 0 ]
  [[ "$output" == *"agent-verify: pass"* ]]
  [ "$(status_json .status)" = "pass" ]
  [ "$(status_json .commit)" = "$head_sha" ]
  [ "$(status_json .base)" = "$base_sha" ]
  [ "$(status_json '.reasons | length')" -eq 0 ]
  [ "$(status_json 'keys | length')" -eq 8 ]
}

@test "replay Task 15: a fake proof is blocked until a result file backs it" {
  echo "Expected output (example)" > "$REPO/docs/proofs/2026-09-25-status.md"
  git -C "$REPO" add -A
  git -C "$REPO" commit -qm "fake proof"

  verify
  [ "$status" -eq 1 ]
  [ "$(status_json '[.reasons[] | select(.check=="proofs-unbacked")] | length')" -eq 1 ]
  msg=$(status_json '.reasons[] | select(.check=="proofs-unbacked") | .message')
  [[ "$msg" == *"docs/proofs/2026-09-25-status.md"* ]]

  mkdir -p "$REPO/.agent-requests"
  echo "backed by docs/proofs/2026-09-25-status.md" > "$REPO/.agent-requests/001-status.result.md"

  verify
  [ "$(status_json '[.reasons[] | select(.check=="proofs-unbacked")] | length')" -eq 0 ]
}

@test "replay Task 20: zero-byte and whitespace-only files block, .gitkeep is spared" {
  mkdir -p "$REPO/team-kit/print"
  : > "$REPO/team-kit/print/qr.png"
  : > "$REPO/team-kit/print/qr.svg"
  printf '   \n\n' > "$REPO/team-kit/print/whitespace.txt"
  touch "$REPO/team-kit/print/.gitkeep"
  git -C "$REPO" add -A
  git -C "$REPO" commit -qm "empty files"

  verify
  [ "$status" -eq 1 ]
  [ "$(status_json '[.reasons[] | select(.check=="empty-files")] | length')" -eq 3 ]
  run jq -e '.reasons[] | select(.message | contains(".gitkeep"))' "$REPO/.agent/STATUS.json"
  [ "$status" -ne 0 ]
}

@test "replay Task 29: a hidden make-check failure blocks and an unjustified fallback warns" {
  printf 'check:\n\t@exit 1\n' > "$REPO/Makefile"
  echo 'make check 2>/dev/null || echo "make check not available"' >> "$REPO/scripts/hello.sh"
  git -C "$REPO" add -A
  git -C "$REPO" commit -qm "hide failure"

  verify
  [ "$status" -eq 1 ]
  [ "$(status_json '[.reasons[] | select(.check=="make-check")] | length')" -eq 1 ]
  make_msg=$(status_json '.reasons[] | select(.check=="make-check") | .message')
  [[ "$make_msg" == "Makefile:"* ]]
  [[ "$make_msg" == *"2"* ]]
  [ -f "$REPO/.agent/make-check.log" ]

  [ "$(status_json '[.warnings[] | select(.check=="failure-hiding")] | length')" -eq 1 ]
  fh_msg=$(status_json '.warnings[] | select(.check=="failure-hiding") | .message')
  [[ "$fh_msg" == "scripts/hello.sh:"* ]]
}

@test "an ok-to-hide justification suppresses the failure-hiding warning" {
  {
    echo "# ok-to-hide: fixture"
    echo 'make check 2>/dev/null || echo "make check not available"'
  } >> "$REPO/scripts/hello.sh"
  git -C "$REPO" add -A
  git -C "$REPO" commit -qm "hide failure justified"

  verify
  [ "$(status_json '[.warnings[] | select(.check=="failure-hiding")] | length')" -eq 0 ]
}

@test "root-files: stray untracked reports block; REPORT.md, an allow-listed name, and a new dir are spared" {
  echo "done" > "$REPO/TASK_15_COMPLETE.md"
  echo "done" > "$REPO/FINAL_REPORT.md"
  echo "status" > "$REPO/REPORT.md"
  mkdir -p "$REPO/.agent-verify"
  echo "MYFILE.md" > "$REPO/.agent-verify/root-allow"
  echo "ok" > "$REPO/MYFILE.md"
  mkdir -p "$REPO/newdir"
  echo "ok" > "$REPO/newdir/file.md"

  verify
  [ "$status" -eq 1 ]
  [ "$(status_json '[.reasons[] | select(.check=="root-files")] | length')" -eq 2 ]
  run jq -e '.reasons[] | select(.message | startswith("REPORT.md"))' "$REPO/.agent/STATUS.json"
  [ "$status" -ne 0 ]
  run jq -e '.reasons[] | select(.message | startswith("MYFILE.md"))' "$REPO/.agent/STATUS.json"
  [ "$status" -ne 0 ]
  run jq -e '.reasons[] | select(.message | contains("newdir"))' "$REPO/.agent/STATUS.json"
  [ "$status" -ne 0 ]
}

@test "make-check: a check target removed since the base commit blocks" {
  rm "$REPO/Makefile"
  git -C "$REPO" add -A
  git -C "$REPO" commit -qm "remove makefile"

  verify
  [ "$status" -eq 1 ]
  msg=$(status_json '.reasons[] | select(.check=="make-check") | .message')
  [[ "$msg" == *"check target removed"* ]]
}

@test "scripts-without-tests warns alone, not when a test also changed" {
  echo "echo more" >> "$REPO/scripts/hello.sh"
  git -C "$REPO" commit -aqm "script only"

  verify
  [ "$(status_json '[.warnings[] | select(.check=="scripts-without-tests")] | length')" -ge 1 ]

  echo "echo more2" >> "$REPO/scripts/hello.sh"
  echo "# t" >> "$REPO/tests/hello.bats"
  git -C "$REPO" commit -aqm "script and test"

  verify
  [ "$(status_json '[.warnings[] | select(.check=="scripts-without-tests")] | length')" -eq 0 ]
}

@test "uncommitted-changes warns, dirty is true, and an uncommitted 0-byte file still blocks" {
  : > "$REPO/scripts/hello.sh"

  verify
  [ "$status" -eq 1 ]
  [ "$(status_json .dirty)" = "true" ]
  [ "$(status_json '[.warnings[] | select(.check=="uncommitted-changes")] | length')" -ge 1 ]
  [ "$(status_json '[.reasons[] | select(.check=="empty-files")] | length')" -ge 1 ]
}

@test "--skip drops a check and --warn demotes one to pass" {
  printf 'check:\n\t@exit 1\n' > "$REPO/Makefile"
  git -C "$REPO" commit -aqm "break check"
  echo "Expected output (example)" > "$REPO/docs/proofs/2026-09-25-status.md"
  git -C "$REPO" add -A
  git -C "$REPO" commit -qm "fake proof"

  verify --skip make-check
  [ "$(status_json '[.reasons[] | select(.check=="make-check")] | length')" -eq 0 ]

  verify --skip make-check --warn proofs-unbacked
  [ "$status" -eq 0 ]
  [ "$(status_json '[.warnings[] | select(.check=="proofs-unbacked")] | length')" -eq 1 ]
  [ "$(status_json '[.reasons[] | select(.check=="proofs-unbacked")] | length')" -eq 0 ]
}

@test "REPORT.md is never read as evidence, and the script names it exactly once" {
  printf 'check:\n\t@exit 1\n' > "$REPO/Makefile"
  cat > "$REPO/REPORT.md" <<'EOF'
Tests: 7/7 passed
Stuck: None
EOF
  git -C "$REPO" add -A
  git -C "$REPO" commit -qm "misleading report"

  verify
  [ "$status" -eq 1 ]
  [ "$(status_json .status)" = "blocked" ]

  count=$(grep -c 'REPORT.md' "$KIT/plugin/scripts/agent-verify.sh")
  [ "$count" -eq 1 ]
}

@test "a bogus --base ref and running outside a git worktree both error" {
  verify --base refs/does/not/exist
  [ "$status" -eq 2 ]
  [ "$(status_json .status)" = "error" ]

  run "$KIT/plugin/scripts/agent-verify.sh" --worktree "$BATS_TEST_TMPDIR"
  [ "$status" -eq 2 ]
}

@test "an unknown check name to --skip exits 2" {
  verify --skip not-a-real-check
  [ "$status" -eq 2 ]
}

@test "--help lists all seven check names" {
  run "$KIT/plugin/scripts/agent-verify.sh" --help
  [ "$status" -eq 0 ]
  for c in make-check proofs-unbacked empty-files root-files failure-hiding scripts-without-tests uncommitted-changes; do
    [[ "$output" == *"$c"* ]]
  done
}
