#!/usr/bin/env bats
setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export TMP="$BATS_TEST_TMPDIR"
  printf 'MEMBER_ACCOUNT_ID=111111111\nMANAGEMENT_ACCOUNT_ID=222222222\nZONE_ID=ZFAKEZONE\n' > "$TMP/kit.env"
  export KIT_ENV_FILE="$TMP/kit.env"
  export SHUTDOWN_D="$TMP/kit-shutdown.d"; mkdir -p "$SHUTDOWN_D"
  unset TEAM_REPO_DIR DRY_RUN
}

# entry <dir> <file> <body-line>: a well-formed entry whose body is one line
entry() {
  printf '%s\n' '#!/usr/bin/env bash' '# xenia-shutdown' "# stops: $2 things" '# added-by: kit' \
    '# restore: not reversible' '# cost-when-running: free' 'set -euo pipefail' "$3" > "$1/$2"
  chmod +x "$1/$2"
}

@test "every entry runs in order, a failure doesn't stop the rest, exit 1 names it" {
  entry "$SHUTDOWN_D" 10-a.sh 'echo "ran a"'
  entry "$SHUTDOWN_D" 20-b.sh 'echo "ran b"; exit 1'
  entry "$SHUTDOWN_D" 30-c.sh 'echo "ran c"'
  run scripts/shutdown.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"ran a"*"ran b"*"ran c"* ]]
  [[ "$output" == *"1 failed: kit/20-b.sh"* ]]
}

@test "TEAM_REPO_DIR unset: kit entries run, one skipped line, exit 0" {
  entry "$SHUTDOWN_D" 10-a.sh 'echo "ran a"'
  run scripts/shutdown.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"ran a"* ]]
  [ "$(printf '%s\n' "$output" | grep -c '^team repo skipped: TEAM_REPO_DIR unset$')" -eq 1 ]
}

@test "TEAM_REPO_DIR without shutdown.d: one skipped line naming the path, exit 0" {
  entry "$SHUTDOWN_D" 10-a.sh 'echo "ran a"'
  mkdir -p "$TMP/team"
  TEAM_REPO_DIR="$TMP/team" run scripts/shutdown.sh
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c "^team repo skipped: $TMP/team/shutdown.d not found$")" -eq 1 ]
}

@test "team entries run after the kit's" {
  entry "$SHUTDOWN_D" 10-a.sh 'echo "ran kit"'
  mkdir -p "$TMP/team/shutdown.d"
  entry "$TMP/team/shutdown.d" 40-t.sh 'echo "ran team"'
  TEAM_REPO_DIR="$TMP/team" run scripts/shutdown.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"ran kit"*"ran team"* ]]
  [[ "$output" != *"skipped"* ]]
}

@test "--dry-run sets DRY_RUN=1 for every entry" {
  entry "$SHUTDOWN_D" 10-a.sh 'echo "dry=${DRY_RUN:-unset}"'
  run scripts/shutdown.sh --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry=1"* ]]
}

@test "--offline validates and lists without running or loading kit.local.env" {
  entry "$SHUTDOWN_D" 10-a.sh 'echo "ran a"'
  KIT_ENV_FILE="$TMP/missing.env" run scripts/shutdown.sh --offline
  [ "$status" -eq 0 ]
  [[ "$output" == *"would run: "*"10-a.sh"* ]]
  [[ "$output" != *"ran a"* ]]
}

@test "--offline fails on a header missing a field" {
  printf '%s\n' '#!/usr/bin/env bash' '# xenia-shutdown' '# stops: x' 'set -euo pipefail' > "$SHUTDOWN_D/10-bad.sh"
  run scripts/shutdown.sh --offline
  [ "$status" -eq 1 ]
  [[ "$output" == *"10-bad.sh"*"added-by"* ]]
}

@test "startup.sh --no-gpu never calls gpu.sh; the default does" {
  export FAKE_STATE="$TMP/state" AWS_CALLS="$TMP/aws-calls" FAKE_ACCOUNT=111111111; mkdir -p "$FAKE_STATE"
  mkdir -p "$TMP/bin" "$TMP/kit/scripts/lib"
  cp tests/helpers/aws-shim.sh "$TMP/bin/aws"
  cp scripts/lib/common.sh "$TMP/kit/scripts/lib/common.sh"
  cp scripts/startup.sh "$TMP/kit/scripts/startup.sh"
  printf '#!/usr/bin/env bash\necho "gpu.sh $*" >> "%s"\n' "$TMP/calls" > "$TMP/kit/scripts/gpu.sh"
  printf '#!/usr/bin/env bash\necho "box.sh $*" >> "%s"\n' "$TMP/calls" > "$TMP/kit/scripts/box.sh"
  chmod +x "$TMP/bin/aws" "$TMP/kit/scripts/"*.sh
  : > "$TMP/calls"
  PATH="$TMP/bin:$PATH" KIT_ROOT="$TMP/kit" run "$TMP/kit/scripts/startup.sh" --no-gpu
  [ "$status" -eq 0 ]
  [[ "$output" == *"run scripts/status.sh in five minutes"* ]]
  [ "$(grep -c 'gpu.sh' "$TMP/calls")" -eq 0 ]
  PATH="$TMP/bin:$PATH" KIT_ROOT="$TMP/kit" run "$TMP/kit/scripts/startup.sh"
  [ "$status" -eq 0 ]
  grep -q 'gpu.sh start' "$TMP/calls"
}
