#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Tests for ensure_networks() in infra/recipes/docker-box/box/lib.sh: creates edge/backend if
# missing, and migrates a box that still carries the old `gateway` Docker network (renamed to
# `backend` because Docker Engine 25 picks a container's default route by which attached network's
# name sorts first lexicographically, and `gateway` sorted after `edge`).
setup() {
  export TMP="$BATS_TEST_TMPDIR"
  export LIB="$BATS_TEST_DIRNAME/../infra/recipes/docker-box/box/lib.sh"
  export DOCKER_CALLS="$TMP/docker-calls"; : > "$DOCKER_CALLS"
  export KIT_ON_BOX="$TMP/kit"
  mkdir -p "$KIT_ON_BOX/infra/recipes/docker-box/gateway"
  # A real box always has the gateway compose file by the time ensure_networks runs post-migration;
  # tests can unset this per-case to prove the "no compose.yml yet" guard too.
  : > "$KIT_ON_BOX/infra/recipes/docker-box/gateway/compose.yml"

  cat > "$TMP/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$DOCKER_CALLS"
case "$1 $2" in
  "network inspect")
    for n in $NETWORKS_EXIST; do [[ "$n" == "$3" ]] && exit 0; done
    exit 1
    ;;
  "network create") exit 0 ;;
  "network rm") exit 0 ;;
  "compose down") exit 0 ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$TMP/docker"
  export PATH="$TMP:$PATH"
}

@test "fresh box: neither network exists, both get created, nothing migrated" {
  NETWORKS_EXIST="" run bash -c 'source "$LIB"; ensure_networks'
  [ "$status" -eq 0 ]
  grep -qF 'network create --opt com.docker.network.bridge.name=edge0 edge' "$DOCKER_CALLS"
  grep -qF 'network create --opt com.docker.network.bridge.name=gw0 backend' "$DOCKER_CALLS"
  ! grep -q 'network rm gateway' "$DOCKER_CALLS"
  ! grep -q 'compose down' "$DOCKER_CALLS"
}

@test "already-migrated box: edge and backend both exist, nothing happens" {
  NETWORKS_EXIST="edge backend" run bash -c 'source "$LIB"; ensure_networks'
  [ "$status" -eq 0 ]
  ! grep -q 'network create' "$DOCKER_CALLS"
  ! grep -q 'network rm' "$DOCKER_CALLS"
  ! grep -q 'compose down' "$DOCKER_CALLS"
}

@test "old-name box: edge exists, gateway still exists — brings the project down, drops gateway, creates backend" {
  NETWORKS_EXIST="edge gateway" run bash -c 'source "$LIB"; ensure_networks'
  [ "$status" -eq 0 ]
  ! grep -q 'network create --opt com.docker.network.bridge.name=edge0 edge' "$DOCKER_CALLS"
  grep -qF 'compose down --remove-orphans' "$DOCKER_CALLS"
  grep -qF 'network rm gateway' "$DOCKER_CALLS"
  grep -qF 'network create --opt com.docker.network.bridge.name=gw0 backend' "$DOCKER_CALLS"
}

@test "old-name box with no gateway compose.yml yet: still drops the network, skips compose down" {
  rm -f "$KIT_ON_BOX/infra/recipes/docker-box/gateway/compose.yml"
  NETWORKS_EXIST="edge gateway" run bash -c 'source "$LIB"; ensure_networks'
  [ "$status" -eq 0 ]
  ! grep -q 'compose down' "$DOCKER_CALLS"
  grep -qF 'network rm gateway' "$DOCKER_CALLS"
  grep -qF 'network create --opt com.docker.network.bridge.name=gw0 backend' "$DOCKER_CALLS"
}
