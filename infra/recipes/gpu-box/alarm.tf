# Should tier (spec section 3): shipped; not proven end to end unless docs/proofs/2026-09-25-gpu-alarm.md exists.
# Two alarms on the GPU box, notifying the gateway's xenia-gateway-alarm topic (email and SMS to Erik and the
# night-shift teammate). A stopped box stops reporting and the second alarm treats missing data as
# breaching, so scripts/gpu.sh stop disables both alarms' actions and start enables them again.

locals {
  # Alarm actions publish to a topic in the alarm's own account. When the box is hosted in the management
  # account (deviation 9) the topic is in the member account: the alarms still exist and show state in the
  # console, but notify nobody. Runbook 04 says so.
  gpu_alarm_actions = local.same_account ? [data.terraform_remote_state.docker_box.outputs.gateway_alarm_topic_arn] : []
}

resource "aws_cloudwatch_metric_alarm" "gpu_unhealthy" {
  provider            = aws.gpu
  alarm_name          = "xenia-gpu-box-unhealthy"
  alarm_description   = "The GPU box failed an EC2 status check for three minutes. The gateway is failing over to Bedrock; run scripts/gpu.sh status."
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  dimensions          = { InstanceId = aws_instance.gpu.id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.gpu_alarm_actions
  ok_actions          = local.gpu_alarm_actions
  lifecycle {
    ignore_changes = [actions_enabled] # gpu.sh toggles it on stop and start
  }
}

# The CloudWatch agent (cloudwatch-agent.json, Task 10) reports nvidia_smi_utilization_gpu to xenia/gpu every
# minute while the box runs. Ten minutes with no datapoint means the agent, the driver, or the box is down.
# A Metrics Insights query aggregates across the agent's dimensions, so the alarm needs no dimension list.
resource "aws_cloudwatch_metric_alarm" "gpu_metrics_missing" {
  provider            = aws.gpu
  alarm_name          = "xenia-gpu-box-metrics-missing"
  alarm_description   = "No GPU utilisation reported for ten minutes while the GPU box should be running. Only meaningful while running; scripts/gpu.sh stop disables this alarm's actions."
  comparison_operator = "LessThanThreshold"
  threshold           = 0
  evaluation_periods  = 10
  datapoints_to_alarm = 10
  treat_missing_data  = "breaching"
  alarm_actions       = local.gpu_alarm_actions
  ok_actions          = local.gpu_alarm_actions
  metric_query {
    id          = "gpu"
    expression  = "SELECT MAX(nvidia_smi_utilization_gpu) FROM \"xenia/gpu\""
    period      = 60
    return_data = true
  }
  lifecycle {
    ignore_changes = [actions_enabled]
  }
}