# 04: GPU box

Status: quota approved Wednesday (8 vCPUs of `L-DB2E81BA`, us-east-1, both accounts); the box is
created Thursday by Task 10.

## What the recipe creates

`infra/recipes/gpu-box`: one `g6e.xlarge` with a 200 GB gp3 volume for weights, an Elastic IP, a
security group open on 8443 to the Docker box only, an instance role (SSM and the CloudWatch agent),
and four SSM parameters under `/xenia/gpu/` (bearer token, TLS key and certificate, API base URL)
that the gateway reads on `scripts/box.sh xenia-gateway Action=restart`.

## Everyday commands

    scripts/gpu.sh status     # state, vLLM health, GPU memory, weights on disk
    scripts/gpu.sh start      # healthy in about 10 minutes; weights stay on the volume
    scripts/gpu.sh stop       # the gateway fails over to Bedrock
    scripts/gpu.sh logs
    scripts/gpu.sh weights
    scripts/gpu.sh model qwen3-coder-fp8   # any key in infra/recipes/gpu-box/models.yaml

## Quota

    aws service-quotas get-service-quota --service-code ec2 --quota-code L-DB2E81BA --region us-east-1 --profile cohack --query Quota.Value
    aws service-quotas get-service-quota --service-code ec2 --quota-code L-DB2E81BA --region us-east-1 --profile personal-admin --query Quota.Value

Expected: `8.0` for both.

## Capacity fallbacks (spec section 18)

On `InsufficientInstanceCapacity`, in order:

1. Another zone: `scripts/tf.sh recipes/gpu-box apply -var availability_zone=us-east-1b` (then 1c, 1d).
2. `-var instance_type=g6e.2xlarge` (8 vCPUs, the whole quota).
3. `-var instance_type=g5.xlarge -var model=gpt-oss-20b` (A10G, 24 GB).

## Switching models

Edit `models.yaml` if needed, then `scripts/gpu.sh model <name>`. Clients never change: every model is
served as `qwen3-coder`. If vLLM rejects the tool parser (`scripts/gpu.sh logs | grep -i parser`),
set `tool_parser: qwen3_coder` for that model and run `scripts/gpu.sh model <name>` again.

## Hosting in the management account (deviation 9)

Only if the member account cannot run the box: `scripts/tf.sh recipes/gpu-box apply -var gpu_host_profile=personal-admin`
(log in to `personal-admin` first). The recipe then adds a member-account role `xenia-gpu-secrets-reader`
that the box assumes at boot to read `/xenia/gpu/*`. `scripts/gpu.sh` and the shutdown entry follow with
`GPU_PROFILE=personal-admin`.

## Cost

About $1.86 an hour while running, plus about $16 a month for the 200 GB volume while it exists.
Stopped overnight Thursday and Friday; started Saturday 08:00 (runbook 06).
