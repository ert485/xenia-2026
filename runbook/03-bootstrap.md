# 03: Thursday bootstrap

Status: **skeleton** — Task 3 wrote this page's bootstrap step; Task 7 appends the SMS sandbox
verification; Task 21 writes the full page.

1. `scripts/bootstrap.sh`: state bucket, lock table, `infra/backend.local.hcl`.

Verify:

    aws s3api get-bucket-versioning --bucket "$(awk -F'"' '/^bucket/ {print $2}' infra/backend.local.hcl)" --profile cohack

Expected: `Enabled`.
