#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export B="$BATS_TEST_TMPDIR/body.md"
}

@test "valid line with a reason prints slug TAB reason" {
  printf 'What and why\n\nRule-feedback: P-two-gates, merged a docs-only hotfix while check was red\n' > "$B"
  run --separate-stderr scripts/ci/rule-feedback.sh "$B"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'P-two-gates\tmerged a docs-only hotfix while check was red')" ]
}

@test "slug with no reason prints an empty reason" {
  printf 'Rule-feedback: P-wheel\n' > "$B"
  run --separate-stderr scripts/ci/rule-feedback.sh "$B"
  [ "$output" = "$(printf 'P-wheel\t')" ]
}

@test "Rule-feedback: none is omitted, and kept with --all" {
  printf 'Rule-feedback: none\n' > "$B"
  run --separate-stderr scripts/ci/rule-feedback.sh "$B"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run --separate-stderr scripts/ci/rule-feedback.sh --all "$B"
  [ "$output" = "$(printf 'none\t')" ]
}

@test "an indented line does not count" {
  printf '  Rule-feedback: P-two-gates, indented\n' > "$B"
  run --separate-stderr scripts/ci/rule-feedback.sh "$B"
  [ -z "$output" ]
}

@test "a line inside a fenced block does not count, with or without a language tag" {
  printf '```\nRule-feedback: P-wheel, inside a plain fence\n```\n```text\nRule-feedback: P-public, inside a tagged fence\n```\nRule-feedback: P-ours, after the fences\n' > "$B"
  run --separate-stderr scripts/ci/rule-feedback.sh "$B"
  [ "$output" = "$(printf 'P-ours\tafter the fences')" ]
}

@test "CRLF line endings are stripped before matching" {
  printf 'What and why\r\n\r\nRule-feedback: P-off-switch, console bucket for the demo\r\nShutdown: none needed because docs\r\n' > "$B"
  run --separate-stderr scripts/ci/rule-feedback.sh "$B"
  [ "$output" = "$(printf 'P-off-switch\tconsole bucket for the demo')" ]
  [[ "$output" != *$'\r'* ]]
}

@test "a line in the wrong format is ignored and reported on stderr" {
  printf 'Rule-feedback: P-Two-Gates, capitals are not a slug\nRule-feedback: P-two-gates,\n' > "$B"
  run --separate-stderr scripts/ci/rule-feedback.sh "$B"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"ignored (not the shared format): Rule-feedback: P-Two-Gates"* ]]
}

@test "several lines keep their order, the last line needs no newline, stdin works" {
  run --separate-stderr bash -c "printf 'Rule-feedback: P-two-gates, one\nRule-feedback: P-wheel, two' | scripts/ci/rule-feedback.sh -"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$(printf 'P-two-gates\tone')" ]
  [ "${lines[1]}" = "$(printf 'P-wheel\ttwo')" ]
}

@test "--lines prints the body with CR stripped and fenced blocks removed" {
  printf 'a\r\n```\nShutdown: none needed because fenced\n```\nShutdown: none needed because docs only\r\n' > "$B"
  run --separate-stderr scripts/ci/rule-feedback.sh --lines "$B"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'a\nShutdown: none needed because docs only')" ]
}

@test "usage error without a file" {
  run --separate-stderr scripts/ci/rule-feedback.sh
  [ "$status" -eq 2 ]
}
