output "zone_id" { value = aws_route53_zone.this.zone_id }
output "zone_name" { value = var.zone_name }
output "name_servers" { value = aws_route53_zone.this.name_servers }
output "apex_certificate_arn" { value = aws_acm_certificate_validation.apex.certificate_arn }
output "backup_bucket" { value = aws_s3_bucket.backups.bucket }
output "log_group_name" { value = aws_cloudwatch_log_group.boxes.name }
output "oidc_provider_arn" {
  value     = aws_iam_openid_connect_provider.github.arn
  sensitive = true
}
output "deploy_role_arns" {
  value     = { for r, role in aws_iam_role.deploy : r => role.arn }
  sensitive = true
}
output "preview_role_arns" {
  value     = { for r, role in aws_iam_role.preview : r => role.arn }
  sensitive = true
}
output "ecr_repository_urls" {
  value     = { for r, repo in aws_ecr_repository.app : r => repo.repository_url }
  sensitive = true
}
output "ssm_prefix" { value = "/xenia" }
