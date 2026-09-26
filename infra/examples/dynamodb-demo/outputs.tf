output "table_name" {
  value = module.demo.table_name
}

output "table_arn" {
  value     = module.demo.table_arn
  sensitive = true
}
