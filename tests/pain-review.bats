#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

setup() {
  export KIT_ROOT="$BATS_TEST_DIRNAME/.."
  cd "$KIT_ROOT"
  export FAKE="$BATS_TEST_TMPDIR/fake"; mkdir -p "$FAKE/bin"
  export GH_CALLS="$FAKE/gh-calls"; : > "$GH_CALLS"
  export PAIN_REVIEW_DIR="$BATS_TEST_TMPDIR/work"
  export PAIN_REVIEW_NOW="2026-09-26T18:00Z"
  export PAIN_REVIEW_NOTIFY="$FAKE/bin/notify"
  unset GITHUB_REPOSITORY TEAM_REPO

  cat > "$FAKE/bin/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_CALLS"
save_body() { local prev=""; for a in "$@"; do [[ "$prev" == --body-file ]] && cp "$a" "$1"; prev="$a"; done; }
case "$*" in
  *"issue list"*"--label friction"*)      cat "$FAKE/friction.json" ;;
  *"pr list"*"--state merged"*)           cat "$FAKE/prs.json" ;;
  *"issue list"*"--label rule-feedback"*) cat "$FAKE/rf-issues.json" ;;
  *"issue list"*"--label next-fix"*)      if [[ -f "$FAKE/next-fix.json" ]]; then cat "$FAKE/next-fix.json"; else echo '[]'; fi ;;
  *"issue list"*"in:title"*)              echo '[{"number":9,"title":"Rule feedback ideas"},{"number":1,"title":"Rule feedback"}]' ;;
  *"issue edit"*)                         save_body "$FAKE/pinned-body.md" "$@" ;;
  *"issue create"*)                       save_body "$FAKE/created-body.md" "$@"; echo "https://github.com/ert485/xenia-test-team/issues/42" ;;
  *) exit 0 ;;
esac
SH
  cat > "$FAKE/bin/claude" <<'SH'
#!/usr/bin/env bash
cat > "$FAKE/claude-stdin.json"
cat "$FAKE/claude-out.json"
SH
  cat > "$FAKE/bin/notify" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$1" > "$FAKE/notified"
SH
  chmod +x "$FAKE/bin/"*
  export PATH="$FAKE/bin:$PATH"

  jq -n '[{number:3,title:"make check takes four minutes",body:"### What hurt\n\nslow\n\n### How often\n\nconstantly",createdAt:"2026-09-26T14:00:00Z",url:"u3"}]' > "$FAKE/friction.json"
  jq -n '[
    {number:12,title:"Hotfix",url:"u12",body:"What and why\r\n\r\nRule-feedback: P-two-gates, merged a docs-only hotfix while check was red\r\nShutdown: none needed because docs only\r\n"},
    {number:15,title:"Demo fix",url:"u15",body:"Rule-feedback: P-two-gates, demo fix merged before check finished\nShutdown: none needed because no infra\n"},
    {number:16,title:"Plain",url:"u16",body:"Rule-feedback: none\n"},
    {number:17,title:"Fenced",url:"u17",body:"Example:\n```\nRule-feedback: P-wheel, only an example\n```\n"},
    {number:18,title:"Indented",url:"u18",body:"  Rule-feedback: P-public, indented so it does not count\n"}
  ]' > "$FAKE/prs.json"
  jq -n '[{number:20,title:"Console bucket for demo assets",url:"u20",body:"### Which rule\n\nP-off-switch\n\n### What you did instead and why\n\nCreated a bucket in the console to unblock the demo; will import it."}]' > "$FAKE/rf-issues.json"

  # The model wraps its JSON in a fenced block, as models do; the script must still find it.
  fence='```'
  answer='{"clusters":[{"title":"Slow checks","items":[3],"pain_score":3,"why":"make check is slow and constant"}],
    "rules":[{"slug":"P-two-gates","verdict":"change","sentence":"Two hotfixes bypassed check; docs-only PRs could skip the slow tests."}],
    "recommendation":"Let docs-only PRs skip the slow test suite in make check.",
    "next_fix":{"title":"Skip slow tests on docs-only PRs","body":"make check runs the full suite for README edits."}}'
  inner="$(printf 'Here is the review:\n%sjson\n%s\n%s\n' "$fence" "$answer" "$fence")"
  jq -n --arg r "$inner" '{type:"result",is_error:false,result:$r}' > "$FAKE/claude-out.json"
}

@test "groups the three seeded items by rule with counts 2 and 1, decoys excluded" {
  run --separate-stderr scripts/pain-review.sh --repo ert485/xenia-test-team --no-model
  [ "$status" -eq 0 ]
  body="$(cat "$FAKE/pinned-body.md")"
  [[ "$body" == *"<!-- xenia-rule-feedback -->"* ]]
  [[ "$body" == *"## P-two-gates (2)"* ]]
  [[ "$body" == *"## P-off-switch (1)"* ]]
  [[ "$body" == *"- #12 (PR): merged a docs-only hotfix while check was red"* ]]
  [[ "$body" == *"- #15 (PR): demo fix merged before check finished"* ]]
  [[ "$body" == *"- #20 (issue): Console bucket for demo assets"* ]]
  [[ "$body" != *"P-wheel"* && "$body" != *"P-public ("* && "$body" != *"#16"* ]]
  [[ "$body" != *$'\r'* ]]
  # the larger group comes first
  [ "$(grep -n '^## P-two-gates' "$FAKE/pinned-body.md" | cut -d: -f1)" -lt "$(grep -n '^## P-off-switch' "$FAKE/pinned-body.md" | cut -d: -f1)" ]
  grep -q '^issue edit 1 --repo ert485/xenia-test-team --body-file' "$GH_CALLS"
}

@test "--dry-run prints the body and writes nothing" {
  run --separate-stderr scripts/pain-review.sh --repo ert485/xenia-test-team --dry-run --post
  [ "$status" -eq 0 ]
  [[ "$output" == *"## P-two-gates (2)"* ]]
  [[ "$output" == *"would open next-fix issue: Skip slow tests on docs-only PRs"* ]]
  ! grep -qE '^issue (edit|create|pin)' "$GH_CALLS"
  [ ! -f "$FAKE/notified" ]
}

@test "the model's answer adds the bot reading, opens the next-fix issue, and posts" {
  run --separate-stderr scripts/pain-review.sh --repo ert485/xenia-test-team --post
  [ "$status" -eq 0 ]
  jq -e '.rule_feedback | length == 3' "$FAKE/claude-stdin.json"
  jq -e '.friction[0].number == 3' "$FAKE/claude-stdin.json"
  grep -q 'Bot reading (advisory' "$FAKE/pinned-body.md"
  grep -q '| P-two-gates | change |' "$FAKE/pinned-body.md"
  grep -q '^issue create --repo ert485/xenia-test-team --label next-fix --title Skip slow tests on docs-only PRs' "$GH_CALLS"
  grep -q '^Bot: proposed by the pain-review run' "$FAKE/created-body.md"
  grep -q 'Let docs-only PRs skip the slow test suite' "$FAKE/notified"
  grep -q 'issues/42' "$FAKE/notified"
}

@test "an open next-fix issue with the same title is not duplicated" {
  echo '[{"number":41,"title":"Skip slow tests on docs-only PRs"}]' > "$FAKE/next-fix.json"
  run --separate-stderr scripts/pain-review.sh --repo ert485/xenia-test-team
  [ "$status" -eq 0 ]
  ! grep -q '^issue create' "$GH_CALLS"
  [[ "$stderr" == *"already open as #41"* ]]
}

@test "unusable model output falls back to the deterministic grouping" {
  jq -n '{type:"result",is_error:false,result:"I could not decide."}' > "$FAKE/claude-out.json"
  run --separate-stderr scripts/pain-review.sh --repo ert485/xenia-test-team --post
  [ "$status" -eq 0 ]
  grep -q '## P-two-gates (2)' "$FAKE/pinned-body.md"
  ! grep -q 'Bot reading' "$FAKE/pinned-body.md"
  ! grep -q '^issue create' "$GH_CALLS"
  [[ "$stderr" == *"falling back to the deterministic grouping"* ]]
  grep -q 'rule-feedback pile updated' "$FAKE/notified"
}

@test "rejects a malformed repo and unknown flags" {
  run --separate-stderr scripts/pain-review.sh --repo 'not a repo'
  [ "$status" -eq 1 ]
  run --separate-stderr scripts/pain-review.sh --bogus
  [ "$status" -eq 2 ]
}
