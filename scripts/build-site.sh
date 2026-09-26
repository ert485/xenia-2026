#!/usr/bin/env bash
# Usage: scripts/build-site.sh
# Builds the kit site into site/dist: team-kit/ (00-tldr.md becomes the home page), the print images,
# runbook/, docs/deferred/, and the Option A page, with a nav generated from the pages' headings.
# The build is --strict, and the rendered output must pass the leak check (P-public/site), so a
# planted account ID, portal URL, zone ID, phone, or unlisted email never reaches the public site.
# MKDOCS overrides the mkdocs binary; otherwise .venv/bin/mkdocs, then mkdocs on PATH (CI).
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
cd "$KIT_ROOT"

build=site/build
docs="$build/docs"
rm -rf site/build site/dist
mkdir -p "$docs/team-kit/print" "$docs/runbook" "$docs/deferred"

for f in team-kit/*.md; do
  [[ -e "$f" ]] || continue
  if [[ "$(basename "$f")" == "00-tldr.md" ]]; then cp "$f" "$docs/index.md"; else cp "$f" "$docs/team-kit/"; fi
done
for f in team-kit/print/*.png team-kit/print/*.svg runbook/*.md docs/deferred/*.md; do
  [[ -e "$f" ]] || continue
  case "$f" in
    team-kit/print/*) cp "$f" "$docs/team-kit/print/" ;;
    runbook/*) cp "$f" "$docs/runbook/" ;;
    docs/deferred/*) cp "$f" "$docs/deferred/" ;;
  esac
done
if [[ -f docs/option-a-claude-platform-on-aws.md ]]; then cp docs/option-a-claude-platform-on-aws.md "$docs/option-a.md"; fi
[[ -f "$docs/index.md" ]] || die "team-kit/00-tldr.md is missing (Task 20 writes it); the site has no home page without it"

# nav_item <file-under-docs> <indent>: - "Heading": path
nav_item() {
  local t
  t="$(sed -n 's/^# //p' "$docs/$1" | head -1)"
  t="${t:-$(basename "$1" .md)}"
  t="$(printf '%s' "$t" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  printf '%s- "%s": %s\n' "$2" "$t" "$1"
}
# section <title> <file-under-docs>...: a nav section with the files that exist
section() {
  local title="$1" f any=0
  shift
  for f in "$@"; do [[ -f "$docs/$f" ]] && any=1; done
  [[ "$any" == 1 ]] || return 0
  printf '  - "%s":\n' "$title"
  for f in "$@"; do if [[ -f "$docs/$f" ]]; then nav_item "$f" "      "; fi; done
}
# list <glob>...: files under docs/ matching the globs (expanded inside docs/, not the repo root)
list() {
  (cd "$docs" && for pat in "$@"; do for f in $pat; do if [[ -f "$f" ]]; then printf '%s\n' "$f"; fi; done; done) | LC_ALL=C sort
}

{
  echo "INHERIT: ../mkdocs.yml"
  echo "docs_dir: docs"
  echo "site_dir: ../dist"
  echo "nav:"
  echo "  - Home: index.md"
  # shellcheck disable=SC2046 # file names are ours and contain no spaces
  section "Team kit" $(list 'team-kit/[0-9][0-9]-*.md')
  section "Principles" team-kit/PRINCIPLES.md team-kit/PRINCIPLES-EXTENDED.md
  # shellcheck disable=SC2046
  section "Runbook" $(list 'runbook/*.md')
  deferred="$(list 'deferred/*.md' | grep -v '^deferred/README.md$' || true)"
  # shellcheck disable=SC2086
  section "Deferred (the cut tier)" deferred/README.md $deferred
  if [[ -f "$docs/option-a.md" ]]; then nav_item option-a.md "  "; fi
} > "$build/mkdocs.yml"

mkdocs="${MKDOCS:-}"
if [[ -z "$mkdocs" ]]; then
  if [[ -x .venv/bin/mkdocs ]]; then mkdocs=.venv/bin/mkdocs; else mkdocs=mkdocs; fi
fi
"$mkdocs" build -f "$build/mkdocs.yml" --strict
scripts/ci/leak-check.sh --allow-emails site/allowed-emails.txt site/dist
log "site built in site/dist and leak-checked"
