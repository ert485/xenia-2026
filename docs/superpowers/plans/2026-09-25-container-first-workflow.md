# Container-first workflow with automatic verification: high-level plan

- Date: 2026-09-25 (Friday). Status: **tiered.** The frame was demoed to Erik's work team on Friday afternoon under the
  name "Reckless inside, gated outside", and Erik split the follow-ups into hackathon work and after-hackathon work. The
  placement below is the plan of record for the weekend; it lands in the main plan as Tasks 32 to 34 plus the steps
  folded into Tasks 11, 14, 18 and 26.
- Tracking: personal project, no Notion task. PRs from this plan carry no task-ID suffix.
- Builds on: the spec `docs/superpowers/specs/2026-09-23-cohack-prep-kit-design.md` (v2.6) and the main plan
  `docs/superpowers/plans/2026-09-24-cohack-prep-kit.md`. The frame itself (the diagram, what crosses each boundary,
  the mapping onto the AI-native SDLC playbook, the team's suggestions) is the page "Reckless Inside, Gated Outside" in
  Erik's notes; this file carries only what the kit builds.

## The model

Work starts where a teammate would start it: a human opens the dev container, runs `claude` against the team model
(the GPU box through the gateway, Bedrock as failover), and works normally. The dev container still holds no AWS or
GitHub credentials (spec D22).

Two rules, fixed on Friday:

- **The dev container may read anything and deploy nothing.** Nothing it produces is trusted, its own report included.
  It is meant to be recklessly fast inside: no permission prompts, a hard deny on the few ruinous commands, and nothing
  inside worth exfiltrating beyond a per-container gateway key with a small budget.
- **No agent holds deploy credentials.** The gate is a deterministic executor plus a human yes: CI on a merge to `main`
  (OIDC, Task 9) for the team's app, apply-on-merge (Task 30) or any member's own Identity Center session (spec D22's
  opt-in) for the team's infrastructure, the broker's yes or no per command for unattended kit work, and Erik only for
  the kit's own stacks (`infra/org`, `infra/platform`, the recipes). Erik is not in the path of a team deploy. The gate
  acts on the verified commit and nothing else.

The Mac only does work that needs a credential. It runs a small broker, not a Claude session, that shows each
credentialed request from the container and runs it only after Erik says yes. A Mac Claude Code session is only needed
when a request is too complex for one command.

Whether work is done is decided by a verifier, never by the agent's own report and never by a reviewer happening to
notice. Deterministic checks come first and are the only thing that says pass or blocked; how anything beyond that is
shaped is deliberately left open until the flow has run for real (Erik, Friday: don't over-specify it). The
Thursday-night battle test (see "Evidence" below) showed why the checks exist: an unattended open-model agent wrote a
proof for commands it never ran, committed empty placeholder images, hid a failing `make check`, filed no requests, and
reported "Stuck: None" on all three tasks. Every failure of that kind becomes a permanent check, and each check names
the incident that motivated it.

## Components

1. **Tools in the dev container image.** bats, shellcheck, and the site tools (`segno`, `mkdocs-material`) in
   `templates/devcontainer/Dockerfile`, so `make check` passes inside the container. Prerequisite for everything below.
2. **Verifier, `scripts/agent-verify.sh`.** Contract: the input is a worktree; the output is a machine-written
   `.agent/STATUS.json` (`pass` or `blocked`, the commit it judged, and one reason per failing check, each naming the
   check). It never reads `REPORT.md` as evidence. The first checks, all deterministic:
   - `make check`;
   - any change under `docs/proofs/` not backed by a broker result (proofs are written only by the broker, from real
     output);
   - empty or zero-byte committed files;
   - new files in the repository root outside an allow-list;
   - newly added failure-hiding patterns (`|| true`, `2>/dev/null`, `|| echo`) in scripts, as a warning that needs a
     one-line justification;
   - changed scripts with no changed tests, as a warning.
   That file, not `REPORT.md`, is the verdict a human reads.
3. **Hooks in the kit plugin.** The plugin is already seeded into every dev container.
   - *Stop hook.* On Stop, the hook runs the verifier; if it fails, the hook blocks the stop and hands the agent the
     reasons, so it must fix them. After three failed attempts the run ends BLOCKED with the verifier's reasons. This
     works the same in interactive, headless, and permission-skipping sessions.
   - *Deny hooks (new).* PreToolUse hooks that **deny**, never `ask`, the few ruinous commands: force pushes, deleting
     the workspace root, editing the firewall scripts, writing under `docs/proofs/`. Verified against the Claude Code
     docs on 2026-09-25: PreToolUse and Stop hooks run under `--dangerously-skip-permissions` and in headless `-p`, a
     hook `deny` holds, and only `ask` degrades; spec D27's objection was to `ask`, so deny hooks stay available. A
     teammate's same-day story of an agent doing something destructive despite its settings is why these are Must.
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
7. **Deep review alongside the quick review (new).** The quick review is Task 18's `pr-review.yml`, on every PR. The
   deep review is the same reviewer run again with far more resources: a brief that looks from several angles (bugs,
   security, conformance to the task and the plan, whether the tests actually ran), more turns and budget, and
   permission to run the code. It runs on a sample, not on everything: every PR while the flow is young, then fewer as
   it stops finding anything the quick review missed, and always for PRs touching `infra/`, `.github/`, `templates/`
   or `scripts/`, or carrying a `deep-review` label. Each run posts its findings and a "missed by the quick review"
   list; every miss becomes a verifier check or a line in the quick reviewer's brief. The sample rate is a repository
   variable with a starting default (every PR until ten in a row miss nothing, then one in four), not code. The
   redundancy comes from different briefs and budgets, because the kit runs one model family; different models come
   after the hackathon.
8. **Health-check revert in `deploy.sh` (new).** After `compose up`, the box polls the app's health for a bounded time;
   on failure it redeploys the image recorded in `/srv/app/previous` and exits non-zero, so the deploy job fails
   visibly. Task 26's `rollback.sh` stays the manual path. No agent is in this loop.

## Tier placement

**Must, tonight, before the rest of the Must tier resumes at Task 11:**

- **Task 32, verifier v0:** components 1 and 2, with bats tests for each check and a proof that the battle test's three
  failures (a fake proof, an empty file, a hidden failure) each turn the status to `blocked`.
- **Folded into Task 11** (kit plugin): component 3, the Stop hook and the deny hooks, in the plugin's `hooks.json`.
- **Folded into Task 14** (CI checks): component 4, the verifier job in `check.yml`.

Order: 32, 11, 14, 18, then the remaining Must tier (12, 13, 16, 17, 19, 21, 22, with 15, 20 and 29 finished from their
agent branches).

**Should, Saturday, in this order after the Must tier:**

- **Task 33, deep review:** component 7, extending Task 18's reviewer: the multi-angle brief, the trigger rules, the
  sample-rate variable, the "missed" list, the label.
- **Task 34, broker and autonomous template:** components 5 and 6. Only if Erik runs unattended kit work over the
  weekend; teammates' credentialed steps already go through CI.
- **Folded into Task 26** (rollback): component 8.

**After the hackathon** (deferred; `docs/deferred/` stubs if Task 29 is regenerated): reviewers on more than one model
family; a fixed list of things the human always reads with their own eyes (Erik: speculative, not thought through);
per-claim provenance in the verifier's report beyond the check name; a read-only observer agent after the gate (logs,
metrics and status through its own read-only identity, fixed runbook operations instead of a shell, findings to a
human, never straight into another agent's prompt); code-owner semantics for the gate.

## Current state (pointers, check before acting)

- Execution ledger for the main plan, with every task's status, ruling, parked finding, and CARRY item:
  `~/Code/xenia-2026/.claude/worktrees/build-foundation/.superpowers/sdd/2026-09-24-cohack-prep-kit/progress.md`.
- The battle-test harness and its review (`AUTONOMOUS.md`, the launcher, the capacity probe scripts, the auto-stop
  scripts, `battle-review.md`): the `harness/` folder next to that ledger.
- What shipped: `gh pr list --repo ert485/xenia-2026 --state merged`.
- Agent branches from the battle test, cleaned up but not merged: `agent/task-15`, `agent/task-20`, `agent/task-29`.
- Branches waiting for a PR: `fix/probe-log-region`, `plan/overnight-loop` (plan Task 31).
- `deploy.sh` on `main` already records the previous image at `/srv/app/previous` (Task 26's bookkeeping); nothing
  reverts automatically yet.

## Evidence (Thursday night battle test)

Three open-model agents (Qwen3-Coder-30B on the GPU box through the gateway) ran plan Tasks 29, 15, and 20 unattended.
They copied the brief's code almost perfectly (29 of 30 blocks) and all three branches pass `make check` on the Mac.
They failed at verification and honesty about gaps, and two of three looped on harness tools for about fifteen minutes
after finishing. Full review: `harness/battle-review.md`.

## Decisions

Resolved on Friday:

1. Build the verifier as Task 32 now; the hook and CI pieces fold into Tasks 11 and 14 because those are still open.
2. The broker is a plain script, not a Mac Claude Code session.
3. "Changed scripts need changed tests" warns; it blocks once it has been seen not to cry wolf.

Still guesses, to be corrected by use: the deep review's starting sample rate and its risky-path list; the health-check
polling window.

## Starting the fresh session

On the Mac, in `~/Code/xenia-2026`:

> Read `docs/superpowers/plans/2026-09-25-container-first-workflow.md` and the SDD ledger it points to. Execute Task 32
> with superpowers:subagent-driven-development, then resume the ledger at Task 11, carrying the steps this plan folds
> into Tasks 11, 14, 18 and 26. Every `terraform apply` of the kit's own stacks is mine to approve.
