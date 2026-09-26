#!/usr/bin/env bash
# /preview: this branch's PR, its preview URL and HTTP status, and the latest preview-up run.
set -euo pipefail
domain="${PREVIEW_DOMAIN:-box.26.cohack.tetl.ca}"
pr="$(gh pr view --json number,headRefName,url 2>/dev/null)" \
  || { echo "preview: this branch has no open PR; push it and open one, and the preview appears a few minutes later" >&2; exit 1; }
n="$(jq -r .number <<< "$pr")"
ref="$(jq -r .headRefName <<< "$pr")"
host="https://pr-$n.$domain"
code="$(curl -s -o /dev/null -w '%{http_code}' -m 10 "$host/" || echo 000)"
echo "PR:      $(jq -r .url <<< "$pr")"
echo "preview: $host (HTTP $code)"
run="$(gh run list --workflow preview-up.yml --branch "$ref" -L 1 --json status,conclusion,url \
  --jq '.[0] | "\(.status) \(.conclusion // "") \(.url)"' 2>/dev/null || true)"
echo "last preview-up run: ${run:-none found}"
