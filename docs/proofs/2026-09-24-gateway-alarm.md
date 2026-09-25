# Proof: the gateway health alarm reaches Erik by email and SMS

Date: 2026-09-25 01:47 and 01:49 UTC (Thursday evening CST). Plan Task 7, steps 14 to 16; spec §10
("Route 53 health check on `llm…/health` alarming to SNS with SMS").

## Why it's shaped this way

Route 53 health-check metrics exist only in us-east-1, so the alarm `xenia-llm-gateway-down` lives
there, and so does its email topic `xenia-gateway-alarm`. The member account's us-east-1 has no SMS
origination identity, so AWS can't deliver SMS to +1 numbers from it: the sandbox verification code
never arrived, and a voice resend was refused with `INVALID_PARAMETER originationIdentity`. SMS
does work from the member account's ca-central-1, where Erik's number is verified in the sandbox.
So an EventBridge rule in us-east-1 forwards the alarm's state changes to the ca-central-1 default
bus, and a rule there sends a short text through the topic `xenia-gateway-alarm-sms`.

## Test

```bash
aws cloudwatch set-alarm-state --alarm-name xenia-llm-gateway-down --state-value ALARM \
  --state-reason "Test of the gateway alarm relay (Task 7), not a real outage" --region us-east-1 --profile cohack
aws cloudwatch set-alarm-state --alarm-name xenia-llm-gateway-down --state-value OK \
  --state-reason "End of the relay test" --region us-east-1 --profile cohack
```

## Result

- 01:47 UTC: both texts arrived (ALARM, then OK). The email subscription wasn't confirmed yet, so
  no email was sent.
- 01:49 UTC, after the email subscription was confirmed: both emails arrived.

The night-shift teammate's number needs the same sandbox verification in the member account's
ca-central-1 on Saturday (`aws sns create-sms-sandbox-phone-number` then
`verify-sms-sandbox-phone-number`, both with `--region ca-central-1`), and a second SMS
subscription on `xenia-gateway-alarm-sms`.
