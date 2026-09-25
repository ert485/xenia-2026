data "terraform_remote_state" "platform" {
  backend = "s3"
  config = {
    bucket  = var.state_bucket
    key     = "platform.tfstate"
    region  = "ca-central-1"
    profile = "cohack"
  }
}

data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-arm64"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

locals {
  platform  = data.terraform_remote_state.platform.outputs
  zone_id   = local.platform.zone_id
  zone_name = local.platform.zone_name
  subnet_id = sort(data.aws_subnets.default.ids)[0]
}

resource "aws_security_group" "box" {
  name        = "xenia-docker-box"
  description = "Docker box: HTTP and HTTPS in (Caddy), everything out. No SSH: admin is SSM only."
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description      = "HTTP (redirects to HTTPS)"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  ingress {
    description      = "HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  tags = { Name = "xenia-docker-box" }
}

resource "aws_instance" "box" {
  ami                    = data.aws_ssm_parameter.al2023_arm64.insecure_value
  instance_type          = var.instance_type
  subnet_id              = local.subnet_id
  vpc_security_group_ids = [aws_security_group.box.id]
  iam_instance_profile   = aws_iam_instance_profile.box.name

  user_data = templatefile("${path.module}/user-data.sh", {
    kit_repo      = var.kit_repo
    kit_ref       = var.kit_ref
    zone_name     = local.zone_name
    log_group     = local.platform.log_group_name
    backup_bucket = local.platform.backup_bucket
    app_port      = var.app_port
  })

  # Deviation 1: IMDSv2 required, hop limit 2 so Caddy (Route 53 DNS-01) and LiteLLM (Bedrock) can use
  # the instance role from containers on the backend network (bridge gw0); the iptables guard in
  # user-data drops metadata traffic from every other bridge.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size = 60
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name         = "xenia-docker-box"
    "xenia-role" = "docker-box"
  }

  # user_data runs only at first boot; later changes (for example kit_ref) are made on the box through
  # /etc/xenia.env, so a changed template must not stop and restart a running box.
  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

resource "aws_eip" "box" {
  domain = "vpc"
  tags   = { Name = "xenia-docker-box" }
}

resource "aws_eip_association" "box" {
  instance_id   = aws_instance.box.id
  allocation_id = aws_eip.box.id
}
