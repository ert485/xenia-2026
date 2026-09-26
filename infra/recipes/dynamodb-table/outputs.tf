output "table_name" {
  value = aws_dynamodb_table.this.name
}

output "table_arn" {
  description = "Contains the account ID; mark it sensitive where a stack re-exports it"
  value       = aws_dynamodb_table.this.arn
  sensitive   = true
}