output "hackathon_group_id" { value = aws_identitystore_group.hackathon.group_id }
output "identity_store_id" { value = local.id_store }
output "sso_instance_arn" { value = local.sso_arn }
output "alerts_topic_arn" {
  value     = aws_sns_topic.alerts.arn
  sensitive = true
}
