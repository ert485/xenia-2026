#!/usr/bin/env bash
# Usage: scripts/teardown.sh [--all]
# After the event: stops everything (scripts/shutdown.sh), then destroys the workload stacks in
# order, each only after a typed "yes": recipes/gpu-box, examples/kit-site, recipes/docker-box.
# --all also offers platform (the zone survives unless you say otherwise) and org.
# Closing the member account is a console step afterwards (runbook 99).
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
load_env
require_cmd aws
require_profile cohack "$MEMBER_ACCOUNT_ID"

all=0
for arg in "$@"; do
  case "$arg" in
    --all) all=1 ;;
    *) die "unknown argument: $arg (use --all)" ;;
  esac
done

tf() { "$KIT_ROOT/scripts/tf.sh" "$@"; }
ask() { local ans=""; read -r -p "$1 [type yes]: " ans || true; [[ "$ans" == "yes" ]]; }

log "== shutdown first"
"$KIT_ROOT/scripts/shutdown.sh" || log "warning: some shutdown entries failed; the destroys below still run"

log "== recipes/gpu-box: the GPU box and its 200 GB weights volume"
if ask "Destroy recipes/gpu-box?"; then tf recipes/gpu-box destroy; else log "kept recipes/gpu-box"; fi

log "== examples/kit-site: the public kit site at the apex"
if ask "Destroy examples/kit-site?"; then
  bucket="$(TF_NO_MASK=1 tf examples/kit-site output -raw bucket 2>/dev/null || true)"
  if [[ -n "$bucket" ]]; then aws s3 rm "s3://$bucket" --recursive --profile cohack --only-show-errors; fi
  tf examples/kit-site destroy
else
  log "kept examples/kit-site"
fi

log "== recipes/docker-box: the gateway (its Postgres holds keys and spend history), the demo app, previews"
log "   the hourly backups stay in the backup bucket"
if ask "Destroy recipes/docker-box?"; then tf recipes/docker-box destroy; else log "kept recipes/docker-box"; fi

if [[ "$all" == 1 ]]; then
  log "== platform: zone, certificate, OIDC roles, ECR, parameters"
  if ask "Destroy platform?"; then
    if ask "Keep the Route 53 zone (26.cohack.tetl.ca) and its GoDaddy delegation?"; then
      tf platform state rm aws_route53_zone.this
    else
      log "the zone has prevent_destroy: remove that lifecycle block from infra/platform/dns.tf, then re-run with --all"
    fi
    # The backups and container logs outlive the stack; closing the account removes them.
    tf platform state rm aws_s3_bucket.backups aws_s3_bucket_versioning.backups aws_s3_bucket_public_access_block.backups \
      aws_s3_bucket_lifecycle_configuration.backups aws_cloudwatch_log_group.boxes
    tf platform destroy
  else
    log "kept platform"
  fi
  log "== org: hackathon group, permission set, budgets, alert topic (management account)"
  if ask "Destroy org?"; then tf org destroy; else log "kept org"; fi
fi

cat <<'EOF'

What remains (on purpose):
  - the Terraform state bucket xenia-tfstate-* and lock table xenia-tflock (scripts/bootstrap.sh made them)
  - the backup bucket xenia-backups-* (hourly dumps, 14-day expiry) and the /xenia/boxes log group
  - the Route 53 zone, if you kept it
To remove everything: close the member account (runbook 99, step 7). It is suspended for 90 days,
then closed; its S3 objects go with it. Check the billing console afterwards: your AWS bill is yours.
EOF