#!/usr/bin/env bats
# Preview isolation checker (spec section 9, D36). Needs PyYAML: source .venv/bin/activate first.
bats_require_minimum_version 1.5.0

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  CHECK=infra/recipes/docker-box/box/compose-check.py
  PROJ="$BATS_TEST_TMPDIR/proj"; mkdir -p "$PROJ"
  PY="${PYTHON:-python3}"
  "$PY" -c 'import yaml' 2>/dev/null || { echo "PyYAML missing: run 'source .venv/bin/activate' (Task 10 adds pyyaml to site/requirements.txt)" >&2; return 1; }
}

# compose <service-lines...>: writes a compose file with a web service plus the given lines under it
compose() {
  { printf 'services:\n  web:\n    build: .\n'; for l in "$@"; do printf '    %s\n' "$l"; done; } > "$PROJ/compose.yml"
}

@test "privileged is refused" {
  compose 'privileged: true'
  run "$PY" "$CHECK" "$PROJ/compose.yml" "$PROJ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"service web: privileged: true"* ]]
}

@test "network_mode host is refused" {
  compose 'network_mode: host'
  run "$PY" "$CHECK" "$PROJ/compose.yml" "$PROJ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"service web: network_mode: host"* ]]
}

@test "pid host is refused" {
  compose 'pid: host'
  run "$PY" "$CHECK" "$PROJ/compose.yml" "$PROJ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"service web: pid: host"* ]]
}

@test "the Docker socket is refused" {
  compose 'volumes:' '  - /var/run/docker.sock:/var/run/docker.sock'
  run "$PY" "$CHECK" "$PROJ/compose.yml" "$PROJ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"service web: mounts the Docker socket"* ]]
}

@test "an absolute host path is refused" {
  compose 'volumes:' '  - /etc:/x'
  run "$PY" "$CHECK" "$PROJ/compose.yml" "$PROJ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"service web: bind mount outside the project directory: /etc"* ]]
}

@test "a parent-relative host path is refused" {
  compose 'volumes:' '  - ../secrets:/x'
  run "$PY" "$CHECK" "$PROJ/compose.yml" "$PROJ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"service web: bind mount outside the project directory: ../secrets"* ]]
}

@test "a long-syntax bind outside the project is refused" {
  compose 'volumes:' '  - type: bind' '    source: /run/xenia' '    target: /x'
  run "$PY" "$CHECK" "$PROJ/compose.yml" "$PROJ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"service web: bind mount outside the project directory: /run/xenia"* ]]
}

@test "an env_file outside the project is refused (it would read the gateway master key)" {
  compose 'env_file: /run/xenia/litellm.env'
  run "$PY" "$CHECK" "$PROJ/compose.yml" "$PROJ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"service web: env_file outside the project directory"* ]]
}

@test "joining the gateway network is refused" {
  compose 'networks: [gateway]'
  printf 'networks:\n  gateway:\n    external: true\n' >> "$PROJ/compose.yml"
  run "$PY" "$CHECK" "$PROJ/compose.yml" "$PROJ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"top-level network gateway: external networks other than edge"* ]]
}

@test "a named volume pointing at another project's data is refused" {
  compose 'volumes:' '  - db:/data'
  printf 'volumes:\n  db:\n    name: gateway_pgdata\n' >> "$PROJ/compose.yml"
  run "$PY" "$CHECK" "$PROJ/compose.yml" "$PROJ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"top-level volume db: explicit name"* ]]
}

@test "build with host networking is refused" {
  printf 'services:\n  web:\n    build:\n      context: .\n      network: host\n' > "$PROJ/compose.yml"
  run "$PY" "$CHECK" "$PROJ/compose.yml" "$PROJ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"service web: build.network: host"* ]]
}

@test "a variable in a host path is refused" {
  compose 'volumes:' '  - ${DATA_DIR}:/data'
  run "$PY" "$CHECK" "$PROJ/compose.yml" "$PROJ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"service web: variable in a host path"* ]]
}

@test "a compose file without a web service is refused" {
  printf 'services:\n  api:\n    build: .\n' > "$PROJ/compose.yml"
  run "$PY" "$CHECK" "$PROJ/compose.yml" "$PROJ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"needs a service named web"* ]]
}

@test "a project-relative bind and a named volume are accepted" {
  compose 'volumes:' '  - ./data:/data' '  - cache:/cache'
  printf 'volumes:\n  cache: {}\n' >> "$PROJ/compose.yml"
  run "$PY" "$CHECK" "$PROJ/compose.yml" "$PROJ"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ports are accepted with a warning on stderr" {
  compose 'ports: ["3000:3000"]'
  run --separate-stderr "$PY" "$CHECK" "$PROJ/compose.yml" "$PROJ"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"warning: service web: ports are ignored in previews"* ]]
}

@test "the kit's own example compose passes" {
  cp templates/team-repo/compose.example.yml "$PROJ/compose.yml"
  run "$PY" "$CHECK" "$PROJ/compose.yml" "$PROJ"
  [ "$status" -eq 0 ]
}
