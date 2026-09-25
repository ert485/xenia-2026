#!/usr/bin/env bash
# Usage: scripts/gpu.sh start|stop|status|logs|weights|model <name>
#   start    start the GPU box (weights stay on the volume; vLLM healthy in about 10 minutes)
#   stop     stop it (the gateway fails over to Bedrock)
#   status   instance state, vLLM health, GPU memory and utilization, weights on disk
#   logs     last 100 lines of the vLLM container
#   weights  what is in the Hugging Face cache on the volume
#   model    switch the served weights to a model in infra/recipes/gpu-box/models.yaml
# The AWS profile is GPU_PROFILE, else the stack's host_profile output, else cohack (deviation 9).
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
require_cmd aws jq

action="${1:-}"
region=us-east-1
recipe_on_box=/srv/kit/infra/recipes/gpu-box

if [[ "$action" == "model" ]]; then
  name="${2:?usage: scripts/gpu.sh model <name from models.yaml>}"
  py="$KIT_ROOT/.venv/bin/python"; [[ -x "$py" ]] || py=python3
  line="$("$py" - "$KIT_ROOT/infra/recipes/gpu-box/models.yaml" "$name" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
m = d["models"].get(sys.argv[2])
if m is None:
    sys.exit(3)
print("\t".join([m["repo"], m["tool_parser"], str(m["max_num_seqs"]), m.get("extra_args") or ""]))
PY
)" || die "no model named $name in models.yaml"
  IFS=$'\t' read -r repo parser seqs extra <<< "$line"
  [[ "$repo" =~ ^[A-Za-z0-9._/-]+$ && "$parser" =~ ^[a-z0-9_]+$ && "$seqs" =~ ^[0-9]+$ && "$extra" =~ ^[A-Za-z0-9\ ._=/-]*$ ]] \
    || die "models.yaml entry $name has unexpected characters"
fi

if [[ -n "${GPU_PROFILE:-}" ]]; then
  profile="$GPU_PROFILE"
else
  profile="$(TF_NO_MASK=1 "$KIT_ROOT/scripts/tf.sh" recipes/gpu-box output -raw host_profile 2>/dev/null || true)"
  [[ "$profile" =~ ^[A-Za-z0-9_-]+$ ]] || profile=cohack
fi
aws_() { aws --profile "$profile" --region "$region" "$@"; }

instance() {
  aws_ ec2 describe-instances \
    --filters Name=tag:xenia-role,Values=gpu-box Name=instance-state-name,Values=pending,running,stopping,stopped \
    --query 'Reservations[].Instances[0].[InstanceId,State.Name,InstanceType]' --output text | head -1
}

# run_on_box <shell command>: AWS-RunShellScript on the GPU box, waits up to 5 minutes, prints stdout.
run_on_box() {
  local cid st i
  cid="$(aws_ ssm send-command --instance-ids "$id" --document-name AWS-RunShellScript \
    --parameters "$(jq -nc --arg c "$1" '{commands: [$c]}')" --query Command.CommandId --output text)"
  for ((i = 0; i < 100; i++)); do
    st="$(aws_ ssm get-command-invocation --command-id "$cid" --instance-id "$id" --query Status --output text 2>/dev/null || echo Pending)"
    case "$st" in Pending|InProgress|Delayed) sleep 3 ;; *) break ;; esac
  done
  aws_ ssm get-command-invocation --command-id "$cid" --instance-id "$id" \
    --query '[StandardOutputContent,StandardErrorContent]' --output text | mask
  [[ "$st" == "Success" ]] || die "command on the GPU box ended with status $st"
}

read -r id state itype <<< "$(instance)"
[[ -n "${id:-}" && "$id" != "None" ]] || die "no GPU box found (tag xenia-role=gpu-box, profile $profile, $region)"

case "$action" in
  start)
    aws_ ec2 start-instances --instance-ids "$id" >/dev/null
    aws_ ec2 wait instance-running --instance-ids "$id"
    log "GPU box running; vLLM is healthy in about 10 minutes (no download: weights are on the volume)"
    ;;
  stop)
    aws_ ec2 stop-instances --instance-ids "$id" >/dev/null
    log "GPU box stopping; the gateway serves from Bedrock meanwhile"
    ;;
  status)
    echo "gpu box: $state ($itype, profile $profile)"
    [[ "$state" == "running" ]] || exit 0
    run_on_box 'curl -fsk -m 5 -o /dev/null https://localhost:8443/health && echo "vllm: healthy" || echo "vllm: not healthy yet"; nvidia-smi --query-gpu=memory.used,memory.total,utilization.gpu --format=csv,noheader | sed "s/^/gpu: /"; du -sh /data/hf 2>/dev/null | sed "s/^/weights: /"; grep -E "^(MODEL_REPO|MAX_NUM_SEQS)=" /etc/xenia/vllm.env'
    ;;
  logs)
    run_on_box 'docker logs --tail 100 vllm-vllm-1 2>&1'
    ;;
  weights)
    run_on_box 'ls -1 /data/hf/hub 2>/dev/null || echo "(empty)"; du -sh /data/hf/hub/* 2>/dev/null'
    ;;
  model)
    [[ "$state" == "running" ]] || die "the GPU box is $state; scripts/gpu.sh start first"
    run_on_box "set -e; f=/etc/xenia/vllm.env; sed -i -e 's|^MODEL_REPO=.*|MODEL_REPO=$repo|' -e 's|^TOOL_PARSER=.*|TOOL_PARSER=$parser|' -e 's|^MAX_NUM_SEQS=.*|MAX_NUM_SEQS=$seqs|' -e 's|^EXTRA_ARGS=.*|EXTRA_ARGS=$extra|' \$f; cd $recipe_on_box && docker compose up -d --force-recreate; grep -E '^(MODEL_REPO|TOOL_PARSER|MAX_NUM_SEQS)=' \$f"
    log "switched to $name; a new repository downloads first (watch scripts/gpu.sh logs)"
    ;;
  *)
    die "usage: scripts/gpu.sh start|stop|status|logs|weights|model <name>"
    ;;
esac
