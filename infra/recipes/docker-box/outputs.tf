output "instance_id" { value = aws_instance.box.id }
output "public_ip" {
  value     = aws_eip.box.public_ip
  sensitive = true
}
output "security_group_id" { value = aws_security_group.box.id }
# Read by the GPU box alarms (Task 26) through remote state.
output "gateway_alarm_topic_arn" {
  value     = aws_sns_topic.gateway_alarm.arn
  sensitive = true
}
