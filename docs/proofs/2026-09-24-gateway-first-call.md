# Proof: first inference through the gateway

Date: 2026-09-25 01:20 UTC. Plan Task 7, steps 9 and 13. No GPU box yet, so the vLLM deployment
fails fast and the Bedrock deployment answers.

## Public surface (step 9)

| Check | Result |
|---|---|
| `GET /health/readiness` | `{"status":"healthy","db":"connected"}` |
| `GET /ui` | 404 |
| `POST /key/generate` | 404 |
| `GET /v1/models` without a key | 401 |
| certificate issuer on `llm.` | Let's Encrypt (YE1) |
| `https://pr-1.box.26.cohack.tetl.ca/` | `no such preview` 404 |
| Caddy's default route (box status) | via the `backend` network |

## Calls (step 13)

`$KEY` is Erik's gateway key, read from a local file and never printed.

```bash
curl -sS https://llm.26.cohack.tetl.ca/v1/messages \
  -H "x-api-key: $KEY" -H 'anthropic-version: 2023-06-01' -H 'content-type: application/json' \
  -d '{"model":"qwen3-coder","max_tokens":2048,"thinking":{"type":"enabled","budget_tokens":1024},"messages":[{"role":"user","content":"Reply with the single word ready."}]}'
```
Result: `{"type":"message","stop_reason":"end_turn","text":["ready"]}`. The thinking block was
dropped, not rejected.

```bash
curl -sS -D - -o /dev/null https://llm.26.cohack.tetl.ca/v1/chat/completions \
  -H "Authorization: Bearer $KEY" -H 'content-type: application/json' \
  -d '{"model":"qwen3-coder","max_tokens":16,"messages":[{"role":"user","content":"Say ok."}]}'
```
Result: `HTTP/2 200`, `x-litellm-model-id: qwen3-coder-bedrock`, in about 1 s (the vLLM deployment
has no host yet and fails immediately).

```bash
curl -sS https://llm.26.cohack.tetl.ca/v1/models -H "Authorization: Bearer $KEY"
```
Result: `qwen3-coder`, `qwen3-coder-bedrock`.

## Found and fixed

The same Messages call with the alias `claude-sonnet-5` failed: LiteLLM looks up fallbacks under
the alias name, and only `qwen3-coder` had one, so aliases never failed over to Bedrock. The fix
adds a fallback entry for every alias, with a test that fails if an alias lacks one.
