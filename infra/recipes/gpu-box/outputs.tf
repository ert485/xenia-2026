output "instance_id" { value = aws_instance.gpu.id }
output "public_ip" {
  value     = aws_eip.gpu.public_ip
  sensitive = true
}
output "host_profile" { value = var.gpu_host_profile }
