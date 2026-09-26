#!/usr/bin/env bats
# Before any AWS or GitHub change, onboard-repo.sh refuses a repo whose derived IAM role names
# would exceed 64 characters, and a repo whose owner-repo slug collides with an already allowed
# repo's (Task 4's review, carried into Task 17). A fake `gh` guards the tests: if either check
# were missing, the script would reach step 1's real `gh repo view` next, which the fake refuses
# instead of touching the network.
setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export KIT_ROOT="$BATS_TEST_TMPDIR/kit"
  mkdir -p "$KIT_ROOT/scripts/lib" "$KIT_ROOT/infra/platform"
  cp scripts/lib/allowed-repos.sh "$KIT_ROOT/scripts/lib/allowed-repos.sh"
  printf '{"allowed_repos": {"a/b-c": ["deploy-docker-box.yml"]}}\n' > "$KIT_ROOT/infra/platform/allowed-repos.auto.tfvars.json"
  export KIT_ENV_FILE="$BATS_TEST_TMPDIR/kit.local.env"
  printf 'MEMBER_ACCOUNT_ID=%s\nMANAGEMENT_ACCOUNT_ID=%s\nZONE_ID=ZFAKE\n' \
    "$(printf '%012d' 111111111)" "$(printf '%012d' 222222222)" > "$KIT_ENV_FILE"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/usr/bin/env bash\nprintf "FAKE_GH_CALLED: %%s\\n" "$*" >&2\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/gh"
  chmod +x "$BATS_TEST_TMPDIR/bin/gh"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "onboard-repo.sh refuses a repo whose derived IAM role name would exceed 64 characters" {
  long_owner="$(printf 'o%.0s' $(seq 1 40))"
  long_repo="$(printf 'r%.0s' $(seq 1 40))"
  run scripts/onboard-repo.sh "$long_owner/$long_repo" --owners @a
  [ "$status" -eq 1 ]
  [[ "$output" == *"IAM role name too long"* ]] || return 1
  [[ "$output" == *"max 64"* ]] || return 1
  [[ "$output" != *"FAKE_GH_CALLED"* ]]
}

@test "onboard-repo.sh refuses a repo whose owner-repo slug collides with an already allowed repo" {
  run scripts/onboard-repo.sh "a-b/c" --owners @a
  [ "$status" -eq 1 ]
  [[ "$output" == *"IAM role name collision"* ]] || return 1
  [[ "$output" == *"a-b/c"* ]] || return 1
  [[ "$output" == *"a/b-c"* ]] || return 1
  [[ "$output" != *"FAKE_GH_CALLED"* ]]
}
