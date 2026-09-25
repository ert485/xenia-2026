# Inventory cron

Reader: for kit maintainers. Cut tier: documented, not built.

## What it was

An `inventory.yml` workflow on a schedule that listed every running billable resource in the member account
and posted the list to the team channel, so forgotten resources surfaced without anyone asking.

## Why it was cut

`scripts/status.sh` answers "what is running" in under a minute whenever someone asks, and the Resource
Explorer view finds resources with no tags at all, which is the real click-ops signal (spec §8). A scheduled
workflow would also need AWS credentials in public CI on a schedule, which means a new OIDC role trusted from
scheduled runs: more surface for a signal the kit already has.

## What exists instead

`scripts/status.sh` (Task 15): instances with type and uptime, gateway health and active backend, open
previews, last backup, alarm state; plus `scripts/untagged.sh` (Task 28), which lists untagged resources and
appears in `status.sh` once the Resource Explorer index exists. `SHUTDOWN.md` lists everything the kill switch
covers.

## How to revive

- In `infra/platform/oidc.tf`: a read-only role `xenia-inventory-<owner>-<repo>` with `ReadOnlyAccess` plus
  the guard-rail deny, trusted only from `job_workflow_ref` `inventory.yml` on `refs/heads/main` (the same
  pinning as the deploy role).
- Create `templates/workflows/inventory.yml`: `schedule` every 6 hours (cron in UTC, CST in a comment),
  `workflow_dispatch`, `id-token: write` in its one job, running `scripts/status.sh --json` and
  `scripts/untagged.sh`, then posting a summary with `plugin/scripts/notify.sh`.
- `status.sh --json` must not print anything the leak check would flag; route it through `mask`.

Effort: 3 hours, mostly the role and a check that the output is safe to post.