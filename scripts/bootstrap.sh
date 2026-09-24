#!/usr/bin/env bash
# Creates the Terraform state bucket and lock table in the member account (idempotent) and writes
# infra/backend.local.hcl (gitignored). Run once, Thursday morning, before any scripts/tf.sh init.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
load_env
require_cmd aws openssl
require_profile cohack "$MEMBER_ACCOUNT_ID"

region=ca-central-1
backend="${KIT_BACKEND_FILE:-$KIT_ROOT/infra/backend.local.hcl}"
table=xenia-tflock

if [[ -f "$backend" ]]; then
  bucket="$(awk -F'"' '/^bucket/ {print $2}' "$backend")"
  log "reusing state bucket from $backend"
else
  bucket="xenia-tfstate-$(openssl rand -hex 3)"
fi

if ! aws s3api head-bucket --bucket "$bucket" --profile cohack >/dev/null 2>&1; then
  aws s3api create-bucket --bucket "$bucket" --region "$region" \
    --create-bucket-configuration LocationConstraint="$region" --profile cohack >/dev/null
  aws s3api put-bucket-versioning --bucket "$bucket" --versioning-configuration Status=Enabled --profile cohack
  aws s3api put-public-access-block --bucket "$bucket" --profile cohack \
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
  aws s3api put-bucket-encryption --bucket "$bucket" --profile cohack \
    --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
  aws s3api put-bucket-tagging --bucket "$bucket" --tagging 'TagSet=[{Key=kit,Value=true}]' --profile cohack
  log "created state bucket"
fi

if ! aws dynamodb describe-table --table-name "$table" --region "$region" --profile cohack >/dev/null 2>&1; then
  aws dynamodb create-table --table-name "$table" --region "$region" --profile cohack \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST \
    --tags Key=kit,Value=true >/dev/null
  aws dynamodb wait table-exists --table-name "$table" --region "$region" --profile cohack
  log "created lock table $table"
fi

mkdir -p "$(dirname "$backend")"
cat > "$backend" <<EOF
bucket         = "$bucket"
dynamodb_table = "$table"
region         = "$region"
encrypt        = true
EOF
log "wrote $backend"
