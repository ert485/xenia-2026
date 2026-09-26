# Shutdown inventory

Rendered by `make shutdown-md`; CI fails a PR when this file is stale. `scripts/shutdown.sh` runs every entry below; `--dry-run` shows what it would do.

| Entry | Stops | Added by | Restore | Cost when running |
|---|---|---|---|---|
| `10-gpu-box.sh` | the GPU box (vLLM, g6e.xlarge) in us-east-1; the gateway fails over to Bedrock | erik | scripts/gpu.sh start (weights stay on the volume) | about $1.86/hour |
| `20-docker-box.sh` | the Docker box (Caddy, LiteLLM gateway, demo app, previews) in ca-central-1 | erik | scripts/startup.sh | about $1.60/day |
