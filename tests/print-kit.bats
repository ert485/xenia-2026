#!/usr/bin/env bats
setup() {
  REAL="$BATS_TEST_DIRNAME/.."
  export KIT_ROOT="$BATS_TEST_TMPDIR/kit"
  mkdir -p "$KIT_ROOT/scripts/lib" "$KIT_ROOT/team-kit"
  cp "$REAL/scripts/print-kit.sh" "$KIT_ROOT/scripts/"
  cp "$REAL/scripts/lib/common.sh" "$KIT_ROOT/scripts/lib/"
  export CALLS="$BATS_TEST_TMPDIR/calls"; : > "$CALLS"
  cat > "$BATS_TEST_TMPDIR/python" <<'SH'
#!/usr/bin/env bash
printf 'python %s\n' "$*" >> "$CALLS"
prev=""
for a in "$@"; do [[ "$prev" == "--output" ]] && : > "$a"; prev="$a"; done
SH
  chmod +x "$KIT_ROOT/scripts/print-kit.sh" "$BATS_TEST_TMPDIR/python"
  export PYTHON="$BATS_TEST_TMPDIR/python" CHROME="$BATS_TEST_TMPDIR/no-chrome"
}

@test "writes qr.png and qr.svg for the kit URL and exits 0 without Chrome" {
  run "$KIT_ROOT/scripts/print-kit.sh"
  [ "$status" -eq 0 ]
  [ -f "$KIT_ROOT/team-kit/print/qr.png" ]
  [ -f "$KIT_ROOT/team-kit/print/qr.svg" ]
  grep -q -- '-m segno --scale 12 --output team-kit/print/qr.png https://26.cohack.tetl.ca$' "$CALLS"
  [[ "$output" == *"Chrome not found"* ]]
  [[ "$output" == *"11-join-flyer"* ]]
}
