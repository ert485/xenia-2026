#!/usr/bin/env bats
# Tests for infra/recipes/docker-box/box/lib.sh with a fake docker and a fake preview-down.sh.
setup() {
  export TMP="$BATS_TEST_TMPDIR"
  export LIB="$BATS_TEST_DIRNAME/../infra/recipes/docker-box/box/lib.sh"
  export BOX_SCRIPTS="$TMP/box"; mkdir -p "$BOX_SCRIPTS"
  export DOWN_CALLS="$TMP/down-calls"; : > "$DOWN_CALLS"
  cat > "$TMP/docker" <<'EOF'
#!/usr/bin/env bash
# fake docker. "compose ls" prints $PROJECTS as JSON plus two projects that are not previews;
# "inspect" prints a creation time derived from the PR number, so lower numbers are older.
if [[ "$1 $2" == "compose ls" ]]; then
  out='[{"Name":"gateway","Status":"running(3)"},{"Name":"app","Status":"running(2)"}'
  for p in $PROJECTS; do out+=",{\"Name\":\"$p\",\"Status\":\"running(2)\"}"; done
  printf '%s]\n' "$out"
  exit 0
fi
if [[ "$1" == "inspect" ]]; then
  name="${*: -1}"; n="${name#pr-}"; n="${n%-web}"
  printf '2026-09-25T10:%02d:00Z\n' "$n"
  exit 0
fi
exit 0
EOF
  cat > "$BOX_SCRIPTS/preview-down.sh" <<'EOF'
#!/usr/bin/env bash
echo "$1" >> "$DOWN_CALLS"
EOF
  chmod +x "$TMP/docker" "$BOX_SCRIPTS/preview-down.sh"
  export PATH="$TMP:$PATH"
}

@test "list_previews keeps only pr-<n> projects, oldest first" {
  PROJECTS="pr-3 pr-1 pr-12 pr-2" run bash -c 'source "$LIB"; list_previews'
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'pr-1\npr-2\npr-3\npr-12')" ]
}

@test "evict: four previews, cap 3, keep pr-1: pr-1 is skipped, only pr-2 goes" {
  PROJECTS="pr-3 pr-1 pr-2 pr-4" run bash -c 'source "$LIB"; evict_oldest_previews 3 pr-1'
  [ "$status" -eq 0 ]
  [ "$(cat "$DOWN_CALLS")" = "2" ]
}

@test "evict: at or under the cap nothing is removed" {
  PROJECTS="pr-1 pr-2 pr-3" run bash -c 'source "$LIB"; evict_oldest_previews 3 pr-9'
  [ "$status" -eq 0 ]
  PROJECTS="" run bash -c 'source "$LIB"; evict_oldest_previews 2 pr-9'
  [ "$status" -eq 0 ]
  [ ! -s "$DOWN_CALLS" ]
}

@test "evict: cap 2 with three running removes exactly the oldest" {
  PROJECTS="pr-7 pr-5 pr-6" run bash -c 'source "$LIB"; evict_oldest_previews 2 pr-8'
  [ "$status" -eq 0 ]
  [ "$(cat "$DOWN_CALLS")" = "5" ]
}

@test "preview_cap_for: 3 for a project already running (resync), 2 for a new one" {
  PROJECTS="pr-1 pr-2" run bash -c 'source "$LIB"; preview_cap_for pr-2'
  [ "$output" = "3" ]
  PROJECTS="pr-1 pr-2" run bash -c 'source "$LIB"; preview_cap_for pr-9'
  [ "$output" = "2" ]
}
