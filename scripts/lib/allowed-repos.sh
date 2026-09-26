#!/usr/bin/env bash
# shellcheck shell=bash
# Idempotent edits of the kit's two allow-lists. Source it; don't execute it.

# allowed_repos_add <json-file> <owner/repo> <workflow-file>: the repo gets deploy and preview roles
# and an ECR repository at the next platform apply; the workflow file is trusted from main.
allowed_repos_add() {
  python3 - "$1" "$2" "$3" <<'PY'
import json
import sys

path, repo, workflow = sys.argv[1:4]
with open(path, encoding="utf-8") as fh:
    data = json.load(fh)
workflows = data.setdefault("allowed_repos", {}).setdefault(repo, [])
if workflow not in workflows:
    workflows.append(workflow)
with open(path, "w", encoding="utf-8") as fh:
    fh.write(json.dumps(data, indent=2) + "\n")
PY
}

# plugin_allow <owner/repo> [file]: the SessionStart hook reads that repo's own PRINCIPLES.md.
plugin_allow() {
  local f="${2:-$KIT_ROOT/plugin/allowed-repos.txt}"
  grep -qxF -- "$1" "$f" 2>/dev/null || printf '%s\n' "$1" >> "$f"
}

# oidc_sub_prefix_set <json-file> <owner/repo> <prefix>: record the repo's immutable OIDC subject prefix,
# repo:OWNER@OWNER_ID/REPO@REPO_ID, from gh api repos/OWNER/REPO/actions/oidc/customization/sub
# (.sub_claim_prefix). Every role's trust policy is built from it (infra/platform/oidc.tf). Idempotent.
oidc_sub_prefix_set() {
  local path="$1" repo="$2" prefix="$3"
  if [[ ! "$prefix" =~ ^repo:([^@/]+)@[0-9]+/([^@/]+)@[0-9]+$ ]]; then
    printf 'error: %s is not an immutable OIDC subject prefix (repo:OWNER@ID/REPO@ID)\n' "$prefix" >&2
    return 1
  fi
  if [[ "${BASH_REMATCH[1]}" != "${repo%%/*}" || "${BASH_REMATCH[2]}" != "${repo#*/}" ]]; then
    printf 'error: %s does not name %s\n' "$prefix" "$repo" >&2
    return 1
  fi
  python3 - "$path" "$repo" "$prefix" <<'PY'
import json
import sys

path, repo, prefix = sys.argv[1:4]
with open(path, encoding="utf-8") as fh:
    data = json.load(fh)
data.setdefault("oidc_sub_prefixes", {})[repo] = prefix
with open(path, "w", encoding="utf-8") as fh:
    fh.write(json.dumps(data, indent=2) + "\n")
PY
}
