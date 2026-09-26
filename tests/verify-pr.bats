#!/usr/bin/env bats
# Tests for scripts/ci/verify-pr.sh: the check.yml verify job's shell snippet, extracted so it's
# testable (the pattern scripts/ci/shutdown-coverage.sh uses). Each test builds a fresh fixture
# repository and runs the script from this kit checkout, so it finds this kit's own verifier.

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
  mkdir -p "$REPO/docs/proofs"
  touch "$REPO/docs/proofs/.gitkeep"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "init"
  BASE_SHA="$(git -C "$REPO" rev-parse HEAD)"
}

verify() { (cd "$REPO" && "$KIT/scripts/ci/verify-pr.sh" "$BASE_SHA"); }

@test "a clean change passes with no ::error lines" {
  printf 'more\n' >> "$REPO/README.md"
  git -C "$REPO" add -A && git -C "$REPO" commit -qm "docs"
  run verify
  [ "$status" -eq 0 ]
  [[ "$output" == *"agent-verify: pass"* ]] || return 1
  [[ "$output" != *"::error"* ]]
}

@test "a 0-byte file fails with an ::error line naming it" {
  mkdir -p "$REPO/docs"
  : > "$REPO/docs/empty.txt"
  git -C "$REPO" add -A && git -C "$REPO" commit -qm "empty file"
  run verify
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error file=docs/empty.txt::docs/empty.txt: 0 bytes"* ]]
}

@test "a new docs/proofs/ file passes with a ::warning line" {
  echo "some real output" > "$REPO/docs/proofs/2026-09-26-test.md"
  git -C "$REPO" add -A && git -C "$REPO" commit -qm "proof"
  run verify
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning file=docs/proofs/2026-09-26-test.md::"* ]] || return 1
  [[ "$output" != *"::error"* ]]
}

@test "the all-zeros SHA is skipped without running the verifier" {
  zeros="$(printf '0%.0s' $(seq 1 40))"
  run bash -c "cd '$REPO' && '$KIT/scripts/ci/verify-pr.sh' '$zeros'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping"* ]]
}
