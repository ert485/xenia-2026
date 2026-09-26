#!/usr/bin/env bats
setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export TMP="$BATS_TEST_TMPDIR"
  export CONTRACT="infra/recipes/docker-box/box/compose-contract.sh"
  DEPLOY="infra/recipes/docker-box/box/deploy.sh"

  # Fixtures for deploy.sh's health-check revert: fake git (clones a fixture compose.yml with a web
  # service, so the real check_compose_contract passes), fake aws (the shared shim; ecr
  # get-login-password just needs to exit 0), fake docker (records calls in $CALLS; "inspect" answers
  # from $RUNNING_IMAGE, "up" overwrites it with $IMAGE, simulating the container it just started),
  # and a fake curl standing in for the Caddy health check: healthy unless $RUNNING_IMAGE's tag says
  # "bad" or nothing is running yet. HEALTH_URL bypasses the real --resolve/APP_HOST plumbing.
  export CALLS="$TMP/calls"; : > "$CALLS"
  export APP_STATE_DIR="$TMP/app-state"; mkdir -p "$APP_STATE_DIR"
  export RUNNING_IMAGE="$TMP/running-image"
  export HEALTH_URL="http://health.invalid/"
  printf 'ZONE=26.cohack.tetl.ca\nAPP_PORT=3000\n' > "$TMP/xenia.env"
  export XENIA_ENV_FILE="$TMP/xenia.env"
  printf 'services:\n  web:\n    image: ${IMAGE:-web:local}\n    build: .\n' > "$TMP/fixture-compose.yml"
  export FIXTURE_COMPOSE="$TMP/fixture-compose.yml"

  BIN="$TMP/bin"; mkdir -p "$BIN"
  cat > "$BIN/git" <<'SH'
#!/usr/bin/env bash
printf 'git %s\n' "$*" >> "$CALLS"
if [[ "$1" == "clone" ]]; then
  dest="${!#}"
  mkdir -p "$dest"
  cp "$FIXTURE_COMPOSE" "$dest/compose.yml"
fi
exit 0
SH

  cat > "$BIN/docker" <<'SH'
#!/usr/bin/env bash
printf 'docker %s\n' "$*" >> "$CALLS"
case "$*" in
  login*)
    cat >/dev/null
    exit 0 ;;
  inspect*)
    if [[ -s "$RUNNING_IMAGE" ]]; then cat "$RUNNING_IMAGE"; exit 0; fi
    exit 1 ;;
  *" up -d --no-build --remove-orphans")
    printf '%s\n' "$IMAGE" > "$RUNNING_IMAGE"
    exit 0 ;;
  *)
    exit 0 ;;
esac
SH

  cat > "$BIN/curl" <<'SH'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >> "$CALLS"
img="$(cat "$RUNNING_IMAGE" 2>/dev/null || true)"
case "$img" in
  *bad*) exit 1 ;;
  "") exit 1 ;;
  *) exit 0 ;;
esac
SH

  cp "$BATS_TEST_DIRNAME/helpers/aws-shim.sh" "$BIN/aws"
  chmod +x "$BIN/git" "$BIN/docker" "$BIN/curl" "$BIN/aws"
  export PATH="$BIN:$PATH"

  SHA="$(printf 'a%.0s' $(seq 1 40))"
  OLD_IMAGE="111111111.dkr.ecr.ca-central-1.amazonaws.com/xenia/xenia-test-team:sha-old"
  NEW_GOOD_IMAGE="111111111.dkr.ecr.ca-central-1.amazonaws.com/xenia/xenia-test-team:sha-newgood"
  NEW_BAD_IMAGE="111111111.dkr.ecr.ca-central-1.amazonaws.com/xenia/xenia-test-team:sha-newbad"
  # Deliberately NOT what's running: $APP_STATE_DIR/previous is one generation behind by design
  # (only a passing health check advances it), so a revert that reads the file instead of asking
  # docker what's actually running would restore this instead of $OLD_IMAGE.
  STALE_PREVIOUS_IMAGE="111111111.dkr.ecr.ca-central-1.amazonaws.com/xenia/xenia-test-team:sha-stale"
}

compose() { printf '%b' "$1" > "$TMP/compose.yml"; }

@test "contract accepts a top-level web service (2-space indent)" {
  compose 'services:\n  web:\n    build: .\n  db:\n    image: postgres:16\n'
  run bash -c 'source "$CONTRACT"; check_compose_contract "$TMP/compose.yml"'
  [ "$status" -eq 0 ]
}

@test "contract accepts 4-space indent, a quoted name, and a leading name: key" {
  compose 'name: demo\nservices:\n    "web":\n        image: x\n'
  run bash -c 'source "$CONTRACT"; check_compose_contract "$TMP/compose.yml"'
  [ "$status" -eq 0 ]
}

@test "contract rejects a compose without a web service" {
  compose 'services:\n  api:\n    build: .\n  db:\n    image: postgres:16\n'
  run bash -c 'source "$CONTRACT"; check_compose_contract "$TMP/compose.yml"'
  [ "$status" -eq 1 ]
  [[ "$output" == *"needs a service named web"* ]]
}

@test "contract ignores web when it only appears nested or outside services" {
  compose 'services:\n  api:\n    web: nope\n    depends_on: [web]\nvolumes:\n  web: {}\n'
  run bash -c 'source "$CONTRACT"; check_compose_contract "$TMP/compose.yml"'
  [ "$status" -eq 1 ]
}

@test "deploy.sh refuses a bad sha, an app dir with .., and a repo that is not owner/name" {
  run infra/recipes/docker-box/box/deploy.sh ert485/xenia-2026 notasha x.test/xenia/app:sha-1 .
  [ "$status" -eq 1 ]; [[ "$output" == *"40 hex"* ]] || return 1
  run infra/recipes/docker-box/box/deploy.sh ert485/xenia-2026 "$(printf 'a%.0s' $(seq 1 40))" x.test/xenia/app:sha-1 ../etc
  [ "$status" -eq 1 ]; [[ "$output" == *"relative path inside the repo"* ]] || return 1
  run infra/recipes/docker-box/box/deploy.sh xenia "$(printf 'a%.0s' $(seq 1 40))" x.test/xenia/app:sha-1 .
  [ "$status" -eq 1 ]; [[ "$output" == *"owner/name"* ]]
}

@test "a healthy deploy updates previous and exits 0" {
  printf '%s\n' "$OLD_IMAGE" > "$RUNNING_IMAGE"
  HEALTH_TIMEOUT=3 HEALTH_POLL_INTERVAL=1 run "$DEPLOY" ert485/xenia-2026 "$SHA" "$NEW_GOOD_IMAGE" .
  [ "$status" -eq 0 ]
  [ "$(cat "$APP_STATE_DIR/previous")" = "$OLD_IMAGE" ]
  [ "$(jq -r .image "$APP_STATE_DIR/current.json")" = "$NEW_GOOD_IMAGE" ]
  [[ "$output" == *"deployed ert485/xenia-2026"* ]]
}

@test "an unhealthy deploy reverts to the image actually running, not previous's stale value, and leaves previous untouched, exiting 1" {
  # $RUNNING_IMAGE (what docker inspect reports) and $APP_STATE_DIR/previous are seeded to
  # DIFFERENT images on purpose: if the revert ever read the file instead of asking docker what's
  # running, it would redeploy $STALE_PREVIOUS_IMAGE and this test would catch it.
  printf '%s\n' "$OLD_IMAGE" > "$RUNNING_IMAGE"
  printf '%s\n' "$STALE_PREVIOUS_IMAGE" > "$APP_STATE_DIR/previous"
  HEALTH_TIMEOUT=1 HEALTH_POLL_INTERVAL=1 run "$DEPLOY" ert485/xenia-2026 "$SHA" "$NEW_BAD_IMAGE" .
  [ "$status" -eq 1 ]
  [ "$(cat "$RUNNING_IMAGE")" = "$OLD_IMAGE" ]
  [ "$(cat "$APP_STATE_DIR/previous")" = "$STALE_PREVIOUS_IMAGE" ]
  [ "$(grep -c ' up -d --no-build --remove-orphans' "$CALLS")" -eq 2 ]
  [[ "$output" == *"rolled back to $OLD_IMAGE"* ]]
}

@test "an unhealthy deploy with no previous image exits 2 and says so" {
  rm -f "$RUNNING_IMAGE" "$APP_STATE_DIR/previous"
  HEALTH_TIMEOUT=1 HEALTH_POLL_INTERVAL=1 run "$DEPLOY" ert485/xenia-2026 "$SHA" "$NEW_BAD_IMAGE" .
  [ "$status" -eq 2 ]
  [ ! -f "$APP_STATE_DIR/previous" ]
  [ "$(grep -c ' up -d --no-build --remove-orphans' "$CALLS")" -eq 1 ]
  [[ "$output" == *"no previous image"* ]]
}

@test "HEALTH_TIMEOUT=abc is refused" {
  HEALTH_TIMEOUT=abc run "$DEPLOY" ert485/xenia-2026 "$SHA" "$NEW_GOOD_IMAGE" .
  [ "$status" -eq 1 ]
  [[ "$output" == *"HEALTH_TIMEOUT"* ]] || return 1
  [[ "$output" == *"positive integer"* ]]
}
