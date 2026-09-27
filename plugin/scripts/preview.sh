#!/usr/bin/env bash
# /preview: this branch's PR, its preview URL and HTTP status, and the latest preview-up run.
set -euo pipefail
domain="${PREVIEW_DOMAIN:-box.26.cohack.tetl.ca}"
if ! pr="$(gh pr view --json number,headRefName,url 2>&1)"; then
  case "$pr" in
    *"no pull requests found"*)
      echo "preview: this branch has no open PR; push it and open one, and the preview appears a few minutes later" >&2 ;;
    *)
      echo "preview: gh failed: $pr" >&2 ;;
  esac
  exit 1
fi
n="$(jq -r .number <<< "$pr")"
ref="$(jq -r .headRefName <<< "$pr")"
host="https://pr-$n.$domain"
# ok-to-hide: HTTP status probe; a network failure falls back to "000", printed as-is below.
code="$(curl -s -o /dev/null -w '%{http_code}' -m 10 "$host/" || echo 000)"
echo "PR:      $(jq -r .url <<< "$pr")"
echo "preview: $host (HTTP $code)"
run="$(gh run list --workflow preview-up.yml --branch "$ref" -L 1 --json status,conclusion,url \
  --jq '.[0] | "\(.status) \(.conclusion // "") \(.url)"' 2>/dev/null || true)" # ok-to-hide: optional lookup; "none found" is the default below
echo "last preview-up run: ${run:-none found}"
