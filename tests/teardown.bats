#!/usr/bin/env bats
setup() {
  REAL="$BATS_TEST_DIRNAME/.."
  export TMP="$BATS_TEST_TMPDIR"
  mkdir -p "$TMP/kit/scripts/lib" "$TMP/bin"
  cp "$REAL/scripts/lib/common.sh" "$TMP/kit/scripts/lib/"
  cp "$REAL/scripts/teardown.sh" "$TMP/kit/scripts/"
  export KIT_ROOT="$TMP/kit" CALLS="$TMP/calls"; : > "$CALLS"
  printf 'MEMBER_ACCOUNT_ID=111111111\nMANAGEMENT_ACCOUNT_ID=222222222\nZONE_ID=ZFAKEZONE\n' > "$TMP/kit.env"
  export KIT_ENV_FILE="$TMP/kit.env"
  printf '#!/usr/bin/env bash\necho "tf.sh $*" >> "$CALLS"\ncase "$*" in *"output -raw bucket"*) echo xenia-site-kit-abc123 ;; esac\n' > "$TMP/kit/scripts/tf.sh"
  printf '#!/usr/bin/env bash\necho "shutdown.sh $*" >> "$CALLS"\n' > "$TMP/kit/scripts/shutdown.sh"
  printf '#!/usr/bin/env bash\ncase "$*" in *get-caller-identity*personal-admin*) echo 222222222 ;; *get-caller-identity*) echo 111111111 ;; *) echo "aws $*" >> "$CALLS" ;; esac\n' > "$TMP/bin/aws"
  chmod +x "$TMP/kit/scripts/"*.sh "$TMP/bin/aws"
  export PATH="$TMP/bin:$PATH"
}

@test "answering no everywhere destroys nothing but still runs shutdown.sh" {
  run bash -c 'printf "no\nno\nno\n" | "$KIT_ROOT/scripts/teardown.sh"'
  [ "$status" -eq 0 ]
  grep -q '^shutdown.sh' "$CALLS"
  [ "$(grep -c 'destroy' "$CALLS")" -eq 0 ]
  [[ "$output" == *"What remains"* ]]
}

@test "yes to the GPU box only destroys only that stack, in order" {
  run bash -c 'printf "yes\nno\nno\n" | "$KIT_ROOT/scripts/teardown.sh"'
  [ "$status" -eq 0 ]
  grep -qx 'tf.sh recipes/gpu-box destroy' "$CALLS"
  [ "$(grep -c 'destroy' "$CALLS")" -eq 1 ]
}

@test "the kit site's bucket is emptied before its destroy" {
  run bash -c 'printf "no\nyes\nno\n" | "$KIT_ROOT/scripts/teardown.sh"'
  [ "$status" -eq 0 ]
  first="$(grep -n 's3 rm s3://xenia-site-kit-abc123 --recursive' "$CALLS" | cut -d: -f1)"
  second="$(grep -n 'tf.sh examples/kit-site destroy' "$CALLS" | cut -d: -f1)"
  [ -n "$first" ] && [ -n "$second" ] && [ "$first" -lt "$second" ]
}

@test "without --all, platform and org are never offered" {
  run bash -c 'printf "yes\nyes\nyes\nyes\nyes\n" | "$KIT_ROOT/scripts/teardown.sh"'
  [ "$status" -eq 0 ]
  [ "$(grep -cE 'tf.sh (platform|org) ' "$CALLS")" -eq 0 ]
}

@test "--all keeps the zone, backup bucket, and log group out of the destroy when asked" {
  run bash -c 'printf "no\nno\nno\nyes\nyes\nno\n" | "$KIT_ROOT/scripts/teardown.sh" --all'
  [ "$status" -eq 0 ]
  grep -q 'tf.sh platform state rm aws_route53_zone.this' "$CALLS"
  grep -q 'tf.sh platform state rm .*aws_s3_bucket.backups' "$CALLS"
  grep -qx 'tf.sh platform destroy' "$CALLS"
  [ "$(grep -c 'tf.sh org destroy' "$CALLS")" -eq 0 ]
}
