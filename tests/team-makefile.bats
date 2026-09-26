#!/usr/bin/env bats
# Tests for templates/team-repo/Makefile. Task 23 writes the types cases; Task 25 adds the check cases.
setup() {
  export MK="$BATS_TEST_DIRNAME/../templates/team-repo/Makefile"
  export PROJ="$BATS_TEST_TMPDIR/proj"; mkdir -p "$PROJ/contracts"
  export CALLS="$BATS_TEST_TMPDIR/calls"; : > "$CALLS"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  for c in npx datamodel-codegen; do
    printf '#!/usr/bin/env bash\necho "%s $*" >> "%s"\n' "$c" "$CALLS" > "$BATS_TEST_TMPDIR/bin/$c"
    chmod +x "$BATS_TEST_TMPDIR/bin/$c"
  done
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  cp "$BATS_TEST_DIRNAME/../templates/contracts/openapi.yaml" "$PROJ/contracts/openapi.yaml"
}

@test "types does nothing in a repo without contracts" {
  rm -rf "$PROJ/contracts"
  run make -s -C "$PROJ" -f "$MK" types
  [ "$status" -eq 0 ]
  [[ "$output" == *"no contracts/openapi.yaml"* ]] || return 1
  [ ! -s "$CALLS" ]
}

@test "types runs the pinned openapi-typescript in a TypeScript repo" {
  echo '{}' > "$PROJ/package.json"
  run make -s -C "$PROJ" -f "$MK" types
  [ "$status" -eq 0 ]
  grep -qx 'npx --yes openapi-typescript@7.13.0 contracts/openapi.yaml -o src/contracts/openapi.d.ts' "$CALLS"
  [ -d "$PROJ/src/contracts" ]
}

@test "types runs datamodel-codegen without a timestamp in a Python repo" {
  touch "$PROJ/pyproject.toml"
  run make -s -C "$PROJ" -f "$MK" types
  [ "$status" -eq 0 ]
  grep -q 'datamodel-codegen --input contracts/openapi.yaml --input-file-type openapi --output src/contracts/models.py' "$CALLS"
  grep -q -- '--disable-timestamp' "$CALLS"
  ! grep -q '^npx' "$CALLS"
}
