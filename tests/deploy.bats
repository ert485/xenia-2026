#!/usr/bin/env bats
setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export TMP="$BATS_TEST_TMPDIR"
  export CONTRACT="infra/recipes/docker-box/box/compose-contract.sh"
  export LIB="infra/recipes/docker-box/box/lib.sh"
  cp tests/helpers/aws-shim.sh "$TMP/aws"; chmod +x "$TMP/aws"
  export PATH="$TMP:$PATH"
}

# app_params_fixture <path>: writes a $FAKE_APP_PARAMS-shaped `get-parameters-by-path --output
# json` document exercising: a normal accepted name; the exact name/value from the hotfix brief
# that would blow up bash's `export NAME=value` on main and, per the workflow's masking (12-digit
# numbers only), leak straight into this public repo's Actions log; a multi-line value (stands in
# for a PEM key or pretty-printed JSON); and two reserved names (PATH, HEALTH_URL) that are
# otherwise shell-identifier-shaped. Every value here is an obvious fake, not a real secret.
app_params_fixture() {
  cat > "$1" <<'JSON'
{
  "Parameters": [
    {"Name": "/xenia/app/STRIPE_KEY", "Value": "sk_test_FAKEVALUE123"},
    {"Name": "/xenia/app/stripe-key", "Value": "SECRET-VALUE-123"},
    {"Name": "/xenia/app/MULTILINE_CFG", "Value": "fake-line-one\nfake-line-two\nfake-line-three"},
    {"Name": "/xenia/app/PATH", "Value": "/fake/evil/bin"},
    {"Name": "/xenia/app/HEALTH_URL", "Value": "http://fake.example.invalid/health"}
  ]
}
JSON
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

# --- apply_ssm_app_params (box/lib.sh): validates + exports /xenia/app/<NAME> parameters that
# deploy.sh reads as JSON instead of the old --output text loop. Sourced and unit-tested here
# (like ensure_networks in tests/ensure-networks.bats) rather than driven through a full
# deploy.sh run: deploy.sh clones into the hardcoded /srv/app/src, a path this repo (and CI) has
# no write access to outside the real Docker box.

@test "apply_ssm_app_params: a valid name reaches the environment docker compose would see" {
  app_params_fixture "$TMP/params.json"
  export FAKE_APP_PARAMS="$TMP/params.json"
  export ENV_DUMP="$TMP/env-dump"
  cat > "$TMP/docker" <<'EOF'
#!/usr/bin/env bash
[[ "$1 $2" == "compose up" ]] && env > "$ENV_DUMP"
exit 0
EOF
  chmod +x "$TMP/docker"
  run bash -c '
    source "$LIB"
    apply_ssm_app_params "$(aws ssm get-parameters-by-path --region ca-central-1 --path /xenia/app --with-decryption --output json)"
    docker compose up
  '
  [ "$status" -eq 0 ]
  grep -qx "STRIPE_KEY=sk_test_FAKEVALUE123" "$ENV_DUMP"
}

@test "apply_ssm_app_params: app/stripe-key with a secret value is skipped, stays exit 0, and the value never appears in output" {
  app_params_fixture "$TMP/params.json"
  export FAKE_APP_PARAMS="$TMP/params.json"
  run bash -c '
    source "$LIB"
    apply_ssm_app_params "$(aws ssm get-parameters-by-path --region ca-central-1 --path /xenia/app --with-decryption --output json)"
    echo deploy-continued
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"deploy-continued"* ]]
  [[ "$output" != *"SECRET-VALUE-123"* ]]
}

@test "apply_ssm_app_params: a multi-line value arrives intact" {
  app_params_fixture "$TMP/params.json"
  export FAKE_APP_PARAMS="$TMP/params.json"
  # 2>/dev/null: the fixture's other, deliberately-rejected entries each log one skip line (to
  # stderr, which `run` merges into $output); this test only cares about MULTILINE_CFG's value.
  run bash -c '
    source "$LIB"
    apply_ssm_app_params "$(aws ssm get-parameters-by-path --region ca-central-1 --path /xenia/app --with-decryption --output json)" 2>/dev/null
    printf "%s" "$MULTILINE_CFG"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'fake-line-one\nfake-line-two\nfake-line-three')" ]
}

@test "apply_ssm_app_params: PATH and HEALTH_URL are skipped (reserved names)" {
  app_params_fixture "$TMP/params.json"
  export FAKE_APP_PARAMS="$TMP/params.json"
  run bash -c '
    orig_path="$PATH"
    source "$LIB"
    apply_ssm_app_params "$(aws ssm get-parameters-by-path --region ca-central-1 --path /xenia/app --with-decryption --output json)"
    [[ "$PATH" == "$orig_path" ]] && echo "PATH unchanged"
    [[ -z "${HEALTH_URL:-}" ]] && echo "HEALTH_URL unset"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"PATH unchanged"* ]]
  [[ "$output" == *"HEALTH_URL unset"* ]]
}
