#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# install_capacity_probe() in infra/recipes/docker-box/box/lib.sh: idempotent install of the
# xenia-gpu-capacity-probe systemd service + timer, called from user-data.sh and from
# box/gateway.sh update (so a box that is already running gets it too — main.tf ignores user_data
# changes, so a plain re-apply never reaches a running box).
setup() {
  export TMP="$BATS_TEST_TMPDIR"
  export LIB="$BATS_TEST_DIRNAME/../infra/recipes/docker-box/box/lib.sh"
  export SYSTEMCTL_CALLS="$TMP/systemctl-calls"; : > "$SYSTEMCTL_CALLS"
  export SYSTEMD_UNIT_DIR="$TMP/systemd-units"; mkdir -p "$SYSTEMD_UNIT_DIR"
  export KIT_ON_BOX="$TMP/kit"
  cat > "$TMP/systemctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SYSTEMCTL_CALLS"
exit 0
EOF
  chmod +x "$TMP/systemctl"
  export PATH="$TMP:$PATH"
}

@test "installs the service and timer, points ExecStart at the kit checkout, enables the timer" {
  run bash -c 'source "$LIB"; install_capacity_probe'
  [ "$status" -eq 0 ]
  [ -f "$SYSTEMD_UNIT_DIR/xenia-gpu-capacity-probe.service" ]
  [ -f "$SYSTEMD_UNIT_DIR/xenia-gpu-capacity-probe.timer" ]
  grep -qF "ExecStart=$KIT_ON_BOX/infra/recipes/docker-box/box/gpu-capacity-probe.sh" "$SYSTEMD_UNIT_DIR/xenia-gpu-capacity-probe.service"
  grep -q 'OnUnitActiveSec=10min' "$SYSTEMD_UNIT_DIR/xenia-gpu-capacity-probe.timer"
  grep -q 'daemon-reload' "$SYSTEMCTL_CALLS"
  grep -q 'enable --now xenia-gpu-capacity-probe.timer' "$SYSTEMCTL_CALLS"
}

@test "running it twice is idempotent: same unit content, no error" {
  run bash -c 'source "$LIB"; install_capacity_probe'
  [ "$status" -eq 0 ]
  before="$(cat "$SYSTEMD_UNIT_DIR/xenia-gpu-capacity-probe.service")"
  run bash -c 'source "$LIB"; install_capacity_probe'
  [ "$status" -eq 0 ]
  [ "$(cat "$SYSTEMD_UNIT_DIR/xenia-gpu-capacity-probe.service")" = "$before" ]
}
