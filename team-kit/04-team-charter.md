# Team charter

Teammate: how we work, one default per row. A row stands unless someone names it and proposes a change ("C3: I want one reviewer on the API"). A one-person team skips this page and keeps the [timeline](05-24h-timeline.md) and the [demo script](07-demo-script.md).

Money, IP, and roles are not defaults: rows C6, C8, and C15 are asked aloud at idea lock ([checklist](02-idea-lock-checklist.md)).

| Default | Why | Disagree? name the line |
|---|---|---|
| **C1** One repo, public (confirmed at idea lock), services as folders. | One place to look; public gets free CI minutes and Codespaces prebuilds. | Name C1: private repo, or one repo per service. |
| **C2** Trunk-based. Small PRs, rebase before merge. Shared files (schema, contracts, compose) have a named owner who merges changes to them. | Small PRs keep merges cheap; one owner per shared file stops two agents rewriting it at once. | Name C2: a longer-lived feature branch for one area. |
| **C3** PRs required. Self-merge once CI is green. No human review before merge. Humans look at the preview URL. Add the `review` label when you want the bot's eyes. | Review queues stall a 24-hour team; the preview shows what changed. | Name C3: a required reviewer for one path. |
| **C4** Done, for the demo path, means: deployed to `app.`, health check green, one happy path clicked by someone other than the author. | "Works on my machine" doesn't win a demo. | Name C4. |
| **C5** Work is claimed by assigning yourself the GitHub issue. One area, one owner at a time. | Nobody builds the same thing twice. | Name C5. |
| **C6** Tie-breaks: the product owner decides product questions; Erik decides kit infrastructure only (account, gateway, spend); the team decides application architecture; anything else gets a two-minute timer, then a coin flip. | Decisions in minutes, not hours. | Asked aloud at idea lock. |
| **C7** Scope freeze at hour 18 (Sunday 03:00), demo freeze at hour 24 (09:00), rehearsal at 10:00. | The last hours go to polish and rehearsal, not new features. | Name C7: different freeze times. |
| **C8** Night shift: at least one person awake in each three-hour block from 23:00 to 07:00, drawn from the sign-up sheet's sleep plans, named at idea lock. | Someone answers the gateway alarm and keeps agents unstuck overnight. | Asked aloud at idea lock. |
| **C9** Formatter and linter settings are fixed at idea lock (the language's defaults). | Agents don't fight over style. | Name C9: a different formatter. |
| **C10** Product API keys live in the kit's parameter store under the app's prefix, read at deploy time, never in the repo. | The repo is public and permanent. | Name C10. |
| **C11** Agents run inside the dev container; no AWS credentials in agent containers; own subscriptions welcome. | An agent that can't reach AWS can't wreck it; CI deploys instead. | Name C11. |
| **C12** Every PR that adds something billable carries a `shutdown.d` script or a `Shutdown: none needed because...` line. CI blocks otherwise. | One command stops everything that costs money. | Name C12. |
| **C13** Contracts, when there is an API: OpenAPI plus event schemas in `contracts/`, types generated, boundaries validated. | Agents writing both sides of an API break each other quietly otherwise. | Name C13: skip for a server-rendered app. |
| **C14** Comms: one Discord server (text and voice), tasks as GitHub issues. Agents post to the team channel through `/notify`. Contact details are exchanged in a private channel, never committed. | One place for humans, a path for agents, nothing personal in public. | Name C14: another channel. |
| **C15** Not legal advice. Nothing here about money or IP applies to you until you've said yes to it out loud at idea lock. | Silence is not consent for money or IP. | Asked aloud at idea lock. |
