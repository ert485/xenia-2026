#!/usr/bin/env bats
setup() {
  cd "$BATS_TEST_DIRNAME/.."
  S="$BATS_TEST_TMPDIR/prefixes.json"
  printf '{\n  "oidc_sub_prefixes": {\n    "ert485/xenia-2026": "repo:ert485@6201488/xenia-2026@1384206368"\n  }\n}\n' > "$S"
  source scripts/lib/allowed-repos.sh
}

@test "a new repo's prefix is added and the existing entry is kept" {
  oidc_sub_prefix_set "$S" o/team "repo:o@11/team@22"
  [ "$(jq -r '.oidc_sub_prefixes["o/team"]' "$S")" = "repo:o@11/team@22" ]
  [ "$(jq -r '.oidc_sub_prefixes["ert485/xenia-2026"]' "$S")" = "repo:ert485@6201488/xenia-2026@1384206368" ]
}

@test "setting the same prefix twice changes nothing" {
  oidc_sub_prefix_set "$S" o/team "repo:o@11/team@22"
  cp "$S" "$BATS_TEST_TMPDIR/once.json"
  oidc_sub_prefix_set "$S" o/team "repo:o@11/team@22"
  cmp -s "$S" "$BATS_TEST_TMPDIR/once.json"
}

@test "the old mutable form is refused" {
  run oidc_sub_prefix_set "$S" o/team "repo:o/team"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not an immutable OIDC subject prefix"* ]] || return 1
  [ "$(jq -r '.oidc_sub_prefixes["o/team"] // "absent"' "$S")" = absent ]
}

@test "a prefix for another repo is refused" {
  run oidc_sub_prefix_set "$S" o/team "repo:o@11/other@22"
  [ "$status" -eq 1 ]
  run oidc_sub_prefix_set "$S" o/team "repo:x@11/team@22"
  [ "$status" -eq 1 ]
}

@test "a repo name with dots works" {
  oidc_sub_prefix_set "$S" o/team.app "repo:o@11/team.app@22"
  [ "$(jq -r '.oidc_sub_prefixes["o/team.app"]' "$S")" = "repo:o@11/team.app@22" ]
}
