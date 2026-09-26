#!/usr/bin/env bash
# Usage: scripts/gpu.sh start|stop|status|logs|weights|model <name>|capacity [region] [type]|capacity-log [n]
#   start         start the GPU box (weights stay on the volume; vLLM healthy in about 10 minutes)
#   stop          stop it (the gateway fails over to Bedrock)
#   status        instance state, vLLM health, GPU memory and utilization, weights on disk
#   logs          last 100 lines of the vLLM container
#   weights       what is in the Hugging Face cache on the volume
#   model         switch the served weights to a model in infra/recipes/gpu-box/models.yaml
#   capacity      on-demand g6e capacity probe (profile cohack, default region us-east-1, default
#                 both g6e types) — same create-then-cancel-a-reservation check as the Docker box's
#                 xenia-gpu-capacity-probe.timer (box/gpu-capacity-probe.sh), for a human on the day
#   capacity-log  last n (default 50) probe lines from CloudWatch (/xenia/boxes,
#                 xenia-gpu-capacity-probe stream) plus an availability summary per type/zone
# The AWS profile is GPU_PROFILE, else the stack's host_profile output, else cohack (deviation 9).
# capacity/capacity-log always use profile cohack: they are a human's on-demand check, not tied to
# whichever account host_profile currently resolves to.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
require_cmd aws jq

action="${1:-}"
region=us-east-1
recipe_on_box=/srv/kit/infra/recipes/gpu-box

if [[ "$action" == "capacity" ]]; then
  cap_region="${2:-us-east-1}"
  only_type="${3:-}"
  aws_cap() { aws --profile cohack --region "$cap_region" "$@"; }
  types=(g6e.xlarge g6e.2xlarge)
  [[ -z "$only_type" ]] || types=("$only_type")

  ids="$(aws_cap ec2 describe-capacity-reservations \
    --filters Name=tag:purpose,Values=capacity-probe Name=state,Values=active,pending \
    --query 'CapacityReservations[].CapacityReservationId' --output text)"
  if [[ -n "$ids" && "$ids" != "None" ]]; then
    for cid in $ids; do
      aws_cap ec2 cancel-capacity-reservation --capacity-reservation-id "$cid" >/dev/null \
        || die "ALERT: failed to cancel stale reservation $cid"
      log "swept stale reservation $cid"
    done
  fi

  for t in "${types[@]}"; do
    zones="$(aws_cap ec2 describe-instance-type-offerings --location-type availability-zone \
      --filters Name=instance-type,Values="$t" --query 'InstanceTypeOfferings[].Location' --output text)"
    if [[ -z "$zones" || "$zones" == "None" ]]; then
      echo "$t: no zone in $cap_region offers this type"
      continue
    fi
    for az in $zones; do
      if out="$(aws_cap ec2 create-capacity-reservation \
            --instance-type "$t" --instance-platform "Linux/UNIX" --availability-zone "$az" \
            --instance-count 1 \
            --tag-specifications 'ResourceType=capacity-reservation,Tags=[{Key=kit,Value=true},{Key=purpose,Value=capacity-probe}]' \
            --query 'CapacityReservation.[CapacityReservationId,State]' --output text 2>&1)"; then
        read -r rid rstate <<< "$out"
        echo "$t $az: AVAILABLE (reservation $rid, $rstate)"
        aws_cap ec2 cancel-capacity-reservation --capacity-reservation-id "$rid" >/dev/null \
          || die "ALERT: failed to cancel reservation $rid ($t $az)"
      else
        echo "$t $az: NONE"
      fi
    done
  done
  exit 0
fi

if [[ "$action" == "capacity-log" ]]; then
  n="${2:-50}"
  # /xenia/boxes lives in ca-central-1 (infra/platform, the kit's platform region) — a different
  # region from the us-east-1 EC2 capacity probing above, so this uses its own region.
  log_region=ca-central-1
  aws_cap() { aws --profile cohack --region "$log_region" "$@"; }
  lines="$(aws_cap logs filter-log-events --log-group-name /xenia/boxes \
    --log-stream-names xenia-gpu-capacity-probe --query 'events[].message' --output text 2>/dev/null)" \
    || die "could not read /xenia/boxes (profile cohack, $log_region)"
  lines="$(tail -n "$n" <<< "$lines")"
  [[ -n "$lines" ]] || die "no xenia-gpu-capacity-probe log lines found in /xenia/boxes yet"
  printf '%s\n' "$lines"
  echo
  echo "availability summary (rounds AVAILABLE / total probed, per type and zone):"
  printf '%s\n' "$lines" \
    | grep -E ': (AVAILABLE|NONE)' \
    | sed -E 's/^\[[^]]*\] ([^ ]+) ([^ ]+): (AVAILABLE|NONE).*/\1 \2 \3/' \
    | awk '{ key=$1" "$2; total[key]++; if ($3=="AVAILABLE") avail[key]++ } END { for (k in total) printf "  %-24s %d/%d\n", k, avail[k]+0, total[k] }' \
    | sort
  exit 0
fi

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

# gpu_alarm_actions <enable|disable> <profile>: the metrics-missing alarm fires on a stopped box, so stop
# silences both GPU alarms and start re-arms them. Never fatal: the alarms are Should tier.
gpu_alarm_actions() {
  aws cloudwatch "$1-alarm-actions" --region us-east-1 --profile "$2" \
    --alarm-names xenia-gpu-box-unhealthy xenia-gpu-box-metrics-missing 2>/dev/null \
    || log "could not $1 the GPU alarms (not applied yet?)"
}

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

# wait_for_vllm_health: polls https://localhost:8443/health on the GPU box itself, bounded at 20
# minutes (first boot downloads weights; a warm reboot is healthy in well under a minute). Returns
# non-zero on timeout instead of dying: the caller updates the gateway either way (start.sh's own
# probe, Task 7-follow-up-a, is what actually decides real-api-base vs. placeholder).
wait_for_vllm_health() {
  local cid st i
  # shellcheck disable=SC2016  # this is the remote command's source, not something to expand here
  cid="$(aws_ ssm send-command --instance-ids "$id" --document-name AWS-RunShellScript \
    --parameters '{"commands":["for i in $(seq 1 240); do curl -fsk -m 3 -o /dev/null https://localhost:8443/health && { echo healthy; exit 0; }; sleep 5; done; echo timeout; exit 1"]}' \
    --query Command.CommandId --output text)"
  for ((i = 0; i < 450; i++)); do
    st="$(aws_ ssm get-command-invocation --command-id "$cid" --instance-id "$id" --query Status --output text 2>/dev/null || echo Pending)"
    case "$st" in Pending|InProgress|Delayed) sleep 3 ;; *) break ;; esac
  done
  aws_ ssm get-command-invocation --command-id "$cid" --instance-id "$id" \
    --query '[StandardOutputContent,StandardErrorContent]' --output text | mask
  [[ "$st" == "Success" ]]
}

read -r id state itype <<< "$(instance)"
[[ -n "${id:-}" && "$id" != "None" ]] || die "no GPU box found (tag xenia-role=gpu-box, profile $profile, $region)"

case "$action" in
  start)
    aws_ ec2 start-instances --instance-ids "$id" >/dev/null
    aws_ ec2 wait instance-running --instance-ids "$id"
    gpu_alarm_actions enable "$profile"
    log "GPU box running; waiting for vLLM to report healthy (up to 20 minutes on a first boot that has to download weights; a warm reboot is much faster)"
    if wait_for_vllm_health; then
      log "vLLM healthy"
    else
      log "vLLM still not healthy after 20 minutes; updating the gateway anyway — it will use the placeholder (fail over to Bedrock) until vLLM comes up"
    fi
    log "updating the gateway so it re-reads /xenia/gpu/api-base"
    "$KIT_ROOT/scripts/box.sh" xenia-gateway Action=update
    ;;
  stop)
    gpu_alarm_actions disable "$profile"
    aws_ ec2 stop-instances --instance-ids "$id" >/dev/null
    log "GPU box stopping; updating the gateway now so it fails over to Bedrock immediately instead of waiting on a future request to notice"
    "$KIT_ROOT/scripts/box.sh" xenia-gateway Action=update
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
    die "usage: scripts/gpu.sh start|stop|status|logs|weights|model <name>|capacity [region] [type]|capacity-log [n]"
    ;;
esac
