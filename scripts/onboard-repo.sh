#!/usr/bin/env bash
# Usage: scripts/onboard-repo.sh <owner/repo> --owners @a[,@b[,@c]] [--deploy-workflow deploy-docker-box.yml] [--private]
# Turns an existing, empty-or-not GitHub repo into a kit team repo in one run (spec section 7).
# Every step is idempotent and printed; re-running after a failure picks up where it stopped.
# Create the repo first: gh repo create <owner/repo> --public
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
source "$KIT_ROOT/scripts/lib/allowed-repos.sh"
load_env
require_cmd gh git jq python3 terraform aws make

repo="${1:?usage: onboard-repo.sh <owner/repo> --owners @a[,@b[,@c]] [--deploy-workflow <file>] [--private]}"
shift
owners_csv=""
deploy_wf="deploy-docker-box.yml"
private=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --owners) owners_csv="${2:?--owners needs @a,@b}"; shift 2 ;;
    --deploy-workflow) deploy_wf="${2:?--deploy-workflow needs a file name}"; shift 2 ;;
    --private) private=1; shift ;;
    *) die "unknown argument: $1" ;;
  esac
done
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "not an owner/repo: $repo"
[[ "$deploy_wf" =~ ^[A-Za-z0-9_.-]+\.ya?ml$ ]] || die "not a workflow file name: $deploy_wf"
[[ -n "$owners_csv" ]] || die "--owners is required (the two or three PRINCIPLES.md owners named at idea lock)"
IFS=, read -r -a owner_list <<< "$owners_csv"
[[ ${#owner_list[@]} -ge 1 && ${#owner_list[@]} -le 3 ]] || die "name one to three owners"
for o in "${owner_list[@]}"; do [[ "$o" =~ ^@[A-Za-z0-9-]+$ ]] || die "owners look like @handle: $o"; done
[[ ${#owner_list[@]} -ge 2 ]] || log "warning: one owner means an owner-authored rule change needs a second owner who doesn't exist yet; name another at idea lock"
owners_space="$(printf '%s' "$owners_csv" | tr ',' ' ')"
owner="${repo%%/*}"
name="${repo#*/}"

# Before any AWS or GitHub change: the platform module names each repo's IAM roles
# xenia-deploy-<owner>-<repo> and xenia-preview-<owner>-<repo> (infra/platform/oidc.tf,
# local.repo_slug replaces "/" with "-"). Refuse a repo whose role names would exceed IAM's
# 64-character limit, and a repo whose owner-repo slug collides with an already allowed repo's
# (for example a-b/c against a/b-c: both slug to a-b-c), which would make two roles fight over
# one name at the next platform apply (Task 4's review).
repo_slug="$(printf '%s' "$repo" | tr '/' '-')"
for role_prefix in xenia-deploy xenia-preview; do
  role_name="$role_prefix-$repo_slug"
  [[ ${#role_name} -le 64 ]] || die "IAM role name too long ($role_name, ${#role_name} chars, max 64): shorten $repo or its owner"
done
allowed_repos_file="$KIT_ROOT/infra/platform/allowed-repos.auto.tfvars.json"
if [[ -f "$allowed_repos_file" ]]; then
  while IFS= read -r existing_repo; do
    [[ "$existing_repo" != "$repo" ]] || continue
    existing_slug="$(printf '%s' "$existing_repo" | tr '/' '-')"
    [[ "$existing_slug" != "$repo_slug" ]] || die "IAM role name collision: $repo and $existing_repo both slug to $repo_slug; onboard one with a different owner or name"
  done < <(jq -r '.allowed_repos // {} | keys[]' "$allowed_repos_file")
fi

rule_feedback_body() {
  cat <<EOF
Teammate: this issue is where rule feedback gathers, grouped by rule. Rule feedback is about rules, never about the teammate who made a change (P-ours): the pile only decides whether we keep a rule, change it by PR, or bring the code back in line.

An entry gets here from a \`Rule-feedback: P-<slug>, <reason>\` line in a PR body (or \`/rule-feedback\` in Claude Code), or from an issue with the \`rule-feedback\` label.

Bot: the pain-review run rewrites the sections below with counts. Until it runs, these saved searches are the source:
- PRs: https://github.com/$repo/pulls?q=is%3Apr+%22Rule-feedback%3A+P-%22
- Issues: https://github.com/$repo/issues?q=label%3Arule-feedback

We look at the pile for five minutes at 18:00 and at the retro. Three sightings of one rule mean the rule gets reviewed as a whole at the next checkpoint.

## P-ours
_none yet_

## P-fix-once
_none yet_

## P-two-gates
_none yet_

## P-off-switch
_none yet_

## P-wheel
_none yet_

## P-public
_none yet_
EOF
}

step() { printf '\n== step %s: %s\n' "$1" "$2"; }
ruleset_exists() { gh api "repos/$repo/rulesets" --jq '.[] | select(.name == "main") | .id' 2>/dev/null | grep -q .; }

step 1 "the repo exists; its OIDC subject claim names the workflow file"
gh repo view "$repo" --json name >/dev/null 2>&1 || die "no such repo: $repo (create it first: gh repo create $repo --public)"
gh api -X PUT "repos/$repo/actions/oidc/customization/sub" --input - >/dev/null \
  <<< '{"use_default":false,"include_claim_keys":["repo","context","job_workflow_ref"]}'
sub_prefix="$(gh api "repos/$repo/actions/oidc/customization/sub" --jq '.sub_claim_prefix // empty')"
[[ -n "$sub_prefix" ]] || die "GitHub returned no sub_claim_prefix for $repo; the platform roles can't trust it without one"
log "OIDC subject prefix: $sub_prefix"

step 2 "kit allow-lists, then the platform apply (deploy and preview roles, ECR repository)"
allowed_repos_add "$KIT_ROOT/infra/platform/allowed-repos.auto.tfvars.json" "$repo" "$deploy_wf"
plugin_allow "$repo"
oidc_sub_prefix_set "$KIT_ROOT/infra/platform/oidc-sub-prefixes.auto.tfvars.json" "$repo" "$sub_prefix"
make -C "$KIT_ROOT" -s sync-plugin
"$KIT_ROOT/scripts/tf.sh" platform apply
git -C "$KIT_ROOT" add infra/platform/allowed-repos.auto.tfvars.json infra/platform/oidc-sub-prefixes.auto.tfvars.json plugin/allowed-repos.txt plugin/bundled/PRINCIPLES.md
if git -C "$KIT_ROOT" diff --cached --quiet; then
  log "the kit's allow-lists already list $repo"
else
  git -C "$KIT_ROOT" commit -q -m "Allow $repo: deploy and preview roles, ECR repository, principles injection"
  log "committed the allow-list change on the kit's current branch: push it and merge it today"
fi

step 3 "copy the kit into the team repo"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
dest="$work/repo"
gh repo clone "$repo" "$dest" -- -q 2>/dev/null
cd "$dest"
if git rev-parse -q --verify HEAD >/dev/null; then
  default="$(gh repo view "$repo" --json defaultBranchRef --jq .defaultBranchRef.name)"
  git checkout -q "$default"
else
  default=main
  git symbolic-ref HEAD refs/heads/main
fi
mkdir -p .github/workflows .github/ISSUE_TEMPLATE .devcontainer shutdown.d
for wf in check shutdown-coverage render-shutdown-md pr-review deploy-docker-box preview-up preview-down devcontainer-image; do
  if [[ -f "$KIT_ROOT/templates/workflows/$wf.yml" ]]; then cp "$KIT_ROOT/templates/workflows/$wf.yml" .github/workflows/
  else log "warning: templates/workflows/$wf.yml is missing from the kit; skipped (re-run once it exists)"; fi
done
cp "$KIT_ROOT/templates/team-repo/PULL_REQUEST_TEMPLATE.md" .github/
cp "$KIT_ROOT/templates/team-repo/ISSUE_TEMPLATE/"*.yml .github/ISSUE_TEMPLATE/
for f in CODEOWNERS Makefile CLAUDE.md AGENTS.md CONTRIBUTING.md .gitleaks.toml compose.example.yml; do
  cp "$KIT_ROOT/templates/team-repo/$f" "./$f"
done
sed -i.bak "s|@OWNER1 @OWNER2|$owners_space|g" CODEOWNERS && rm -f CODEOWNERS.bak
cp "$KIT_ROOT/team-kit/PRINCIPLES.md" "$KIT_ROOT/team-kit/PRINCIPLES-EXTENDED.md" .
for f in "$KIT_ROOT"/templates/devcontainer/*; do
  case "$(basename "$f")" in upstream-*) ;; *) cp "$f" .devcontainer/ ;; esac
done
cp "$KIT_ROOT/templates/opencode/opencode.json" .devcontainer/opencode.json
image="ghcr.io/$(printf '%s' "$repo" | tr '[:upper:]' '[:lower:]')-devcontainer:main"
sed -i.bak "s|ghcr.io/ert485/xenia-2026-devcontainer:main|$image|" .devcontainer/devcontainer.json && rm -f .devcontainer/devcontainer.json.bak
rm -rf plugin && cp -R "$KIT_ROOT/plugin" plugin
if [[ -d "$KIT_ROOT/templates/team-repo/.claude/skills" ]]; then
  mkdir -p .claude && cp -R "$KIT_ROOT/templates/team-repo/.claude/skills" .claude/
fi
if [[ -f "$KIT_ROOT/templates/team-repo/README.md" && ! -f README.md ]]; then
  cp "$KIT_ROOT/templates/team-repo/README.md" README.md
fi
cp "$KIT_ROOT/shutdown.d/README.md" shutdown.d/README.md
touch shutdown.d/.gitkeep
"$KIT_ROOT/scripts/render-shutdown-md.sh" shutdown.d > SHUTDOWN.md
for line in '*.local.env' '.venv/' 'node_modules/' '.kit/' '.agent/' '.agent-requests/'; do
  grep -qxF -- "$line" .gitignore 2>/dev/null || printf '%s\n' "$line" >> .gitignore
done
git add -A
if git diff --cached --quiet; then
  log "the team repo already has the current kit files"
else
  git commit -q -m "Add the Co.Hack 2026 kit"
  if ruleset_exists; then
    branch="kit-sync-$(date -u +%Y%m%d%H%M)"
    git push -q origin "HEAD:refs/heads/$branch"
    log "main is protected now: pushed $branch; open a PR from it in $repo"
  else
    git push -q origin "HEAD:$default"
    log "pushed the kit to $default (before the ruleset exists)"
  fi
fi
cd "$KIT_ROOT"

step 4 "labels"
jq -c '.[]' "$KIT_ROOT/templates/team-repo/labels.json" | while read -r l; do
  color="$(jq -r .color <<< "$l")"
  gh label create "$(jq -r .name <<< "$l")" --color "${color#\#}" --description "$(jq -r .description <<< "$l")" --force --repo "$repo" >/dev/null
done
log "labels: $(jq -r '[.[].name] | join(", ")' "$KIT_ROOT/templates/team-repo/labels.json")"

step 5 "the pinned Rule feedback issue"
existing="$(gh issue list --repo "$repo" --state open --search 'in:title "Rule feedback"' --json number,title \
  --jq '.[] | select(.title == "Rule feedback") | .number' | head -1)"
if [[ -n "$existing" ]]; then
  log "Rule feedback issue already open (#$existing)"
else
  body="$(rule_feedback_body)"
  url="$(gh issue create --repo "$repo" --title "Rule feedback" --body "$body")"
  gh issue pin "$url" >/dev/null
  log "created and pinned $url"
fi

step 6 "the main ruleset (zero approvals, code-owner review, required checks, empty bypass list)"
if ruleset_exists; then
  log "ruleset main already exists"
else
  gh api -X POST "repos/$repo/rulesets" --input "$KIT_ROOT/templates/team-repo/ruleset.json" >/dev/null
  log "ruleset main created"
fi

step 7 "repo settings: secret scanning, push protection, fork approval, interaction limits, read-only token"
gh api -X PATCH "repos/$repo" --input - >/dev/null \
  <<< '{"security_and_analysis":{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"}}}' \
  || log "warning: secret scanning could not be enabled (a private repo on a free plan doesn't get it); gitleaks in check.yml still runs"
gh api -X PUT "repos/$repo/actions/permissions/fork-pr-contributor-approval" --input - >/dev/null \
  <<< '{"approval_policy":"all_external_contributors"}'
gh api -X PUT "repos/$repo/interaction-limits" --input - >/dev/null \
  <<< '{"limit":"collaborators_only","expiry":"one_week"}'
gh api -X PUT "repos/$repo/actions/permissions/workflow" --input - >/dev/null \
  <<< '{"default_workflow_permissions":"read","can_approve_pull_request_reviews":false}'

step 8 "secrets and variables"
tfout() { TF_NO_MASK=1 "$KIT_ROOT/scripts/tf.sh" platform output -json "$1" | jq -r --arg r "$repo" '.[$r] // empty'; }
v="$(tfout deploy_role_arns)"; [[ -n "$v" ]] || die "no deploy role for $repo in the platform outputs (did step 2's apply finish?)"
printf '%s' "$v" | gh secret set AWS_DEPLOY_ROLE_ARN --repo "$repo"
v="$(tfout preview_role_arns)"; printf '%s' "$v" | gh secret set AWS_PREVIEW_ROLE_ARN --repo "$repo"
v="$(tfout ecr_repository_urls)"; printf '%s' "${v%%/*}" | gh secret set ECR_REGISTRY --repo "$repo"
unset v
if gh secret list --repo "$repo" --json name --jq '.[].name' | grep -qx GATEWAY_CI_KEY; then
  log "GATEWAY_CI_KEY already set (rotate with scripts/rotate-key.sh ci)"
else
  key="$("$KIT_ROOT/scripts/gateway-key.sh" generate "ci-$name" 10 ci)"
  printf '%s' "$key" | gh secret set GATEWAY_CI_KEY --repo "$repo"
  unset key
fi
if [[ -n "${DISCORD_WEBHOOK_URL:-}" ]]; then
  printf '%s' "$DISCORD_WEBHOOK_URL" | gh secret set DISCORD_WEBHOOK_URL --repo "$repo"
else
  log "DISCORD_WEBHOOK_URL is not in kit.local.env yet: add it there and re-run, or gh secret set DISCORD_WEBHOOK_URL --repo $repo"
fi
gh variable set AWS_REGION --body ca-central-1 --repo "$repo"
gh variable set APP_HOST --body app.26.cohack.tetl.ca --repo "$repo"
gh variable set PREVIEW_DOMAIN --body box.26.cohack.tetl.ca --repo "$repo"
gh variable set APP_PORT --body 3000 --repo "$repo"
gh variable set APP_DIR --body . --repo "$repo"

step 9 "owners get write access"
for o in "${owner_list[@]}"; do
  h="${o#@}"
  if [[ "$h" == "$owner" ]]; then log "$h owns the repo"; continue; fi
  gh api -X PUT "repos/$repo/collaborators/$h" -f permission=push >/dev/null
  log "invited $h with write access (they accept the invitation from GitHub's email or notifications)"
done

step 10 "follow-ups for Erik"
cat <<EOF
1. Push and merge the kit commit from step 2 today (git -C $KIT_ROOT log -1 --oneline).
2. Codespaces prebuild (UI only): https://github.com/$repo/settings/codespaces, add a prebuild for $default and .devcontainer/devcontainer.json, region US West or US East.
3. Watch the first devcontainer-image run: gh run list --repo $repo --workflow devcontainer-image.yml -L 1
4. Give every other teammate write access: gh api -X PUT repos/$repo/collaborators/<handle> -f permission=push
5. Tell the team: https://github.com/$repo and the kit site https://26.cohack.tetl.ca
EOF
if [[ "$private" == 1 ]]; then
  cat <<'EOF'
6. Private repo: Actions minutes are billed past the free 2,000 a month and arm64 runners are not free.
   Switch runs-on in .github/workflows/deploy-docker-box.yml to ubuntu-24.04 with docker/setup-qemu-action,
   or register the Docker box as a self-hosted runner (documented, not automated). Secret scanning may be off.
EOF
fi
