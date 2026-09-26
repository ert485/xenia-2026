#!/usr/bin/env bats
# shutdown-coverage: billable diffs need a shutdown.d change or a column-0 Shutdown line outside code fences.

setup() {
  KIT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export GIT_AUTHOR_NAME=kit GIT_AUTHOR_EMAIL=kit@example.invalid GIT_COMMITTER_NAME=kit GIT_COMMITTER_EMAIL=kit@example.invalid
  REPO="$BATS_TEST_TMPDIR/repo"; mkdir -p "$REPO"; cd "$REPO"
  git init -q -b main
  printf '# team repo\n' > README.md
  git add README.md && git commit -qm base
  BASE="$(git rev-parse HEAD)"
  git checkout -qb feature
  BODY="$BATS_TEST_TMPDIR/body.txt"; : > "$BODY"
  FENCE="$(printf '\140\140\140')"
  unset TEAM_REPO_DIR
}

commit() { git add -A && git commit -qm change; HEAD_SHA="$(git rev-parse HEAD)"; }

entry() {
  mkdir -p shutdown.d
  printf '%s\n' '#!/usr/bin/env bash' '# xenia-shutdown' '# stops: the probe box in ca-central-1' '# added-by: kit' \
    '# restore: not reversible' '# cost-when-running: about $0.01/hour' 'set -euo pipefail' \
    'if [[ "${DRY_RUN:-0}" == "1" ]]; then echo "would stop the probe box"; exit 0; fi' 'echo "stopped the probe box"' > "shutdown.d/$1"
  chmod +x "shutdown.d/$1"
}

cover() { run "$KIT/scripts/ci/shutdown-coverage.sh" "$BASE" "$HEAD_SHA" "$BODY"; }

@test "infra change without an entry or a Shutdown line fails with the policy" {
  mkdir -p infra && printf 'resource "aws_instance" "x" {}\n' > infra/x.tf && commit
  cover
  [ "$status" -eq 1 ]
  [[ "$output" == *"infra/x.tf"* ]]
  [[ "$output" == *"must either touch that repo's shutdown.d/"* ]]
}

@test "infra change with a new shutdown.d entry passes" {
  mkdir -p infra && printf 'resource "aws_instance" "x" {}\n' > infra/x.tf
  entry 50-x.sh && commit
  cover
  [ "$status" -eq 0 ]
  [[ "$output" == *"covered by a shutdown.d/ change"* ]]
}

@test "a CRLF Shutdown line at column 0 passes" {
  mkdir -p infra && printf 'resource "aws_instance" "x" {}\n' > infra/x.tf && commit
  printf 'What and why\r\n\r\nShutdown: none needed because docs only\r\n' > "$BODY"
  cover
  [ "$status" -eq 0 ]
  [[ "$output" == *"covered by the Shutdown: line"* ]]
}

@test "the same line indented by two spaces fails" {
  mkdir -p infra && printf 'resource "aws_instance" "x" {}\n' > infra/x.tf && commit
  printf 'What and why\n\n  Shutdown: none needed because docs only\n' > "$BODY"
  cover
  [ "$status" -eq 1 ]
}

@test "the line inside a code fence fails" {
  mkdir -p infra && printf 'resource "aws_instance" "x" {}\n' > infra/x.tf && commit
  printf '%s\n' 'Example:' "$FENCE" 'Shutdown: none needed because docs only' "$FENCE" > "$BODY"
  cover
  [ "$status" -eq 1 ]
}

@test "a Shutdown line with no reason fails" {
  mkdir -p infra && printf 'resource "aws_instance" "x" {}\n' > infra/x.tf && commit
  printf 'Shutdown: none needed because \n' > "$BODY"
  cover
  [ "$status" -eq 1 ]
}

@test "the template's unedited <reason> placeholder fails and says to fill it in" {
  mkdir -p infra && printf 'resource "aws_instance" "x" {}\n' > infra/x.tf && commit
  printf 'Rule-feedback: none\nShutdown: none needed because <reason>\n' > "$BODY"
  cover
  [ "$status" -eq 1 ]
  [[ "$output" == *"fill in the reason on the Shutdown: line"* ]]
}

@test "a compose file anywhere counts as billable" {
  mkdir -p api && printf 'services: {}\n' > api/docker-compose.yml && commit
  cover
  [ "$status" -eq 1 ]
  [[ "$output" == *"api/docker-compose.yml"* ]]
}

@test "a deploy workflow counts as billable" {
  mkdir -p .github/workflows && printf 'name: x\n' > .github/workflows/deploy-docker-box.yml && commit
  cover
  [ "$status" -eq 1 ]
}

@test "a README-only diff passes with an empty body" {
  printf 'more\n' >> README.md && commit
  cover
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing billable changed"* ]]
}

@test "an entry with a broken header fails even when nothing billable changed" {
  mkdir -p shutdown.d
  printf '%s\n' '#!/usr/bin/env bash' '# xenia-shutdown' '# stops: x' 'set -euo pipefail' > shutdown.d/60-bad.sh
  commit
  cover
  [ "$status" -eq 1 ]
  [[ "$output" == *"60-bad.sh"*"added-by"* ]]
}
