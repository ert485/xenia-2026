# The gateway talks to vLLM over TLS with a self-signed certificate it pins (start.sh bundles it) and
# a bearer token. Both live in the member account's SSM; the private key is also in Terraform state,
# which sits in the private, encrypted state bucket.
resource "random_password" "vllm_token" {
  length  = 48
  special = false
}

resource "tls_private_key" "vllm" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "vllm" {
  private_key_pem = tls_private_key.vllm.private_key_pem
  subject {
    common_name = "xenia-gpu-box"
  }
  ip_addresses          = [aws_eip.gpu.public_ip]
  validity_period_hours = 720
  set_subject_key_id    = true
  set_authority_key_id  = true
  allowed_uses          = ["key_encipherment", "digital_signature", "server_auth"]
}

resource "aws_ssm_parameter" "vllm_token" {
  name  = "/xenia/gpu/vllm-token"
  type  = "SecureString"
  value = random_password.vllm_token.result
}

resource "aws_ssm_parameter" "vllm_key" {
  name  = "/xenia/gpu/vllm-key"
  type  = "SecureString"
  value = tls_private_key.vllm.private_key_pem
}

resource "aws_ssm_parameter" "vllm_cert" {
  name  = "/xenia/gpu/vllm-cert"
  type  = "String"
  value = tls_self_signed_cert.vllm.cert_pem
}

resource "aws_ssm_parameter" "api_base" {
  name  = "/xenia/gpu/api-base"
  type  = "String"
  value = "https://${aws_eip.gpu.public_ip}:8443/v1"
}
