#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

setup() {
  export KIT_ROOT="$BATS_TEST_TMPDIR/kit"; mkdir -p "$KIT_ROOT/scripts/lib" "$BATS_TEST_TMPDIR/bin"
  cp "$BATS_TEST_DIRNAME/../scripts/rollback.sh" "$KIT_ROOT/scripts/"
  cp "$BATS_TEST_DIRNAME/../scripts/lib/common.sh" "$KIT_ROOT/scripts/lib/"
  export CALLS="$BATS_TEST_TMPDIR/calls"; : > "$CALLS"
  export CURRENT="$BATS_TEST_TMPDIR/current"
  A="$(printf 'a%.0s' $(seq 40))"; B="$(printf 'b%.0s' $(seq 40))"; export A B
  printf 'previous=xenia/xenia-test-team:sha-%s\nrepo=ert485/xenia-test-team\nsha=%s\nimage=xenia/xenia-test-team:sha-%s\n' "$A" "$B" "$B" > "$CURRENT"
  cat > "$KIT_ROOT/scripts/box.sh" <<'SH'
#!/usr/bin/env bash
printf 'box.sh %s\n' "$*" >> "$CALLS"
if [[ "$*" == *"Action=current"* ]]; then cat "$CURRENT"; fi
SH
  cat > "$KIT_ROOT/scripts/tf.sh" <<'SH'
#!/usr/bin/env bash
printf 'tf.sh %s\n' "$*" >> "$CALLS"
echo '{"ert485/xenia-test-team":"111111111.dkr.ecr.ca-central-1.amazonaws.com/xenia/xenia-test-team"}'
SH
  cat > "$BATS_TEST_TMPDIR/bin/gh" <<'SH'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >> "$CALLS"
[[ -n "${FAKE_APP_DIR:-}" ]] && echo "$FAKE_APP_DIR"
exit 0
SH
  chmod +x "$KIT_ROOT/scripts/"*.sh "$BATS_TEST_TMPDIR/bin/gh"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export R="$KIT_ROOT/scripts/rollback.sh"
}

@test "unknown flag is a usage error" {
  run --separate-stderr "$R" --bogus
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"usage: scripts/rollback.sh"* ]]
}

@test "nothing to roll back to after a single deploy" {
  sed -i.bak 's/^previous=.*/previous=none/' "$CURRENT"
  run --separate-stderr "$R" --app-dir .
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"nothing to roll back to"* ]]
  ! grep -q 'xenia-deploy' "$CALLS"
}

@test "re-sends xenia-deploy with the previous image and the commit it was built from" {
  run --separate-stderr "$R" --app-dir web
  [ "$status" -eq 0 ]
  grep -qx "box.sh xenia-deploy Repo=ert485/xenia-test-team Sha=$A Image=111111111.dkr.ecr.ca-central-1.amazonaws.com/xenia/xenia-test-team:sha-$A AppDir=web" "$CALLS"
}

@test "AppDir comes from the repo variable when no flag is given, else defaults to ." {
  FAKE_APP_DIR=infra/examples/hello-docker-box run --separate-stderr "$R"
  grep -q 'gh variable get APP_DIR --repo ert485/xenia-test-team' "$CALLS"
  grep -q 'AppDir=infra/examples/hello-docker-box$' "$CALLS"
  : > "$CALLS"
  run --separate-stderr "$R"
  grep -q 'AppDir=\.$' "$CALLS"
}

@test "--dry-run prints the plan with the account masked and sends nothing" {
  run --separate-stderr "$R" --app-dir . --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would send xenia-deploy Repo=ert485/xenia-test-team"* ]]
  ! grep -q 'box.sh xenia-deploy' "$CALLS"
}

@test "a previous tag that is not sha-<commit> keeps the current commit" {
  sed -i.bak 's/^previous=.*/previous=xenia\/xenia-test-team:latest/' "$CURRENT"
  run --separate-stderr "$R" --app-dir .
  [ "$status" -eq 0 ]
  grep -q "xenia-deploy Repo=ert485/xenia-test-team Sha=$B Image=.*:latest AppDir=." "$CALLS"
}

@test "stderr appended after a tab on the last output line does not break parsing" {
  printf 'previous=xenia/xenia-test-team:sha-%s\nrepo=ert485/xenia-test-team\nsha=%s\nimage=xenia/xenia-test-team:sha-%s\tsome stderr\n' "$A" "$B" "$B" > "$CURRENT"
  run --separate-stderr "$R" --app-dir .
  [ "$status" -eq 0 ]
  grep -q "Sha=$A " "$CALLS"
}