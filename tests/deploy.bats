#!/usr/bin/env bats
setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export TMP="$BATS_TEST_TMPDIR"
  export CONTRACT="infra/recipes/docker-box/box/compose-contract.sh"
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
  [ "$status" -eq 1 ]; [[ "$output" == *"40 hex"* ]]
  run infra/recipes/docker-box/box/deploy.sh ert485/xenia-2026 "$(printf 'a%.0s' $(seq 1 40))" x.test/xenia/app:sha-1 ../etc
  [ "$status" -eq 1 ]; [[ "$output" == *"relative path inside the repo"* ]]
  run infra/recipes/docker-box/box/deploy.sh xenia "$(printf 'a%.0s' $(seq 1 40))" x.test/xenia/app:sha-1 .
  [ "$status" -eq 1 ]; [[ "$output" == *"owner/name"* ]]
}
