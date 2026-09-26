# Option A: Claude Platform on AWS

Teammate: the kit runs on Scenario B, an open-weight model behind our own gateway, with no Anthropic account. This page is the documented way to switch to Anthropic's own models, billed on the same AWS bill. It is not built; switching takes Erik about 15 minutes if the sign-up was done in advance.

## What it is

The Claude Platform on AWS is the Anthropic-operated API, billed through AWS Marketplace at list prices, with same-day model parity (including Fable 5.1) in every AWS commercial region. Claude Code supports it natively. Signing up creates a new Anthropic organization tied to the AWS account; until then, the kit involves no Anthropic account at all.

## Sign up in advance, as dormant insurance

The sign-up can be done before the event and left unused: nothing is billed until something calls the API. If the team wants Sonnet-class quality after all, the switch is then an env-file change.

## Switching, in four steps

1. In the member account's AWS console, open the Claude Platform on AWS service page, sign up, complete the Anthropic organization form, create a ca-central-1 workspace, and note its `wrkspc_` ID. Set an organization monthly spend limit on the Billing page.
2. Grant the teammate permission set and the deploy role the `aws-external-anthropic` invoke actions (a commented-out block in the org and platform stacks), and add `aws-external-anthropic.ca-central-1.api.aws` to the dev container's firewall allow-list.
3. In the dev container's `ai.local.env`: unset the gateway variables; set `CLAUDE_CODE_USE_ANTHROPIC_AWS=1`, `ANTHROPIC_AWS_WORKSPACE_ID`, `AWS_REGION=ca-central-1`; pin `ANTHROPIC_DEFAULT_SONNET_MODEL=claude-sonnet-5` and `ANTHROPIC_DEFAULT_HAIKU_MODEL=claude-haiku-4-5`; set `awsAuthRefresh` to the SSO login command so expiring sessions refresh. Teammates then authenticate with their Identity Center login, which puts AWS credentials inside the container again: any agent they run inherits that access.
4. In the PR review workflow, swap the gateway secret for the OIDC role (already trusted) and the same variables.

## Costs

Sonnet 5 is $2 per million input tokens and $10 per million output tokens. Four heavy users come to roughly $50 to $150 for the weekend, capped by the spend limit. Starting tier limits: 1,000 requests and 2M input tokens per minute for Sonnet 5, and a $500 monthly cap.

## What works and what doesn't

- Works: Claude Code with Anthropic's models, web search, the same dev container and CI.
- Doesn't: fast mode, the packaged GitHub action, and features that exist only on claude.ai.
