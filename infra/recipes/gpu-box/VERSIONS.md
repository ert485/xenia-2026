# GPU box versions

| Component | Version | Notes |
|---|---|---|
| AMI | Deep Learning Base OSS Nvidia Driver GPU AMI (Ubuntu 24.04), latest at first boot | SSM parameter `/aws/service/deeplearning/ami/x86_64/base-oss-nvidia-driver-gpu-ubuntu-24.04/latest/ami-id`; `ignore_changes` keeps a running box on its AMI |
| vLLM | `vllm/vllm-openai:v0.30.0` (2026-09-22) | Record the digest seen at first boot: `docker inspect -f '{{index .RepoDigests 0}}' vllm/vllm-openai:v0.30.0` through `scripts/gpu.sh` or SSM |
| Model | `models.yaml` `default` | The repository was chosen on 2026-09-24 with the Hugging Face query in Task 10 step 1 |

Update vLLM: change the tag in `compose.yml`, merge, then on the box `git -C /srv/kit fetch --depth 1 origin <ref> && git -C /srv/kit reset --hard FETCH_HEAD` (over SSM) and `cd infra/recipes/gpu-box && docker compose up -d`, and watch `scripts/gpu.sh logs`.
