# gpu-box recipe

One `g6e.xlarge` (NVIDIA L40S, 48 GB) in us-east-1 running vLLM behind TLS on port 8443, reachable
only from the Docker box's Elastic IP. The gateway on the Docker box uses it as the primary backend
for `qwen3-coder` and fails over to Bedrock whenever it is stopped or unhealthy.

- Operate it with `scripts/gpu.sh start|stop|status|logs|weights|model <name>`.
- Stop it with `shutdown.d/10-gpu-box.sh` (part of `scripts/shutdown.sh`); about $1.86 an hour while running.
- Models and their tool parsers are in `models.yaml`.
- Runbook: `runbook/04-gpu-box.md` (quota, capacity fallbacks, hosting in the management account).
