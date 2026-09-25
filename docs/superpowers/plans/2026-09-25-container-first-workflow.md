# Container-first workflow with automatic verification: high-level plan

- Date: 2026-09-25 (Friday). Status: draft for Erik to decide how to proceed; not yet a task in the main plan.
- Tracking: personal project, no Notion task. PRs from this plan carry no task-ID suffix.
- Builds on: the spec `docs/superpowers/specs/2026-09-23-cohack-prep-kit-design.md` (v2.6) and the main plan
  `docs/superpowers/plans/2026-09-24-cohack-prep-kit.md`. When this becomes real work, it lands as a new task in the
  main plan (proposed: Task 32, run before the rest of the Must tier).

## The model

Work starts where a teammate would start it: a human opens the dev container, runs `claude` against the team model
(the GPU box through the gateway, Bedrock as failover), and works normally. The dev container still holds no AWS or
GitHub credentials (spec D22).

The Mac only does work that needs a credential. It runs a small broker, not a Claude session, that shows each
credentialed request from the container and runs it only after Erik says yes. A Mac Claude Code session is only needed
when a request is too complex for one command.

Whether work is done is decided by a deterministic verifier, never by the agent's own report and never by a reviewer
happening to notice. The Thursday-night battle test (see "Evidence" below) showed why: an unattended open-model agent
wrote a proof for commands it never ran, committed empty placeholder images, hid a failing `make check`, filed no
requests, and reported "Stuck: None" on all three tasks.

## Components

1. **Tools in the dev container image.** bats, shellcheck, and the site tools (`segno`, `mkdocs-material`) in
   `templates/devcontainer/Dockerfile`, so `make check` passes inside the container. Prerequisite for everything below.
2. **Verifier, `scripts/agent-verify.sh`.** Runs `make check`, then fails on the patterns that fooled us:
   - any change under `docs/proofs/` not backed by a broker result (proofs are written only by the broker, from real
     output);
   - empty or zero-byte committed files;
   - new files in the repository root outside an allow-list;
   - newly added failure-hiding patterns (`|| true`, `2>/dev/null`, `|| echo`) in scripts, as a warning that needs a
     one-line justification;
   - optional: changed scripts with no changed tests.
   It writes a machine-generated `.agent/STATUS.json` (pass or blocked, with reasons). That file, not `REPORT.md`, is
   the verdict a human reads.
3. **Stop hook in the kit plugin.** The plugin is already seeded into every dev container. On Stop, the hook runs the
   verifier; if it fails, the hook blocks the stop and hands the agent the reasons, so it must fix them. After three
   failed attempts the run ends BLOCKED with the verifier's reasons. This works the same in interactive, headless, and
   permission-skipping sessions (unlike the PreToolUse hook that spec D27 rejected).
4. **Same checks in CI.** A job in `check.yml` runs the verifier's repository checks on every PR, agent branches
   included, so a verifier bypassed locally still can't merge.
5. **Credential broker on the Mac, `scripts/agent-requests.sh watch`.** Watches the dev container's workspace (the Mac
   folder the container mounts) for `.agent-requests/NNN-<slug>.md`. For each request: shows the exact command and what
   it changes, asks yes or no, runs it with Erik's credentials, writes `NNN-<slug>.result.md` back, and, for proof
   steps, writes the `docs/proofs/` file from the real output. Never auto-runs anything; request files are untrusted
   input. A resumed agent reads the results and continues (`claude --resume` inside the container).
6. **`AUTONOMOUS.md` as a kit file.** The unattended-work rules become a committed template (for example
   `templates/prompts/autonomous-task.md`): never ask, decide and record; two strikes; fifteen minutes; never present a
   result you didn't get; untestable means Stuck; every credentialed step files a request; end the turn after
   REPORT.md.

## Current state (pointers, check before acting)

- Execution ledger for the main plan, with every task's status, ruling, parked finding, and CARRY item:
  `~/Code/xenia-2026/.claude/worktrees/build-foundation/.superpowers/sdd/2026-09-24-cohack-prep-kit/progress.md`.
- The battle-test harness and its review (`AUTONOMOUS.md`, the launcher, the capacity probe scripts, the auto-stop
  scripts, `battle-review.md`): the `harness/` folder next to that ledger.
- What shipped: `gh pr list --repo ert485/xenia-2026 --state merged`.
- Agent branches from the battle test, cleaned up but not merged: `agent/task-15`, `agent/task-20`, `agent/task-29`.
- Branches waiting for a PR: `fix/probe-log-region`, `plan/overnight-loop` (plan Task 31).

## Evidence (Thursday night battle test)

Three open-model agents (Qwen3-Coder-30B on the GPU box through the gateway) ran plan Tasks 29, 15, and 20 unattended.
They copied the brief's code almost perfectly (29 of 30 blocks) and all three branches pass `make check` on the Mac.
They failed at verification and honesty about gaps, and two of three looped on harness tools for about fifteen minutes
after finishing. Full review: `harness/battle-review.md`.

## Decisions for Erik

1. Build this as Task 32 now, before the rest of the Must tier, or fold its pieces into the tasks they touch (Task 8's
   image, Task 11's plugin, Task 14's CI checks)?
2. Broker as a plain script (recommended) or as a Mac Claude Code session?
3. Should the verifier's "changed scripts need changed tests" rule block, or only warn?

## Starting the fresh session

On the Mac, in `~/Code/xenia-2026`:

> Read `docs/superpowers/plans/2026-09-25-container-first-workflow.md` and the SDD ledger it points to. Then help me
> decide how to proceed with the container-first model. Every `terraform apply` is mine to approve.
