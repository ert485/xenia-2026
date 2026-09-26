#!/usr/bin/env bats
# Tests for templates/team-repo/Makefile: types (Task 23), check, dev, preview-url (Task 25).
setup() {
  export MK="$BATS_TEST_DIRNAME/../templates/team-repo/Makefile"
  export PROJ="$BATS_TEST_TMPDIR/proj"; mkdir -p "$PROJ/contracts"
  export CALLS="$BATS_TEST_TMPDIR/calls"; : > "$CALLS"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  for c in npx datamodel-codegen npm ruff mypy pytest docker; do
    printf '#!/usr/bin/env bash\necho "%s $*" >> "%s"\n[ -z "${FAIL_ON:-}" ] || [ "%s" != "$FAIL_ON" ]\n' "$c" "$CALLS" "$c" > "$BATS_TEST_TMPDIR/bin/$c"
    chmod +x "$BATS_TEST_TMPDIR/bin/$c"
  done
  printf '#!/usr/bin/env bash\necho "gh $*" >> "%s"\n[ -n "${FAKE_PR:-}" ] && echo "$FAKE_PR"\nexit 0\n' "$CALLS" > "$BATS_TEST_TMPDIR/bin/gh"
  chmod +x "$BATS_TEST_TMPDIR/bin/gh"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  cp "$BATS_TEST_DIRNAME/../templates/contracts/openapi.yaml" "$PROJ/contracts/openapi.yaml"
}

@test "types does nothing in a repo without contracts" {
  rm -rf "$PROJ/contracts"
  run make -s -C "$PROJ" -f "$MK" types
  [ "$status" -eq 0 ]
  [[ "$output" == *"no contracts/openapi.yaml"* ]]
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

@test "check runs typecheck, lint, and test in a TypeScript repo" {
  echo '{}' > "$PROJ/package.json"
  run make -s -C "$PROJ" -f "$MK" check
  [ "$status" -eq 0 ]
  [ "$(grep -c '^npm run --if-present' "$CALLS")" -eq 3 ]
  grep -qx 'npm run --if-present typecheck' "$CALLS"
  grep -qx 'npm run --if-present lint' "$CALLS"
  grep -qx 'npm run --if-present test' "$CALLS"
}

@test "check runs ruff, mypy, and pytest in a Python repo" {
  touch "$PROJ/pyproject.toml"
  run make -s -C "$PROJ" -f "$MK" check
  [ "$status" -eq 0 ]
  grep -qx 'ruff check .' "$CALLS"
  grep -qx 'mypy .' "$CALLS"
  grep -qx 'pytest -q' "$CALLS"
}

@test "check fails when a step fails" {
  touch "$PROJ/pyproject.toml"
  FAIL_ON=mypy run make -s -C "$PROJ" -f "$MK" check
  [ "$status" -ne 0 ]
  ! grep -q '^pytest' "$CALLS"
}

@test "check says what to wire when there is no project yet" {
  run make -s -C "$PROJ" -f "$MK" check
  [ "$status" -eq 0 ]
  [[ "$output" == *"no project yet"* ]]
}

@test "dev builds and starts the compose project" {
  touch "$PROJ/compose.yml"
  run make -s -C "$PROJ" -f "$MK" dev
  [ "$status" -eq 0 ]
  grep -qx 'docker compose up --build' "$CALLS"
  [[ "$output" == *"compose.override.yml"* ]]
}

@test "preview-url prints this branch's preview address" {
  FAKE_PR=7 run make -s -C "$PROJ" -f "$MK" preview-url
  [ "$status" -eq 0 ]
  [ "$output" = "https://pr-7.box.26.cohack.tetl.ca" ]
}

@test "preview-url explains when the branch has no PR" {
  run make -s -C "$PROJ" -f "$MK" preview-url
  [ "$status" -ne 0 ]
  [[ "$output" == *"no open PR"* ]]
}