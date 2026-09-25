#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export TMP="$BATS_TEST_TMPDIR"
  export CURL_CALLS="$TMP/curl-calls"; : > "$CURL_CALLS"
  cat > "$TMP/curl" <<'EOF'
#!/usr/bin/env bash
# fake curl: records the URL, the -d body, and headers (including -H @file); answers canned JSON.
# Fails outright if the Authorization header ever shows up inline in argv, since that's exactly the
# leak (visible in `ps`/process listings) that the @file form exists to avoid.
url=""; body=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -H) if [[ "$2" == @* ]]; then cat "${2#@}" >> "$CURL_CALLS"; else
          case "$2" in Authorization:*) echo "fake curl: refusing an inline Authorization header" >&2; exit 1 ;; esac
          printf 'header %s\n' "$2" >> "$CURL_CALLS"
        fi; shift 2 ;;
    -d|--data) body="$2"; shift 2 ;;
    -X|-m|-o|-w) shift 2 ;;
    http*) url="$1"; shift ;;
    *) shift ;;
  esac
done
printf 'url %s\nbody %s\n' "$url" "$body" >> "$CURL_CALLS"
case "$url" in
  */key/generate) printf '{"key":"sk-xxxxxxxxxxxxxxxxxxxxxxxx","key_alias":"erik"}\n' ;;
  */key/list*)    printf '{"keys":[{"token":"tok-aaa","key_alias":"erik","spend":1.25,"max_budget":30},{"token":"tok-bbb","key_alias":"ci","spend":0,"max_budget":10}]}\n' ;;
  */key/delete)   printf '{"deleted_keys":["tok-aaa"]}\n' ;;
  *) printf '{}\n' ;;
esac
EOF
  chmod +x "$TMP/curl"
  export PATH="$TMP:$PATH"
  export GATEWAY_API_BASE="http://gateway.test" GATEWAY_MASTER_KEY="sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
}

@test "generate posts alias, budget, limits and kind with the master key, prints only the key" {
  run --separate-stderr scripts/gateway-key.sh generate erik 30
  [ "$status" -eq 0 ]
  [ "$output" = "sk-xxxxxxxxxxxxxxxxxxxxxxxx" ]
  grep -qF 'Authorization: Bearer sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx' "$CURL_CALLS"
  grep -qF 'url http://gateway.test/key/generate' "$CURL_CALLS"
  body="$(grep '^body {' "$CURL_CALLS" | head -1 | cut -c6-)"
  [ "$(jq -r .key_alias <<< "$body")" = "erik" ]
  [ "$(jq -r .max_budget <<< "$body")" = "30" ]
  [ "$(jq -r .budget_duration <<< "$body")" = "30d" ]
  [ "$(jq -r .max_parallel_requests <<< "$body")" = "8" ]
  [ "$(jq -r .rpm_limit <<< "$body")" = "120" ]
  [ "$(jq -r .tpm_limit <<< "$body")" = "400000" ]
  [ "$(jq -r .metadata.kind <<< "$body")" = "member" ]
  [ "$(jq -c .models <<< "$body")" = '["qwen3-coder","qwen3-coder-bedrock"]' ]
}

@test "generate with kind ci records it in metadata" {
  run --separate-stderr scripts/gateway-key.sh generate ci 10 ci
  [ "$status" -eq 0 ]
  grep -q '"kind":"ci"' "$CURL_CALLS"
}

@test "generate rejects a non-numeric budget and a bad alias" {
  run scripts/gateway-key.sh generate erik lots
  [ "$status" -eq 1 ]
  run scripts/gateway-key.sh generate 'Erik Smith' 30
  [ "$status" -eq 1 ]
  ! grep -q '/key/generate' "$CURL_CALLS"
}

@test "revoke looks up the alias and deletes only its tokens" {
  run scripts/gateway-key.sh revoke erik
  [ "$status" -eq 0 ]
  grep -qF 'url http://gateway.test/key/list?key_alias=erik&return_full_object=true' "$CURL_CALLS"
  grep -qF 'body {"keys":["tok-aaa"]}' "$CURL_CALLS"
}

@test "revoke of an unknown alias fails without deleting" {
  run scripts/gateway-key.sh revoke nobody
  [ "$status" -eq 1 ]
  [[ "$output" == *"no key with alias nobody"* ]]
  ! grep -q '/key/delete' "$CURL_CALLS"
}

@test "list prints alias, spend and budget per key" {
  run --separate-stderr scripts/gateway-key.sh list
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$(printf 'erik\tspend=1.25\tbudget=30')" ]
  [ "${lines[1]}" = "$(printf 'ci\tspend=0\tbudget=10')" ]
}
