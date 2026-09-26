#!/usr/bin/env bats
setup() {
  cd "$BATS_TEST_DIRNAME/.."
  D="$BATS_TEST_TMPDIR/shutdown.d"; mkdir -p "$D"
}

entry() {
  printf '%s\n' '#!/usr/bin/env bash' '# xenia-shutdown' "# stops: $2" "# added-by: $3" "# restore: $4" \
    "# cost-when-running: $5" 'set -euo pipefail' 'echo ok' > "$D/$1"
}

@test "two entries render as two rows in filename order" {
  entry 20-box.sh 'the box | and its disk' erik 'scripts/startup.sh' 'about $1.60/day'
  entry 10-gpu.sh 'the GPU box' erik 'scripts/gpu.sh start' 'about $1.86/hour'
  run scripts/render-shutdown-md.sh "$D"
  [ "$status" -eq 0 ]
  [[ "$output" == *"| Entry | Stops | Added by | Restore | Cost when running |"* ]]
  rows="$(printf '%s\n' "$output" | grep '^| `')"
  [ "$(printf '%s\n' "$rows" | wc -l | tr -d ' ')" -eq 2 ]
  [[ "$(printf '%s\n' "$rows" | head -1)" == '| `10-gpu.sh` | the GPU box | erik | scripts/gpu.sh start | about $1.86/hour |' ]]
  [[ "$(printf '%s\n' "$rows" | tail -1)" == *'the box \| and its disk'* ]]
}

@test "output is identical on a second run" {
  entry 10-gpu.sh 'the GPU box' erik 'scripts/gpu.sh start' 'about $1.86/hour'
  a="$(scripts/render-shutdown-md.sh "$D")"
  b="$(scripts/render-shutdown-md.sh "$D")"
  [ "$a" = "$b" ]
}

@test "a missing restore: exits 1 naming the file and the field" {
  printf '%s\n' '#!/usr/bin/env bash' '# xenia-shutdown' '# stops: x' '# added-by: erik' '# cost-when-running: free' 'set -euo pipefail' > "$D/10-x.sh"
  run scripts/render-shutdown-md.sh "$D"
  [ "$status" -eq 1 ]
  [[ "$output" == *"10-x.sh: missing '# restore:'"* ]]
}

@test "a missing marker line exits 1" {
  printf '%s\n' '#!/usr/bin/env bash' '# stops: x' > "$D/10-x.sh"
  run scripts/render-shutdown-md.sh "$D"
  [ "$status" -eq 1 ]
  [[ "$output" == *"10-x.sh: line 2 must be '# xenia-shutdown'"* ]]
}

@test "an empty directory renders the no-entries line" {
  run scripts/render-shutdown-md.sh "$D"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No entries yet"* ]]
}
