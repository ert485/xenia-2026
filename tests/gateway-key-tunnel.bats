#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Exercises scripts/gateway-key.sh's SSM port-forward path (the one GATEWAY_API_BASE/GATEWAY_MASTER_KEY
# skip in tests/gateway-key.bats): a fake aws whose "ssm start-session" backgrounds a sleeping child,
# to prove (a) `set -m` keeps stdout clean of job-control noise and (b) cleanup's process-group kill
# actually reaches that child, not just the aws wrapper around it.
setup() {
  export TMP="$BATS_TEST_TMPDIR"
  export TUNNEL_PID_FILE="$TMP/tunnel.pid"
  export TUNNEL_CHILD_PID_FILE="$TMP/tunnel-child.pid"
  MEMBER_ID="$(printf '%012d' 111111111)"
  export MEMBER_ID
  printf 'MEMBER_ACCOUNT_ID=%s\nMANAGEMENT_ACCOUNT_ID=%s\nZONE_ID=ZFAKEZONE\n' "$MEMBER_ID" "$MEMBER_ID" > "$TMP/kit.env"
  export KIT_ENV_FILE="$TMP/kit.env"

  cat > "$TMP/aws" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in
  "sts get-caller-identity") printf '%s\n' "$MEMBER_ID" ;;
  "ec2 describe-instances")  printf 'i-0123456789abcdef0\n' ;;
  "ssm get-parameter")       printf 'sk-testmasterkeytestmasterkeytest\n' ;;
  "ssm start-session")
    # Simulate aws ssm start-session spawning session-manager-plugin as a child: the child (a
    # long sleep) inherits this process's process group, same as the real pair does.
    sleep 1000 &
    echo "\$!" > "$TUNNEL_CHILD_PID_FILE"
    echo "\$\$" > "$TUNNEL_PID_FILE"
    wait
    ;;
  *) echo "fake aws: unhandled: \$*" >&2; exit 1 ;;
esac
EOF
  chmod +x "$TMP/aws"

  printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/session-manager-plugin"
  chmod +x "$TMP/session-manager-plugin"

  cat > "$TMP/curl" <<'EOF'
#!/usr/bin/env bash
# fake curl: the liveliness poll always succeeds (no real tunnel exists in the test); key/generate
# answers a canned key.
for a in "$@"; do
  case "$a" in
    */health/liveliness) exit 0 ;;
    */key/generate) printf '{"key":"sk-xxxxxxxxxxxxxxxxxxxxxxxx"}\n'; exit 0 ;;
  esac
done
printf '{}\n'
EOF
  chmod +x "$TMP/curl"

  export PATH="$TMP:$PATH"
  unset GATEWAY_API_BASE GATEWAY_MASTER_KEY
}

still_alive() {
  [[ -f "$1" ]] || return 1
  kill -0 "$(cat "$1")" 2>/dev/null
}

@test "tunnel path: stdout is only the key, and the tunnel (plus its child) dies with the script" {
  cd "$BATS_TEST_DIRNAME/.."
  run --separate-stderr scripts/gateway-key.sh generate erik 30
  [ "$status" -eq 0 ]
  [ "$output" = "sk-xxxxxxxxxxxxxxxxxxxxxxxx" ]

  [ -s "$TUNNEL_PID_FILE" ]
  [ -s "$TUNNEL_CHILD_PID_FILE" ]

  # cleanup's kill is asynchronous from the OS's point of view; give it a moment to land.
  for _ in $(seq 1 20); do
    still_alive "$TUNNEL_PID_FILE" || still_alive "$TUNNEL_CHILD_PID_FILE" || break
    sleep 0.1
  done
  ! still_alive "$TUNNEL_PID_FILE"
  ! still_alive "$TUNNEL_CHILD_PID_FILE"
}
