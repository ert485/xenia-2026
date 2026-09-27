# Schemathesis conformance

Reader: for kit maintainers. Cut tier: documented, not built.

## What it was

A `conformance.yml` workflow that runs Schemathesis (property-based tests generated from
`contracts/openapi.yaml`) against each PR's preview URL, so the running API is checked against its own spec,
not just the spec against itself.

## Why it was cut

Decision D17 ships contract lint, generated types, and breaking-change detection, and documents Schemathesis
only. It needs a running, stable preview and an API that already behaves; on a 24-hour build it mostly reports
unfinished endpoints. And the natural trigger, "after the preview is up", would be a `workflow_run` workflow,
which the CI hardening rules forbid (D35).

## What exists instead

`contract-check.yml` (Task 23): Redocly lint, stale-type detection, and `oasdiff` breaking-change detection;
generated types make consumers fail at compile time; the deploy smoke test and the preview health check prove
the app is up.

## How to revive

- Add a final job to `templates/workflows/preview-up.yml` (not a separate `workflow_run` workflow), gated on
  `hashFiles('contracts/openapi.yaml') != ''`, that runs
  `uvx schemathesis run contracts/openapi.yaml --url "https://pr-<n>.box.26.cohack.tetl.ca" --checks all --max-examples 25`
  with a pinned Schemathesis version, and uploads the report.
- Keep it advisory (`continue-on-error: true`) and post a one-line summary into the existing preview comment.
- Document in `templates/contracts/README.md` how to exclude unfinished operations.

Effort: 2 to 3 hours.
