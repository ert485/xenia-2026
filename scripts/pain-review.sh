#!/usr/bin/env bash
# Usage: scripts/pain-review.sh [--repo owner/repo] [--post] [--dry-run] [--no-model]
# Should tier: shipped and tested with fakes; not proven end to end unless
# docs/proofs/2026-09-25-pain-review.md exists.
#
# The pain-review bot (P-fix-once, D16, D25). Reads from the repo: open issues labelled friction, the
# Rule-feedback: lines of the last 100 merged PRs (scripts/ci/rule-feedback.sh), and open issues labelled
# rule-feedback. Then:
#   1. rewrites the pinned "Rule feedback" issue grouped by rule with counts, deterministically, with no
#      model involved, so "three sightings" is computed, not eyeballed;
#   2. asks the model through the gateway for clusters, pain scores, a reading per rule, one
#      recommendation, and one proposed next-fix issue (skipped with --no-model; when the answer is not
#      usable JSON the run keeps step 1 only);
#   3. opens that next-fix issue unless an open next-fix issue already has the same title;
#   4. with --post, sends the recommendation to the team channel through plugin/scripts/notify.sh.
# --dry-run prints everything it would write and changes nothing.
# Repo: --repo, else $GITHUB_REPOSITORY, else $TEAM_REPO, else the current directory's GitHub repo.
# shellcheck disable=SC2016  # jq and awk programs and Markdown backticks sit in single quotes on purpose
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
require_cmd gh jq python3

repo="" post=0 dry=0 use_model=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="${2:?--repo needs owner/repo}"; shift 2 ;;
    --post) post=1; shift ;;
    --dry-run) dry=1; shift ;;
    --no-model) use_model=0; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1 (see --help)" >&2; exit 2 ;;
  esac
done
repo="${repo:-${GITHUB_REPOSITORY:-${TEAM_REPO:-}}}"
[[ -n "$repo" ]] || repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "not an owner/repo: $repo"

work="${PAIN_REVIEW_DIR:-$(mktemp -d)}"; mkdir -p "$work"
now="${PAIN_REVIEW_NOW:-$(date -u +%Y-%m-%dT%H:%MZ)}"
rf="$KIT_ROOT/scripts/ci/rule-feedback.sh"
prompt="$KIT_ROOT/templates/review/pain-review-prompt.md"
notify="${PAIN_REVIEW_NOTIFY:-$KIT_ROOT/plugin/scripts/notify.sh}"
pinned_title="Rule feedback"

# 1. Gather.
gh issue list --repo "$repo" --label friction --state open --limit 200 --json number,title,body,createdAt,url > "$work/friction.json"
gh pr list --repo "$repo" --state merged --limit 100 --json number,title,body,url > "$work/prs.json"
gh issue list --repo "$repo" --label rule-feedback --state open --limit 200 --json number,title,body,url > "$work/rf-issues.json"

: > "$work/rows.tsv"   # slug, kind, number, reason
count="$(jq length "$work/prs.json")"
for ((i = 0; i < count; i++)); do
  num="$(jq -r ".[$i].number" "$work/prs.json")"
  jq -r ".[$i].body // \"\"" "$work/prs.json" > "$work/body.txt"
  "$rf" "$work/body.txt" 2>/dev/null | while IFS=$'\t' read -r slug reason; do
    printf '%s\tPR\t%s\t%s\n' "$slug" "$num" "$reason"
  done >> "$work/rows.tsv"
done
count="$(jq length "$work/rf-issues.json")"
for ((i = 0; i < count; i++)); do
  num="$(jq -r ".[$i].number" "$work/rf-issues.json")"
  title="$(jq -r ".[$i].title" "$work/rf-issues.json")"
  jq -r ".[$i].body // \"\"" "$work/rf-issues.json" > "$work/body.txt"
  found="$("$rf" "$work/body.txt" 2>/dev/null || true)"
  if [[ -n "$found" ]]; then
    printf '%s\n' "$found" | while IFS=$'\t' read -r slug reason; do
      printf '%s\tissue\t%s\t%s\n' "$slug" "$num" "${reason:-$title}"
    done >> "$work/rows.tsv"
  else
    # Issue form: the slug is the dropdown answer; the title is the reason.
    slug="$(tr -d '\r' < "$work/body.txt" | grep -oE '(^|[^A-Za-z0-9])P-[a-z-]+' | head -1 | grep -oE 'P-[a-z-]+' || true)"
    printf '%s\tissue\t%s\t%s\n' "${slug:-unknown}" "$num" "$title" >> "$work/rows.tsv"
  fi
done

# 2. The deterministic pinned body.
{
  printf '<!-- xenia-rule-feedback -->\n'
  printf 'Bot: this issue is rewritten by the pain-review run (last run %s) from every `Rule-feedback:` line in merged PR bodies and every open issue labelled `rule-feedback`.\n\n' "$now"
  printf 'Teammate: this pile is only ever used to decide, as a team, whether a rule stays, changes, or the code is brought back in line. It is never used to challenge a merged change or the teammate who made it (P-ours). Three or more sightings of one rule put it on the agenda of the next checkpoint (18:00, then the retro).\n\n'
  if [[ ! -s "$work/rows.tsv" ]]; then
    printf 'No rule feedback recorded yet.\n'
  else
    cut -f1 "$work/rows.tsv" | sort | uniq -c | sort -k1,1nr -k2,2 | while read -r n slug; do
      label="$slug"; [[ "$slug" == unknown ]] && label="no rule named"
      if (( n >= 3 )); then printf '## %s (%s): review at the next checkpoint\n\n' "$label" "$n"
      else printf '## %s (%s)\n\n' "$label" "$n"; fi
      awk -F'\t' -v s="$slug" '$1 == s { printf "- #%s (%s): %s\n", $3, $2, ($4 == "" ? "no reason given" : $4) }' "$work/rows.tsv" \
        | sort -t'#' -k2,2n
      printf '\n'
    done
  fi
} > "$work/pinned.md"

# 3. The model's reading (advisory).
: > "$work/answer.json"
if (( use_model )); then
  jq -n --arg repo "$repo" --arg now "$now" --slurpfile friction "$work/friction.json" --rawfile rows "$work/rows.tsv" '
    {repo: $repo, now: $now,
     friction: [$friction[0][] | {number, title, created_at: .createdAt, body: ((.body // "") | .[0:1500])}],
     rule_feedback: [$rows | split("\n")[] | select(length > 0) | split("\t")
                     | {slug: .[0], kind: .[1], number: (.[2] | tonumber), reason: (.[3] // "")}]}' > "$work/input.json"
  export ANTHROPIC_BASE_URL="${ANTHROPIC_BASE_URL:-https://llm.26.cohack.tetl.ca}"
  if [[ -z "${ANTHROPIC_AUTH_TOKEN:-}" && -r "$HOME/.xenia-erik-key" ]]; then
    ANTHROPIC_AUTH_TOKEN="$(cat "$HOME/.xenia-erik-key")"; export ANTHROPIC_AUTH_TOKEN
  fi
  export ANTHROPIC_MODEL="${ANTHROPIC_MODEL:-qwen3-coder}" CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
  if ! command -v claude >/dev/null 2>&1; then
    log "claude not on PATH; falling back to the deterministic grouping"
  elif claude -p "$(cat "$prompt")" --output-format json --max-turns 2 \
         --disallowedTools "Bash,Edit,Write,MultiEdit,NotebookEdit,WebFetch,WebSearch,Task,Read,Grep,Glob" \
         < "$work/input.json" > "$work/model.json" 2> "$work/model.err"; then
    python3 - "$work/model.json" > "$work/answer.json" <<'PY' || true
import json, sys
try:
    outer = json.load(open(sys.argv[1]))
except ValueError:
    sys.exit(1)
if outer.get("is_error"):
    sys.exit(1)
text = outer.get("result") or ""
start, end = text.find("{"), text.rfind("}")
if start < 0 or end <= start:
    sys.exit(1)
try:
    ans = json.loads(text[start:end + 1])
except ValueError:
    sys.exit(1)
nf = ans.get("next_fix") if isinstance(ans.get("next_fix"), dict) else {}
if not isinstance(ans.get("recommendation"), str) or not str(nf.get("title") or "").strip():
    sys.exit(1)
json.dump(ans, sys.stdout)
PY
  fi
  if [[ -s "$work/answer.json" ]]; then
    {
      printf '## Bot reading (advisory, from the model)\n\n'
      jq -r '"Recommendation: \(.recommendation)\n",
             (if ((.rules // []) | length) > 0 then "| Rule | Reading | Why |\n|---|---|---|" else empty end),
             ((.rules // [])[] | "| \(.slug // "?") | \(.verdict // "?") | \((.sentence // "") | tostring | gsub("\\|"; "/")) |"),
             "",
             ((.clusters // [])[] | "- \(.title // "cluster") (pain \(.pain_score // "?")): \(.why // "")")' "$work/answer.json"
    } >> "$work/pinned.md"
  else
    log "the model's answer was not usable JSON; falling back to the deterministic grouping (see $work/model.err)"
  fi
fi

# 4. Write the pinned issue.
pinned="$(gh issue list --repo "$repo" --state open --limit 100 --search "\"$pinned_title\" in:title" --json number,title \
  | jq -r --arg t "$pinned_title" 'map(select(.title == $t)) | .[0].number // empty')"
if (( dry )); then
  printf -- '--- would write the pinned issue %s ---\n' "${pinned:+#$pinned}"
  cat "$work/pinned.md"
elif [[ -n "$pinned" ]]; then
  gh issue edit "$pinned" --repo "$repo" --body-file "$work/pinned.md" >/dev/null
else
  url="$(gh issue create --repo "$repo" --title "$pinned_title" --body-file "$work/pinned.md")"
  gh issue pin "$url" --repo "$repo" >/dev/null || log "could not pin $url; pin it by hand"
  pinned="${url##*/}"
fi
pinned_url="https://github.com/$repo/issues/${pinned:-new}"

# 5. The next-fix issue.
nf_url=""
if [[ -s "$work/answer.json" ]]; then
  nf_title="$(jq -r '.next_fix.title' "$work/answer.json")"
  jq -r '"Bot: proposed by the pain-review run from the friction pile and the rule-feedback pile. Teammate: assign yourself to take it (C5); close it with a comment if the team disagrees.\n\n" + ((.next_fix.body // "") | tostring)' \
    "$work/answer.json" > "$work/next-fix.md"
  existing="$(gh issue list --repo "$repo" --label next-fix --state open --limit 100 --json number,title \
    | jq -r --arg t "$nf_title" 'map(select(.title == $t)) | .[0].number // empty')"
  if [[ -n "$existing" ]]; then
    log "next-fix already open as #$existing: not opening another"
    nf_url="https://github.com/$repo/issues/$existing"
  elif (( dry )); then
    printf 'would open next-fix issue: %s\n' "$nf_title"
    cat "$work/next-fix.md"
  else
    nf_url="$(gh issue create --repo "$repo" --label next-fix --title "$nf_title" --body-file "$work/next-fix.md")"
  fi
fi

# 6. Tell the team.
if (( post )); then
  if [[ -s "$work/answer.json" ]]; then
    msg="pain-review: $(jq -r '.recommendation' "$work/answer.json")${nf_url:+ Next fix: $nf_url}"
  else
    msg="pain-review: rule-feedback pile updated; the model's reading was unavailable this run. $pinned_url"
  fi
  if (( dry )); then printf 'would post: %s\n' "$msg"
  else "$notify" "$msg" || log "posting to the team channel failed; the pinned issue is still updated"; fi
fi

log "pain-review done: pinned $pinned_url${nf_url:+, next fix $nf_url}"