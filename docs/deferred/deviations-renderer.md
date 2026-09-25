# Deviations renderer

Reader: for kit maintainers. Cut tier: documented, not built.

## What it was

A workflow that collected every `Rule-feedback:` line from merged PRs and rendered them into a committed
`DEVIATIONS.md`, grouped by rule, so the team could read every recorded exception in one file.

## Why it was cut

A workflow can't commit to a protected `main` with the default token: the team repo's ruleset requires PRs and
code-owner review with an empty bypass list, so a bot push is refused (spec §3). Working around that means a
GitHub App with a bypass, which undoes the ruleset's point.

## What exists instead

The same data in three places that need no commits to `main`: the `Rule-feedback:` line in each PR body, the
`rule-feedback` issue label, and the pinned "Rule feedback" issue that `scripts/pain-review.sh` rewrites grouped
by rule with counts (Task 24). The kit site links a saved GitHub search to the same lines.

## How to revive

Prefer the pattern the kit already uses for `SHUTDOWN.md` (deviation 2 in the plan): a committed file rendered
by a `make` target and checked at PR time.

- Add `scripts/render-deviations.sh` that builds the grouped Markdown from `gh pr list --state merged` bodies
  through `scripts/ci/rule-feedback.sh` (the same grouping code `pain-review.sh` uses, factored into a shared
  function).
- Add `make deviations` and a `render-deviations.yml` PR check that fails with "run make deviations and
  commit" when the file is stale. Teammates update it in their own PRs; no bot writes to `main`.

Effort: 2 hours, since the parser and the grouping already exist.