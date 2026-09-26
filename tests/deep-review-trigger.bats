#!/usr/bin/env bats
# deep-review-trigger: decides whether a PR gets the deep review (component 7). First match wins:
# the deep-review label, then a risky changed path, then the sample rate.

setup() {
  KIT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export GIT_AUTHOR_NAME=kit GIT_AUTHOR_EMAIL=kit@example.invalid GIT_COMMITTER_NAME=kit GIT_COMMITTER_EMAIL=kit@example.invalid
  REPO="$BATS_TEST_TMPDIR/repo"; mkdir -p "$REPO"; cd "$REPO"
  git init -q -b main
  printf '# team repo\n' > README.md
  git add README.md && git commit -qm base
  BASE="$(git rev-parse HEAD)"
  git checkout -qb feature
  unset SAMPLE LABELS PR
}

commit() { git add -A && git commit -qm change; HEAD_SHA="$(git rev-parse HEAD)"; }

trigger() { run "$KIT/scripts/ci/deep-review-trigger.sh" "$BASE" "$HEAD_SHA"; }

@test "the deep-review label wins over a risky path and a bad SAMPLE" {
  mkdir -p scripts && printf 'echo hi\n' > scripts/x.sh && commit
  LABELS="review,deep-review" SAMPLE=banana PR=abc trigger
  [ "$status" -eq 0 ]
  [ "$output" = "run=true reason=label" ]
}

@test "the deep-review label wins even alone, with no other labels" {
  printf 'more\n' >> README.md && commit
  LABELS="deep-review" trigger
  [ "$status" -eq 0 ]
  [ "$output" = "run=true reason=label" ]
}

@test "a scripts/ change is a risky path" {
  mkdir -p scripts && printf 'echo hi\n' > scripts/x.sh && commit
  SAMPLE=all trigger
  [ "$status" -eq 0 ]
  [ "$output" = "run=true reason=risky-path scripts/x.sh" ]
}

@test "an infra/ change is a risky path" {
  mkdir -p infra && printf 'resource "aws_instance" "x" {}\n' > infra/x.tf && commit
  trigger
  [ "$status" -eq 0 ]
  [[ "$output" == "run=true reason=risky-path infra/x.tf" ]] || return 1
}

@test "a .github/ change is a risky path" {
  mkdir -p .github/workflows && printf 'name: x\n' > .github/workflows/x.yml && commit
  trigger
  [ "$status" -eq 0 ]
  [[ "$output" == "run=true reason=risky-path .github/workflows/x.yml" ]] || return 1
}

@test "a templates/ change is a risky path" {
  mkdir -p templates && printf 'x\n' > templates/x.yml && commit
  trigger
  [ "$status" -eq 0 ]
  [[ "$output" == "run=true reason=risky-path templates/x.yml" ]] || return 1
}

@test "a docs-only change with SAMPLE unset runs (sample all)" {
  printf 'more\n' >> README.md && commit
  trigger
  [ "$status" -eq 0 ]
  [ "$output" = "run=true reason=sample all" ]
}

@test "a docs-only change with SAMPLE=all runs (sample all)" {
  printf 'more\n' >> README.md && commit
  SAMPLE=all trigger
  [ "$status" -eq 0 ]
  [ "$output" = "run=true reason=sample all" ]
}

@test "SAMPLE=4 with PR=8 runs" {
  printf 'more\n' >> README.md && commit
  SAMPLE=4 PR=8 trigger
  [ "$status" -eq 0 ]
  [ "$output" = "run=true reason=sample 1-in-4" ]
}

@test "SAMPLE=4 with PR=9 does not run" {
  printf 'more\n' >> README.md && commit
  SAMPLE=4 PR=9 trigger
  [ "$status" -eq 0 ]
  [ "$output" = "run=false reason=sample 1-in-4" ]
}

@test "SAMPLE=banana exits 2" {
  printf 'more\n' >> README.md && commit
  SAMPLE=banana PR=1 trigger
  [ "$status" -eq 2 ]
}

@test "PR=abc with a sampling SAMPLE exits 2" {
  printf 'more\n' >> README.md && commit
  SAMPLE=4 PR=abc trigger
  [ "$status" -eq 2 ]
}

@test "SAMPLE=0 exits 2 (not a positive integer)" {
  printf 'more\n' >> README.md && commit
  SAMPLE=0 PR=1 trigger
  [ "$status" -eq 2 ]
}

@test "a label list with surrounding whitespace still matches" {
  printf 'more\n' >> README.md && commit
  LABELS=" review , deep-review " trigger
  [ "$status" -eq 0 ]
  [ "$output" = "run=true reason=label" ]
}

@test "a newline-separated label list matches too" {
  printf 'more\n' >> README.md && commit
  LABELS="$(printf 'review\ndeep-review\n')" trigger
  [ "$status" -eq 0 ]
  [ "$output" = "run=true reason=label" ]
}

@test "a non-matching label list falls through to sampling" {
  printf 'more\n' >> README.md && commit
  LABELS="review,breaking-ok" SAMPLE=all trigger
  [ "$status" -eq 0 ]
  [ "$output" = "run=true reason=sample all" ]
}

@test "bad base SHA exits 2" {
  printf 'more\n' >> README.md && commit
  run "$KIT/scripts/ci/deep-review-trigger.sh" "not-a-sha" "$HEAD_SHA"
  [ "$status" -eq 2 ]
}

@test "missing arguments exits 2" {
  run "$KIT/scripts/ci/deep-review-trigger.sh"
  [ "$status" -eq 2 ]
}
