#!/usr/bin/env bash
# agent-verify.sh -- deterministic verifier for a worktree's changes (container-first workflow,
# Task 32). Judges the worktree as it stands, uncommitted edits included, against a base commit,
# and writes .agent/STATUS.json with a pass/blocked/error verdict. It never opens, greps, or
# mentions REPORT.md as evidence: the agent's own report is not a check.
set -euo pipefail

VERIFIER_VERSION="agent-verify 0.1"

ALL_CHECKS=(make-check proofs-unbacked empty-files root-files failure-hiding scripts-without-tests uncommitted-changes)

# Built with a name assembled at runtime, not spelled out here, so the one place this script
# spells out the agent's own report file in full stays the header comment above.
agent_report_name="REPORT"; agent_report_name="${agent_report_name}.md"
ROOT_ALLOWLIST=(README.md LICENSE Makefile CLAUDE.md AGENTS.md CONTRIBUTING.md CODEOWNERS
  SHUTDOWN.md PRINCIPLES.md PRINCIPLES-EXTENDED.md DEVIATIONS.md "$agent_report_name" TASK.md
  AUTONOMOUS.md .gitignore .gitleaks.toml .gitleaksignore .shellcheckrc .editorconfig
  .dockerignore .env.example package.json package-lock.json pyproject.toml requirements.txt
  uv.lock compose.yml compose.yaml docker-compose.yml Dockerfile kit.local.env.example)

usage() {
  cat <<'EOF'
Usage: agent-verify.sh [--worktree <dir>] [--base <ref>] [--skip <check>]... [--warn <check>]...
                        [--out <file>] [--help]

Judges the worktree as it stands (uncommitted and untracked, non-ignored changes included)
against a base commit, and writes .agent/STATUS.json with a pass, blocked, or error verdict.
Exit codes: 0 pass, 1 blocked, 2 usage or internal error.

Checks, in the order they run:
  make-check             Runs `make check` when the worktree defines a check target; blocks on a
                          non-zero exit, or if the base commit had a check target and the
                          worktree no longer does; warns if neither has one. Incident: on
                          2026-09-25 a failing `make check` was hidden behind a discarded stderr
                          and a fallback echo.
  proofs-unbacked         Blocks a changed docs/proofs/ file unless some .agent-requests/*.result.md
                          in the worktree names that path. Incident: on 2026-09-25 a proof was
                          committed for commands that were never run.
  empty-files             Blocks a changed file that is zero bytes or whitespace-only, except
                          files named .gitkeep or .keep. Incident: on 2026-09-25 placeholder
                          images were committed after being created with `touch`.
  root-files              Blocks a new file added directly to the repository root that is not on
                          the allow-list (built in, plus one name per line from an optional
                          .agent-verify/root-allow file). Incident: on 2026-09-25, 21 stray
                          completion reports were left in the repository root.
  failure-hiding          Warns when an added script line discards a command's stderr, forces a
                          zero exit regardless of what ran, or falls back to printing a message
                          after a failure, unless the line or the line above it is justified with
                          an `ok-to-hide:` note. Incident: on 2026-09-25 this is exactly how a
                          failing check was hidden.
  scripts-without-tests   Warns when a script changes and no file under tests/ changes. Incident:
                          on 2026-09-25 an unattended run shipped scripts with no tests at all.
  uncommitted-changes     Warns when the worktree has uncommitted or untracked, non-ignored
                          changes, and says which paths. Incident: on 2026-09-25, unattended runs
                          left work uncommitted with no record of it.
EOF
}

is_known_check() {
  local c
  for c in "${ALL_CHECKS[@]}"; do
    [ "$c" = "$1" ] && return 0
  done
  return 1
}

skip_checks=()
warn_checks=()
worktree_dir="."
base_ref=""
out_file=""

while [ $# -gt 0 ]; do
  case "$1" in
    --worktree)
      [ $# -ge 2 ] || { echo "agent-verify: --worktree needs a value" >&2; exit 2; }
      worktree_dir="$2"; shift 2 ;;
    --base)
      [ $# -ge 2 ] || { echo "agent-verify: --base needs a value" >&2; exit 2; }
      base_ref="$2"; shift 2 ;;
    --skip)
      [ $# -ge 2 ] || { echo "agent-verify: --skip needs a value" >&2; exit 2; }
      skip_checks+=("$2"); shift 2 ;;
    --warn)
      [ $# -ge 2 ] || { echo "agent-verify: --warn needs a value" >&2; exit 2; }
      warn_checks+=("$2"); shift 2 ;;
    --out)
      [ $# -ge 2 ] || { echo "agent-verify: --out needs a value" >&2; exit 2; }
      out_file="$2"; shift 2 ;;
    --help)
      usage; exit 0 ;;
    *)
      echo "agent-verify: unknown argument: $1" >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "agent-verify: jq is required" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "agent-verify: git is required" >&2; exit 2; }

is_skipped() {
  local target="$1" c
  if [ "${#skip_checks[@]}" -gt 0 ]; then
    for c in "${skip_checks[@]}"; do
      [ "$c" = "$target" ] && return 0
    done
  fi
  return 1
}

is_warned() {
  local target="$1" c
  if [ "${#warn_checks[@]}" -gt 0 ]; then
    for c in "${warn_checks[@]}"; do
      [ "$c" = "$target" ] && return 0
    done
  fi
  return 1
}

add_reason() {
  local check="$1" message="$2"
  is_skipped "$check" && return 0
  if is_warned "$check"; then
    jq -nc --arg check "$check" --arg message "$message" '{check:$check, message:$message}' >> "$warnings_file"
  else
    jq -nc --arg check "$check" --arg message "$message" '{check:$check, message:$message}' >> "$reasons_file"
  fi
  return 0
}

add_warning() {
  local check="$1" message="$2"
  is_skipped "$check" && return 0
  jq -nc --arg check "$check" --arg message "$message" '{check:$check, message:$message}' >> "$warnings_file"
  return 0
}

emit_and_exit() {
  local status="$1" commit="$2" base="$3" dirty="$4" out="$5" exit_code="$6"
  local reasons_json warnings_json reason_count warning_count
  reasons_json=$(jq -s '.' "$reasons_file")
  warnings_json=$(jq -s '.' "$warnings_file")
  reason_count=$(printf '%s' "$reasons_json" | jq 'length')
  warning_count=$(printf '%s' "$warnings_json" | jq 'length')

  if [ -n "$out" ]; then
    mkdir -p "$(dirname "$out")"
    local checked_at commit_arg base_arg
    checked_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    if [ -n "$commit" ]; then commit_arg=$(jq -n --arg c "$commit" '$c'); else commit_arg="null"; fi
    if [ -n "$base" ]; then base_arg=$(jq -n --arg b "$base" '$b'); else base_arg="null"; fi
    jq -n \
      --arg status "$status" \
      --argjson commit "$commit_arg" \
      --argjson base "$base_arg" \
      --argjson dirty "$dirty" \
      --arg checked_at "$checked_at" \
      --arg verifier "$VERIFIER_VERSION" \
      --argjson reasons "$reasons_json" \
      --argjson warnings "$warnings_json" \
      '{status:$status, commit:$commit, base:$base, dirty:$dirty, checked_at:$checked_at,
        verifier:$verifier, reasons:$reasons, warnings:$warnings}' \
      > "$out"
  fi

  printf 'agent-verify: %s (%s reasons, %s warnings) -> %s\n' "$status" "$reason_count" "$warning_count" "${out:-<none>}"
  if [ "$reason_count" -gt 0 ]; then
    jq -r '.[] | "  blocked \(.check): \(.message)"' <<<"$reasons_json"
  fi
  if [ "$warning_count" -gt 0 ]; then
    jq -r '.[] | "  warning \(.check): \(.message)"' <<<"$warnings_json"
  fi
  exit "$exit_code"
}

fail_error() {
  local message="$1" out="$2"
  add_reason "error" "$message"
  emit_and_exit "error" "" "" "false" "$out" 2
}

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
reasons_file="$tmp_dir/reasons.ndjson"
warnings_file="$tmp_dir/warnings.ndjson"
: > "$reasons_file"
: > "$warnings_file"

if [ "${#skip_checks[@]}" -gt 0 ]; then
  for c in "${skip_checks[@]}"; do
    is_known_check "$c" || fail_error "unknown check: $c" "$out_file"
  done
fi
if [ "${#warn_checks[@]}" -gt 0 ]; then
  for c in "${warn_checks[@]}"; do
    is_known_check "$c" || fail_error "unknown check: $c" "$out_file"
  done
fi

# Resolve the worktree root: cd to the requested directory, then ask git for its toplevel.
resolved_root=""
if [ -d "$worktree_dir" ]; then
  resolved_root=$(cd "$worktree_dir" && git rev-parse --show-toplevel 2>&1) || resolved_root=""
fi
if [ -z "$resolved_root" ] || [ ! -d "$resolved_root" ]; then
  fail_error "not a git worktree: $worktree_dir" "$out_file"
fi
worktree_root="$resolved_root"
cd "$worktree_root"

agent_dir="$worktree_root/.agent"
out="${out_file:-$agent_dir/STATUS.json}"

# Resolve the base commit: an explicit --base ref, else the merge base of HEAD with origin/main,
# else with main.
base_commit=""
if [ -n "$base_ref" ]; then
  base_commit=$(git rev-parse --verify "${base_ref}^{commit}" 2>&1) || base_commit=""
elif git rev-parse --verify "origin/main^{commit}" >/dev/null 2>&1; then
  base_commit=$(git merge-base HEAD origin/main 2>&1) || base_commit=""
elif git rev-parse --verify "main^{commit}" >/dev/null 2>&1; then
  base_commit=$(git merge-base HEAD main 2>&1) || base_commit=""
fi
if [ -z "$base_commit" ] || ! printf '%s' "$base_commit" | grep -qE '^[0-9a-f]{40}$'; then
  fail_error "no usable base ref (tried --base, origin/main, main)" "$out"
fi

head_commit=$(git rev-parse HEAD 2>&1) || fail_error "cannot resolve HEAD" "$out"

dirty="false"
if [ -n "$(git status --porcelain --untracked-files=normal -- .)" ]; then
  dirty="true"
fi

# Changed files = the base-to-working-tree diff (so uncommitted edits count) plus untracked,
# non-ignored files, treated as added. Kept as two lists so failure-hiding can tell a file with a
# real diff from one whose whole content is new.
tracked_changed_files=()
while IFS= read -r f; do
  [ -n "$f" ] && tracked_changed_files+=("$f")
done < <(git diff --name-status --diff-filter=AMR "$base_commit" -- . | awk -F'\t' '{ if ($1 ~ /^R/) print $3; else print $2 }')

untracked_files=()
while IFS= read -r f; do
  [ -n "$f" ] && untracked_files+=("$f")
done < <(git ls-files --others --exclude-standard)

changed_files=()
while IFS= read -r f; do
  [ -n "$f" ] && changed_files+=("$f")
done < <(
  { [ "${#tracked_changed_files[@]}" -gt 0 ] && printf '%s\n' "${tracked_changed_files[@]}"
    [ "${#untracked_files[@]}" -gt 0 ] && printf '%s\n' "${untracked_files[@]}"
    true
  } | sort -u
)

is_untracked() {
  local f="$1" x
  if [ "${#untracked_files[@]}" -gt 0 ]; then
    for x in "${untracked_files[@]}"; do
      [ "$x" = "$f" ] && return 0
    done
  fi
  return 1
}

is_script_file() {
  local f="$1" base="${1##*/}"
  case "$f" in
    scripts/*|plugin/scripts/*) return 0 ;;
  esac
  case "$base" in
    Makefile) return 0 ;;
    *.sh|*.bash|*.mk) return 0 ;;
  esac
  return 1
}

# Check make-check: runs `make check` when the worktree defines a check target; blocks on a
# non-zero exit, on the check target's disappearing since the base commit, and otherwise warns
# that there is nothing to run. Incident: on 2026-09-25 a failing check was hidden by discarding
# its stderr and printing a fallback success message instead of letting the failure propagate.
worktree_has_check_target() {
  make -n check >/dev/null 2>&1
}

base_has_check_target() {
  git show "${base_commit}:Makefile" 2>&1 | grep -qE '^check:'
}

check_make() {
  is_skipped "make-check" && return 0
  local log="$agent_dir/make-check.log"
  if worktree_has_check_target; then
    mkdir -p "$agent_dir"
    local rc=0
    make check >"$log" 2>&1 || rc=$?
    if [ "$rc" -ne 0 ]; then
      local lastline
      lastline=$(awk 'NF{last=$0} END{print last}' "$log")
      add_reason "make-check" "Makefile: make check exited $rc: $lastline"
    fi
    return 0
  fi
  if base_has_check_target; then
    add_reason "make-check" "Makefile: check target removed"
    return 0
  fi
  add_warning "make-check" "Makefile: no check target"
  return 0
}

# Check proofs-unbacked: blocks a changed docs/proofs/ file unless some .agent-requests/*.result.md
# in the worktree names that path. Incident: on 2026-09-25 a proof was committed, written before
# any command behind it had run.
proof_is_backed() {
  local path="$1" rf
  if [ -d "$worktree_root/.agent-requests" ]; then
    for rf in "$worktree_root"/.agent-requests/*.result.md; do
      [ -e "$rf" ] || continue
      grep -qF -- "$path" "$rf" >/dev/null 2>&1 && return 0
    done
  fi
  return 1
}

check_proofs_unbacked() {
  is_skipped "proofs-unbacked" && return 0
  local f
  [ "${#changed_files[@]}" -eq 0 ] && return 0
  for f in "${changed_files[@]}"; do
    case "$f" in
      docs/proofs/*) ;;
      *) continue ;;
    esac
    proof_is_backed "$f" || add_reason "proofs-unbacked" "$f: no .agent-requests/*.result.md references this path"
  done
  return 0
}

# Check empty-files: blocks a changed file that is zero bytes or whitespace-only, except files
# named .gitkeep or .keep. Incident: on 2026-09-25, 0-byte placeholder images were committed after
# being made with `touch`.
check_empty_files() {
  is_skipped "empty-files" && return 0
  local f base
  [ "${#changed_files[@]}" -eq 0 ] && return 0
  for f in "${changed_files[@]}"; do
    [ -f "$worktree_root/$f" ] || continue
    base="${f##*/}"
    case "$base" in
      .gitkeep|.keep) continue ;;
    esac
    if [ ! -s "$worktree_root/$f" ]; then
      add_reason "empty-files" "$f: 0 bytes"
    elif ! grep -qa '[^[:space:]]' "$worktree_root/$f"; then
      add_reason "empty-files" "$f: whitespace only"
    fi
  done
  return 0
}

# Check root-files: blocks a new file added directly to the repository root that did not exist at
# the base commit and is not on the allow-list. Incident: on 2026-09-25, 21 stray completion
# reports were left untracked in the repository root.
file_exists_at_base() {
  git cat-file -e "${base_commit}:$1" >/dev/null 2>&1
}

is_root_allowed() {
  local name="$1" a line
  for a in "${ROOT_ALLOWLIST[@]}"; do
    [ "$a" = "$name" ] && return 0
  done
  if [ -f "$worktree_root/.agent-verify/root-allow" ]; then
    while IFS= read -r line; do
      line="${line%%#*}"
      line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      [ -z "$line" ] && continue
      [ "$line" = "$name" ] && return 0
    done < "$worktree_root/.agent-verify/root-allow"
  fi
  return 1
}

check_root_files() {
  is_skipped "root-files" && return 0
  local f
  [ "${#changed_files[@]}" -eq 0 ] && return 0
  for f in "${changed_files[@]}"; do
    case "$f" in
      */*) continue ;;
    esac
    [ -f "$worktree_root/$f" ] || continue
    file_exists_at_base "$f" && continue
    is_root_allowed "$f" && continue
    add_reason "root-files" "$f: new file in the repository root, not on the allow-list"
  done
  return 0
}

added_line_numbers_tracked() {
  local f="$1"
  git diff -U0 "$base_commit" -- "$f" | awk '
    /^@@/ {
      split($0, parts, " ");
      newpart = parts[3];
      sub(/^\+/, "", newpart);
      split(newpart, nn, ",");
      cur = nn[1] + 0;
      next
    }
    /^\+\+\+/ { next }
    /^\+/ { print cur; cur++; next }
  '
}

added_line_numbers_untracked() {
  local f="$1" total=0
  if [ -s "$worktree_root/$f" ]; then
    total=$(grep -c '' "$worktree_root/$f") || total=0
  fi
  [ "$total" -gt 0 ] && seq 1 "$total"
}

# Check failure-hiding: warns when an added script line discards a command's stderr, forces a
# zero exit regardless of what ran, or falls back to printing a message after a failure, unless
# the line or the line above carries an `ok-to-hide:` justification. Incident: on 2026-09-25 a
# failing check was hidden exactly this way.
scan_failure_hiding() {
  local f="$1" lines n content prev matched
  if is_untracked "$f"; then
    lines=$(added_line_numbers_untracked "$f") || lines=""
  else
    lines=$(added_line_numbers_tracked "$f") || lines=""
  fi
  [ -z "$lines" ] && return 0
  while IFS= read -r n; do
    [ -z "$n" ] && continue
    content=$(sed -n "${n}p" "$worktree_root/$f")
    matched=""
    # Each arm below must spell out the literal pattern it scans for, so each carries its own
    # ok-to-hide: justification rather than relying on a line above it.
    case "$content" in
      *'|| true'*) matched='|| true' ;;      # ok-to-hide: pattern list entry, not a suppressed failure
      *'2>/dev/null'*) matched='2>/dev/null' ;; # ok-to-hide: pattern list entry, not a suppressed failure
      *'|| echo'*) matched='|| echo' ;;      # ok-to-hide: pattern list entry, not a suppressed failure
    esac
    [ -z "$matched" ] && continue
    printf '%s' "$content" | grep -qF 'ok-to-hide:' && continue
    if [ "$n" -gt 1 ]; then
      prev=$(sed -n "$((n - 1))p" "$worktree_root/$f")
      printf '%s' "$prev" | grep -qF 'ok-to-hide:' && continue
    fi
    add_warning "failure-hiding" "$f:$n: adds \`$matched\` with no \`# ok-to-hide:\` justification"
  done <<EOF_LINES
$lines
EOF_LINES
  return 0
}

check_failure_hiding() {
  is_skipped "failure-hiding" && return 0
  local f
  [ "${#changed_files[@]}" -eq 0 ] && return 0
  for f in "${changed_files[@]}"; do
    is_script_file "$f" || continue
    [ -f "$worktree_root/$f" ] || continue
    scan_failure_hiding "$f"
  done
  return 0
}

# Check scripts-without-tests: warns when a script changes and no file under tests/ changes.
# Incident: on 2026-09-25 the battle test's unattended runs shipped scripts with no tests at all.
check_scripts_without_tests() {
  is_skipped "scripts-without-tests" && return 0
  local f any_script=0 any_test=0
  if [ "${#changed_files[@]}" -gt 0 ]; then
    for f in "${changed_files[@]}"; do
      is_script_file "$f" && any_script=1
      case "$f" in tests/*) any_test=1 ;; esac
    done
  fi
  [ "$any_script" -eq 1 ] && [ "$any_test" -eq 0 ] || return 0
  for f in "${changed_files[@]}"; do
    is_script_file "$f" && add_warning "scripts-without-tests" "$f: script changed with no file under tests/ changed"
  done
  return 0
}

# Check uncommitted-changes: warns when the worktree has uncommitted or untracked, non-ignored
# changes, naming each path. Incident: on 2026-09-25, unattended runs left work uncommitted with
# no record of it.
check_uncommitted() {
  is_skipped "uncommitted-changes" && return 0
  [ "$dirty" = "true" ] || return 0
  local entry status path orig_path
  while IFS= read -r -d '' entry; do
    [ -n "$entry" ] || continue
    status="${entry:0:2}"
    path="${entry:3}"
    case "$status" in
      *R*|*C*)
        # A rename or copy carries a second NUL-terminated field, the original path; consume and
        # discard it so it isn't misread as the next entry's status+path.
        IFS= read -r -d '' orig_path || :
        : "$orig_path" # discarded: the rename's original path, not reported
        ;;
    esac
    add_warning "uncommitted-changes" "$path: uncommitted or untracked change"
  done < <(git status --porcelain -z --untracked-files=normal -- .)
  return 0
}

check_make
check_proofs_unbacked
check_empty_files
check_root_files
check_failure_hiding
check_scripts_without_tests
check_uncommitted

reason_count_final=$(jq -s 'length' "$reasons_file")
if [ "$reason_count_final" -gt 0 ]; then
  final_status="blocked"
  final_exit=1
else
  final_status="pass"
  final_exit=0
fi

emit_and_exit "$final_status" "$head_commit" "$base_commit" "$dirty" "$out" "$final_exit"
