# 03: Thursday bootstrap

Status: **skeleton** — Task 3 wrote this page's bootstrap step; Task 7 appends the SMS sandbox
verification; Task 21 writes the full page.

1. `scripts/bootstrap.sh`: state bucket, lock table, `infra/backend.local.hcl`.

Verify:

    aws s3api get-bucket-versioning --bucket "$(awk -F'"' '/^bucket/ {print $2}' infra/backend.local.hcl)" --profile cohack

Expected: `Enabled`.

## Task 7: gateway alarm SMS sandbox verification

The gateway health alarm lives in us-east-1 (Route 53 health-check metrics only exist there), but
that region has no SMS origination identity in the member account, so SMS delivery is relayed
through a ca-central-1 topic instead. Verify the alert phone number in ca-central-1's SMS sandbox:

    aws sns create-sms-sandbox-phone-number --phone-number "<alert-sms>" --language-code en-US --profile cohack --region ca-central-1
    aws sns verify-sms-sandbox-phone-number --phone-number "<alert-sms>" --one-time-password <code-from-the-text> --profile cohack --region ca-central-1

Expected: `aws sns list-sms-sandbox-phone-numbers --profile cohack --region ca-central-1 --query 'PhoneNumbers[].Status'` returns `Verified`.

A night-shift teammate's number is verified the same way, still in ca-central-1: swap in their
`+1` number for `<alert-sms>` and repeat both commands.
