#!/usr/bin/env bats
# The shared rule-feedback regex (spec section 13), verbatim:
#   ^Rule-feedback:\s*(P-[a-z-]+|none)(?:,\s*(.+))?$
# matched per line after stripping \r; lines inside ``` fences are ignored; only column 0 counts.
# extract() below is the reference reader until Task 24 writes scripts/ci/rule-feedback.sh.
setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export TMP="$BATS_TEST_TMPDIR"
  PY="$PWD/.venv/bin/python"; [ -x "$PY" ] || PY=python3
  export PY
  {
    printf '%s\n' 'Rule-feedback: P-two-gates, merged with a red preview because the box was rebooting'
    printf '%s\n' 'Rule-feedback: none'
    printf '%s\n' 'Rule-feedback: P-Two-Gates, uppercase slug'
    printf '%s\n' '  Rule-feedback: P-wheel, indented'
    printf '%s\n' '```'
    printf '%s\n' 'Rule-feedback: P-off-switch, inside a fence'
    printf '%s\n' '```'
    printf '%s\r\n' 'Rule-feedback: P-public, a CRLF line'
  } > "$TMP/body.md"
}

extract() {
  "$PY" - "$1" <<'PY'
import re, sys
rx = re.compile(r'^Rule-feedback:\s*(P-[a-z-]+|none)(?:,\s*(.+))?$')
fence = False
with open(sys.argv[1], encoding="utf-8", newline="") as f:
    for raw in f:
        line = raw.rstrip("\n").replace("\r", "")
        if line.lstrip().startswith("```"):
            fence = not fence
            continue
        if fence:
            continue
        m = rx.match(line)
        if m:
            print(f"{m.group(1)}\t{m.group(2) or ''}")
PY
}

@test "valid, none and CRLF lines match; invalid slug, indented and fenced lines do not" {
  run extract "$TMP/body.md"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  [ "${lines[0]}" = "$(printf 'P-two-gates\tmerged with a red preview because the box was rebooting')" ]
  [ "${lines[1]}" = "none" ]
  [ "${lines[2]}" = "$(printf 'P-public\ta CRLF line')" ]
}

@test "rule-feedback-line.sh agrees: valid lines round-trip, the invalid slug is refused" {
  for l in 'P-two-gates, merged with a red preview' 'none' 'P-no-clickops, console-made test bucket'; do
    out="$(plugin/scripts/rule-feedback-line.sh "$l")"
    printf '%s\n' "$out" > "$TMP/one.md"
    [ -n "$(extract "$TMP/one.md")" ]
  done
  run plugin/scripts/rule-feedback-line.sh 'P-Two-Gates, uppercase slug'
  [ "$status" -eq 1 ]
}

@test "both PR templates carry the two lines at column 0, outside any fence" {
  for t in templates/team-repo/PULL_REQUEST_TEMPLATE.md .github/PULL_REQUEST_TEMPLATE.md; do
    [ "$(extract "$t")" = "none" ]
    grep -qx 'Shutdown: none needed because <reason>' "$t"
  done
}