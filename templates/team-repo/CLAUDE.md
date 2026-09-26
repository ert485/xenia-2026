Agent: the team's rules are PRINCIPLES.md (core) and PRINCIPLES-EXTENDED.md (why and practices) in this repo's root; read the core before acting.
Agent: record every workaround you discover under "Workarounds" below so no agent rediscovers it (P-fix-once/claude-md).

## Repo facts

Teammate: fill these in at the 11:30 architecture checkpoint and keep them current; agents read this table first.

| Fact | Value |
|---|---|
| Stack | (TypeScript or Python, decided at idea lock) |
| Services | (one folder per service, C1) |
| Run the checks | `make check` (the same command CI runs) |
| Regenerate contract types | `make types` (only when `contracts/` exists) |
| Run locally | `make dev` |
| This branch's preview | `make preview-url`, pattern `https://pr-<n>.box.26.cohack.tetl.ca` |
| Demo URL | `https://app.26.cohack.tetl.ca` |
| Product API keys | SSM under `/xenia/app/<NAME>`, read at deploy time (C10) |

## How to run checks locally

1. `make check` before every push. It is one of the two blocking gates, so if it passes locally it passes in CI.
2. After changing `contracts/openapi.yaml`, run `make types` and commit the generated files in the same PR.
3. After changing a compose file or anything under `infra/`, either add an entry under `shutdown.d/` or put
   `Shutdown: none needed because <reason>` in the PR description.

## What agents must never do

- Agent: never paste environment values, tokens, keys, transcripts, or logs containing emails or IP addresses
  into an issue, a PR, a commit, or the team channel (P-public/agents).
- Agent: never create, edit, or commit `.devcontainer/ai.local.env` or any other `*.local.env` file.
- Agent: never run with AWS credentials. Ship by pushing a branch; CI deploys (C11). If a task seems to need
  AWS access, stop and ask the teammate.
- Agent: never edit `PRINCIPLES.md`, `PRINCIPLES-EXTENDED.md`, or `CODEOWNERS` unless the teammate asked
  for exactly that change; those are the only paths that need a different owner's approval (Erik's
  decision, 2026-09-24). `.github/workflows/` and `.devcontainer/` self-merge behind `make check` and
  shutdown coverage, but still get flagged by the reviewer as a CI/secrets-handling change worth a look.
- Agent: never post to the team channel or open an issue for `/pain` or `/rule-feedback` before the teammate
  confirms the wording.
- Agent: after fifteen minutes of looping with no progress, stop and hand back to the teammate (P-wheel).

## Workarounds

Agent: add one row per workaround, newest first, in this format. Keep each row to one line; link a PR for the
detail.

| Date | Symptom | Workaround | Link |
|---|---|---|---|