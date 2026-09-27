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

@test "cap_add NET_ADMIN is refused" {
  compose 'cap_add: [NET_ADMIN]'
  run "$PY" "$CHECK" "$PROJ/compose.yml" "$PROJ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"service web: cap_add NET_ADMIN"* ]]
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

@test "an external top-level secret is refused" {
  compose 'secrets: [dbpass]'
  printf 'secrets:\n  dbpass:\n    external: true\n' >> "$PROJ/compose.yml"
  run "$PY" "$CHECK" "$PROJ/compose.yml" "$PROJ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"top-level secret dbpass: external secrets are not allowed"* ]]
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

# --- Rendered-JSON form (C2, spec section 9, D36): docker compose config --format json resolves
# ${VAR:-default} interpolation, a committed .env file, anchors and extends before the checker ever
# sees the file. These fixtures are written as the RENDERED form (real JSON booleans, canonical
# long-syntax volumes with resolved absolute paths) instead of the raw YAML the checker used to be
# fed, since compose-check.py accepts either (JSON is valid YAML).

@test "a rendered privileged:true (resolved from \${X:-true} interpolation) is refused" {
  printf '{"services":{"web":{"build":".","privileged":true}}}' > "$PROJ/compose.yml"
  run "$PY" "$CHECK" "$PROJ/compose.yml" "$PROJ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"service web: privileged: true"* ]]
}

@test "a rendered cap_add SYS_ADMIN (resolved from interpolation) is refused" {
  printf '{"services":{"web":{"build":".","cap_add":["SYS_ADMIN"]}}}' > "$PROJ/compose.yml"
  run "$PY" "$CHECK" "$PROJ/compose.yml" "$PROJ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"service web: cap_add SYS_ADMIN"* ]]
}

@test "device_cgroup_rules is refused" {
  printf '{"services":{"web":{"build":".","device_cgroup_rules":["b 259:* rwm"]}}}' > "$PROJ/compose.yml"
  run "$PY" "$CHECK" "$PROJ/compose.yml" "$PROJ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"service web: device_cgroup_rules is not allowed"* ]]
}

@test "sysctls is refused" {
  printf '{"services":{"web":{"build":".","sysctls":{"net.ipv4.ip_forward":"1"}}}}' > "$PROJ/compose.yml"
  run "$PY" "$CHECK" "$PROJ/compose.yml" "$PROJ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"service web: sysctls is not allowed"* ]]
}

@test "cgroup_parent is refused" {
  printf '{"services":{"web":{"build":".","cgroup_parent":"/"}}}' > "$PROJ/compose.yml"
  run "$PY" "$CHECK" "$PROJ/compose.yml" "$PROJ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"service web: cgroup_parent is not allowed"* ]]
}

@test "a non-web service claiming container_name app-web is refused" {
  printf '{"services":{"web":{"build":"."},"sidecar":{"image":"alpine","container_name":"app-web"}}}' > "$PROJ/compose.yml"
  run "$PY" "$CHECK" "$PROJ/compose.yml" "$PROJ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"service sidecar: container_name is not allowed on a non-web service"* ]]
}

@test "the web service's own container_name is still allowed" {
  printf '{"services":{"web":{"build":".","container_name":"app-web"}}}' > "$PROJ/compose.yml"
  run "$PY" "$CHECK" "$PROJ/compose.yml" "$PROJ"
  [ "$status" -eq 0 ]
}

@test "a non-web service aliasing itself on the edge network is refused" {
  printf '{"services":{"web":{"build":".","networks":{"edge":{}}},"sidecar":{"image":"alpine","networks":{"edge":{"aliases":["app-web"]}}}},"networks":{"edge":{"external":true}}}' > "$PROJ/compose.yml"
  run "$PY" "$CHECK" "$PROJ/compose.yml" "$PROJ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"service sidecar: sets aliases on the edge network"* ]]
}

@test "a rendered absolute bind path inside the project directory is accepted" {
  printf '{"services":{"web":{"build":".","volumes":[{"type":"bind","source":"%s/data","target":"/data"}]}}}' "$PROJ" > "$PROJ/compose.yml"
  mkdir -p "$PROJ/data"
  run "$PY" "$CHECK" "$PROJ/compose.yml" "$PROJ"
  [ "$status" -eq 0 ]
}

@test "kriket-like rendered compose (web/frontend/backend/db, required BETTER_AUTH_SECRET resolved) is accepted" {
  printf '%s' '{
    "name": "app",
    "services": {
      "web": {"image": "ghcr.io/example/kriket-web:sha-fake"},
      "frontend": {"image": "ghcr.io/example/kriket-web-frontend:sha-fake"},
      "backend": {
        "image": "ghcr.io/example/kriket-web-backend:sha-fake",
        "environment": {"BETTER_AUTH_SECRET": "fake-test-secret-do-not-use"},
        "depends_on": {"db": {"condition": "service_healthy"}}
      },
      "db": {
        "image": "postgres:16",
        "volumes": [{"type": "volume", "source": "pgdata", "target": "/var/lib/postgresql/data"}]
      }
    },
    "volumes": {"pgdata": {}}
  }' > "$PROJ/compose.yml"
  run "$PY" "$CHECK" "$PROJ/compose.yml" "$PROJ"
  [ "$status" -eq 0 ]
}
