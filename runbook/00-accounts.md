# 00: Accounts and Identity Center

Status: **done** Wednesday 2026-09-23 and verified Thursday 2026-09-24.

Erik: these steps made the personal account the Organizations management account and created the member account that holds everything else.

1. Confirmed the personal account was not a member of another organization.
2. Enabled Organizations (all features) and clicked the root-email verification link.
3. Enabled root access management (IAM console, **Root access management**, both capabilities), so the member account has no root credentials.
4. Created the member account `cohack-26` with a plus-address of Erik's mailbox as its root email.
5. Enabled Identity Center in ca-central-1 and, under **Settings, Authentication**, turned on **Send email OTP for users created from API** (without it `scripts/onboard-teammate.sh` users get no invitation).
6. Created Erik's user, the `admin` permission set, and assignments to both accounts; configured the CLI profiles `personal-admin` and `cohack` with `aws configure sso`.
7. Verified Erik's phone in the SNS SMS sandbox (management account, ca-central-1).

Verify:

    aws organizations list-accounts --profile personal-admin --query 'Accounts[].[Name,Status]' --output table
    aws sso-admin list-instances --profile personal-admin --region ca-central-1 --query 'Instances[].Status' --output text
    aws sns list-sms-sandbox-phone-numbers --profile personal-admin --region ca-central-1 --query 'PhoneNumbers[].Status' --output text

Expected: `cohack-26` is `ACTIVE`; `ACTIVE`; `Verified`.
