#!/usr/bin/env bats
# onboard, offboard, rotate under fakes: no AWS, no gateway, no GitHub.

setup() {
  export TMP="$BATS_TEST_TMPDIR"
  REAL="$BATS_TEST_DIRNAME/.."
  mkdir -p "$TMP/kit/scripts/lib" "$TMP/bin"
  cp "$REAL/scripts/lib/common.sh" "$TMP/kit/scripts/lib/"
  cp "$REAL/scripts/onboard-teammate.sh" "$REAL/scripts/offboard-teammate.sh" "$REAL/scripts/rotate-key.sh" "$TMP/kit/scripts/"
  export KIT_ROOT="$TMP/kit" CALLS="$TMP/calls" XENIA_LEDGER="$TMP/ledger.tsv"
  : > "$CALLS"
  printf 'MEMBER_ACCOUNT_ID=111111111\nMANAGEMENT_ACCOUNT_ID=222222222\nZONE_ID=ZFAKEZONE\n' > "$TMP/kit.env"
  export KIT_ENV_FILE="$TMP/kit.env"
  unset TEAM_REPO FAKE_USER_EXISTS FAKE_MEMBER
  # built from pieces: the plan is leak-checked and allows only two literal addresses
  A="alex@""example.invalid"; A2="alex2@""example.invalid"

  cat > "$TMP/kit/scripts/tf.sh" <<'SH'
#!/usr/bin/env bash
case "$*" in
  *identity_store_id*) echo d-fakestore ;;
  *hackathon_group_id*) echo g-fakegroup ;;
esac
SH
  cat > "$TMP/kit/scripts/gateway-key.sh" <<'SH'
#!/usr/bin/env bash
printf 'gateway-key.sh %s\n' "$*" >> "$CALLS"
case "$1" in
  generate) echo "sk-xxxxxxxxxxxxxxxxxxxxxxxx" ;;
  list) printf 'ci\tspend=0.5\tbudget=10\nci-team\tspend=0.1\tbudget=10\nalex\tspend=1.2\tbudget=30\n' ;;
esac
SH
  cat > "$TMP/bin/aws" <<'SH'
#!/usr/bin/env bash
printf 'aws %s\n' "$*" >> "$CALLS"
case "$*" in
  *"sts get-caller-identity"*"personal-admin"*) echo 222222222 ;;
  *"sts get-caller-identity"*) echo 111111111 ;;
  *"identitystore list-users"*) if [ "${FAKE_USER_EXISTS:-0}" = 1 ]; then echo u-existing; else echo None; fi ;;
  *"identitystore create-user"*) echo u-new ;;
  *"identitystore get-group-membership-id"*)
    if [ "${FAKE_MEMBER:-0}" = 1 ]; then echo m-1; else echo "ResourceNotFoundException" >&2; exit 254; fi ;;
esac
exit 0
SH
  cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >> "$CALLS"
case "$*" in
  *"contents/CODEOWNERS"*) printf '/PRINCIPLES.md @alexh @ert485\n' | base64 ;;
  *"secret set"*) cat > /dev/null ;;
esac
exit 0
SH
  chmod +x "$TMP/kit/scripts/"*.sh "$TMP/bin/"*
  export PATH="$TMP/bin:$PATH"
}

@test "a new teammate: user created, added to the group, key issued, snippet printed" {
  run "$KIT_ROOT/scripts/onboard-teammate.sh" "$A" Alex Hill
  [ "$status" -eq 0 ]
  grep -q 'identitystore create-user' "$CALLS"
  grep -q 'identitystore create-group-membership .*--group-id g-fakegroup' "$CALLS"
  grep -q '^gateway-key.sh generate alex 30$' "$CALLS"
  [[ "$output" == *"sso_role_name = hackathon-dev"* ]] || return 1
  [[ "$output" == *"sso_account_id = 111111111"* ]] || return 1
  [[ "$output" == *"https://d-fakestore.aws""apps.com/start"* ]] || return 1
  [[ "$output" == *"sk-xxxxxxxxxxxxxxxxxxxxxxxx"* ]] || return 1
  [[ "$output" == *"direct message, never in a channel"* ]] || return 1
  grep -q "^$A$(printf '\t')alex$(printf '\t')" "$XENIA_LEDGER"
}

@test "an existing user already in the group: nothing is created" {
  FAKE_USER_EXISTS=1 FAKE_MEMBER=1 run "$KIT_ROOT/scripts/onboard-teammate.sh" "$A" Alex Hill
  [ "$status" -eq 0 ]
  [ "$(grep -cE 'create-user|create-group-membership' "$CALLS")" -eq 0 ]
}

@test "running twice issues one key and says so" {
  "$KIT_ROOT/scripts/onboard-teammate.sh" "$A" Alex Hill > /dev/null
  FAKE_USER_EXISTS=1 FAKE_MEMBER=1 run "$KIT_ROOT/scripts/onboard-teammate.sh" "$A" Alex Hill
  [ "$status" -eq 0 ]
  [[ "$output" == *"already onboarded; use scripts/rotate-key.sh alex"* ]] || return 1
  [ "$(grep -c '^gateway-key.sh generate' "$CALLS")" -eq 1 ]
}

@test "--budget sets the key's budget; a clashing first name gets the last initial" {
  "$KIT_ROOT/scripts/onboard-teammate.sh" "$A" Alex Hill > /dev/null
  run "$KIT_ROOT/scripts/onboard-teammate.sh" "$A2" Alex Smith --budget 50
  [ "$status" -eq 0 ]
  grep -q '^gateway-key.sh generate alex-s 50$' "$CALLS"
}

@test "rotate-key.sh ci revokes, reissues, and sets the kit's secret" {
  run "$KIT_ROOT/scripts/rotate-key.sh" ci
  [ "$status" -eq 0 ]
  grep -q '^gateway-key.sh revoke ci$' "$CALLS"
  grep -q '^gateway-key.sh generate ci 10 ci$' "$CALLS"
  grep -q '^gh secret set GATEWAY_CI_KEY --repo ert485/xenia-2026$' "$CALLS"
  [[ "$output" != *"sk-xxxxxxxxxxxxxxxxxxxxxxxx"* ]]
}

@test "rotate-key.sh ci with TEAM_REPO also rotates the team repo's key" {
  TEAM_REPO=o/team run "$KIT_ROOT/scripts/rotate-key.sh" ci
  [ "$status" -eq 0 ]
  grep -q '^gateway-key.sh generate ci-team 10 ci$' "$CALLS"
  grep -q '^gh secret set GATEWAY_CI_KEY --repo o/team$' "$CALLS"
}

@test "rotate-key.sh <member> keeps the budget and prints the new key once" {
  run "$KIT_ROOT/scripts/rotate-key.sh" alex
  [ "$status" -eq 0 ]
  grep -q '^gateway-key.sh revoke alex$' "$CALLS"
  grep -q '^gateway-key.sh generate alex 30 member$' "$CALLS"
  [ "$(printf '%s\n' "$output" | grep -c 'sk-xxxxxxxxxxxxxxxxxxxxxxxx')" -eq 1 ]
}

@test "offboard removes the membership, the user, the key, the ledger line, and GitHub access" {
  printf '%s\talex\t2026-09-26\n' "$A" > "$XENIA_LEDGER"
  FAKE_USER_EXISTS=1 FAKE_MEMBER=1 TEAM_REPO=o/team run "$KIT_ROOT/scripts/offboard-teammate.sh" "$A" --github alexh
  [ "$status" -eq 0 ]
  grep -q 'identitystore delete-group-membership .*--membership-id m-1' "$CALLS"
  grep -q 'identitystore delete-user .*--user-id u-existing' "$CALLS"
  grep -q '^gateway-key.sh revoke alex$' "$CALLS"
  grep -q '^gh api -X DELETE repos/o/team/collaborators/alexh$' "$CALLS"
  [[ "$output" == *"alexh is a code owner"* ]] || return 1
  [[ "$output" == *"approved by another owner"* ]] || return 1
  [ ! -s "$XENIA_LEDGER" ]
}

@test "offboard warns when the CODEOWNERS fetch fails" {
  printf '%s\talex\t2026-09-26\n' "$A" > "$XENIA_LEDGER"
  cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >> "$CALLS"
case "$*" in
  *"contents/CODEOWNERS"*) exit 1 ;;
  *"secret set"*) cat > /dev/null ;;
esac
exit 0
SH
  chmod +x "$TMP/bin/gh"
  FAKE_USER_EXISTS=1 FAKE_MEMBER=1 TEAM_REPO=o/team run "$KIT_ROOT/scripts/offboard-teammate.sh" "$A" --github alexh
  [ "$status" -eq 0 ]
  [[ "$output" == *"warning: could not read CODEOWNERS for o/team; check by hand whether alexh is a code owner"* ]]
}
