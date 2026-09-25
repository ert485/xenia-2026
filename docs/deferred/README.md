# Deferred: the Cut tier

Reader: these pages are for whoever maintains the kit (Erik today; a teammate or another team that forks it
later). Nothing here is built.

The kit was scoped in three tiers (spec §3, decision D21), because two build days can't prove everything:

- **Must**: proven end to end by Friday night, or reported as not proven in `docs/proofs/README.md`.
- **Should**: built and shipped as templates; proven if Friday allowed, and each says "not proven" in its
  README or header until its proof file exists.
- **Cut**: documented here only. Each page says what the piece was, why it was cut, what the kit does instead,
  and what reviving it would take.

| Page | What it was | Instead |
|---|---|---|
| [Lambda API recipe](lambda-api-recipe.md) | API Gateway plus Lambda, with per-PR previews | the Docker box runs any API in compose |
| [Static-site previews](static-site-previews.md) | a CloudFront preview per PR for static frontends | frontends preview on the Docker box |
| [CPU dev box](cpu-dev-box.md) | a cloud VM per teammate for the dev container | Codespaces |
| [Evals template](evals-template.md) | an eval harness and `evals.yml` for LLM features | the P-evals principle; evals run in `make check` |
| [Schemathesis conformance](schemathesis-conformance.md) | property-based API tests against each preview | `contract-check.yml` and the preview health check |
| [Inventory cron](inventory-cron.md) | a scheduled workflow listing everything running | `scripts/status.sh` and the Resource Explorer view |
| [Budget alerts to Discord](budget-to-discord-lambda.md) | a Lambda relaying budget alerts to the team channel | SNS email and SMS, `scripts/cost.sh` |
| [Cost Anomaly Detection](cost-anomaly-detection.md) | an AWS anomaly monitor on the member account | five budget tiers plus a forecast |
| [Click-ops PreToolUse hook](click-ops-pretooluse-hook.md) | a hook blocking AWS mutations from agents | no AWS credentials in agent containers |
| [Deviations renderer](deviations-renderer.md) | a generated `DEVIATIONS.md` from rule feedback | the pinned "Rule feedback" issue |

To revive one, open a PR that adds it with its tests or proof, a `shutdown.d/` entry or a
`Shutdown: none needed because ...` line if it costs money (P-off-switch), and then move its row in spec §3
from Cut to Should.
