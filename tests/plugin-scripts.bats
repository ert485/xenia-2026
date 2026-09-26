#!/usr/bin/env bats
setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export TMP="$BATS_TEST_TMPDIR"
  export CURL_CALLS="$TMP/curl-calls"; : > "$CURL_CALLS"
  cat > "$TMP/curl" <<'EOF'
#!/usr/bin/env bash
# fake curl: records the -d body and the URL
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d) printf 'body %s\n' "$2" >> "$CURL_CALLS"; shift 2 ;;
    http*) printf 'url %s\n' "$1" >> "$CURL_CALLS"; shift ;;
    -H|-m) shift 2 ;;
    *) shift ;;
  esac
done
EOF
  chmod +x "$TMP/curl"
  export PATH="$TMP:$PATH"
  export DISCORD_WEBHOOK_URL="https://discord.test/api/webhooks/1/x"
}

# notify.sh

@test "notify posts the message with the agent, repo and author prefix" {
  run plugin/scripts/notify.sh "deploy is green"
  [ "$status" -eq 0 ]
  body="$(grep '^body ' "$CURL_CALLS" | cut -c6-)"
  [[ "$(jq -r .content <<< "$body")" == "[agent · "*" · "*"] deploy is green" ]]
  [ "$(jq -c .allowed_mentions <<< "$body")" = '{"parse":[]}' ]
  grep -qF 'url https://discord.test/api/webhooks/1/x' "$CURL_CALLS"
}

@test "notify refuses a message containing a gateway-key-shaped string" {
  run plugin/scripts/notify.sh "my key is sk-xxxxxxxxxxxxxxxxxxxxxxxx"
  [ "$status" -eq 1 ]
  [[ "$output" == *"looks like a gateway key"* ]]
  [ ! -s "$CURL_CALLS" ]
}

@test "notify refuses an environment dump" {
  run plugin/scripts/notify.sh "$(printf 'here:\nAWS_REGION=ca-central-1\nFOO=bar')"
  [ "$status" -eq 1 ]
  [[ "$output" == *"environment dump"* ]]
  [ ! -s "$CURL_CALLS" ]
}

@test "notify says how to set the webhook when it is missing" {
  DISCORD_WEBHOOK_URL="" run plugin/scripts/notify.sh "hello"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DISCORD_WEBHOOK_URL is not set"* ]]
}

# shutdown-entry.sh

@test "shutdown-entry writes 40-foo.sh with all five header fields and valid bash, then 50-bar.sh" {
  export SHUTDOWN_DIR="$TMP/shutdown.d"
  run plugin/scripts/shutdown-entry.sh foo "the foo queue workers" "scripts/foo-start.sh" "about \$0.10/hour" "touch $TMP/stopped"
  [ "$status" -eq 0 ]
  f="$SHUTDOWN_DIR/40-foo.sh"
  [ -x "$f" ]
  [ "$(sed -n 1p "$f")" = "#!/usr/bin/env bash" ]
  [ "$(sed -n 2p "$f")" = "# xenia-shutdown" ]
  grep -qx '# stops: the foo queue workers' "$f"
  grep -q '^# added-by: ' "$f"
  grep -qx '# restore: scripts/foo-start.sh' "$f"
  grep -qx '# cost-when-running: about \$0.10/hour' "$f"
  grep -qx 'set -euo pipefail' "$f"
  bash -n "$f"
  run plugin/scripts/shutdown-entry.sh bar "bar" "not reversible" "free" "true"
  [ -f "$SHUTDOWN_DIR/50-bar.sh" ]
}

@test "the generated entry honours DRY_RUN and otherwise runs the stop command" {
  export SHUTDOWN_DIR="$TMP/shutdown.d"
  plugin/scripts/shutdown-entry.sh foo "foo" "x" "free" "touch $TMP/stopped"
  DRY_RUN=1 run "$SHUTDOWN_DIR/40-foo.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"would stop foo"* ]]
  [ ! -e "$TMP/stopped" ]
  run "$SHUTDOWN_DIR/40-foo.sh"
  [ -e "$TMP/stopped" ]
}

@test "shutdown-entry refuses a bad name and a multi-line field" {
  export SHUTDOWN_DIR="$TMP/shutdown.d"
  run plugin/scripts/shutdown-entry.sh "Foo Bar" "x" "x" "x" "true"
  [ "$status" -eq 1 ]
  run plugin/scripts/shutdown-entry.sh foo "$(printf 'two\nlines')" "x" "x" "true"
  [ "$status" -eq 1 ]
}

# rule-feedback-line.sh

@test "rule-feedback-line normalizes a slug with a reason" {
  run plugin/scripts/rule-feedback-line.sh "P-two-gates,   skipped the preview because the box was down"
  [ "$status" -eq 0 ]
  [ "$output" = "Rule-feedback: P-two-gates, skipped the preview because the box was down" ]
}

@test "rule-feedback-line accepts none and an already-prefixed line" {
  run plugin/scripts/rule-feedback-line.sh "none"
  [ "$output" = "Rule-feedback: none" ]
  run plugin/scripts/rule-feedback-line.sh "Rule-feedback:P-off-switch, console test bucket"
  [ "$output" = "Rule-feedback: P-off-switch, console test bucket" ]
}

@test "rule-feedback-line strips CRLF" {
  run plugin/scripts/rule-feedback-line.sh "$(printf 'P-public, false positive on a test fixture\r')"
  [ "$status" -eq 0 ]
  [ "$output" = "Rule-feedback: P-public, false positive on a test fixture" ]
}

@test "rule-feedback-line rejects an invalid slug and a second line" {
  run plugin/scripts/rule-feedback-line.sh "P-Two-Gates, shouting"
  [ "$status" -eq 1 ]
  run plugin/scripts/rule-feedback-line.sh "two-gates, no prefix"
  [ "$status" -eq 1 ]
  run plugin/scripts/rule-feedback-line.sh "$(printf 'P-ours, a\nP-wheel, b')"
  [ "$status" -eq 1 ]
}
