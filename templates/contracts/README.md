# Contracts template (Should tier)

**Kit status: Should tier. Shipped as a template; not proven end to end unless
`docs/proofs/2026-09-25-contract-check.md` exists in the kit repo.** How to prove it is at the bottom.

Teammate: this folder becomes `contracts/` in the team repo when the product has an API (charter C13,
principle P-contracts). A server-rendered monolith with no API between services skips it, and skips the
workflow too.

## What you get

| File | Purpose |
|---|---|
| `openapi.yaml` | OpenAPI 3.1 starter: `GET /health` and `GET /items/{id}` with a response schema |
| `redocly.yaml` | Redocly lint config: the `recommended` ruleset |
| `events/` | JSON Schemas for events, one file per event |
| `../workflows/contract-check.yml` | the CI check (copy it to `.github/workflows/`) |

`make types` (already in the team repo's `Makefile`) regenerates `src/contracts/openapi.d.ts` in a
TypeScript repo (openapi-typescript 7.13.0) or `src/contracts/models.py` in a Python repo
(datamodel-code-generator 0.83.0; install it once with `pipx install datamodel-code-generator==0.83.0`).
Commit the generated files: consumers then break at compile time when the contract changes.

## Adopt it (about five minutes)

From the team repo root:

    git clone --depth 1 https://github.com/ert485/xenia-2026 /tmp/xenia-kit
    cp -R /tmp/xenia-kit/templates/contracts contracts
    cp /tmp/xenia-kit/templates/workflows/contract-check.yml .github/workflows/contract-check.yml
    make types
    git add contracts src/contracts .github/workflows/contract-check.yml

Open a PR. `.github/workflows/` isn't code-owned (only `PRINCIPLES.md`, `PRINCIPLES-EXTENDED.md`, and `CODEOWNERS` are), so it self-merges once `make check` and shutdown coverage pass.

## What the check does on every PR

The job named `contract-check` runs on every pull request and does nothing unless the PR touches
`contracts/` or `src/contracts/`. When it does:

1. `redocly lint` over `contracts/openapi.yaml` (errors fail; warnings print).
2. `make types`, then fails if `src/contracts/` changed: the generated types are stale, run `make types`
   and commit.
3. `oasdiff breaking` between the base branch's `contracts/openapi.yaml` and the PR's, failing on
   error-level changes (a removed path, a removed required response field, a new required request
   field). A PR labelled `breaking-ok` skips this step: use it when every consumer changes in the same PR.

This is the one blocking check beyond `make check` and shutdown coverage that a team can opt into, because
agent-written mismatches between services are exactly what it catches (spec §12).

## Make it a required check

Once the team adopts contracts, add `contract-check` to the `main` ruleset's required checks. The
rulesets API replaces a ruleset with `PUT`, so read it, add the context, and write it back:

    repo=<owner>/<repo>
    id="$(gh api "repos/$repo/rulesets" --jq '.[] | select(.name == "main") | .id')"
    gh api "repos/$repo/rulesets/$id" \
      | jq '{name, target, enforcement, bypass_actors, conditions, rules}
            | (.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks)
              += [{"context": "contract-check"}]' \
      | gh api -X PUT "repos/$repo/rulesets/$id" --input -

The workflow runs on every PR (it has no `paths:` filter), so a required `contract-check` never sits
pending on a PR that doesn't touch contracts.

## Prove it (kit maintainers)

In a throwaway public repo: commit this folder, the workflow, the team `Makefile`, a `package.json`, and
the generated types to `main`; open a PR that removes `name` from `Item` and runs `make types`;
`contract-check` fails on `oasdiff`; add the `breaking-ok` label and it passes. Record both run URLs in
`docs/proofs/2026-09-25-contract-check.md`. Task 23 of the kit plan has the exact commands.
