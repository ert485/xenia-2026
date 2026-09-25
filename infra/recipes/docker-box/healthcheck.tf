# Route 53 health check on the gateway (deviation 6: /health/readiness is unauthenticated and checks
# the database). Health-check metrics live in us-east-1, so the alarm and its topic do too.
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

resource "aws_sns_topic_subscription" "gateway_alarm_sms" {
  provider  = aws.use1
  topic_arn = aws_sns_topic.gateway_alarm.arn
  protocol  = "sms"
  endpoint  = var.alert_sms
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
