data "terraform_remote_state" "docker_box" {
  backend = "s3"
  config = {
    bucket  = var.state_bucket
    key     = "recipes-docker-box.tfstate"
    region  = "ca-central-1"
    profile = "cohack"
  }
}

data "aws_ssm_parameter" "dlami" {
  provider = aws.gpu
  name     = "/aws/service/deeplearning/ami/x86_64/base-oss-nvidia-driver-gpu-ubuntu-24.04/latest/ami-id"
}

data "aws_vpc" "gpu" {
  provider = aws.gpu
  default  = true
}

data "aws_subnet" "gpu" {
  provider          = aws.gpu
  vpc_id            = data.aws_vpc.gpu.id
  availability_zone = var.availability_zone
  default_for_az    = true
}

locals {
  models       = yamldecode(file("${path.module}/models.yaml"))
  model        = local.models.models[var.model]
  docker_box   = data.terraform_remote_state.docker_box.outputs.public_ip
  same_account = var.gpu_host_profile == "cohack"
}

resource "aws_security_group" "gpu" {
  provider    = aws.gpu
  name        = "xenia-gpu-box"
  description = "vLLM over TLS, reachable only from the Docker box's Elastic IP"
  vpc_id      = data.aws_vpc.gpu.id
  ingress {
    description = "vLLM (TLS) from the gateway only"
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = ["${local.docker_box}/32"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "xenia-gpu-box" }
}

resource "aws_eip" "gpu" {
  provider = aws.gpu
  domain   = "vpc"
  tags     = { Name = "xenia-gpu-box" }
}

resource "aws_instance" "gpu" {
  provider               = aws.gpu
  ami                    = data.aws_ssm_parameter.dlami.insecure_value
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnet.gpu.id
  vpc_security_group_ids = [aws_security_group.gpu.id]
  iam_instance_profile   = aws_iam_instance_profile.gpu.name

  user_data = templatefile("${path.module}/user-data.sh", {
    kit_repo        = var.kit_repo
    kit_ref         = var.kit_ref
    reader_role_arn = local.same_account ? "" : aws_iam_role.reader[0].arn
    model_repo      = local.model.repo
    tool_parser     = local.model.tool_parser
    max_num_seqs    = local.model.max_num_seqs
    extra_args      = local.model.extra_args
  })

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size = 200
    volume_type = "gp3"
    throughput  = 250
    encrypted   = true
  }

  tags = {
    Name         = "xenia-gpu-box"
    "xenia-role" = "gpu-box"
  }

  # The secrets must exist before first boot reads them.
  depends_on = [
    aws_ssm_parameter.vllm_token,
    aws_ssm_parameter.vllm_key,
    aws_ssm_parameter.vllm_cert,
  ]

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

resource "aws_eip_association" "gpu" {
  provider      = aws.gpu
  instance_id   = aws_instance.gpu.id
  allocation_id = aws_eip.gpu.id
}
