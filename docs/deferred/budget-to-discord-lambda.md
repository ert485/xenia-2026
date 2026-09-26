# Budget alerts to Discord

Reader: for kit maintainers. Cut tier: documented, not built.

## What it was

A small Lambda subscribed to the `xenia-alerts` SNS topic in the management account that reformatted each
AWS Budgets notification and posted it to the team channel through the Discord webhook, so the whole team saw
spend crossing a tier, not only Erik.

## Why it was cut

Budgets already reach Erik by email and SMS, and they lag billing by several hours: they are a smoke detector,
not a breaker (spec §8). Relaying them would put the Discord webhook, another secret, into the management
account, the account that holds the card, for a signal that arrives hours late. Two build days went to the
controls that actually keep the weekend predictable: fixed-price boxes, `status.sh`, and automatic failover.

## What exists instead

Budgets `xenia-actual` (five tiers), `xenia-forecast`, and `xenia-bedrock` to SNS email and SMS (Task 5);
`scripts/cost.sh` for month-to-date and yesterday by service (Task 15); anyone can post a spend update with
`/notify`.

## How to revive

- Create `infra/org/budget-discord.tf`: an `aws_lambda_function` (Python 3.12, about 30 lines using only the
  standard library's `urllib`), its execution role with only `logs:*` on its own log group and
  `ssm:GetParameter` on one parameter, an `aws_sns_topic_subscription` with protocol `lambda`, and the
  `aws_lambda_permission` for SNS.
- Store the webhook in the management account's SSM as a SecureString (never in `tfvars`).
- The function posts `{"content": "[bot · budgets] <budget name> passed $<threshold>"}` and nothing from the
  message body that could carry account details.

Effort: 2 to 3 hours.
