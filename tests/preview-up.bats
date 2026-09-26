#!/usr/bin/env bats
# preview-up: a resync redeploys in place, never counts twice toward the cap, never evicts itself.

setup() {
  export TMP="$BATS_TEST_TMPDIR"
  cp -R "$BATS_TEST_DIRNAME/../infra/recipes/docker-box" "$TMP/recipe"
  export BOX="$TMP/recipe/box"
  export KIT_ON_BOX="$TMP/recipe"
  cat > "$BOX/compose-check.py" <<'PY'
import os, sys
sys.stdout.write(os.environ.get("FAKE_CHECK_MSG", ""))
sys.exit(int(os.environ.get("FAKE_CHECK_EXIT", "0")))
PY
  export CALLS="$TMP/calls"; : > "$CALLS"
  export STATE="$TMP/projects"
  export PREVIEWS_ROOT="$TMP/previews"; mkdir -p "$PREVIEWS_ROOT"
  printf 'ZONE=26.cohack.tetl.ca\nAPP_PORT=3000\n' > "$TMP/xenia.env"
  export XENIA_ENV_FILE="$TMP/xenia.env"
  printf 'services:\n  web:\n    image: ${IMAGE:-web:local}\n    build: .\n' > "$TMP/compose.yml"
  export FIXTURE_COMPOSE="$TMP/compose.yml"
  mkdir -p "$TMP/bin"

  cat > "$TMP/bin/git" <<'SH'
#!/usr/bin/env bash
printf 'git %s\n' "$*" >> "$CALLS"
if [[ "$1" == "clone" ]]; then dest="${!#}"; mkdir -p "$dest"; cp "$FIXTURE_COMPOSE" "$dest/compose.yml"; fi
exit 0
SH

  cat > "$TMP/bin/docker" <<'SH'
#!/usr/bin/env bash
printf 'docker %s\n' "$*" >> "$CALLS"
project=""; prev=""
for a in "$@"; do [[ "$prev" == "-p" ]] && project="$a"; prev="$a"; done
case "$*" in
  "compose ls"*)
    first=1; printf '['
    while read -r p; do
      [[ -n "$p" ]] || continue
      [[ $first == 1 ]] || printf ','; first=0
      printf '{"Name":"%s","Status":"running(1)","ConfigFiles":"/srv/%s/compose.yml"}' "$p" "$p"
    done < "$STATE"
    printf ']\n' ;;
  *inspect*)
    for a in "$@"; do
      if [[ "$a" =~ ^pr-([0-9]+)-web$ ]]; then printf '2026-09-25T%02d:00:00.000000000Z\n' "${BASH_REMATCH[1]}"; exit 0; fi
    done
    exit 1 ;;
  compose*" down"*)
    grep -vx -- "$project" "$STATE" > "$STATE.new" || true; mv "$STATE.new" "$STATE" ;;
  compose*" up "*)
    grep -qx -- "$project" "$STATE" || echo "$project" >> "$STATE" ;;
  *) : ;;
esac
exit 0
SH
  chmod +x "$TMP/bin/git" "$TMP/bin/docker"
  export PATH="$TMP/bin:$PATH"
  # four running previews plus the gateway and the app, which must never be counted or evicted
  printf 'gateway\napp\npr-1\npr-2\npr-3\npr-4\n' > "$STATE"
  SHA="$(printf 'a%.0s' $(seq 1 40))"
}

downs() { grep -oE 'compose -p pr-[0-9]+ down' "$CALLS" | awk '{print $3}' | sort -u | tr '\n' ' '; }

@test "resync of pr-4 evicts only the oldest other preview (cap 3)" {
  run "$BOX/preview-up.sh" 4 ert485/xenia-2026 "$SHA" .
  [ "$status" -eq 0 ]
  [ "$(downs)" = "pr-1 " ]
  grep -q 'compose -p pr-4 .* up -d --remove-orphans' "$CALLS"
  [[ "$output" == *"preview: https://pr-4.box.26.cohack.tetl.ca" ]]
}

@test "a new PR makes room for itself (cap 2)" {
  run "$BOX/preview-up.sh" 5 ert485/xenia-2026 "$SHA" .
  [ "$status" -eq 0 ]
  [ "$(downs)" = "pr-1 pr-2 " ]
  grep -qx 'pr-5' "$STATE"
  [ "$(grep -c '^pr-' "$STATE")" -eq 3 ]
}

@test "resync of the oldest preview never evicts itself" {
  run "$BOX/preview-up.sh" 1 ert485/xenia-2026 "$SHA" .
  [ "$status" -eq 0 ]
  [ "$(downs)" = "pr-2 " ]
  grep -qx 'pr-1' "$STATE"
}

@test "gateway and app projects are never touched" {
  run "$BOX/preview-up.sh" 5 ert485/xenia-2026 "$SHA" .
  ! grep -qE 'compose -p (gateway|app) ' "$CALLS"
}

@test "a refused compose file stops before any eviction or build" {
  FAKE_CHECK_EXIT=1 FAKE_CHECK_MSG="service web: privileged: true" run "$BOX/preview-up.sh" 5 ert485/xenia-2026 "$SHA" .
  [ "$status" -ne 0 ]
  [[ "$output" == *"preview refused"* ]] || return 1
  [ -z "$(downs)" ]
  ! grep -q ' up -d' "$CALLS"
}

@test "bad arguments are refused before anything runs" {
  run "$BOX/preview-up.sh" 12x ert485/xenia-2026 "$SHA" .
  [ "$status" -ne 0 ]
  run "$BOX/preview-up.sh" 12 ert485/xenia-2026 "$SHA" ../etc
  [ "$status" -ne 0 ]
  ! grep -q '^git clone' "$CALLS"
}
