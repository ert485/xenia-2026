# Each kit SSM document is a YAML file under ssm/ whose single runCommand calls a box script.
resource "aws_ssm_document" "gateway" {
  name            = "xenia-gateway"
  document_type   = "Command"
  document_format = "YAML"
  content         = file("${path.module}/ssm/gateway.yaml")
}

resource "aws_ssm_document" "deploy" {
  name            = "xenia-deploy"
  document_type   = "Command"
  document_format = "YAML"
  content         = file("${path.module}/ssm/deploy.yaml")
}
