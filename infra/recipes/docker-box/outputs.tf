output "instance_id" { value = aws_instance.box.id }
output "public_ip" {
  value     = aws_eip.box.public_ip
  sensitive = true
}
output "security_group_id" { value = aws_security_group.box.id }
