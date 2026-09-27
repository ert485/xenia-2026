# Prompts template (Should tier)

**Kit status: Should tier. Shipped as a template; not proven end to end beyond the Thursday-night
battle test that motivated it (see `docs/superpowers/plans/2026-09-25-container-first-workflow.md`).**

`autonomous-task.md` is the unattended-work ruleset: never ask, decide and record, two strikes,
fifteen minutes, every credentialed step files a request (`scripts/agent-requests.sh` on the Mac
is the other half of that), never present a result you didn't get, and end the turn after
`REPORT.md`. It is generic: drop it into any repo, alongside that repo's own `TASK.md` (the task's
actual requirements), and start an unattended run from it.

`scripts/agent-requests.sh` runs an approved command from the agent's own workspace, not a
pristine clone, so it can only refuse a tampered git state (a planted hook, a stray local config
key) before prompting — it can't stop a plain-looking `make`, script, npm, or terraform call from
doing something other than what its request describes.

## Before starting a run

The base branch must already contain the kit plugin (the Stop hook and the deny hooks) and
`plugin/scripts/agent-verify.sh`: the template leans on both (`agent-verify.sh` is what decides
whether the run passes; the Stop hook is what enforces that decision). An unattended agent on a
branch with neither has nothing holding it to the rules above.

## Starting a headless run

From inside the dev container, on the branch with `TASK.md` and `autonomous-task.md` (copied from
this template) both committed:

    claude -p "$(cat autonomous-task.md)" \
      --allowedTools Read,Write,Edit,Bash \
      --disallowedTools Skill,ScheduleWakeup,CronCreate,CronDelete,CronList,TaskStop,TaskCreate,TaskUpdate,EnterWorktree,ExitWorktree,Workflow,SendMessage,Monitor,Task,Agent,WebFetch,WebSearch \
      --max-turns 120 \
      --dangerously-skip-permissions

Two things today's open-model runs showed are load-bearing, not optional:

- **Both `--allowedTools` and `--disallowedTools`.** `--allowedTools` alone does not restrict which
  tools a run can reach once `--dangerously-skip-permissions` is set. An open model that has
  finished its real work loops on whichever of the disallowed tools it can still call — scheduling
  itself, spawning another agent, browsing the web — unless `--disallowedTools` names them
  explicitly. If a future run finds another tool to loop on, add to this list rather than trimming
  it.
- **`--max-turns 120`.** A cap for a run that never calls Stop cleanly on its own.

Resume a stopped or blocked run with `claude --resume` inside the same container; the template
tells the agent to read every `.agent-requests/*.result.md` before continuing, so results the
broker wrote while the run was paused are picked up automatically.
