# Proof: Claude Code in the dev container, through the gateway, against Bedrock

Date: 2026-09-25 01:21–01:22 UTC (Thursday evening CST). Plan Task 8, step 10; spec §17 "Thursday
midday" and §1 success criterion 3. The GPU box doesn't exist yet, so the gateway's vLLM deployment
fails fast and every request is served by the Bedrock deployment (`qwen3-coder-bedrock`).

## Setup

- `devcontainer up --workspace-folder .` on branch `build/gateway`, with Erik's gateway key in the
  gitignored `.devcontainer/ai.local.env`.
- Firewall: `init-firewall.sh` applied default-deny, logged `WARNING: 26.cohack.tetl.ca did not
  resolve yet; skipping` (the kit site isn't built yet), and passed its self-test. From inside the
  container, `https://example.com` was blocked and `https://llm.26.cohack.tetl.ca/health/readiness`
  returned 200.
- Versions: Claude Code 2.1.280, OpenCode 1.18.32.

## The task

A one-file project where `add.js` returns `a - b` and a vitest test expects `add(2, 3) === 5`. The
test fails before the run.

```bash
claude -p --verbose --output-format stream-json --max-turns 12 --dangerously-skip-permissions \
  "Agent: run the tests with npx vitest run, fix the bug in add.js so they pass, run them again, and report the final test output."
```

## Result

- Wall clock: 01:21:48 to 01:22:13 UTC (25 s).
- `turns=7 is_error=false`, 6 tool calls (run tests, read, edit, run tests again).
- Every assistant message reports model `qwen3-coder`.
- `add.js` afterwards: `return a + b;`. `npx vitest run`: 1 file passed, 1 test passed.
- The final answer summarised the change (subtraction to addition) and the passing test output.
- Claude Code logged `unrecognized_model` for `qwen3-coder` on stderr (informational: it doesn't
  know the model's limits, which is why `CLAUDE_CODE_MAX_CONTEXT_TOKENS` and
  `CLAUDE_CODE_MAX_OUTPUT_TOKENS` are set).

## Thinking blocks

Claude Code sends a thinking block for unknown model IDs. A direct Messages API call to the gateway
with `"thinking": {"type": "enabled", "budget_tokens": 1024}` and model `qwen3-coder` returned
`type: message`, `stop_reason: end_turn`, text `ready`: the gateway's `drop_params` dropped the
thinking field instead of rejecting the request (see `2026-09-24-gateway-first-call.md`).

## OpenCode

`opencode run "Agent: list the files here and say which one has a bug"` answered through the same
gateway (after Claude Code's fix, it correctly reported no remaining bug in `add.js`).
