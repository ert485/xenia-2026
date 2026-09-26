# 06: Saturday

Status: **to do** Saturday 2026-09-26.

Erik: in this order.

1. **08:00** `scripts/gpu.sh start`, then `scripts/status.sh` after ten minutes: expect `status: green` with the gateway on `qwen3-coder-vllm`.
2. **After idea lock:**
    1. `gh repo create <owner>/<repo> --public` (private only if the team said so at idea lock).
    2. `scripts/onboard-repo.sh <owner>/<repo> --owners @a,@b` with the owners named at idea lock, and add `TEAM_REPO` and `TEAM_REPO_DIR` to `kit.local.env`.
    3. `scripts/onboard-teammate.sh <email> <first> <last>` for each person who wants AWS access; send each block by direct message.
    4. Create the Discord webhook, add `DISCORD_WEBHOOK_URL` to `kit.local.env`, and run `printf '%s' "$DISCORD_WEBHOOK_URL" | gh secret set DISCORD_WEBHOOK_URL --repo <owner>/<repo>` from a shell that sourced it.
    5. Subscribe the night-shift teammate's phone to the gateway alarm. The member account's SMS sandbox needs the number verified first (runbook 03, step 6, with their number and their code), then:

            read -r -p "night-shift phone (E.164): " NS_PHONE
            aws sns subscribe --protocol sms --notification-endpoint "$NS_PHONE" --profile cohack --region us-east-1 \
              --topic-arn "$(TF_NO_MASK=1 scripts/tf.sh recipes/docker-box output -raw gateway_alarm_topic_arn)"
            unset NS_PHONE

        This subscription is made by hand on purpose (the number must never reach a file); runbook 99 removes it.
    6. Enable the Codespaces prebuild in the team repo's settings (UI only), then watch the first `devcontainer-image` run.
    7. Tell the team the kit site: `https://26.cohack.tetl.ca`.