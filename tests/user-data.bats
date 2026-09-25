#!/usr/bin/env bats
# First-boot ordering in the Docker box's user-data: the metadata guard must be running before the kit
# clone, so a first boot that can't reach GitHub still leaves containers cut off from instance
# credentials.
setup() {
  USER_DATA="$BATS_TEST_DIRNAME/../infra/recipes/docker-box/user-data.sh"
}

# line number of the first line matching a fixed string, or empty
first_line() { grep -nF -- "$2" "$1" | head -1 | cut -d: -f1; }

# succeeds only if both guard units are enabled before the git clone line
guard_before_clone() {
  local pre post clone
  pre="$(first_line "$1" 'systemctl enable --now xenia-imds-guard-pre.service')"
  post="$(first_line "$1" 'systemctl enable --now xenia-imds-guard.service')"
  clone="$(first_line "$1" 'git clone')"
  [ -n "$pre" ] && [ -n "$post" ] && [ -n "$clone" ] || return 1
  [ "$pre" -lt "$clone" ] && [ "$post" -lt "$clone" ]
}

@test "user-data enables the metadata guard units before cloning the kit" {
  guard_before_clone "$USER_DATA"
}

@test "user-data writes /etc/xenia.env and the tmpfiles rule before cloning the kit" {
  clone="$(first_line "$USER_DATA" 'git clone')"
  [ "$(first_line "$USER_DATA" 'cat > /etc/xenia.env')" -lt "$clone" ]
  [ "$(first_line "$USER_DATA" 'systemd-tmpfiles --create')" -lt "$clone" ]
}

@test "the ordering check fails when the clone is moved above the guard" {
  swapped="$BATS_TEST_TMPDIR/user-data.sh"
  { echo 'git clone https://example.invalid/kit.git /srv/kit'; cat "$USER_DATA"; } > "$swapped"
  run guard_before_clone "$swapped"
  [ "$status" -ne 0 ]
}
