# Contributing

Teammate: this is how we work. The why is in `PRINCIPLES.md` and `PRINCIPLES-EXTENDED.md`.

- **Trunk-based.** Small PRs against `main`, rebased before merge.
- **Self-merge when CI is green.** No human review before merge; look at the preview URL instead.
  Only `make check` and shutdown coverage block (P-two-gates). Add the `review` label when you want the
  bot's advisory review.
- **Rule feedback.** Every PR body has a `Rule-feedback:` line. Leave `Rule-feedback: none`, or write
  `Rule-feedback: P-<slug>, <what you did differently and why>`, at the start of the line.
- **Shutdown policy.** A PR that adds or changes something billable must either touch that repo's
  `shutdown.d/` or contain the line `Shutdown: none needed because <reason>` in its body. The
  `shutdown-coverage` check blocks the merge otherwise; `/shutdown-entry` scaffolds an entry.
- **Contracts.** When the project has an API, `contracts/` holds the OpenAPI file and event schemas,
  types are generated from them, and boundaries validate against them. A server-rendered monolith skips
  this.
- **Compose convention.** The service the world sees is named `web`, listens on `APP_PORT` (3000 by
  default), and publishes no `ports:`; the kit attaches it to the demo URL and to each PR's preview.
