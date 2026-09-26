# Co.Hack 2026 prep kit: design

- Date: 2026-09-23 (Wednesday). Event starts Saturday 2026-09-26 09:00 CST.
- Status: **v2.7, amended 2026-09-26.** v2.5 was approved by Erik on 2026-09-24 after his review, one fresh adversarial review of the whole spec, two focused fresh reviews of the principles (a teammate persona and a mechanism check), and a public-exposure review. v2.6 adds two things Erik decided the same day: a Should-tier capability (D39: team infrastructure changes by PR, applied on merge) and a Must-tier access kill switch (D40: one break-glass SCP, attached by `scripts/lockdown.sh`). v2.7 adds a seventh core principle, `P-simple` (D41), which Erik asked for on event morning. Plan: `docs/superpowers/plans/2026-09-24-cohack-prep-kit.md` (Task 30 carries v2.6; D41 is folded into Tasks 11, 12, 18, and 20).
- Tracking: personal project, no Notion task. PRs from this plan carry no task-ID suffix.
- Scenario: **B, open-weight model, no Anthropic account**. Scenario A (Claude Platform on AWS) is documented in the appendix only.

## What changed in v2

The fresh review found four blockers and a long tail of should-fixes. The consequential changes:

1. **Scope is tiered.** Section 3 now separates Must (proven by Friday night), Should (built, may ship unproven), and Cut (documented only). The old cut order protected the wrong things.
2. **The model path no longer waits on the GPU quota.** Bedrock serves Qwen3-Coder-30B-A3B serverless in us-east-1. The gateway is wired to it Thursday morning, so Claude Code, LiteLLM, and the model are proven end to end before any GPU exists. The GPU box becomes the primary backend when it arrives, and Bedrock stays as automatic failover. Cost is per token but cheap, and only while the GPU is down.
3. **The gateway moves to the Docker box** in Canada, which is always on and already runs Postgres. The GPU box exposes vLLM only to the gateway's IP. One public LLM hostname, one place to harden.
4. **Claude Code's client config was wrong.** The capability variables do nothing behind a gateway. Replaced with explicit context and output-token limits, `drop_params` on the gateway, and a Fable alias mapping.
5. **Certificates were wrong.** A single-label wildcard doesn't cover `pr-3.box.26…`. Previews now live only on the Docker box under its own `*.box.` wildcard, issued once via DNS-01, and no box holds a broad Route 53 role.
6. **Security tightened**: LiteLLM pinned by digest with only inference routes exposed, a fuller deny list on the teammate permission set, keyless dev container template, no AWS credentials inside agent containers by default.
7. **Sizing and money**: Docker box is t4g.large, GPU hours re-counted, alert tiers gain a $150 step, the cost estimate is about $110 to $130.
8. **The team kit was rewritten after two focused reviews** (v2.2). The rules live in the team repo as `PRINCIPLES.md`, owned by two or three people the team names at idea lock, not by Erik by default. Money and IP are asked out loud at idea lock, not settled by silent defaults. The steering mechanism shrank to what works: a condensed SessionStart injection plus skills, a `Rule-feedback:` PR line with a label and a saved search, and a code-owner ruleset. The click-ops hook and the deviations renderer are gone; the first silently allows in permission-skipping mode and blocks headless runs, the second can't commit to a protected main. Erik's tie-break narrowed to kit infrastructure. Two OIDC roles instead of one.
9. **Kit is public, principles are two-tier** (v2.3). The kit repo is public under MIT so teammates and other teams can use it; helping other teams is on the table. `PRINCIPLES.md` is a core of five lines a stranger reads in a minute, `PRINCIPLES-EXTENDED.md` holds the why, the practices, and the mechanics, and an AI consistency review checks that nothing significant in the extended file is missing from the core. Onboarding leads with the rules being everyone's, with Erik having written only the first draft.
10. **Digital safety after a public-exposure review** (v2.4). A sixth core principle, `P-public`: everything here is public and permanent. CI hardening for a public repo with OIDC (no untrusted-trigger workflows, deploy trust pinned to the deploy workflow on push, empty default permissions, SHA-pinned actions), preview isolation on the box that holds the gateway, a reviewer that never holds secrets while reading PR content, per-key spend budgets and one-step key rotation, and a firm rule that teammates' contact details and idea-lock answers never enter a repo. Secret scanning and push protection are on; the sign-up sheet stays on paper.
11. **Final edits at approval** (v2.5): `P-comms` (sandboxed agents can talk to the team through the chosen channel, with agent-friendliness noted when the team chooses), `P-who` (say which entity you mean), and clearer wording for what rule feedback is never used for.
12. **Team infrastructure by PR, applied on merge** (v2.6, D39, Should tier). Agents still hold no AWS credentials (D22), but they can now change the team's own AWS infrastructure: a PR touching the team's Terraform folder gets a plan comment (addresses and counts only), and a merge to `main` applies it from CI. Two new per-repo roles: a read-only plan role and an infra role with the guard-rail deny list plus an EC2 instance-type allow-list. Any delete or replace pauses the apply until the merged PR carries a `destroy-ok` label, and the pause is posted to the team channel. No second approver, consistent with C3. The kit's own stacks stay manual. D35's "Terraform never runs in public CI" is narrowed to the kit's stacks, with log rules for the team stack.
13. **Access kill switch** (v2.6, D40, Must tier). `infra/org` enables service control policies on the organization root (AWS attaches `FullAWSAccess` everywhere, so nothing changes) and creates one SCP, `xenia-lockdown`, left unattached. `scripts/lockdown.sh` attaches it to the member account: every identity there is denied everything, including sessions already issued, except Erik's admin role, `OrganizationAccountAccessRole` (assumable only from the management account: Erik's second way in), and the two kit box roles, so the gateway keeps answering. `--undo` detaches it. It is separate from `shutdown.sh`: stopping spend and cutting access are different emergencies. D2's "No SCPs" gains this one carve-out. Erik also accepted both PR-review callouts as intended: teammates and CI deliberately get near-admin, and the lockdown is the counterweight.
14. **`CODEOWNERS` scope narrowed to the rules files** (v2.6 amendment, same day as D39/D40). Code-owner review now gates only `PRINCIPLES.md`, `PRINCIPLES-EXTENDED.md`, and `CODEOWNERS` itself; `.github/workflows/`, `.devcontainer/`, the vendored plugin, `Makefile`, compose files, and (per D39) `infra/team/**` all self-merge once `make check` and shutdown coverage pass. Rules edits are rare and a team agreement worth a second reviewer; the other paths change often mid-event as agents fix CI, and a second-owner gate there added little given every member's near-admin AWS access. The residual risk — an agent tricked into leaking the gateway CI key or the Discord webhook — is covered by per-key budgets, one-step rotation, `gitleaks`, fork skip, and the reviewer ranking CI and secrets changes as a finding.
15. **A seventh core principle, `P-simple`** (v2.7, D41). Build the simplest thing that works from small single-job pieces, and let agents push back: when the problem or the asked-for solution is more complex than the job needs, the agent says so and offers the simpler version, and the teammate decides. The extended entry defines "small" as few moving parts rather than many files, adds a second-use test for abstractions and a one-sentence PR reason for any new moving part, and the bot's review flags unrequested complexity. It advises; the merge gates stay at two.

## 1. Purpose

Arrive at Co.Hack 2026 with no team and no fixed idea, and still be the person who can say
"we have hosting, a domain, CI, an AI coding setup, and a one-page way of working, all ready to
adopt in ten minutes". Nothing in the kit assumes what the team will build.

### Event facts (verified from the Luma page on 2026-09-23)

- Co.Hack 2026, hosted by Co.Labs. Saturday 2026-09-26 09:00 to Sunday 2026-09-27 12:00. Saskatchewan is on CST (UTC-6) year-round; GitHub cron runs in UTC, so 09:00 CST is 15:00 UTC.
- In person at Andgo Systems, 701 Broadway Ave #200, Saskatoon.
- Teams or individuals, with or without an idea. Day 1 form ideas and build, Day 2 demo for judging. Two cash prizes.
- Judging criteria and the Saturday-morning agenda are not published, and Erik prefers not to ask the organizers. The pitch outline uses common hackathon criteria, and the idea-lock time flexes to whatever the morning agenda turns out to be.
- Sponsors include a law firm (McKercher LLP), so an IP session is plausible. The charter carries an IP clause regardless.

### Success criteria (Saturday 09:00)

1. Any GitHub repo added to an allow-list deploys to `app.26.cohack.tetl.ca` on its first merge, over TLS, in under five minutes, without anyone holding AWS keys.
2. A teammate gets console and CLI access to the AWS account within the time it takes to accept an email invite, if they want it.
3. A teammate with no paid AI subscription opens the dev container and has a working Claude Code (or OpenCode) session against the team model in under five minutes.
4. Every PR gets a preview URL, and any PR labelled `review` gets an automated review comment.
5. What is running is visible within a minute (`scripts/status.sh`), spend is visible with the billing lag of a few hours, and `scripts/shutdown.sh` stops everything billable in one command.
6. The team kit gives any newly formed team a filled-in default for every day-of decision, so only disagreements get discussed.
7. Every team-kit page is readable at `https://26.cohack.tetl.ca` and reachable from a printed QR code, and friction gets logged from inside Claude Code in one line.

## 2. Decisions log

Decisions made in the design conversation and the two review rounds, with the reason. Settled unless a review reopens them.

| # | Decision | Reason |
|---|---|---|
| D1 | Existing personal AWS account becomes the Organizations management account; one new member account `cohack-26` holds everything | Total isolation, one bill on the existing card, no sign-up or verification holds. Closable after the event. |
| D2 | No SCPs in normal operation, no hard spend enforcement. One carve-out (v2.6, D40): a single break-glass SCP, `xenia-lockdown`, exists unattached and is attached only by `scripts/lockdown.sh` in an emergency or at the event's end | Erik wants members autonomous. Safety comes from alerts plus a process kill switch. The break-glass SCP changes nothing until it is attached. |
| D3 | Kill switch is `scripts/shutdown.sh` over `shutdown.d/` directories, with a CI check that PRs adding billable things also add a shutdown entry | Every expensive thing has a documented off switch, consolidated into one script. |
| D4 | Primary region ca-central-1 for the core | Erik's preference. Downsides are small: CloudFront certs live in us-east-1 anyway. |
| D5 | GPU box in us-east-1 | 48GB L40S (g6e) is not offered in Canada. Canada only has 24GB L4 (g6). |
| D6 | Open-weight model, no Anthropic account (Scenario B) | Fixed hourly bill, everything on AWS, no per-token surprise. Scenario A documented for switching. |
| D7 | Claude Code via a translation gateway as the primary client, OpenCode as fallback | Keeps one UX for everyone; the gateway path is a documented Claude Code configuration surface but not Anthropic-supported for non-Claude models. |
| D8 | Deploys via GitHub Actions with OIDC; Identity Center access for humans who want the console or a local CLI loop | Nobody needs long-lived AWS keys. Both paths are per-person and revocable. |
| D9 | Per-PR preview environments instead of a staging environment | Parallel, disposable, real-URL testing. Staging serialises a team. |
| D10 | Docker box (compose behind Caddy) as the primary deploy recipe; static site for the kit site and any static frontend | App Runner is not in Canada and closed to new customers in April 2026. The Docker box runs any stack including Postgres. |
| D11 | Dev containers as the sandbox standard, with Codespaces as the alternative | Anthropic's own guidance: unattended or permission-skipping agent runs belong inside a container or VM. |
| D12 | Full team kit, defaults-first | Strangers plus cash prizes need prize split, IP, tie-breaks, and scope freeze agreed before code. Defaults mean only disagreements cost time. |
| D13 | Alert tiers $10, $25, $50, $100, $150 plus a forecast alert | $10 is the canary that proves alerts are wired (it fires Thursday, on purpose). The rest are realistic tiers for a GPU weekend. One variable. |
| D14 | Own headless PR review in CI, no @claude action | The packaged action doesn't fit Scenario B. Headless Claude Code on a fresh runner gives an unbiased review. |
| D15 | PITR and deletion protection on for the demo DynamoDB table, off for previews | Cents per month, and the realistic weekend risk is an agent wiping a table. |
| D16 | A principles page with an AI-native feedback path: one friction log, a pain-review agent, shared tooling fixed once | Bugs in shared tooling should be fixed once, not rediscovered by each developer. Minor pain gets logged and only acted on when accumulated. |
| D17 | Contract tooling: OpenAPI lint, breaking-change detection, generated types shipped as a template; Schemathesis documented only | Deterministic feedback agents can act on. Default on for API-shaped projects, off for a monolith. |
| D18 | Team kit and runbook published as a public site at the apex, with a printed QR flyer | Anyone can read the way of working before agreeing to it. Nothing in those pages is secret. |
| D19 | Bedrock's serverless Qwen3-Coder-30B-A3B is the bring-up backend and the automatic failover | Removes the GPU quota from the critical path. No Anthropic account, on the AWS bill, per-token only while the GPU is down. (Review round 2.) |
| D20 | The LLM gateway (LiteLLM behind Caddy) lives on the Docker box, not the GPU box | Always on, already has Postgres, one public LLM hostname, one place to harden. The GPU box is reachable only from the gateway. (Round 2.) |
| D21 | Scope tiered into Must, Should, Cut (section 3) | Two build days can't prove the v1 scope. A working model path and a working deploy path are the point. (Round 2.) |
| D22 | Agent containers hold no AWS credentials by default; deploys go through CI | A permission-skipping agent with a member's Identity Center session has near-admin reach. Humans who want a local CLI loop opt in knowingly. (Round 2.) |
| D23 | Team repo defaults to public | Free Actions minutes, free Codespaces prebuilds, and it matches the MIT default. Private is the opt-out. (Round 2.) |
| D24 | Docker box is t4g.large, previews capped at three per box, hourly `pg_dump` to S3 | 2 GB won't hold a demo stack plus per-PR Postgres instances. Backups because agents delete things. (Round 2.) |
| D25 | Principles are soft rules steered early (SessionStart injection, skills, structural defaults), checked softly at PR time, with every knowing exception recorded as **rule feedback** in one place: a `Rule-feedback:` PR line, a `rule-feedback` issue label, and a pinned issue grouped by rule | Erik: exceptions are allowed but must be visible in one place so the group can decide to reverse, accept, or change the rule. Framed as feedback on rules, never on people (teammate review). Only dollar- and safety-consequential checks block. |
| D26 | No click-ops beyond the one-time account bootstrap; Terraform default tags make untagged resources visible as drift | Everything reproducible lives in code; the runbook's console steps are the documented exception. |
| D27 | Shared skills and a SessionStart hook ship as a kit plugin, vendored into the team repo and seeded into the dev container image at user scope; the hook injects a condensed copy of the repo's `PRINCIPLES.md`; `CLAUDE.md` and `AGENTS.md` carry a two-line pointer for clients without the plugin | A user-scope plugin follows the person into any repo opened in the container. Seeding at image build is the documented container path; a per-repo plugin pin would add a trust dialog. No PreToolUse hook: `ask` becomes `allow` under permission-skipping and `deny` in headless runs. (v2.2, mechanism review.) |
| D28 | Canonical `PRINCIPLES.md`, `CODEOWNERS`, and a zero-approval code-owner ruleset live in the **team repo**; two or three owners named at idea lock, any one approves, owner-authored changes need another owner. `CODEOWNERS` names only the three rules files (`PRINCIPLES.md`, `PRINCIPLES-EXTENDED.md`, `CODEOWNERS` itself); everything else self-merges once `make check` and shutdown coverage pass | The rules are the team's, not the kit's, so they live where the team works; the kit supplies the first draft. (v2.2, reasoning updated in v2.4 now that the kit is public.) The owned set shrank to just the rules files in v2.6: rules edits are rare and are a team agreement, so a second reviewer costs little; everything else (workflows, dev container, plugin, `Makefile`, compose files) changes often mid-event and a second-owner gate there added little security given every member's near-admin AWS access. |
| D29 | Prize split, license and IP, and repo visibility are spoken yes/no questions at idea lock, recorded per person; everything else stays defaults-first | Silence-as-consent is wrong for money and IP. (Teammate review.) |
| D30 | Erik's tie-break covers kit infrastructure only (account, gateway, spend); the team decides application architecture; the product owner decides product | The teammate reads "Erik on infra" plus a veto over the rules as a platform owner's terms, not a team agreement. |
| D31 | Two OIDC roles: `deploy` trusted only from `main`, `preview` trusted from any branch with preview-only permissions | A repo collaborator with write access could otherwise assume the near-admin deploy role from any branch. |
| D32 | The kit repo is public under MIT; account IDs, zone IDs, and other environment values live in gitignored `tfvars` and SSM, not in committed files | Erik wants teammates and other teams to be able to use it; competition is cooperative. Public also removes every "teammates can't reach the kit" problem. (v2.3.) |
| D34 | Core principle `P-public`: everything in the repos, issues, PRs, and the kit site is public and permanent; no keys, no contact details, nothing personal about anyone; a leaked key is an incident to announce and rotate, not hide | Public-exposure review: the text is safe to publish, the CI and preview machinery and teammates' personal data are where harm would come from. (v2.4.) |
| D35 | CI hardening for a public repo with OIDC: no `pull_request_target` or `workflow_run`, `permissions: {}` by default with `id-token: write` only in deploy and preview jobs, deploy-role trust pinned to the deploy workflow file on a push to `main`, third-party actions pinned by SHA, approval required for workflows from all external contributors. The kit's own Terraform (`infra/org`, `infra/platform`, the recipes) never runs in public CI. From v2.6 the team stack does (D39), under log rules: the plan body never reaches a log or a comment, only resource addresses, counts, and error lines; every printed line passes the 12-digit mask; Terraform outputs are never printed; the plan JSON never leaves the runner. `CODEOWNERS` review is not part of this hardening: it gates only the three rules files, so the workflow templates themselves (along with `.devcontainer/`, the vendored plugin, `Makefile`, and compose files) self-merge behind `make check`, shutdown coverage, and the deterministic guards above (fork skip, `gitleaks`, per-key budgets, one-step rotation, the reviewer ranking CI and secrets changes as a finding) | Both repos are public and forkable; "no forks" was a false premise. A near-admin role must not be reachable from untrusted input. (v2.4; amended v2.6.) |
| D36 | Preview isolation on the Docker box: IMDSv2 with hop limit 1, the preview SSM document rejects privileged and host-namespace compose settings and out-of-project bind mounts, the gateway master key is injected only into the LiteLLM container | A preview is arbitrary code from a teammate running on the box that holds the gateway and its keys. (v2.4.) |
| D37 | Teammates' contact details and idea-lock answers never enter any repo: the sign-up sheet stays on paper, idea-lock answers live in a private Discord channel and are deleted a week after the retro | The team repo is public and permanent. (v2.4.) |
| D38 | Two more extended entries: `P-comms` (agents get a path into whatever channel the team picks; the checklist notes which tools agents can use easily) and `P-who` (name the entity you address; "you", "I", "the AI", "the system" are ambiguous between humans and agents) | Erik, final review. |
| D33 | Principles are two-tier: a five-line core everyone reads, an extended file with the why, the practices, and the mechanics, and an AI consistency review on any change to either | A stranger should be able to read the rules in a minute and trust that the long version hides nothing. Everyone has an equal say; Erik only wrote the first draft. (v2.3.) |
| D39 | **Team infrastructure by PR, applied on merge (Should tier).** Agents, still without AWS credentials (D22), change the team's AWS infrastructure by editing Terraform in the team repo's `infra/team/` and opening a PR. `terraform-plan.yml` posts one PR comment with resource addresses and add/change/destroy counts, never the plan body, through the 12-digit mask, using a read-only role (`xenia-plan-<owner>-<repo>`); it skips fork PRs. On merge to `main`, `terraform-apply.yml` plans again with the infra role (`xenia-infra-<owner>-<repo>`: AdministratorAccess, the guard-rail deny list, and an EC2 instance-type allow-list) and applies the saved plan. Any delete or replace stops the apply unless the merged PR carries the `destroy-ok` label, which anyone may add, the author included; the stop and any completed delete or replace are posted to the team channel. Applies are serialized; state is `team-<repo>.tfstate` in the kit's bucket and lock table. The kit's own stacks (`infra/org`, `infra/platform`, the recipes) stay manual | Erik wants agents to ship infrastructure without holding keys, the same way they ship code. A mandatory second approver would contradict C3 and P-two-gates (only `make check` and shutdown coverage block a merge); the guards that matter are mechanical: read-only plans on PRs, a label speed bump before anything is deleted, the instance-type allow-list, the deny list, the alerts, and a channel post that tells the whole team. (v2.6.) |
| D40 | **Access kill switch (Must tier).** `infra/org` enables the `SERVICE_CONTROL_POLICY` type on the organization root (no behaviour change: `FullAWSAccess` stays attached) and creates `xenia-lockdown`, unattached: deny `*` on `*` unless `aws:PrincipalArn` is Erik's admin Identity Center role (`arn:aws:iam::*:role/aws-reserved/sso.amazonaws.com/*AWSReservedSSO_admin_*`) `OrganizationAccountAccessRole` (`arn:aws:iam::*:role/OrganizationAccountAccessRole`, assumable only from the management account, so Erik has a second way in while locked if Identity Center misbehaves), or a kit box instance role (`xenia-docker-box`, `xenia-gpu-box`). The exemption patterns are safe because IAM reserves the `/aws-reserved/` path for service-created roles and the other names are guarded by the deny list. `scripts/lockdown.sh [--undo] [--dry-run]` attaches it to, or detaches it from, the member account, idempotently. It is deliberately separate from `shutdown.sh`: a leaked key wants access cut without stopping the boxes, and an overnight bill wants the boxes stopped without locking anyone out. Runbook 99 runs `shutdown.sh`, then `lockdown.sh`, then removes the group assignment | An attached SCP neutralises every identity in the member account at once, including sessions already issued: teammates' 12-hour console and CLI sessions, any agent running with one, and the `deploy`, `preview`, `plan`, and `infra` CI roles. Identity Center's reserved roles can't be edited in IAM, so a per-role deny can't revoke a teammate's live session; an SCP can. SCPs never apply to the management account, so Erik can always detach it from there. Erik accepted that teammates and CI get near-admin (the two PR-review callouts); this is the counterweight. (v2.6.) |
| D41 | Seventh core principle `P-simple`: build the simplest thing that works, from small pieces that each do one job, and nothing for a need nobody has yet; when the problem or the asked-for solution is more complex than the job needs, the agent says so and offers the simpler version before building, and the teammate decides. Extended entries: `P-simple/second-use` (small means few moving parts, not many files; a helper, layer, interface, or option waits for a second real use), `P-simple/moving-parts` (a new queue, cache, database, or worker gets one sentence in the PR on why the plain version fails), `P-simple/pushback` (a proposal, never a veto or a quiet cut). The bot's review lists unrequested complexity under probable rule exceptions | Erik, 2026-09-26: simpler pieces make later changes quicker and safer, even if they take longer to find. Over-engineering (extra files, needless abstractions, unrequested flexibility) is a known agent tendency, and Anthropic's prompting guide recommends saying so explicitly. Small, scoped pieces also suit the shared model, which is weaker on long multi-step runs. "Small components" alone would invite the opposite failure, many thin files and layers, hence the few-moving-parts definition. Pushback stays a proposal so it can't turn into an agent quietly cutting scope. Advisory only: complexity is a judgement call, and P-two-gates keeps the merge gates at two. (v2.7.) |

## 3. Scope, in tiers

**Must (proven end to end by Friday night):**

- Organization, member account, Identity Center with the email-OTP setting, `hackathon` group and permission sets.
- Route 53 zone, certificates, GitHub OIDC deploy role, Terraform state.
- Docker box recipe with Caddy wildcard previews, Postgres, backups, `deploy-docker-box.yml`, `preview-up.yml`, `preview-down.yml`, `check.yml`.
- Static-site recipe used for the kit site (no per-PR previews).
- Model path: gateway on the Docker box, Bedrock Qwen backend Thursday morning, GPU box with vLLM as primary once quota lands, failover wired.
- Dev container (keyless template) with Claude Code and OpenCode configured against the gateway.
- `shutdown.sh`, `shutdown.d/`, `status.sh`, `shutdown-coverage.yml`, and the access kill switch `lockdown.sh` with its unattached SCP (D40).
- `pr-review.yml`, label-triggered.
- Kit plugin (skills `/pain`, `/rule-feedback`, `/notify`, `/doctor`, `/preview`, `/shutdown-entry`, `/demo-checklist`; SessionStart hook that injects a condensed `PRINCIPLES.md`), vendored into the team repo and seeded into the dev container image at user scope. PR template, `friction` and `rule-feedback` issue templates and labels, `CODEOWNERS`, and the code-owner ruleset in the team repo.
- Team kit markdown, kit site, QR flyer. Runbook. `onboard-teammate.sh`, `onboard-repo.sh`.

**Should (built and shipped; proven if Friday allows):**

- `contract-check.yml` (Redocly lint, `oasdiff`, generated types) and the `contracts/` template.
- `scripts/pain-review.sh` (manual), with the cron workflow as an optional extra.
- Team-repo templates: `CLAUDE.md`, `CONTRIBUTING.md`, `Makefile` with `check`, `.claude/skills/`.
- GPU box health check and SMS alarm, `rollback.sh`, `restore.sh`.
- `dynamodb-table` recipe.
- Team infrastructure by PR, applied on merge (D39): `terraform-plan.yml`, `terraform-apply.yml`, the `xenia-plan-*` and `xenia-infra-*` roles, the `destroy-ok` label, and the `infra/examples/team-stack/` starter that becomes the team repo's `infra/team/`.

**Cut (documented under `docs/deferred/`, not built):** Lambda API recipe and its previews, per-PR static-site previews, CPU dev-box recipe, evals template, Schemathesis conformance, inventory cron, budget-to-Discord Lambda, Cost Anomaly Detection (no baseline in a new account), a PreToolUse click-ops hook (cut: it turns into `allow` under permission-skipping and `deny` in headless runs, and D22 already removes the credentials it would guard), a rendered `DEVIATIONS.md` (cut: a workflow can't commit to a protected `main` with the default token; replaced by the PR line, label, and pinned issue).

Out of scope entirely: application code, any opinion about the product, managed databases, Scenario A build-out, high availability.

## 4. Architecture overview

```
GoDaddy (tetl.ca, untouched)
  └─ NS: 26.cohack.tetl.ca ──► Route 53 zone (member account)
       ├─ 26.cohack.tetl.ca          ──► CloudFront + S3  (kit site; ACM cert in us-east-1)
       ├─ app.26.cohack.tetl.ca      ──► Docker box       (demo)
       ├─ *.box.26.cohack.tetl.ca    ──► Docker box       (pr-<n>.box previews; Caddy wildcard cert via DNS-01)
       └─ llm.26.cohack.tetl.ca      ──► Docker box       (Caddy ─► LiteLLM gateway)
                                                              ├─ primary:  vLLM on GPU box (us-east-1, reachable only from the box's IP)
                                                              └─ failover: Bedrock qwen.qwen3-coder-30b-a3b (us-east-1, instance role)

Personal AWS account (management)           Member account cohack-26 (all workloads)
  ├─ Organizations, consolidated billing      ├─ Route 53 zone, ACM cert (us-east-1)
  ├─ IAM Identity Center (org instance)       ├─ GitHub OIDC provider + deploy role (allowed_repos)
  │    ├─ erik: admin                         ├─ Terraform state bucket + lock table, SSM parameters, log groups, backup bucket
  │    └─ group hackathon: hackathon-dev      ├─ Docker box (ca-central-1, t4g.large): Caddy, compose, Postgres, LiteLLM
  ├─ AWS Budgets ─► SNS (email, SMS)          ├─ GPU box (us-east-1, g6e.xlarge): vLLM
  └─ GPU quota request (fallback location)    └─ Kit site (S3 + CloudFront)

GitHub (ert485/xenia-2026 = kit, public, MIT; team repo created Saturday, public by default)
  ├─ deploy-docker-box (OIDC), preview-up/down, check, shutdown-coverage, pr-review (label), publish-kit-site
  └─ friction issues ─► /pain skill, pain-review script
```

## 5. Accounts and isolation

- **Management account**: Erik's existing personal account. Runbook step 00 first confirms it is not already a member of another organization; if it is, stop and re-plan. Enable Organizations with all features, click the root-email verification link, and turn on **root access management** (in the **IAM console**, not Organizations: IAM, **Root access management**, **Enable**, both capabilities; if it shows as disabled, first enable trusted access for IAM under Organizations, **Services**) so the member account is created with no root credentials at all.
- **Member account** `cohack-26`, root email a plus-address on Erik's personal mailbox (value kept out of the repo), created from the console or with `aws organizations create-account`. Access from the management account via `OrganizationAccountAccessRole` for Terraform bootstrap only.
- **Identity Center**: organization instance in ca-central-1 in the management account. In **Settings, Authentication**, enable **Send email OTP for users created from API**; without it, users created by the onboarding script get no invitation and can't sign in. Groups and permission sets:
  - Erik: `admin` (AdministratorAccess) on both accounts.
  - Group `hackathon`: permission set `hackathon-dev` on the member account only, session duration 12 hours. Assignments are to the group, never to individuals. The group's assignment is removed at Sunday 12:00 by runbook step 99, so nobody keeps near-admin access after the event by accident.
  - Erik's own root user on the management account and his Identity Center user both use phishing-resistant MFA (a passkey or hardware key); the management account is the one holding the card.
- **`hackathon-dev`**: AdministratorAccess plus an inline deny. This is a guard rail against expensive mistakes, not a security boundary: an administrator can create a role without the deny. Erik reviewed and accepted this as intended (v2.6): teammates and CI deliberately get near-admin, and the counterweight is the access kill switch below, not a narrower permission set. The deny covers, and costs members no autonomy:
  - Org, billing, quota, and identity plumbing: `organizations:*`, `sso:*`, `sso-directory:*`, `budgets:*`, `ce:*`, `account:*`, `aws-portal:*`, `servicequotas:RequestServiceQuotaIncrease`.
  - Unbounded-cost purchases: `shield:CreateSubscription`, `route53domains:*`, `aws-marketplace:Subscribe`, `ec2:PurchaseReservedInstancesOffering`, `ec2:PurchaseHostReservation`, `savingsplans:*`.
  - Long-lived credentials: `iam:CreateUser`, `iam:CreateAccessKey`, `iam:CreateLoginProfile`. Roles are allowed.
  - Kit plumbing: deleting or modifying the Terraform state bucket, the OIDC provider, the deploy role, the hosted zone, the ACM certificates, and the backup bucket. `ssm:StartSession` on instances tagged `kit=true` (the Docker and GPU boxes), so the gateway's master key stays with Erik.
  - Regions: deny `aws:RequestedRegion` outside ca-central-1 and us-east-1, with the standard exemption for global services.
- **Onboarding**: `scripts/onboard-teammate.sh <email> <first> <last>` creates the Identity Center user, adds them to `hackathon`, issues their gateway key (section 10), and prints the start URL, the CLI profile snippet, and their key once. `scripts/offboard-teammate.sh <email>` reverses both.
- **Access kill switch (D40)**: `scripts/lockdown.sh` attaches the break-glass SCP `xenia-lockdown` to the member account, which denies every identity there everything, live sessions included, except Erik's admin role, `OrganizationAccountAccessRole`, and the two box roles (so the gateway, Bedrock failover, backups, and DNS-01 keep working). `scripts/lockdown.sh --undo` detaches it. Both run as `personal-admin` in the management account, which no SCP can touch. Use it for a leaked credential, a runaway agent, or a teammate who should lose access now rather than when their session expires.
- **After the event**: runbook 99 runs `scripts/shutdown.sh`, then `scripts/lockdown.sh`, then removes the `hackathon` group assignment; later `scripts/teardown.sh` destroys workloads and the runbook closes the member account from Organizations.

## 6. DNS and TLS

- Route 53 public hosted zone `26.cohack.tetl.ca` in the member account, created **Wednesday night** as soon as the `cohack` profile exists, so Erik can add the four NS records for host `26.cohack` at GoDaddy the same evening and certificate validation is off Thursday's critical path. No other tetl.ca record changes.
- ACM certificate in us-east-1 for `26.cohack.tetl.ca`, DNS-validated, for the kit site's CloudFront distribution. No other ACM certificates are needed in this scope.
- Docker box: Caddy built with the Route 53 DNS module issues **one** wildcard `*.box.26.cohack.tetl.ca` plus `app.` and `llm.` via DNS-01, so previews never mint new certificates and Let's Encrypt's 50-certificates-per-week limit on `tetl.ca` is never approached. The instance role may change only `_acme-challenge.*` records in the zone, enforced with the normalized-record-names condition.
- GPU box: no public hostname and no DNS role. It serves vLLM over TLS with a self-signed certificate that the gateway pins, on a port open only to the Docker box's Elastic IP.
- Hostnames: `26.cohack.tetl.ca` (kit site), `app.` (demo), `pr-<n>.box.` (previews), `llm.` (gateway). Any future static frontend gets `web.` on CloudFront with its own certificate entry.

## 7. Access and CI identity

- GitHub OIDC provider in the member account with two roles per allowed repo. `deploy` trusts only `repo:<owner>/<repo>:ref:refs/heads/main` and carries the broad permissions. `preview` trusts `repo:<owner>/<repo>:*` and may only run the preview SSM document on the Docker box and read its logs, so a branch workflow can't reach the rest of the account. Both repos are public and forkable, so the `deploy` trust is pinned further: GitHub's subject claim is customised to include the workflow file, and the role trusts only `deploy-docker-box.yml` on a push to `main`. Workflows from forks need approval from a maintainer before they run (set on the kit repo already; `onboard-repo.sh` sets it on the team repo). Saturday: add the team repo to `allowed_repos`, `terraform apply`, done.
- `scripts/onboard-repo.sh <owner/repo>` adds the repo to `allowed_repos`, applies, copies the workflow templates, dev container, the vendored kit plugin, `PRINCIPLES.md`, `CODEOWNERS`, the PR template, `CLAUDE.md` and `AGENTS.md` (repo facts plus a two-line pointer to `PRINCIPLES.md`), `CONTRIBUTING.md`, and `Makefile` into the repo, creates the `friction`, `rule-feedback`, `next-fix`, `review`, and `breaking-ok` labels (plus `destroy-ok` with D39), creates the pinned "Rule feedback" issue, applies the `main` ruleset (zero required approvals, code-owner review required, empty bypass list), enables push protection, and sets the repo secrets the workflows read (both role ARNs, gateway CI key). `offboard-teammate.sh` also removes a leaving member's write access and, if they were a code owner, edits `CODEOWNERS`.
- The `deploy` role has broad permissions inside the member account, bounded by the same deny list as `hackathon-dev`, plus SSM `SendCommand` to the Docker box. The `preview` role has only the preview document and log reads.
- **Subject claims are immutable for new repos.** GitHub gives repos created after 2026-07-15 an immutable OIDC subject: the repo segment is `repo:OWNER@OWNER_ID/REPO@REPO_ID`, not `repo:OWNER/REPO`, and it can't be turned off. Every trust policy is therefore written against a per-repo prefix read from `gh api repos/<owner>/<repo>/actions/oidc/customization/sub` (the `.sub_claim_prefix` field) and kept in `infra/platform/oidc-sub-prefixes.auto.tfvars.json`; `onboard-repo.sh` writes it. The numeric IDs are public GitHub IDs, not secrets. Where this section writes `repo:<owner>/<repo>`, read that prefix.
- **Two more roles per allowed repo, for team infrastructure (D39, Should tier).** `plan` (`xenia-plan-<owner>-<repo>`) trusts `<prefix>:*` but only for the job workflow `terraform-plan.yml`, and carries `ReadOnlyAccess` plus the deny list, plus denies on `ssm:GetParameter*` and `ssm:GetParametersByPath` under `/xenia/*`, on `secretsmanager:GetSecretValue`, and on object reads in the backup bucket. `infra` (`xenia-infra-<owner>-<repo>`) trusts only `terraform-apply.yml` on `main`, and carries AdministratorAccess, the deny list, and an EC2 instance-type allow-list: launching or resizing any type outside one variable is denied (small-to-large `t4g` and `t3` plus three `m7g` sizes by default; GPU and big families denied), and so are the launch paths IAM can't inspect for instance type (launch templates, EC2 Fleet, Spot Fleet, Spot requests). The allow-list applies to this role only, not to `hackathon-dev` or `deploy`. A bucket policy on the state bucket keeps both roles to their own `team-<repo>.tfstate` plus read-only `platform.tfstate` (which the team stack reads through `terraform_remote_state`), so a PR's plan can't read the kit's other state files. The same policy denies the `hackathon-dev` role reads of `org.tfstate`, which holds Erik's alert email and phone number; teammates otherwise have AdministratorAccess on the bucket. The deny list stops any guarded role from editing either role. As with `deploy`, this is a guard rail, not a boundary: an administrator role can create a new role without the deny.
- **Default for agents: no AWS credentials in the container.** Agents ship by pushing; CI deploys. A human who wants a local CLI or console loop logs in with Identity Center on their own machine, knowing that any agent they run with that session inherits near-admin reach. The onboarding doc says this in one sentence.
- Terraform for the kit's stacks runs from Erik's machine only (`personal-admin` and `cohack` Identity Center profiles); the deploy role runs deploys, not Terraform. The team's own stack runs from CI with the `plan` and `infra` roles (D39). State in S3 with a DynamoDB lock table, bootstrapped by `scripts/bootstrap.sh`.

## 8. Cost visibility and the kill switch

### Alerts

- AWS Budgets in the management account, filtered to the member account: actual-cost notifications at $10, $25, $50, $100, $150 (variable `alert_tiers`) plus a forecast notification at $150. Delivery via SNS to email and SMS. SMS needs the destination number verified in the SNS sandbox first (runbook step 00). The $10 notification is expected to fire Thursday; that's the test that alerts work.
- `scripts/cost.sh` prints month-to-date and yesterday's spend by service from Cost Explorer.
- `scripts/status.sh` lists, in under a minute: running instances with type and uptime, gateway health and which backend is active, open previews, and the last backup time. If the Should-tier Resource Explorer view is built, it also lists resources with no tags at all (the Tagging API can't see never-tagged resources; Resource Explorer's `tag:none` can), which is the click-ops signal. This replaces the inventory cron.

### Kill switch

- Two `shutdown.d/` directories: the kit repo's holds entries for kit infrastructure (GPU box, Docker box, previews); the team repo's holds entries for anything the team adds. `scripts/shutdown.sh [--dry-run]` in the kit runs its own entries and then the team repo's (path from the `team_repo` variable). Each entry is an idempotent script with a header stating what it stops, who added it, and how to bring it back. `scripts/startup.sh` reverses the reversible ones.
- Stopping the GPU box is not an outage: the gateway fails over to Bedrock automatically.
- **Access is a separate switch** (D40): `shutdown.sh` stops spend and leaves access alone; `scripts/lockdown.sh` cuts access and leaves the boxes running. A leaked key calls for the second, an overnight bill for the first, the event's end for both (shutdown first).
- `SHUTDOWN.md` is rendered by CI from the headers in each repo.
- **Policy (charter and CONTRIBUTING)**: a PR that adds or changes something billable must either touch that repo's `shutdown.d/` or contain the line `Shutdown: none needed because <reason>` in its body.
- **CI check `shutdown-coverage.yml` (blocking, in both repos)**: if the diff touches `infra/**`, `.github/workflows/deploy*`, or any compose file, require one of the two above; also `bash -n`, `shellcheck`, and a dry run.

### Honest limits

Budgets evaluate on billing data that lags several hours. Alerts are a smoke detector, not a breaker. The fixed-price boxes, `status.sh`, and automatic failover are what keep the weekend predictable.

## 9. Deploy recipes and preview environments

Each recipe is a Terraform module under `infra/recipes/`, a workflow template under `templates/workflows/`, and a hello-world example under `infra/examples/` deployed before Saturday to prove the path.

| Recipe | Tier | What it is | URL | Previews | Idle cost |
|---|---|---|---|---|---|
| `docker-box` | Must | One EC2 `t4g.large` (4 vCPU, 8 GB, variable) in ca-central-1 with Docker Compose behind Caddy; Postgres in compose with a persistent volume; SSM access only, no inbound SSH; also hosts the LLM gateway | `app.26.cohack.tetl.ca` | Per-PR compose project on the same box, Caddy routes `pr-<n>.box.…`; capped at three previews, oldest evicted | about $1.60/day |
| `static-site` | Must (kit site) | S3 + CloudFront + us-east-1 cert; reusable for a static frontend at `web.` | `26.cohack.tetl.ca` | none (use the box) | pennies |
| `dynamodb-table` | Should | On-demand table with TTL; PITR and deletion protection on for the demo table, off for previews | n/a | table-name suffix | free tier |
| `lambda-api` | Cut | documented in `docs/deferred/` | | | |

- Preview lifecycle: `preview-up.yml` on PR open or sync deploys over SSM and comments the URL; `preview-down.yml` on PR close removes it. `shutdown.d/30-previews.sh` removes all previews.
- Preview isolation (D36): a preview is arbitrary code from a teammate on the same box as the gateway. The box runs IMDSv2 with a hop limit of 1 so containers can't reach instance credentials; the preview SSM document refuses compose files that use `privileged`, `network_mode: host`, `pid: host`, the Docker socket, or bind mounts outside the project directory; previews get their own Docker network with no route to the gateway's internal ports; the gateway master key is injected only into the LiteLLM container.
- Main branch is the demo. Deploys keep the previous image tag; `scripts/rollback.sh` is one command.
- Backups: hourly `pg_dump` of every Postgres in compose to a versioned S3 bucket, an EBS snapshot at the 03:00 scope freeze, and `scripts/restore.sh <dump>`.
- Images: the box is arm64. Workflows build with `docker buildx` for `linux/arm64`, or build on the box over SSM when a base image has no arm64 variant.
- Managed Postgres (Neon, Supabase) and bring-your-own hosting (Vercel and friends) are documented as no-penalty alternatives in the onboarding doc. The kit is there to remove friction, not to mandate a host.

## 10. AI coding layer (Scenario B)

### Backends

| Backend | Where | Role | Cost |
|---|---|---|---|
| vLLM on the GPU box | `g6e.xlarge` (4 vCPU, 32 GiB, one NVIDIA L40S 48 GB), us-east-1, Deep Learning Base AMI, 200 GB gp3 volume for weights, snapshotted Friday | Primary once the quota lands | about $1.86/hour while running |
| Bedrock `qwen.qwen3-coder-30b-a3b-v1:0` | Serverless, us-east-1, called from the gateway with the Docker box's instance role | Bring-up backend Thursday morning; automatic failover afterwards; the only backend if the quota never lands | per token, cents to a few dollars for the weekend at fallback usage |

The Bedrock model is the same model family as the GPU default, so members see one model name either way. Bedrock's serverless quota is the standard token-per-minute quota, checked Thursday with the first calls.

### GPU box

- Only one port open, to the Docker box's Elastic IP, serving vLLM over TLS with a self-signed certificate and a bearer token the gateway holds. No public hostname, no DNS role. Admin via SSM.
- `scripts/gpu.sh start|stop|status|logs`. Stop is `shutdown.d/10-gpu-box.sh`; failover covers the gap.
- Docker `restart: unless-stopped` on vLLM, a watchdog that restarts the container on a failed `/health`, and CloudWatch agent for GPU memory.
- **Quota**: `Running On-Demand G and VT instances` (code `L-DB2E81BA`) defaults to 0 vCPUs. Runbook step 01 requests 8 vCPUs in us-east-1 in the **management account first** (established account, best odds) and in the member account second. If the management account is approved first, the GPU box runs there: it only needs the security-group rule and the token, nothing else in the design depends on which account hosts it. If neither lands by Friday noon, Bedrock carries the weekend, and a rented GPU from Lambda Cloud or RunPod running the same compose file is the optional upgrade.

### Models

| Role | Default | Why | Alternative |
|---|---|---|---|
| Team coder | Qwen3-Coder-30B-A3B-Instruct, INT4 (AWQ) | Mixture-of-experts with 3B active parameters: fast, good tool use, well supported by vLLM, and the same model Bedrock serves. INT4 leaves ~24 GB for cache, about 500k aggregate tokens. | Official FP8 build: better quality, ~10 GB cache, ~200k aggregate tokens. One flag. |
| Fallback / light | gpt-oss-20b (MXFP4) | 13 GB, enormous cache headroom; the viable model on a 24 GB card if the box must stay in Canada. Its MXFP4 path on Ada GPUs in vLLM needs a Thursday test. | Any small coder with a vLLM tool parser. |

Weights are pulled onto the EBS volume Friday. The INT4 repository is chosen Friday from currently maintained vLLM-compatible quantizations and pinned in `infra/recipes/gpu-box/models.yaml`, together with each model's tool-call parser: `qwen3_xml` for Qwen3-Coder per current vLLM docs (`qwen3_coder` is the older name; test both), `openai` for gpt-oss. Shared vLLM flags to start: `--max-model-len 131072 --kv-cache-dtype fp8 --gpu-memory-utilization 0.92 --enable-auto-tool-choice --max-num-seqs <from the load test>`. Prefix caching is on by default; expect per-session cache hits, not team-wide ones, since Claude Code's per-session environment block and `CLAUDE.md` content sit inside the prefix.

### Gateway

- LiteLLM behind Caddy on the Docker box at `llm.26.cohack.tetl.ca`. Exposes Anthropic's `/v1/messages` and OpenAI's `/v1/chat/completions`, translating to either backend. `drop_params: true` so Anthropic-only fields (thinking, cache control, betas) are dropped rather than rejected. `fallbacks` from the vLLM deployment to the Bedrock deployment. `count_tokens` is optional; Claude Code estimates when it's missing.
- Model aliases: `qwen3-coder`, plus `opus`, `sonnet`, `haiku`, `fable`, and a catch-all for any `claude-*` ID, all routed to the team coder. Remapping `haiku` to gpt-oss-20b later is one line.
- Per-member virtual keys with usage counters and per-key rate and parallel-request limits, backed by the box's Postgres. Issued by `onboard-teammate.sh`, revoked by the offboard script. One CI key for `pr-review.yml`, stored as a repo secret.
- **Hardening** (a malicious LiteLLM release reached PyPI in March 2026): image pinned by digest with the reason recorded; Caddy forwards only `/v1/messages*`, `/v1/chat/completions`, `/v1/models`, and `/health`, so the admin UI and key-management routes are never public; the master key lives in SSM Parameter Store and is injected at start, never in compose; SSE keep-alive relayed so Claude Code's 300-second silent-stream watchdog doesn't abort queued requests. Every virtual key, including the CI key, carries a LiteLLM `max_budget`, and a Bedrock budget caps failover spend, so a leaked key is bounded. `scripts/rotate-key.sh <member|ci>` revokes and reissues in one step and updates the repo secret for the CI key. Keys are delivered by direct message, never in a channel.
- Route 53 health check on `llm…/health` alarming to SNS with SMS to Erik and one named night-shift teammate.

### Clients

- **Claude Code** in the dev container. The committed template `.devcontainer/ai.env` is keyless; each member's key goes in a gitignored `ai.local.env` or a Codespaces user secret. Settings:
  - `ANTHROPIC_BASE_URL=https://llm.26.cohack.tetl.ca`, `ANTHROPIC_AUTH_TOKEN` from the local file
  - `ANTHROPIC_MODEL=qwen3-coder` and `ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU,FABLE}_MODEL=qwen3-coder`
  - `CLAUDE_CODE_MAX_CONTEXT_TOKENS=110000` (vLLM's 131072 minus output budget and margin; Claude Code otherwise assumes 200k for an unknown ID and compacts too late) and `CLAUDE_CODE_MAX_OUTPUT_TOKENS=16000` (also Bedrock Qwen's maximum)
  - `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`; settings `skipWebFetchPreflight: true`
  - The supported-capabilities variables from v1 are gone: they have no effect behind a gateway. Claude Code sends a thinking block for unknown IDs and retries without it when rejected; that path is tested Thursday.
  - Web search is unavailable (server-side tool); WebFetch works.
- **OpenCode** config pointing at the gateway's OpenAI endpoint with the same key, for anyone who prefers it or if Claude Code misbehaves with the model.
- Members with their own paid Claude, Cursor, or other subscription may use them. The charter's rule is about credentials (section 7), not tools.

### What this is and isn't

Claude Code's gateway mode is a documented configuration surface. Anthropic documents it for corporate proxies in front of Claude, not for other models, so problems on this path are ours. Claude Code's prompts are tuned for Claude; expect an open model to be less reliable on long multi-step tasks and to need the occasional nudge. The GPU's fixed cost is really a fixed throughput: agents share one GPU and queue under load. Levers if that bites, in order: INT4 weights (default already), letting more traffic spill to Bedrock, a second identical box behind the gateway (same recipe, ~20 minutes), and finally Scenario A.

### Capacity reference (L40S 48 GB, ~43 GB usable)

| Weights | Cache pool | Aggregate tokens (FP8 cache) | Realistic |
|---|---|---|---|
| Qwen3-Coder-30B INT4 (~17 GB) | ~24 GB | ~500k | 4 agents at ~110k |
| Qwen3-Coder-30B FP8 (~31 GB) | ~10 GB | ~200k | 4 at ~50k or 2 at ~100k |
| gpt-oss-20b MXFP4 (~13 GB) | ~28 GB | >1M | never the constraint |

## 11. Dev sandboxes

- `.devcontainer/` in the kit, copied into the team repo by `onboard-repo.sh`: based on Anthropic's reference dev container with the default-deny egress firewall, allow-listed by explicit hostname for GitHub, npm, PyPI, `llm.26.cohack.tetl.ca`, `app.26.cohack.tetl.ca`, `*.box.` previews, and the team channel's API (Discord by default), with the resolver re-run on a timer because the reference script resolves once at start. Preinstalled: Claude Code (pinned), OpenCode, AWS CLI, Terraform, Node 22, Python 3.12, `gh`, Docker CLI, and the kit plugin seeded at user scope during the image build with `CLAUDE_CODE_PLUGIN_SEED_DIR` from the copy vendored in the repo, kept outside `~/.claude` because the reference container mounts a volume there. Its skills and SessionStart hook are then present in every repo opened inside the container. Seed installs never auto-update: a plugin change needs `claude plugin update` or an image rebuild. Rule text changes need neither, because the hook reads `PRINCIPLES.md` from the open repo.
- The image is prebuilt to GHCR and Codespaces prebuilds are enabled, so venue Wi-Fi never gates the first session.
- Runs two ways unchanged: Docker Desktop on a laptop, or GitHub Codespaces on each member's free hours. The CPU dev-box recipe is cut; a member without Docker or a capable laptop uses Codespaces.
- No AWS credentials inside the container by default (section 7). Permission-skipping (`--dangerously-skip-permissions` or auto mode) is allowed only inside the container, and the charter says so.
- A Python project gets the same treatment: `make check` runs `ruff`, `mypy`, and `pytest`; contract types come from `datamodel-code-generator` instead of `openapi-typescript`.
- **What's already inside versus what a teammate brings.** Inside the container: every tool above, the plugin, the gateway configuration, and the repo. A teammate brings exactly three things: a GitHub account with access to the team repo (Codespaces signs `gh` and git in automatically; a local container needs `gh auth login` once and a git identity), the gateway key from their direct message, and the Discord invite. Everything else is optional and documented in onboarding as tie-ins: their own Claude, Cursor, or other AI subscription (a second env profile switches Claude Code from the gateway to their own login and back), Identity Center if they want the console or a local CLI loop, a dotfiles repo (Codespaces applies it automatically; the local container runs it from `postCreateCommand`), VS Code Settings Sync, a Hugging Face token only if a gated model is chosen, and accounts for bring-your-own hosting such as Vercel or Supabase. A `/doctor` skill (and `scripts/doctor.sh`) checks the lot in thirty seconds: `gh` authenticated, git identity set, gateway reachable with the key, Docker working, `make check` passing on the template, Discord webhook reachable, and prints a green or red list.

## 12. CI workflows (templates copied into the team repo)

| Workflow | Tier | Trigger | Blocking? | What it does |
|---|---|---|---|---|
| `deploy-docker-box.yml` | Must | push to main | n/a | Assume deploy role via OIDC, build arm64 image, deploy over SSM to the demo hostname |
| `preview-up.yml` / `preview-down.yml` | Must | PR open/sync/close | no | Preview lifecycle, URL comment |
| `check.yml` | Must | PR | **yes** | `make check`: typecheck, lint, unit tests; identical to the local target |
| `shutdown-coverage.yml` | Must | PR | **yes** | Section 8 policy check, shellcheck, dry run |
| `pr-review.yml` | Must | PR labelled `review`, or `ready_for_review`; automatically on any change to `PRINCIPLES*.md` (consistency mode) | no (advisory) | Headless Claude Code on a fresh runner via the gateway's CI key: reads the diff, `PRINCIPLES.md`, and the shutdown policy first, then finds every consumer of anything the diff changed, reads those call sites, runs `make check`, posts one ranked comment. When it sees a probable rule exception it proposes a copy-pasteable `Rule-feedback:` line. `--max-turns`, `timeout-minutes: 15`, `concurrency: cancel-in-progress`. |
| `publish-kit-site.yml` | Must | push to main (kit repo) | no | Renders `team-kit/` and `runbook/` to the apex site |
| `render-shutdown-md.yml` | Must | push to main | no | Regenerates `SHUTDOWN.md` from `shutdown.d/` headers |
| `pr-template-check.yml` | Should | PR open/sync | no | Comments once if the PR body lacks the `Rule-feedback:` or `Shutdown:` line from the template; never blocks |
| `contract-check.yml` | Should | PR touching `contracts/**` | **yes** | Redocly lint, regenerate types and fail if stale, `oasdiff` breaking-change detection; `breaking-ok` label overrides |
| `terraform-plan.yml` | Should | PR touching the team Terraform folder (default `infra/team/**`), same-repo PRs only | no (advisory) | Assume the read-only `plan` role, `terraform plan -lock=false`, post or update **one** comment with resource addresses and add/change/destroy counts (never the plan body), masked. A separate job with no OIDC relays the comment; when the plan has any delete or replace it also posts once to the team channel through `DISCORD_WEBHOOK_URL` (D39) |
| `terraform-apply.yml` | Should | push to main touching the same folder; re-run by hand after `destroy-ok` | n/a | Assume the `infra` role, plan, and stop if the plan deletes or replaces anything unless the merged PR carries `destroy-ok`; otherwise apply the saved plan. Output masked, Terraform outputs never printed, one apply at a time. Posts to the team channel when it stops at the gate (PR link, counts, the delete and replace addresses, "add destroy-ok to proceed") and when an apply that deleted or replaced something completes; skips the post with a log line if the webhook secret is unset |
| `pain-review.yml` | Should | manual; optional cron `0 */4 * * *` UTC during the event | no | Runs `scripts/pain-review.sh`: reads open `friction` issues and all `Rule-feedback:` lines from merged PR bodies plus `rule-feedback` issues, clusters, scores accumulated pain, updates the pinned "Rule feedback" issue grouped by rule with counts, posts one prioritised recommendation (fix, or for a rule: keep, change, reverse), opens a `next-fix` issue |
| `conformance.yml`, `evals.yml`, `inventory.yml` | Cut | | | documented in `docs/deferred/` |

Workflow hardening (D35), applied to every template: `permissions: {}` at the top with `id-token: write` granted only inside the deploy and preview jobs and the team Terraform plan and apply jobs; no `pull_request_target` and no `workflow_run`; third-party actions pinned by commit SHA; a `gitleaks` step in `check.yml` with a custom rule for LiteLLM `sk-` keys, and the same rule as a pre-commit hook in the dev container; the account ID masked with `::add-mask::` wherever a role ARN could print; `publish-kit-site.yml` fails the build if the rendered HTML contains a 12-digit number, an `awsapps.com` URL, a hosted-zone ID, an IPv4 address, a phone-number pattern, or an email not on a short allow-list. The kit's Terraform never runs in public CI; the team stack's plan and apply do (D39), and print only resource addresses, counts, and error lines, all masked, never the plan body or Terraform outputs. The reviewer is split into three jobs: `make check` runs with no secrets and publishes its output as an artifact; the agent runs with the full PR checkout, the diff, `PRINCIPLES.md`, the check output, and read-only tools (it can read any file and grep the whole repo, it just can't write, call `gh`, or see any secret other than the gateway CI key), and is skipped when the PR's head repo isn't the base repo; a third job with the write token relays the comment text. The agent's context is not reduced; only what it can *do* is. There is deliberately no separate "malicious intent" pre-review by another model: an intent classifier is itself injectable, and the deterministic guards do the real work (fork skip, collaborators-only interaction limits, `gitleaks`, per-key spend budgets and one-step rotation). `CODEOWNERS` owns only the rules files (`PRINCIPLES.md`, `PRINCIPLES-EXTENDED.md`, `CODEOWNERS` itself), not the blast-radius paths: `.github/workflows/`, `.devcontainer/`, the vendored plugin, `Makefile`, and compose files self-merge once `make check` and shutdown coverage pass (Erik's decision, v2.6 amendment). Rules edits are rare and a team agreement, worth a second reviewer; workflow and dev-container edits happen often mid-event as agents fix CI, and a second-owner gate there added little given every member's near-admin AWS access — the residual risk of an agent tricked into leaking the gateway CI key or the Discord webhook is what the budgets, rotation, `gitleaks`, fork skip, and the reviewer's CI/secrets-change ranking are for. The reviewer's prompt does ask it to rank, as a finding, any change that alters CI, secrets handling, or instructions to agents, which is the useful part of an intent check without a second job. During the event, the team repo's interaction limits are set to collaborators-only, so `pain-review.sh` reads issues only from people on the team. Erik accepted the two PR-review callouts on this design as intended (v2.6): the `deploy` role (and, with D39, the `infra` role) is near-admin, and anyone with write access to the team repo can reach it by merging to `main`; the counterweight is `scripts/lockdown.sh` (D40), which cuts every CI role and every teammate session at once.

Actions minutes: a private repo on a personal plan gets 2,000 free minutes a month and bills arm64 runners, so the team repo defaults to public. If the team insists on private, `onboard-repo.sh` can register the Docker box as a self-hosted runner instead. All crons are written in UTC with the CST time in a comment.

Contracts: the CONTRIBUTING default is one repo, services as folders, shared contracts in `contracts/` as an OpenAPI file plus JSON Schemas for events, with types generated from them so consumers break at compile time, and runtime validation at boundaries so agent-written mismatches fail loudly. The reviewer checks a change against its own service plus `contracts/`, and greps for contract identifiers across services. It cannot prove behaviour; `check.yml` and the preview health check carry that. Default on when an API exists; a server-rendered monolith skips `contracts/` and the contract workflow.

## 13. Team kit (`team-kit/`, copied into the team repo by `onboard-repo.sh`)

Rules for every page, from the teammate review: written for a peer, not for the author; no implementation notes on team-facing pages (those stay in this spec); one decision per numbered row so "name the line" is possible; a five-line TL;DR at the top of the kit site; and the model disclosure as the first line of onboarding and of the principles: *"Our shared model is an open 30B coder through our gateway. Fine for scoped tasks, weaker on long multi-step runs. Your own Claude, Cursor, or other subscription is welcome."*

Defaults-first (a table with **Default**, **Why**, **Disagree? name the line**) is used for logistics. It is **not** used for money, IP, or roles: those are asked aloud at idea lock and recorded per person (D29). A one-person team skips the charter and keeps the timeline and demo script.

| Doc | Purpose | Notes |
|---|---|---|
| `PRINCIPLES.md` | The **core**: seven lines a stranger reads in a minute | Canonical copy in the team repo root, owned via `CODEOWNERS`. First line: everyone on the team has an equal say in these; Erik wrote the first draft. |
| `PRINCIPLES-EXTENDED.md` | The why behind each core line, the practices, and the mechanics | Every entry names the core line it serves. Same ownership. An AI consistency review runs on any change to either file, and also flags ambiguous pronouns (P-who). |
| `01-about-me.md` | Card for meeting people: what Erik brings, wants, and won't do | filled in by Erik |
| `02-idea-lock-checklist.md` | Ten minutes, spoken, one line recorded per person **in a private Discord channel, never in a repo**, deleted a week after the retro | Stack (TypeScript or Python; asked, not defaulted). Prize split (default: equal among everyone registered at idea lock; leaving early keeps the share if you say goodbye in Discord). License (default MIT, co-owned) and an IP confirmation from each person that they're free to contribute, with a note that students and employees may be bound by a school or employer policy. Repo public (default yes). Product owner. Two or three owners of `PRINCIPLES.md`. Area ownership. Night-shift slots from the sign-up sheet. Team channel (default Discord), with the note on which options agents can use easily (P-comms). |
| `03-idea-rubric.md` | Score ideas Saturday morning | Weights: demoable in 20h 40%, judge appeal 30%, team excitement 20%, novelty 10%. Two-round vote, top idea wins, originator becomes product owner. |
| `04-team-charter.md` | How we work, one row per default (C1 to C14) | See the list below. |
| `05-24h-timeline.md` | Checkpoints | 09:00 kickoff; idea lock and the checklist by 10:30 or as the organizers' agenda allows; 11:30 architecture and recipe chosen; 13:00 walking skeleton on the real URL; 18:00 vertical slice plus five minutes on rule feedback; 03:00 scope freeze and EBS snapshot; 09:00 demo freeze; 10:00 rehearsal; 12:00 judging; retro after. Freeze reminders are posted by a bot. |
| `06-onboarding.md` | Cloud kit for teammates | Model disclosure first, then the core principles with the line that they're everyone's to change and Erik only filled in the initial state, then one plain sentence that the repo, issues, PRs, and the kit site are public and carry your GitHub name, then the cloud kit. Accept invite, open dev container, paste your key, run `claude`, push to a branch, get a preview URL. What's already in the sandbox and the three things you bring (GitHub access, your gateway key, the Discord invite), then optional tie-ins (own AI subscription toggle, Identity Center, dotfiles, Settings Sync, Hugging Face, bring-your-own hosting). `/doctor` first. The skills (`/pain`, `/rule-feedback`, `/notify`, `/doctor`, `/preview`, `/shutdown-entry`, `/demo-checklist`). Cheap mode, OpenCode fallback, Kiro note (students get 1,000 credits/month), bring-your-own-host path, Python path, reading box logs with `scripts/logs.sh`, where product API keys live. |
| `07-demo-script.md` | Demo template | 3 minutes, live on the real URL, one slide max, one drives one narrates, backup recording made at rehearsal. |
| `08-pitch-outline.md` | Judged-hackathon pitch | Problem, who has it, demo, what's real vs mocked, what's next. Uses common hackathon criteria; adjust on the day if the organizers announce theirs. |
| `09-team-signup-sheet.md` | Printable, **paper only** | Name, GitHub handle, email, skills, sleep plan (used by C8), phone. The sheet itself says: this stays on paper, nobody photographs or transcribes it, Erik shreds it after the retro. Each field says why it's collected. |
| `10-retro.md` | Sunday after judging | 10 minutes, three questions, plus the rule-feedback pile. |
| `11-join-flyer.md` + `print/` | Printable one-pager with the QR code to the kit site, plus the sign-up sheet and about-me card as PDFs | Printed Friday. |

### Charter defaults (`04-team-charter.md`, one row each)

- **C1** One repo, public (confirmed at idea lock), services as folders.
- **C2** Trunk-based. Small PRs, rebase before merge, shared files (schema, contracts, compose) have a named owner who merges changes to them.
- **C3** PRs required. Self-merge once CI is green. **No human review before merge.** Humans look at the preview URL. Add the `review` label when you want the bot's eyes.
- **C4** Definition of done for the demo path: deployed to `app.`, health check green, one happy path clicked by someone other than the author.
- **C5** Work is claimed by assigning yourself the GitHub issue. One area, one owner at a time.
- **C6** Tie-breaks: the product owner decides product questions; Erik decides kit infrastructure only (account, gateway, spend); the team decides application architecture; anything else gets a two-minute timer then a coin flip.
- **C7** Scope freeze at hour 18 (Sunday 03:00), demo freeze at hour 24 (09:00), rehearsal at 10:00.
- **C8** Night shift: at least one person awake in each three-hour block from 23:00 to 07:00, drawn from the sign-up sheet's sleep plans, named at idea lock.
- **C9** Formatter and linter settings are fixed at idea lock (the language's defaults) so agents don't fight over style.
- **C10** Product API keys live in SSM Parameter Store under the app's prefix, read at deploy time, never in the repo.
- **C11** Agents run inside the dev container; no AWS credentials in agent containers; own subscriptions welcome.
- **C12** Every PR that adds something billable carries a `shutdown.d` script or a `Shutdown: none needed because…` line. CI blocks otherwise.
- **C13** Contracts (when there is an API): OpenAPI plus event schemas in `contracts/`, types generated, boundaries validated.
- **C14** Comms: one Discord server (text and voice), tasks as GitHub issues. Agents post to the team channel through `/notify` (a webhook, stored as a secret). Contact details are exchanged in a private channel, never committed.
- **C15** Not legal advice. Nothing here about money or IP applies to you until you've said yes to it out loud at idea lock.

### Core principles (`PRINCIPLES.md`, seven lines, stable slugs)

Opens with: *"These are the team's rules. Everyone here has an equal say in them; Erik wrote the first draft. Change any line by PR, and one owner approves."*

- **P-ours** Everyone on the team has an equal say in these rules. Change any of it by PR, any one owner approves. Rule feedback is about rules: a recorded exception is never grounds to challenge the merged change or the teammate who made it; it only informs whether the team keeps the rule, changes it, or decides together to bring the code back in line.
- **P-fix-once** If it blocks you, fix it and say so in Discord. If it annoys you, `/pain` it. An agent ranks the pile every few hours; the top item gets fixed once, in shared tooling.
- **P-two-gates** Only `make check` and shutdown coverage block a merge. No human review before merge; humans look at the preview URL. The bot reviews on request.
- **P-simple** Build the simplest thing that works, from small pieces that each do one job, and nothing for a need nobody has yet. Agent: when the problem or the solution you were asked for looks more complex than the job needs, say so and offer the simpler version before building it; the teammate decides.
- **P-off-switch** Anything that costs money has an off switch, or says why it doesn't need one.
- **P-wheel** Product direction, irreversible actions, prize, and IP are human calls. Take over from an agent whenever you like; after fifteen minutes of looping with no progress, you must.
- **P-public** Everything here is public and permanent: no keys, no contact details, nothing personal about anyone in the repo, issues, PRs, or site. If a key leaks, say so in Discord and rotate it. No blame.

### Extended principles (`PRINCIPLES-EXTENDED.md`)

Each entry names the core line it serves and carries the why. A core-only reader should never be surprised by anything here; the consistency review below checks exactly that.

- Under **P-ours**: name the party you mean. "You", "I", "the AI", and "the system" are ambiguous when humans and agents share a channel, so every page, prompt, skill, issue template, and bot comment says which entity it addresses: *teammate* (a human on the team), *Erik*, *agent* (a Claude Code or OpenCode session a teammate is running), *bot* (the CI reviewer or the pain-review run), *gateway*, *model*, *kit* (**P-who**). Instructions for agents start with "Agent:"; the consistency review flags ambiguous pronouns in the team-kit pages. Changing P-ours itself or the owners takes two owners; the repo admin could edit the ruleset outside git, so that part is honour system; rule feedback goes in the `Rule-feedback:` PR line or `/rule-feedback`, and the pile is reviewed at 18:00 and at the retro.
- Under **P-fix-once**: sandboxed agents must be able to talk to the team as easily as teammates do, so whatever channel the team picks gets an agent path on day one (**P-comms**): the plugin ships `/notify <message>` for posting, the dev container's egress allow-list includes the channel's API, and pain-review posts its recommendation there too. The team picks the tool at idea lock; the checklist notes which options are easiest for agents (GitHub issues and PR comments: structured and already permitted; Discord: a webhook for posting in one line, a bot token if agents must also read; Slack: needs an app; anything phone-based: humans only). `CLAUDE.md` records every workaround so no agent rediscovers it (**P-fix-once/claude-md**); anything done twice becomes a skill, shared ones in the kit plugin, repo-specific ones in `.claude/skills/` (**P-skills**).
- Under **P-two-gates**: where there is an API, the spec is the source: generate types, validate at boundaries (**P-contracts**); if we ship an LLM feature and touch its prompt more than twice, the eval comes first (**P-evals**); a real URL by 13:00, everything after is iteration (**P-real-url**).
- Under **P-simple**: every file, layer, and option is something the next teammate or agent must understand before changing anything, often overnight and often on the shared model, which does best on scoped tasks; fewer moving parts make each later change quicker and safer, and that is worth a slower start. Small means few moving parts, not many files: split a piece when it does two jobs, not to make it shorter, and add a helper, layer, interface, or config option only when a second real use needs it (**P-simple/second-use**). A new moving part (a queue, a cache, a second database, a background worker) gets one sentence in the PR on why the plain version fails (**P-simple/moving-parts**). Pushing back is a proposal, not a veto: the agent names the simpler option and what it gives up, and the teammate picks; an agent never quietly drops part of what was asked, and "build it as asked" ends the discussion (**P-simple/pushback**). The bot's review lists unrequested complexity (an abstraction with one caller, an option nothing sets, a layer that only forwards calls) under probable rule exceptions; it advises and never blocks a merge.
- Under **P-off-switch**: if it can be code, it's code; console work gets a `Rule-feedback:` line so it can be imported or destroyed later (**P-no-clickops**).
- Under **P-wheel**: bots hold the clock; freeze reminders and pain ranking come from automation, not from whoever is most awake (**P-clock**). Deleting or replacing team infrastructure is an irreversible action, so the apply-on-merge workflow pauses on it until a teammate adds `destroy-ok` to the merged PR (D39). Agent: add `destroy-ok` (`gh pr edit <n> --add-label destroy-ok`) only after showing the teammate the delete and replace addresses from the plan comment and hearing them approve it in this session. An agent running with permissions skipped could add the label unasked; the label is a deliberate speed bump, not a lock (**P-wheel/destroy**).
- Under **P-public**: commit code, templates, and placeholders only; account IDs, zone IDs, keys, phones, and emails go in gitignored files, SSM, or Codespaces secrets, and push protection plus `gitleaks` catch the rest, with a false positive handled by a `Rule-feedback:` line rather than a bypass (**P-public/commit**); the kit site shows only what a stranger may see and its build fails on anything that looks like an ID, a portal URL, a phone, or an unlisted email (**P-public/site**); contact details stay on paper or in a private channel and are deleted a week after the retro (**P-public/contacts**); a leaked key is an incident, not a mistake to hide: post it, run `scripts/rotate-key.sh`, then fix the path that leaked it once (**P-public/leak**); agents may post summaries, diffs, in-repo paths, and redacted errors, and may never paste env vars, tokens, transcripts, or logs with emails or IPs into an issue or PR, and a human confirms before `/pain` or `/rule-feedback` posts (**P-public/agents**); no workflow runs with secrets or OIDC on content from outside the team (**P-public/ci**).

### Consistency review

Any PR touching `PRINCIPLES.md` or `PRINCIPLES-EXTENDED.md` runs the headless reviewer automatically (no label needed) in a consistency mode with three questions: does every extended entry trace to a core line; would a teammate who read only the core be surprised by anything in the extended file; do the two files contradict each other anywhere. It posts one advisory comment and proposes the core edit when something significant is hiding in the extended file. It also runs once on Friday over the initial files (section 17).

### How the rules reach people, and how exceptions stay visible

The team-facing version of this section is three lines in `PRINCIPLES-EXTENDED.md`: your Claude Code session in the container starts with the core rules injected; only `make check` and shutdown coverage block a merge; exceptions go in the `Rule-feedback:` line of your PR or in `/rule-feedback`, and we look at the pile at 18:00 and at the retro. The rest is mechanism, kept here.

- **Canonical copy and ownership.** `PRINCIPLES.md` and `PRINCIPLES-EXTENDED.md` in the team repo root. `CODEOWNERS` owns both and itself, and nothing else (v2.6 amendment: it no longer extends to `.github/workflows/`, `.devcontainer/`, the vendored plugin, `Makefile`, or compose files). A `main` ruleset requires zero approvals but requires code-owner review, so self-merge stays open everywhere except the rules files. Two or three owners are named at idea lock and given write access; any one approves; a PR authored by an owner needs a different owner. The bypass list is empty, and the page says plainly that the repo admin could edit the ruleset outside git, so that part is honour system.
- **Reaching agents.** The kit plugin's SessionStart hook injects the core (`PRINCIPLES.md`, about 200 tokens) plus the two skills and the path to the extended file. It reads the file from the open repo only when that repo is on the kit's `allowed_repos` list, and from the bundled copy otherwise, capped in size and with no network access, so a cloned third-party repo can't plant text in every session. The plugin is tagged per release and the README tells other teams to pin by commit. It fires on start, resume, clear, and compact. The plugin is seeded into the dev container image at user scope (section 11), so it's present in any repo opened there, including one created mid-event. `CLAUDE.md` and `AGENTS.md` in the team repo carry a two-line pointer to `PRINCIPLES.md` for OpenCode and for people on their own subscriptions outside the container. No PreToolUse hook (D27).
- **Recording exceptions.** The PR template carries `Rule-feedback: none` and `Shutdown:` lines. One regex, shared by the reviewer, `pain-review.sh`, and `pr-template-check.yml`: `^Rule-feedback:\s*(P-[a-z-]+|none)(?:,\s*(.+))?$`. Entries describe the rule and the reason. GitHub shows who wrote them, so the honest promise is narrower: the pile is only ever used to decide, as a team, whether a rule stays, changes, or the code is brought back in line; it is never used to challenge an already-merged change or the teammate who made it. Issues use the `rule-feedback` label. `pain-review.sh` reads merged PR bodies and labelled issues and keeps a pinned "Rule feedback" issue grouped by rule with counts, so "three sightings" is computed, not eyeballed. The kit site links a saved GitHub search to the same data. No rendered file, no workflow commit to `main`.
- **Reviewing exceptions.** Five minutes at the 18:00 checkpoint and again at the retro, run by the product owner. Per rule, three outcomes: keep it, change it by PR, or reverse the exceptions. Three sightings of the same rule mean it gets reviewed in the big picture at the next checkpoint, not in the context of each exception.
- **Propagation.** Rule text edits reach agents on their next session start, and the consistency review keeps the core honest as the extended file grows. Plugin changes (skills, hook) need `claude plugin update` in the container or an image rebuild.

## 14. Repository layout

```
xenia-2026/                     # public, MIT
  LICENSE
  README.md                     # Saturday-morning quickstart, links, "other teams welcome to use this", and: shutdown.sh stops only what has an entry, check your billing console, your AWS bill is yours
  .gitignore                    # *.tfvars, *.local.env: account IDs and environment values never committed
  CONTRIBUTING.md               # shutdown policy, contracts default, PR norms
  SHUTDOWN.md                   # rendered inventory of everything billable (CI)
  docs/superpowers/specs/       # this document
  docs/option-a-claude-platform-on-aws.md
  docs/deferred/                # lambda-api, static previews, dev-box, evals, conformance, inventory, click-ops hook, deviations renderer
  runbook/
    00-accounts.md  01-quota.md  02-dns-godaddy.md  03-bootstrap.md
    04-gpu-box.md   05-friday-dry-run.md  06-saturday.md  99-teardown.md
  infra/
    org/            # mgmt account: Organizations, member account, Identity Center, group, permission sets, budgets, SNS
    platform/       # member account: zone, cert, OIDC, state, SSM namespace, logs, backup bucket
    recipes/        # docker-box (with gateway), static-site, dynamodb-table, gpu-box
    examples/       # hello deployments per recipe
  templates/
    workflows/      # the CI workflows in section 12
    devcontainer/   # keyless .devcontainer for the team repo
    opencode/       # OpenCode config
    contracts/      # openapi.yaml starter, event schema folder, type-generation and oasdiff config
    team-repo/      # PRINCIPLES.md and PRINCIPLES-EXTENDED.md (from team-kit), CODEOWNERS, main ruleset JSON, PR template, CLAUDE.md, AGENTS.md, CONTRIBUTING.md, Makefile with `check`, issue templates, labels
  plugin/           # kit plugin, vendored into the team repo by onboard-repo.sh: skills (/pain, /rule-feedback, /notify, /doctor, /preview, /shutdown-entry, /demo-checklist) and the SessionStart hook
  site/             # static generator config for the kit site
  scripts/
    bootstrap.sh onboard-teammate.sh offboard-teammate.sh onboard-repo.sh
    shutdown.sh startup.sh status.sh cost.sh gpu.sh rollback.sh restore.sh logs.sh doctor.sh
    teardown.sh put-secret.sh pain-review.sh rotate-key.sh lockdown.sh
  shutdown.d/
  team-kit/
    print/          # QR flyer, sign-up sheet, about-me card (PDF + PNG)
```

Terraform stays on the installed 1.5.7. Two providers per stack (ca-central-1 and us-east-1 aliases). One `tfvars` per stack, no workspaces.

## 15. Runbook and schedule

### Erik's steps (each a short page under `runbook/`)

| When | Step | Why it's on the critical path |
|---|---|---|
| Wed (tonight) | **00**: confirm the personal account is not in another organization; enable Organizations; verify the root email; enable root access management; create member account `cohack-26`; enable Identity Center in ca-central-1 with the email-OTP setting; create your user, `admin` permission set, assignments to both accounts; `aws configure sso` into `personal-admin` and `cohack`; verify your phone number in the SNS SMS sandbox | Everything else depends on the account and the profiles |
| Wed (tonight) | **01**: request 8 vCPUs of `L-DB2E81BA` in us-east-1 in the management account first, then in the member account; retry the member request after an hour if it rejects for account activation | Approval takes hours to days; Bedrock covers the gap |
| Wed (tonight) | **02**: add four NS records for host `26.cohack` at GoDaddy once I hand over the nameservers | Puts certificate validation off Thursday's path |
| Thu, Fri | approve each `terraform apply` I run; a Hugging Face token only if the chosen quantization is gated | |
| Thu, optional | **00b**: MFA is confirmed on the management-account root and on Erik's Identity Center user (authenticator apps, checked 2026-09-24). Optional upgrade: add a passkey as a second device on root (Security credentials, Assign MFA device, Passkey or security key) and on the Identity Center user after allowing security keys under Settings, Authentication. Secret scanning and push protection are confirmed on for the kit repo; non-provider patterns aren't offered on this plan and `gitleaks` covers that gap. Optionally set this repo's commit email to the GitHub noreply address | Nothing blocking; the management account holds the card |
| Fri | **05**: a five-minute end-to-end run as a fake teammate; fill in `01-about-me.md`; name the night-shift teammate slot; print `team-kit/print/` | |
| Sun 12:00 | **99a**: `scripts/shutdown.sh`, then `scripts/lockdown.sh` (every live session and CI role in the member account is cut at once), then remove the `hackathon` group assignment; after the retro, shred the sign-up sheet; a week later, delete the idea-lock channel | Nobody keeps access or data by accident; the lockdown covers the up-to-12 hours a removed assignment's sessions would otherwise live on |

### My steps

- **Wed**: spec final review, repo scaffold, `infra/org` and `infra/platform` written, zone created and nameservers handed over as soon as `cohack` exists.
- **Thu**: bootstrap, cert live, OIDC role, budgets and SNS, Docker box up with Caddy and the gateway, **Bedrock Qwen backend live and Claude Code proven end to end through the gateway by midday**, `check.yml` and deploy workflow proven, GPU box first boot the moment quota lands, weights download started.
- **Fri**: vLLM as primary with failover verified, previews, shutdown framework and CI check, `status.sh`, PR review workflow, dev container image published and Codespaces prebuild, backups, health check and SMS alarm, team kit and kit site, QR flyer, onboarding dry run, load test past capacity, EBS snapshot. Should-tier items as time allows. Evening: examples torn down, GPU box stopped, everything else left up.
- **Sat 08:00**: `scripts/gpu.sh start`, `scripts/status.sh` green.

Anything in the Must tier not proven by Friday night is reported as such, not left half-built. Should-tier items ship as templates with a "not proven" note in their README.

## 16. Costs (on-demand list prices, verified at apply time)

| Item | Rate | Estimate |
|---|---|---|
| GPU box g6e.xlarge, us-east-1: Thu/Fri bring-up and load test (~15h) plus Sat 08:00 to Sun 12:00 (28h), plus buffer | ~$1.86/h | ~$95 |
| GPU EBS 200 GB gp3 for a week, plus one snapshot | $0.08/GB-month | ~$5 |
| Docker box t4g.large, Thu to Sun | ~$0.067/h | ~$7 |
| Bedrock Qwen tokens: Thursday bring-up plus failover time | per token, cheap | $1 to $5 |
| Route 53 zone and health check | $0.50 + $0.50/month | ~$1 |
| S3, CloudFront, SSM, logs, backups | free tiers | under $2 |
| Identity Center, Organizations, Budgets (first two), SNS email | free | $0 |
| **Total** | | **roughly $110 to $130** |

Alerts at $10 (Thursday, the canary), $25, $50, $100, $150, plus a $150 forecast. Everyone should expect the $100 notification on Saturday.

## 17. Verification

- `terraform validate` and `plan` clean for every stack; `shellcheck` clean for every script.
- Kit site serves over TLS at the apex; `app.` hello returns 200; a preview opens for a test PR at `pr-<n>.box.…` and disappears on close.
- **Thursday midday**: Claude Code in the dev container completes a multi-step tool-use task (edit a file, run tests) through the gateway against Bedrock Qwen, including the thinking-rejection retry path.
- **Friday**: same task against vLLM; stop the GPU box and confirm the next request succeeds via Bedrock; four concurrent headless sessions, then deliberately more than the box sustains, recording tokens per second, queueing, and whether any stream trips the 300-second watchdog.
- Onboarding dry run with a throwaway email: invite works (OTP path), key issued, session works in Codespaces with the key as a user secret.
- `pr-review.yml` posts a comment on a labelled test PR within its timeout; `shutdown-coverage.yml` fails a PR that adds an instance without a `shutdown.d` entry and passes once added.
- `scripts/shutdown.sh` stops the GPU box, Docker box, and previews; `startup.sh` restores the GPU box with weights intact; `status.sh` reports green; `restore.sh` restores a `pg_dump`.
- A dev container session shows the injected principles in its context on start; `/pain` opens a labelled issue; a test PR with a `Rule-feedback:` line appears grouped in the pinned issue after `pain-review.sh` runs over three seeded items.
- Secret scanning and push protection show enabled on both repos; a planted LiteLLM-style key is blocked by push protection or caught by `gitleaks` in `check.yml`; a planted 12-digit number fails the kit-site build; a PR from a fork gets neither a preview nor a review; from inside a preview container, the instance metadata endpoint is unreachable.
- The consistency review runs over the initial `PRINCIPLES.md` and `PRINCIPLES-EXTENDED.md` and reports nothing hidden; the `main` ruleset blocks a self-merge of a PR that edits `PRINCIPLES.md` and allows one that edits application code; `offboard-teammate.sh` removes a test collaborator's write access.
- The $10 budget notification arrives Thursday by email and SMS. Cost Explorer shows the expected line items Friday morning.
- Access kill switch: `scripts/lockdown.sh` attaches `xenia-lockdown`; a live `hackathon-dev` session and a `preview` role run both get AccessDenied, Erik's admin profile still works, and `llm.26.cohack.tetl.ca/health/readiness` still answers 200; `scripts/lockdown.sh --undo` restores both. A first merge from a real team repo (not the kit) reaches `app.` in under five minutes (success criterion 1).
- Should tier, if reached: `contract-check.yml` fails a test PR that removes a response field and passes with `breaking-ok`.
- Should tier, if reached: in a throwaway team repo, a PR adding a tagged `t4g.nano` gets one plan comment (`1 to add`, the address, no plan body) and merging it applies it; a PR removing it pauses at the gate and posts the pause to Discord, and applies only after `destroy-ok` is added and the run is re-run; a PR adding an `m7i.8xlarge` is denied at apply.

## 18. Risks and fallbacks

| Risk | Likelihood | Fallback |
|---|---|---|
| GPU quota not approved in time | medium | Bedrock Qwen carries the weekend automatically; rented GPU (Lambda Cloud, RunPod) as an optional upgrade |
| Claude Code misbehaves with the open model (tool-call formatting, rejected parameters, compaction) | medium | Context and output limits set; `drop_params`; both parser names tested; OpenCode fallback client; Scenario A appendix |
| Bedrock Qwen token quota too low for a whole team if the GPU never lands | low | Quota increase request Thursday after first calls; spill to gpt-oss on Bedrock if available; Scenario A |
| g6e capacity unavailable in the chosen AZ | low to medium | Try other AZs; g6e.2xlarge; g5.xlarge (24 GB) with gpt-oss-20b |
| Team wants Sonnet-class quality after all | medium | Scenario A appendix; Marketplace sign-up can be done in advance as dormant insurance |
| GoDaddy NS propagation slow | low | Delegation done Wednesday night |
| Headless review too noisy, slow, or eating GPU time | medium | Label-triggered only; timeout; advisory |
| Docker box OOM under previews | low | t4g.large, three-preview cap; resize is one variable |
| GPU box dies overnight | low to medium | Restart policy, watchdog, failover to Bedrock, SMS alarm, named night-shift teammate |

## 19. Appendix: Scenario A, Claude Platform on AWS (documented only)

Anthropic-operated API, billed through AWS Marketplace on the same AWS bill at list prices, same-day model parity including Fable 5.1, all AWS commercial regions. Claude Code supports it natively. Signing up creates a new Anthropic organization tied to the AWS account; until then, Scenario B involves no Anthropic account.

Switching from B takes about 15 minutes of Erik's time if the Marketplace sign-up was done in advance, plus one env-file change:

1. In the member account's AWS Console, open the Claude Platform on AWS service page, sign up, complete the Anthropic organization form, create a ca-central-1 workspace, note the `wrkspc_…` ID. Set an organization monthly spend limit on the Billing page.
2. Grant `hackathon-dev` and the deploy role the `aws-external-anthropic` invoke actions (a commented-out block in `infra/org` and `infra/platform`). Add `aws-external-anthropic.ca-central-1.api.aws` to the dev container firewall allow-list.
3. Dev container `ai.local.env`: unset the gateway variables; set `CLAUDE_CODE_USE_ANTHROPIC_AWS=1`, `ANTHROPIC_AWS_WORKSPACE_ID`, `AWS_REGION=ca-central-1`, pin `ANTHROPIC_DEFAULT_SONNET_MODEL=claude-sonnet-5` and `ANTHROPIC_DEFAULT_HAIKU_MODEL=claude-haiku-4-5`, and set `awsAuthRefresh` to the SSO login command so expiring sessions refresh. Members authenticate with their Identity Center login, which reintroduces AWS credentials inside the container; the read-only trade-off in section 7 applies.
4. PR review workflow: swap the gateway secret for the OIDC role (already trusted) and the same variables.

Costs: Sonnet 5 at $2 in / $10 out per million tokens; four heavy users roughly $50 to $150 for the weekend, capped by the spend limit. Start tier limits: 1,000 requests and 2M input tokens per minute for Sonnet 5, $500/month cap. Web search works. Fast mode, the packaged GitHub action, and claude.ai-only features do not.

## 20. Assumptions to confirm in review

- A1: the personal account is not already a member of another organization.
- A2: Erik is fine with the GPU box (and Bedrock inference) living in us-east-1 while everything else is in Canada.
- A3: Alert tiers $10/$25/$50/$100/$150 and the Discord default for comms.
- A4: The kit repo is `ert485/xenia-2026`, public under MIT, with account IDs and environment values in gitignored files. The team repo defaults to public.
- A5: Team-kit defaults in section 13 stand unless a line is named.
- A6: Publishing the team kit and runbook publicly at the apex is fine; runbook pages use placeholders for account and zone IDs, and the real values live in gitignored `tfvars` and SSM.
- A7: Bedrock Qwen as a per-token failover is compatible with "no per-token surprise": it costs cents to a few dollars and only runs when the GPU is down.
- A8: "No AWS credentials in agent containers by default" is the right reading of member autonomy; humans keep Identity Center access.
- A9: Erik is comfortable not being a default owner of `PRINCIPLES.md`, and with the tie-break narrowed to kit infrastructure.
- A10: the team's rules live in the team repo even though the kit is public, because they are the team's, not the kit's; the kit only supplies the first draft.
- A11: pre-built tooling is within Co.Hack's rules (the event page welcomes adding to existing products and passion projects); the pitch says plainly that the kit predates the event and the product doesn't.
