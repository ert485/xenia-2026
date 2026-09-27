# Click-ops PreToolUse hook

Reader: for kit maintainers. Cut tier: documented, not built.

## What it was

A PreToolUse hook in the kit plugin that inspected every Bash command an agent was about to run and asked the
teammate before any AWS CLI call that creates, changes, or deletes a resource outside Terraform, to keep
infrastructure in code (P-no-clickops).

## Why it was cut

The hook's `ask` decision turns into `allow` under permission-skipping mode, which is how agents run inside the
container, and into `deny` in headless runs, which breaks CI and the reviewer: it would be silent exactly where
it mattered and obstructive everywhere else (D27). And D22 already removed what it would guard: agent
containers hold no AWS credentials, so an agent's `aws` call fails on its own.

## What exists instead

No AWS credentials in agent containers (C11, D22); deploys go through CI with OIDC. Terraform default tags mark
everything the kit creates, and `scripts/untagged.sh` (Task 28) lists anything without tags. Console work that
had to happen gets a `Rule-feedback: P-no-clickops, ...` line so it can be imported or destroyed later.

## How to revive

Only if agents ever hold AWS credentials again (for example Scenario A with Identity Center logins in the
container):

- Add a `PreToolUse` entry with matcher `Bash` to `plugin/hooks/hooks.json` and a script
  `plugin/hooks/block-aws-mutations.sh` that reads the tool input JSON with `jq`, matches
  `aws [a-z0-9-]+ (create|delete|put|update|modify|terminate|run)-`, and returns `deny` with a reason naming
  Terraform and the `Rule-feedback:` path (deny, not ask, so permission-skipping cannot turn it into allow).
- Exempt read-only verbs and the kit's own scripts, and bats-test the matcher in `tests/`.
- Accept that a determined agent can still write a script that calls the SDK; this is a guard rail, not a
  boundary.

Effort: 2 hours plus a day of watching for false positives.
