#!/usr/bin/env bats
setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export ALLOW="$BATS_TEST_TMPDIR/allow"; echo "kit@example.invalid" > "$ALLOW"
  export DIRTY="$BATS_TEST_TMPDIR/dirty.md"
  {
    printf 'account %012d here\n' 123
    printf 'portal https://d-1234567890.%s%s/start\n' awsapps .com
    printf 'zone Z0%s\n' "$(printf 'A%.0s' $(seq 1 18))"
    printf 'box at %s.%s\n' 203.0 113.7
    printf 'call 306-%s\n' "$(printf '555-%04d' 100)"
    printf 'mail someone%s\n' @example.com
  } > "$DIRTY"
}

@test "clean fixture passes (versions, SHAs, timestamps, link-local and resolver IPs, allow-listed email)" {
  run scripts/ci/leak-check.sh --allow-emails "$ALLOW" tests/fixtures/leak/clean.md
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "dirty fixture reports all six classes" {
  run scripts/ci/leak-check.sh --allow-emails "$ALLOW" "$DIRTY"
  [ "$status" -eq 1 ]
  [[ "$output" == *"dirty.md:1: 12-digit number"* ]] || return 1
  [[ "$output" == *"dirty.md:2: awsapps.com"* ]] || return 1
  [[ "$output" == *"dirty.md:3: hosted-zone-shaped"* ]] || return 1
  [[ "$output" == *"dirty.md:4: IPv4"* ]] || return 1
  [[ "$output" == *"dirty.md:5: phone"* ]] || return 1
  [[ "$output" == *"dirty.md:6: email not on the allow-list: someone@"* ]]
}

@test "leak-check:ignore marker suppresses a line" {
  printf 'account %012d <!-- leak-check:ignore -->\n' 123 > "$BATS_TEST_TMPDIR/x.md"
  run scripts/ci/leak-check.sh --allow-emails "$ALLOW" "$BATS_TEST_TMPDIR/x.md"
  [ "$status" -eq 0 ]
}

@test "usage error without paths" {
  run scripts/ci/leak-check.sh
  [ "$status" -eq 2 ]
}
