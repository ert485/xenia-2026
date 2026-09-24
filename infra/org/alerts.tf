resource "aws_sns_topic" "alerts" {
  name = "xenia-alerts"
}

data "aws_iam_policy_document" "alerts_topic" {
  statement {
    sid       = "AllowBudgetsPublish"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.management_account_id]
    }
  }
}
resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.alerts_topic.json
}

# Email needs a confirmation click (runbook 03). SMS works because the number is sandbox-verified here.
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
resource "aws_sns_topic_subscription" "sms" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "sms"
  endpoint  = var.alert_sms
}

# A budget allows five notifications, so the five actual tiers and the forecast are two budgets (both free).
resource "aws_budgets_budget" "actual" {
  name         = "xenia-actual"
  budget_type  = "COST"
  limit_amount = tostring(max(var.alert_tiers...))
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  cost_filter {
    name   = "LinkedAccount"
    values = [var.member_account_id]
  }
  dynamic "notification" {
    for_each = toset([for t in var.alert_tiers : tostring(t)])
    content {
      comparison_operator       = "GREATER_THAN"
      threshold                 = tonumber(notification.value)
      threshold_type            = "ABSOLUTE_VALUE"
      notification_type         = "ACTUAL"
      subscriber_sns_topic_arns = [aws_sns_topic.alerts.arn]
    }
  }
}

resource "aws_budgets_budget" "forecast" {
  name         = "xenia-forecast"
  budget_type  = "COST"
  limit_amount = tostring(var.forecast_threshold)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  cost_filter {
    name   = "LinkedAccount"
    values = [var.member_account_id]
  }
  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = var.forecast_threshold
    threshold_type            = "ABSOLUTE_VALUE"
    notification_type         = "FORECASTED"
    subscriber_sns_topic_arns = [aws_sns_topic.alerts.arn]
  }
}

# Third budget (about two cents a day): the Bedrock failover spend alert from spec section 10.
resource "aws_budgets_budget" "bedrock" {
  name         = "xenia-bedrock"
  budget_type  = "COST"
  limit_amount = tostring(var.bedrock_alert)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  cost_filter {
    name   = "LinkedAccount"
    values = [var.member_account_id]
  }
  cost_filter {
    name   = "Service"
    values = ["Amazon Bedrock"]
  }
  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = var.bedrock_alert
    threshold_type            = "ABSOLUTE_VALUE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.alerts.arn]
  }
}
