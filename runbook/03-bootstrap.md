# 03: Thursday bootstrap

Status: **done** Thursday 2026-09-24 (this page records the order, for a rebuild).

Erik: each `apply` asks for a typed `yes`. Values come from `kit.local.env` (gitignored); nothing here needs an ID typed in.

1. Copy `kit.local.env.example` to `kit.local.env` and fill it in from the project memory note.
2. `scripts/bootstrap.sh`: state bucket, lock table, `infra/backend.local.hcl`.
3. `scripts/tf.sh org init && scripts/tf.sh org apply`: the `hackathon` group, permission set, budgets, alert topic. Click the confirmation link in the SNS email.
4. `scripts/tf.sh platform init`, import the existing zone (`scripts/tf.sh platform import aws_route53_zone.this "$(awk -F= '/^ZONE_ID/ {print $2}' kit.local.env)"`), then `scripts/tf.sh platform apply`.
5. `scripts/tf.sh recipes/docker-box init && scripts/tf.sh recipes/docker-box apply`, then seed the gateway secrets:

        scripts/put-secret.sh gateway/master-key "sk-$(openssl rand -hex 32)"
        scripts/put-secret.sh gateway/postgres-password "$(openssl rand -hex 24)"
        scripts/box.sh xenia-gateway Action=restart

6. Confirm the `xenia-gateway-alarm` email subscription, and verify the alarm phone in the **member** account's us-east-1 SMS sandbox (the health-check metric lives there, and each account and region has its own sandbox). Type the number at the prompt; it is never written to a file:

        read -r -p "alarm phone (E.164): " ALARM_PHONE
        aws sns create-sms-sandbox-phone-number --phone-number "$ALARM_PHONE" --language-code en-US --profile cohack --region us-east-1
        read -r -p "code from the SMS: " OTP
        aws sns verify-sms-sandbox-phone-number --phone-number "$ALARM_PHONE" --one-time-password "$OTP" --profile cohack --region us-east-1
        unset ALARM_PHONE OTP

7. `scripts/tf.sh recipes/gpu-box init && scripts/tf.sh recipes/gpu-box apply`, then `scripts/box.sh xenia-gateway Action=restart` so the gateway reads the GPU's address and token.
8. `scripts/tf.sh examples/kit-site init && scripts/tf.sh examples/kit-site apply`, then set the site's two publish secrets, `KIT_SITE_BUCKET` and `KIT_SITE_DISTRIBUTION_ID`, from its outputs.

Expect the `$10` budget notification by email and SMS on Thursday afternoon: it is the canary that proves the alerts are wired.
