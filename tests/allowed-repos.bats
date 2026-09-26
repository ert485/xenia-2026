#!/usr/bin/env bats
setup() {
  cd "$BATS_TEST_DIRNAME/.."
  J="$BATS_TEST_TMPDIR/allowed.json"
  printf '{"allowed_repos": {"ert485/xenia-2026": ["publish-kit-site.yml", "deploy-docker-box.yml"]}}\n' > "$J"
  P="$BATS_TEST_TMPDIR/allowed-repos.txt"
  printf 'ert485/xenia-2026\n' > "$P"
  source scripts/lib/allowed-repos.sh
}

@test "adding a repo twice yields one entry with one workflow" {
  allowed_repos_add "$J" o/team deploy-docker-box.yml
  allowed_repos_add "$J" o/team deploy-docker-box.yml
  run jq -c '.allowed_repos["o/team"]' "$J"
  [ "$output" = '["deploy-docker-box.yml"]' ]
}

@test "an existing repo's workflow list is unchanged when the workflow is present" {
  allowed_repos_add "$J" ert485/xenia-2026 deploy-docker-box.yml
  run jq -c '.allowed_repos["ert485/xenia-2026"]' "$J"
  [ "$output" = '["publish-kit-site.yml","deploy-docker-box.yml"]' ]
}

@test "a new workflow is appended, other repos untouched" {
  allowed_repos_add "$J" o/team deploy-docker-box.yml
  allowed_repos_add "$J" o/team deploy-api.yml
  run jq -c '.allowed_repos["o/team"]' "$J"
  [ "$output" = '["deploy-docker-box.yml","deploy-api.yml"]' ]
  [ "$(jq '.allowed_repos | length' "$J")" -eq 2 ]
}

@test "plugin_allow appends once" {
  plugin_allow o/team "$P"
  plugin_allow o/team "$P"
  [ "$(grep -cx 'o/team' "$P")" -eq 1 ]
  [ "$(wc -l < "$P" | tr -d ' ')" -eq 2 ]
}
