# Contributing

Teammate: this is how the team works day to day. Each numbered item matches a row of the team charter
(https://26.cohack.tetl.ca/team-kit/04-team-charter/); to change one, name the line in the team channel or
open a PR. The rules themselves are in `PRINCIPLES.md`, and any one owner approves a change to them.

## How we work (charter C1 to C15)

1. **C1, one repo.** One public repo (confirmed at idea lock), with each service as a folder.
2. **C2, trunk-based.** Small PRs, rebased on `main` before merge. Shared files (schema, contracts, compose)
   have a named owner who merges changes to them.
3. **C3, self-merge.** Every change goes through a PR, and you merge your own once CI is green. No human
   review before merge: people look at the preview URL instead. Add the `review` label when you want the
   bot's eyes on a PR.
4. **C4, done for the demo path.** Deployed to `https://app.26.cohack.tetl.ca`, health check green, and one
   happy path clicked by someone other than the author.
5. **C5, claiming work.** Assign yourself the GitHub issue. One area, one owner at a time.
6. **C6, tie-breaks.** The product owner decides product questions. Erik decides kit infrastructure only
   (account, gateway, spend). The team decides application architecture. Anything else gets a two-minute
   timer, then a coin flip.
7. **C7, freezes.** Scope freeze at hour 18 (Sunday 03:00), demo freeze at hour 24 (09:00), rehearsal at 10:00.
8. **C8, night shift.** At least one person awake in each three-hour block from 23:00 to 07:00, from the
   sign-up sheet's sleep plans, named at idea lock.
9. **C9, style.** Formatter and linter settings are the language's defaults, fixed at idea lock, so agents
   don't fight over style. `make check` enforces them.
10. **C10, product API keys.** They live in SSM Parameter Store under `/xenia/app/<NAME>`, read at deploy
    time, never in the repo. Erik stores them with `scripts/put-secret.sh app/<NAME>`.
11. **C11, agents.** Agents run inside the dev container, which holds no AWS credentials. Your own AI
    subscription is welcome.
12. **C12, off switches.** See "Shutdown policy" below. CI blocks a billable PR that has neither.
13. **C13, contracts.** When there is an API: OpenAPI plus event schemas in `contracts/`, types generated,
    boundaries validated. See "Contracts" below.
14. **C14, comms.** One Discord server for text and voice; tasks are GitHub issues. Agents post to the team
    channel through `/notify`. Contact details are exchanged in a private channel, never committed.
15. **C15, not legal advice.** Nothing here about money or IP applies to you until you've said yes to it out
    loud at idea lock.

## Pull requests

The PR template carries two lines. Both must start at the beginning of a line, outside code blocks:

    Rule-feedback: none
    Shutdown: none needed because <reason>

- If you knowingly did something a rule says not to, replace the first with
  `Rule-feedback: P-<slug>, <what you did differently and why>`. It is feedback on the rule, never on a
  person, and the pile is only used to decide whether the rule stays, changes, or the code comes back in line.
  `/rule-feedback` in Claude Code writes the line for you.
- Three checks block a merge: `check` (the same `make check` you run locally), `shutdown-coverage`,
  and `verify` (the kit's agent-hygiene checks: unbacked proofs, empty files, and the like).
  Everything else (the bot review, the template reminder) is advice.
- Keep PRs small enough that the preview tells the whole story.

## Shutdown policy

A PR that adds or changes something billable must either touch that repo's `shutdown.d/` or contain the line
`Shutdown: none needed because <reason>` in its body.

The `shutdown-coverage` check treats a PR as billable when it touches `infra/`, a
`.github/workflows/deploy*` file, or any compose file. `/shutdown-entry` scaffolds a new `shutdown.d/` entry
with the header the kit's `scripts/shutdown.sh` reads, and `SHUTDOWN.md` lists every entry.

## Previews

Every PR gets its own copy of the app at `https://pr-<n>.box.26.cohack.tetl.ca` (`make preview-url` prints
yours). The kit builds it from your branch's compose file, so keep to the convention:

- a service named `web`, listening on `APP_PORT` (3000 unless the repo variable says otherwise);
- no `ports:` on any service (the kit routes to `web` by name);
- no `privileged`, `network_mode: host`, `pid: host`, Docker socket, or bind mounts outside the project
  folder. The preview is refused if it has any of them.

At most three previews run at once; the oldest is removed first. A preview disappears when its PR closes.

## Deploys

After a push to `main` deploys, the box needs `GET /` on `https://app.26.cohack.tetl.ca` to answer 2xx
or 3xx within `HEALTH_TIMEOUT` (90 seconds by default) — otherwise it reverts to the image that was
running before.

## Contracts

When the product has an API, adopt the kit's `contracts/` starter at the 11:30 architecture checkpoint by
following `templates/contracts/README.md` in the kit repo (https://github.com/ert485/xenia-2026): an OpenAPI
3.1 file, event schemas, `make types`, and the `contract-check` workflow (lint, stale generated types, and
breaking changes unless the PR is labelled `breaking-ok`). Change the spec first, then the code. A
server-rendered monolith with no API between services skips all of it.

## Skills

Anything done twice becomes a skill (P-skills). Repo-specific skills live in `.claude/skills/<name>/SKILL.md`
in this repo; `.claude/skills/README.md` shows the shape and `example-repo-skill/` is a working example. A
skill every team could use goes to the kit plugin instead, by PR to `ert485/xenia-2026`.

## Friction

If something blocks you, fix it and say so in Discord. If it only annoys you, run `/pain <one line>` in
Claude Code or open a "Friction" issue. The pain-review bot ranks the pile every few hours, and the top item
gets fixed once, in shared tooling (P-fix-once).
