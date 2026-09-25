# Route 53 health check on the gateway (deviation 6: /health/readiness is unauthenticated and checks
# the database). Health-check metrics live in us-east-1, so the alarm, its topic, and the EMAIL
# subscription do too. The member account's us-east-1 has no SMS origination identity, so SMS is
# relayed instead through a ca-central-1 topic, where the sandbox number is verified (see below).
resource "aws_route53_health_check" "llm" {
  fqdn              = "llm.${local.zone_name}"
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health/readiness"
  request_interval  = 30
  failure_threshold = 3
  tags              = { Name = "xenia-llm-gateway" }
}

resource "aws_sns_topic" "gateway_alarm" {
  provider = aws.use1
  name     = "xenia-gateway-alarm"
}

resource "aws_sns_topic_subscription" "gateway_alarm_email" {
  provider  = aws.use1
  topic_arn = aws_sns_topic.gateway_alarm.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "gateway_down" {
  provider            = aws.use1
  alarm_name          = "xenia-llm-gateway-down"
  alarm_description   = "llm.${local.zone_name}/health/readiness failing from Route 53 health checkers"
  namespace           = "AWS/Route53"
  metric_name         = "HealthCheckStatus"
  dimensions          = { HealthCheckId = aws_route53_health_check.llm.id }
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.gateway_alarm.arn]
  ok_actions          = [aws_sns_topic.gateway_alarm.arn]
}

# --- SMS relay: ca-central-1, where SMS delivery actually works in the sandbox ---

resource "aws_sns_topic" "gateway_alarm_sms" {
  name = "xenia-gateway-alarm-sms"
}

resource "aws_sns_topic_subscription" "gateway_alarm_sms" {
  topic_arn = aws_sns_topic.gateway_alarm_sms.arn
  protocol  = "sms"
  endpoint  = var.alert_sms
}

data "aws_iam_policy_document" "gateway_alarm_sms_topic" {
  statement {
    sid     = "AllowEventBridgePublish"
    effect  = "Allow"
    actions = ["sns:Publish"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    resources = [aws_sns_topic.gateway_alarm_sms.arn]
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.gateway_alarm_relay_target.arn]
    }
  }
}

resource "aws_sns_topic_policy" "gateway_alarm_sms" {
  arn    = aws_sns_topic.gateway_alarm_sms.arn
  policy = data.aws_iam_policy_document.gateway_alarm_sms_topic.json
}

# --- Relay: us-east-1 alarm state change -> ca-central-1 default event bus -> SMS topic ---

data "aws_iam_policy_document" "gateway_alarm_relay_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "gateway_alarm_relay" {
  provider           = aws.use1
  name               = "xenia-gateway-alarm-relay"
  assume_role_policy = data.aws_iam_policy_document.gateway_alarm_relay_assume.json
}

data "aws_iam_policy_document" "gateway_alarm_relay_put_events" {
  statement {
    effect    = "Allow"
    actions   = ["events:PutEvents"]
    resources = ["arn:aws:events:ca-central-1:${var.member_account_id}:event-bus/default"]
  }
}

resource "aws_iam_role_policy" "gateway_alarm_relay_put_events" {
  provider = aws.use1
  name     = "put-events-ca-central-1-default-bus"
  role     = aws_iam_role.gateway_alarm_relay.id
  policy   = data.aws_iam_policy_document.gateway_alarm_relay_put_events.json
}

resource "aws_cloudwatch_event_rule" "gateway_alarm_relay_source" {
  provider    = aws.use1
  name        = "xenia-gateway-alarm-relay"
  description = "Relays gateway alarm ALARM/OK transitions to the ca-central-1 default bus for SMS."
  event_pattern = jsonencode({
    source      = ["aws.cloudwatch"]
    detail-type = ["CloudWatch Alarm State Change"]
    resources   = [aws_cloudwatch_metric_alarm.gateway_down.arn]
    detail = {
      state = {
        value = ["ALARM", "OK"]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "gateway_alarm_relay_target" {
  provider = aws.use1
  rule     = aws_cloudwatch_event_rule.gateway_alarm_relay_source.name
  arn      = "arn:aws:events:ca-central-1:${var.member_account_id}:event-bus/default"
  role_arn = aws_iam_role.gateway_alarm_relay.arn
}

# ca-central-1 side: the rule this account's default bus receives the relayed event on, and the
# name the SNS topic policy above scopes its Allow to.
resource "aws_cloudwatch_event_rule" "gateway_alarm_relay_target" {
  name        = "xenia-gateway-alarm-sms"
  description = "Gateway alarm ALARM/OK transitions relayed from us-east-1, fanned out to SMS."
  event_pattern = jsonencode({
    source      = ["aws.cloudwatch"]
    detail-type = ["CloudWatch Alarm State Change"]
    detail = {
      alarmName = [aws_cloudwatch_metric_alarm.gateway_down.alarm_name]
      state = {
        value = ["ALARM", "OK"]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "gateway_alarm_relay_sms" {
  rule = aws_cloudwatch_event_rule.gateway_alarm_relay_target.name
  arn  = aws_sns_topic.gateway_alarm_sms.arn

  input_transformer {
    input_paths = {
      state  = "$.detail.state.value"
      reason = "$.detail.state.reason"
    }
    # SMS is ~160 chars; keep this short. <reason> is CloudWatch's own text, already terse.
    input_template = "\"xenia gateway <state>: <reason>\""
  }

  depends_on = [aws_sns_topic_policy.gateway_alarm_sms]
}
