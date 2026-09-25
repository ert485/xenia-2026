# Evals template

Reader: for kit maintainers. Cut tier: documented, not built.

## What it was

A `templates/evals/` starter and an `evals.yml` workflow for teams shipping an LLM feature: a small set of
input cases with expected properties, scored against the gateway on every PR that touches a prompt, with the
scores posted as an advisory comment.

## Why it was cut

Nothing in the kit assumes what the team builds, and most hackathon products never touch a prompt more than
twice. Two build days went to the model path and the deploy path (D21). The principle is kept, the machinery is
not: the extended principles say that if the team ships an LLM feature and touches its prompt more than twice,
the eval comes first (P-evals).

## What exists instead

P-evals in `PRINCIPLES-EXTENDED.md`, and `make check`, which runs whatever tests the team adds, including an
eval written as an ordinary test against the gateway with the CI key.

## How to revive

- Create `templates/evals/README.md` and `templates/evals/cases.yaml` (input, expected property, for example
  "mentions the item name" or "valid JSON with field X").
- Create `templates/evals/run.py` (or `run.ts`) that calls `https://llm.26.cohack.tetl.ca/v1/chat/completions`
  with model `qwen3-coder` and the `GATEWAY_CI_KEY` secret, checks each case, and prints a pass-rate table.
- Create `templates/workflows/evals.yml` mirroring the review job of `pr-review.yml`: `pull_request` on paths
  `prompts/**`, fork guard, `permissions: {}` plus `contents: read`, a separate job with
  `pull-requests: write` that upserts one comment. Advisory, never blocking (P-two-gates).
- Budget: the CI key's LiteLLM `max_budget` already bounds the spend.

Effort: 3 to 4 hours.