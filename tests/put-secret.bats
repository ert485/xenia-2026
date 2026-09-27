#!/usr/bin/env bats
# Tests for scripts/put-secret.sh's name validation, in particular the app/<NAME> shape that
# deploy.sh (infra/recipes/docker-box/box/lib.sh's apply_ssm_app_params) later exports as an
# environment variable: a name it would reject at deploy time should be refused here too, before
# it is ever written to SSM. Every value below is an obvious fake, not a real secret.
setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export TMP="$BATS_TEST_TMPDIR"
  export FAKE_STATE="$TMP/state"; mkdir -p "$FAKE_STATE"
  export AWS_CALLS="$TMP/aws-calls"; : > "$AWS_CALLS"
  cp tests/helpers/aws-shim.sh "$TMP/aws"; chmod +x "$TMP/aws"
  export PATH="$TMP:$PATH"
  printf 'MEMBER_ACCOUNT_ID=111111111\nMANAGEMENT_ACCOUNT_ID=222222222\nZONE_ID=ZFAKEZONE\n' > "$TMP/kit.env"
  export KIT_ENV_FILE="$TMP/kit.env" FAKE_ACCOUNT=111111111
}

@test "put-secret.sh refuses app/stripe-key (deploy.sh would export it as an env var and can't)" {
  run bash -c 'printf "%s" "SECRET-VALUE-123" | scripts/put-secret.sh app/stripe-key'
  [ "$status" -eq 1 ]
  [[ "$output" == *"deploy.sh"* ]] || return 1
  [[ "$output" != *"SECRET-VALUE-123"* ]] || return 1
  run grep -q 'put-parameter' "$AWS_CALLS"
  [ "$status" -ne 0 ]
}

@test "put-secret.sh accepts app/STRIPE_KEY (shell-identifier-shaped)" {
  run bash -c 'printf "%s" "sk_test_FAKEVALUE123" | scripts/put-secret.sh app/STRIPE_KEY'
  [ "$status" -eq 0 ]
  grep -q 'put-parameter' "$AWS_CALLS"
  grep -q '/xenia/app/STRIPE_KEY' "$AWS_CALLS"
}

@test "put-secret.sh refuses a reserved app/<NAME> even though it is shell-identifier-shaped" {
  run bash -c 'printf "%s" "/fake/evil/bin" | scripts/put-secret.sh app/PATH'
  [ "$status" -eq 1 ]
  [[ "$output" == *"deploy.sh"* ]] || return 1
  run bash -c 'printf "%s" "http://fake.example.invalid" | scripts/put-secret.sh app/HEALTH_URL'
  [ "$status" -eq 1 ]
  [[ "$output" == *"deploy.sh"* ]]
}

@test "put-secret.sh keeps today's looser rule for gateway/ and gpu/ names" {
  run bash -c 'printf "%s" "fake-master-key" | scripts/put-secret.sh gateway/master-key'
  [ "$status" -eq 0 ]
  run bash -c 'printf "%s" "fake-gpu-token" | scripts/put-secret.sh gpu/api-token'
  [ "$status" -eq 0 ]
}
