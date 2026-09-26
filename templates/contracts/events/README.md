# Event schemas

Teammate: one JSON Schema (draft 2020-12) per event, named `<noun>.<past-tense-verb>.schema.json`
(`item.created`, `order.paid`). `example.event.schema.json` is the shape to copy.

- Every event carries `type`, `version`, `id` (for idempotent consumers), `occurredAt`, and `data`.
- A breaking change to an event is a new `version` and, for a while, both versions are accepted.
- Producers and consumers validate at the boundary: `ajv` in TypeScript, `jsonschema` or a pydantic model
  in Python. Validation failures log loudly and reject; they never pass bad data on.
- `make types` generates types from `../openapi.yaml` only. Event types are validated at run time; if the
  team wants generated event types too, add a line to the `types` target (for example
  `npx --yes json-schema-to-typescript`) and pin its version the same way.

Agent: when you add or change an event, update its schema in the same PR and validate at both ends.