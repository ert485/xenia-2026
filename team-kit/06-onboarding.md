# Onboarding

Our shared model is an open 30B coder through our gateway. Fine for scoped tasks, weaker on long multi-step runs. Your own Claude, Cursor, or other subscription is welcome.

## The rules

Teammate: these are the team's rules, and they're everyone's to change: any line changes by PR, and one owner approves. Erik only filled in the initial state. The canonical copy is [PRINCIPLES.md](PRINCIPLES.md) in the team repo; the why and the practices are in [PRINCIPLES-EXTENDED.md](PRINCIPLES-EXTENDED.md).

- **P-ours** Everyone on the team has an equal say in these rules. Change any of it by PR, any one owner approves. Rule feedback is about rules: a recorded exception is never grounds to challenge the merged change or the teammate who made it; it only informs whether the team keeps the rule, changes it, or decides together to bring the code back in line.
- **P-fix-once** If it blocks you, fix it and say so in Discord. If it annoys you, `/pain` it. An agent ranks the pile every few hours; the top item gets fixed once, in shared tooling.
- **P-two-gates** Only `make check` and shutdown coverage block a merge. No human review before merge; humans look at the preview URL. The bot reviews on request.
- **P-off-switch** Anything that costs money has an off switch, or says why it doesn't need one.
- **P-wheel** Product direction, irreversible actions, prize, and IP are human calls. Take over from an agent whenever you like; after fifteen minutes of looping with no progress, you must.
- **P-public** Everything here is public and permanent: no keys, no contact details, nothing personal about anyone in the repo, issues, PRs, or site. If a key leaks, say so in Discord and rotate it. No blame.

The team repo, its issues and PRs, and this kit site are public, and everything you write there carries your GitHub name.

## Get started (five minutes)

1. Accept the GitHub invitation to the team repo.
2. Open the dev container: on GitHub, **Code, Codespaces, Create codespace on main**; or locally, clone the repo and choose **Reopen in Container** in VS Code.
3. Paste your gateway key (it came by direct message). In Codespaces: GitHub **Settings, Codespaces, Secrets**, add `GATEWAY_KEY` and give it the team repo. Locally: create `.devcontainer/ai.local.env` with the line `ANTHROPIC_AUTH_TOKEN=sk-<your-gateway-key>`; that file is never committed.
4. In the container's terminal, run `bash plugin/scripts/doctor.sh` (inside Claude Code the same check is `/doctor`). Every line should say `ok`.
5. Run `claude` (or `opencode`) and ask for something small.
6. Push a branch and open a PR. The bot comments your preview URL, `https://pr-<number>.box.26.cohack.tetl.ca`, within a few minutes.

## What's already in the sandbox, and what you bring

Already inside: Claude Code, OpenCode, the kit's skills and rules, Node 22, Python 3.12, the GitHub CLI, the Docker CLI, the AWS CLI, Terraform, the gateway settings, and the repo.

You bring three things:

1. GitHub access to the team repo (Codespaces signs you in; a local container needs `gh auth login` once and a git name and email).
2. Your gateway key, from your direct message.
3. The Discord invite.

## Optional tie-ins

- **Your own AI subscription.** Switch Claude Code from the gateway to your own login with `unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN; claude /login`; open a new terminal to switch back.
- **AWS console or a local CLI loop.** Erik can add you to the AWS account (an invitation email with a one-time code). Any agent you run with that session inherits near-admin reach, which is why agents in the container get no AWS credentials by default.
- **Dotfiles.** Codespaces applies your dotfiles repo automatically.
- **VS Code Settings Sync** works in both Codespaces and a local container.
- **A Hugging Face token**, only if the team picks a gated model.
- **Your own hosting.** Vercel, Neon, Supabase, or anything else is fine, with no penalty: the kit removes friction, it doesn't mandate a host.

## Skills

| Skill | What it does |
|---|---|
| `/pain <one line>` | logs friction as a GitHub issue after you confirm the wording |
| `/rule-feedback P-<slug>, <reason>` | records a knowing exception to a rule on your PR |
| `/notify <message>` | posts to the team channel |
| `/doctor` | checks your setup |
| `/preview` | shows this PR's preview URL and status |
| `/shutdown-entry` | writes an off switch for something billable you added |
| `/demo-checklist` | the demo checklist |

## When things are slow or odd

- **Cheap mode.** Fewer turns and smaller tasks: ask for one file or one test at a time. The shared model queues when many agents run at once.
- **OpenCode** is the fallback client with the same key: run `opencode`.
- **Kiro** is another option; students get 1,000 credits a month.
- **Python.** `make check` runs `ruff`, `mypy`, and `pytest`; contract types come from `datamodel-code-generator`.
- **Box logs.** From a clone of the kit repo, with the AWS profile from your invitation: `XENIA_PROFILE=cohack-dev scripts/logs.sh app-web` (or `pr-<number>`, `--since 2h`, `--follow`).
- **Product API keys** (charter C10) go in the parameter store, never the repo: from a kit clone, `scripts/put-secret.sh app/<NAME>` reads the value from your terminal, and the deploy reads it at deploy time. Or ask Erik to add it.