# Cost Anomaly Detection

Reader: for kit maintainers. Cut tier: documented, not built.

## What it was

An AWS Cost Anomaly Detection monitor on the member account with a subscription alerting on any anomaly above
a few dollars, to catch a runaway resource that stayed under the next budget tier.

## Why it was cut

Anomaly detection learns from spending history, and the member account was created on 2026-09-23: with no
baseline it has nothing to compare against during the event, so it would stay silent or be noisy exactly when
it mattered (spec §3).

## What exists instead

Five actual-cost budget tiers ($10, $25, $50, $100, $150), a $150 forecast, and a Bedrock budget (Task 5), with
the $10 tier as the Thursday canary; `scripts/cost.sh` and `scripts/status.sh` for anything faster.

## How to revive

Only worth it for an account with a few weeks of history (for example if the kit's account is reused for a
later event):

- Add to `infra/org/alerts.tf`: `aws_ce_anomaly_monitor` of type `DIMENSIONAL` on `SERVICE`, or `CUSTOM` scoped
  to the member account, and an `aws_ce_anomaly_subscription` with a `threshold_expression` on
  `ANOMALY_TOTAL_IMPACT_ABSOLUTE` of 5 USD, frequency `IMMEDIATE`, to the `xenia-alerts` topic.
- Note that the guard-rail deny list blocks `ce:*` for teammates and CI, so only Erik's admin session can
  change it, which is the intent.

Effort: 1 hour.