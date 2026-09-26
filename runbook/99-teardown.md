# 99: Teardown

Status: **to do** Sunday 2026-09-27 and after.

Erik: nobody keeps access or data by accident.

1. **Sunday 12:00**, in this order: stop what costs money, cut every live session, then remove the group's access. The lockdown matters because removing an assignment leaves sessions already issued alive for up to 12 hours; the SCP cuts them at once, CI roles included, and keeps the gateway up.

        scripts/shutdown.sh
        scripts/lockdown.sh
        scripts/tf.sh org destroy -target=aws_ssoadmin_account_assignment.hackathon_member

   Leave the lockdown on. If the team still needs a deploy for a post-event demo, `scripts/lockdown.sh --undo`, deploy, and lock again.

2. **Sunday 12:00**: unsubscribe the night-shift phone from `xenia-gateway-alarm`:

        aws sns list-subscriptions-by-topic --profile cohack --region us-east-1 \
          --topic-arn "$(TF_NO_MASK=1 scripts/tf.sh recipes/docker-box output -raw gateway_alarm_topic_arn)" \
          --query 'Subscriptions[?Protocol==`sms`].SubscriptionArn' --output text

    then `aws sns unsubscribe --subscription-arn <arn> --profile cohack --region us-east-1` for the teammate's entry.

3. **After the retro**: shred the sign-up sheet.
4. **After the retro**: delete `~/.xenia/teammates.tsv` once every teammate is offboarded (`scripts/offboard-teammate.sh <email>` for each).
5. **A week later**: delete the private idea-lock Discord channel.
6. **When the team is done with the demo**: `scripts/teardown.sh` (workloads), then, before `scripts/teardown.sh --all` (platform and org): `scripts/lockdown.sh --undo` (an attached policy can't be deleted) and `scripts/tf.sh org state rm aws_organizations_organization.this` (the organization outlives the event, and `prevent_destroy` would stop the destroy).
7. **Close the member account**: sign in to the management account console, **AWS Organizations, AWS accounts**, select `cohack-26`, **Close**. The account is suspended for 90 days (billing for anything left stops; it can be reopened in that window), then closed for good. Remaining S3 objects are deleted with it.
