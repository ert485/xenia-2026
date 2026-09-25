#!/usr/bin/env bats
# Tests for gateway_route_check() in infra/recipes/docker-box/box/lib.sh, with fake docker and
# nsenter. This function exists because `docker exec <caddy container> ip route` always fails (the
# pinned Caddy image has no `ip`); the route must be read from the HOST namespace instead.
setup() {
  export TMP="$BATS_TEST_TMPDIR"
  export LIB="$BATS_TEST_DIRNAME/../infra/recipes/docker-box/box/lib.sh"
  cat > "$TMP/docker" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  inspect)
    # docker inspect -f '{{.State.Running}} {{.State.Pid}}' <container>
    if [[ "${CONTAINER_RUNNING:-true}" == "true" ]]; then
      printf 'true %s\n' "${CONTAINER_PID:-4242}"
    else
      printf 'false 0\n'
    fi
    ;;
  network)
    # docker network inspect <network> -f '{{(index .IPAM.Config 0).Gateway}}'
    if [[ "$2" == "inspect" ]]; then
      if [[ "${NET_INSPECT_FAIL:-0}" == "1" ]]; then
        echo "Error: No such network: $3" >&2
        exit 1
      fi
      printf '%s\n' "${NET_GATEWAY:-172.20.0.1}"
    fi
    ;;
  *) exit 1 ;;
esac
EOF
  cat > "$TMP/nsenter" <<'EOF'
#!/usr/bin/env bash
# nsenter -t <pid> -n ip -4 route show default
if [[ "${NSENTER_FAIL:-0}" == "1" ]]; then
  echo "${NSENTER_ERR:-nsenter: cannot open /proc/4242/ns/net: No such file or directory}" >&2
  exit 1
fi
printf '%s\n' "${ROUTE_LINE:-default via 172.20.0.1 dev eth0}"
EOF
  chmod +x "$TMP/docker" "$TMP/nsenter"
  export PATH="$TMP:$PATH"
}

@test "ok: the route matches the network's gateway address" {
  NET_GATEWAY="172.20.0.1" ROUTE_LINE="default via 172.20.0.1 dev eth0" \
    run bash -c 'source "$LIB"; gateway_route_check gateway-caddy-1 gateway'
  [ "$status" -eq 0 ]
  [ "$output" = "default via 172.20.0.1 dev eth0" ]
}

@test "not running: container has no pid yet" {
  CONTAINER_RUNNING=false \
    run bash -c 'source "$LIB"; gateway_route_check gateway-caddy-1 gateway'
  [ "$status" -eq 1 ]
  [[ "$output" == *"not running"* ]]
}

@test "cannot check: nsenter fails (e.g. exec into an image with no ip is not what's used, but the ns lookup itself can still fail)" {
  NSENTER_FAIL=1 NSENTER_ERR="nsenter: cannot open /proc/4242/ns/net: No such file or directory" \
    run bash -c 'source "$LIB"; gateway_route_check gateway-caddy-1 gateway'
  [ "$status" -eq 2 ]
  [[ "$output" == *"cannot open /proc/4242/ns/net"* ]]
}

@test "cannot check: the network itself can't be inspected" {
  NET_INSPECT_FAIL=1 \
    run bash -c 'source "$LIB"; gateway_route_check gateway-caddy-1 gateway'
  [ "$status" -eq 2 ]
  [[ "$output" == *"No such network"* ]]
}

@test "mismatch: caddy's default route goes via the wrong network" {
  NET_GATEWAY="172.20.0.1" ROUTE_LINE="default via 172.30.0.1 dev eth1" \
    run bash -c 'source "$LIB"; gateway_route_check gateway-caddy-1 gateway'
  [ "$status" -eq 3 ]
  [[ "$output" == *"172.30.0.1"* ]]
  [[ "$output" == *"172.20.0.1"* ]]
}
