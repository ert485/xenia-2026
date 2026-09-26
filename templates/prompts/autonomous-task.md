# Autonomous task template

Agent: you are working unattended. Nobody will answer questions until you finish, so never stop
to ask. Make the best reasonable decision, write it down in REPORT.md under "Decisions", and keep
going.

## The job

1. Read `TASK.md` completely before touching anything. It is your requirements: the files to
   create, the exact code, and the tests. Follow its steps in order.
2. Work on the branch you start on. Commit after each step that leaves the tests green, with a
   plain-words message saying what changed. Small commits beat one big one.
3. When every step you can do is done, write `REPORT.md` once (see the end) and end your turn
   immediately. Don't wait, schedule, poll, or re-edit the report.

## Rules

- **Stay on your branch.** Never run `git checkout`, `git switch`, `git branch`, `git reset`,
  `git rebase`, or `git pull`, even where TASK.md tells a human to start a branch from somewhere
  else: those lines are not for you. Only `git add` and `git commit`.
- **Scope.** TASK.md starts with a scope section (what to do, what to skip). Do only the steps it
  lists; the rest belongs to someone else's turn, and no request should be filed for it either.
- **The verifier decides, not you.** Run `plugin/scripts/agent-verify.sh $XENIA_VERIFY_ARGS`
  yourself before finishing; a Stop hook runs it again and blocks you, up to three times, on
  anything it finds — fix every one, commit, and finish again. Never edit `.agent/`, and never
  weaken a check or a test to get past it. If the verifier's only failure is outside your task's
  files, write it under Stuck and stop.
- **Never present a result you didn't get.** Never write or edit anything under `docs/proofs/`:
  proofs record a real run from a credentialed request, not your own claim. Never commit a
  placeholder or empty file to stand in for something you couldn't generate. Never hide a failing
  command (`|| true`, `2>/dev/null`, `|| echo`) — treat shellcheck and test output as instructions,
  not noise to silence.
- **A step that could not run is Stuck**, with the exact error, not a pass. "Stuck: none" is only
  true if every step in your scope ran.
- **Every credentialed or live step files a request.** When a step needs a credential, a push, a
  PR, or anything else you can't do yourself, create `.agent-requests/NNN-<short-slug>.md` (NNN
  counts up from 001) with these headings: **Command** (the exact command, one fenced code block,
  run from the repository root), **Why**, **What it changes** (or "read-only"), **Expected
  result**, **Undo** (or "not needed"), and **Then** (what you'll do with the result). One command
  per request; never put a secret, key, or account ID in one. If you're resumed, read every
  `.result.md` first and continue from there — a request without a result is still pending.
- **Keep the repository root clean.** REPORT.md is the only report file; don't create other
  summaries.
- **Two strikes.** If the same command fails twice the same way, stop repeating it: read the
  error, look at the file or tool involved, and try something different.
- **Fifteen minutes.** If one step has taken about fifteen minutes without progress, write what
  you tried under Stuck, leave a `TODO(agent)` if it helps, and move to the next step.
- **End the turn after REPORT.md.** Once it's written, stop: call no other tool.

## REPORT.md

Sections, in this order, each short: **Done** (what you implemented, step by step), **Tests** (the
command and its final output), **Requests** (every `.agent-requests/` file and its status),
**Decisions**, **Stuck** (anything left undone and what you tried), **Notes**.
