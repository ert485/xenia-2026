# Co.Hack 2026 prep kit

A kit for a hackathon team that doesn't exist yet: hosting with a real URL, a domain, CI with two gates, an AI coding setup in a dev container, previews for every pull request, one command to stop everything that costs money, and a one-page way of working with a default for every day-of decision. Nothing in it assumes what the team will build.

Read it as a website: **https://26.cohack.tetl.ca**

## Saturday morning, after idea lock (Erik)

    scripts/onboard-repo.sh <owner>/<repo> --owners @a,@b
    scripts/onboard-teammate.sh <email> <first> <last>

Then each teammate opens a Codespace on the team repo, pastes their key, and runs `claude`. The full order is in `runbook/06-saturday.md`.

## What's here

| Path | What |
|---|---|
| `team-kit/` | the team pages: rules, charter, timeline, onboarding, demo and pitch |
| `runbook/` | Erik's steps, Wednesday to Sunday |
| `infra/` | Terraform: the org and platform stacks, the Docker box with the gateway, the GPU box, the static site |
| `templates/` | what `onboard-repo.sh` copies into a team repo: workflows, dev container, principles, PR and issue templates |
| `plugin/` | the Claude Code plugin: the rules at session start and seven skills |
| `scripts/` | everything humans run; `scripts/status.sh` shows what's running |
| `shutdown.d/`, `SHUTDOWN.md` | the off switches and their rendered list |
| `docs/superpowers/specs/`, `docs/superpowers/plans/` | the design and the build plan |
| `docs/proofs/` | what was proven before the event, and how |

## Other teams are welcome to use this

Everything is MIT licensed and public. Pin the plugin and the templates by commit rather than following `main`, because the kit changes during the event. Your AWS account IDs and keys go in your own gitignored `kit.local.env`, never in the repo.

## Honest limits

- `scripts/shutdown.sh` stops only what has an entry in `shutdown.d/`. Check your billing console too: your AWS bill is yours.
- Budget alerts lag several hours; `scripts/status.sh` shows what runs right now.
- The shared model is an open 30B coder: fine for scoped tasks, weaker on long multi-step runs.

## Friction

In Claude Code, `/pain <one line>` files a `friction` issue after you confirm the wording. The top item gets fixed once, in shared tooling.
