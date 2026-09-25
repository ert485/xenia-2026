terraform {
  required_version = "~> 1.5.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
  backend "s3" {}
}

# Member account, ca-central-1: the SSM parameters the gateway reads.
provider "aws" {
  region  = "ca-central-1"
  profile = "cohack"
  default_tags {
    tags = { kit = "true", stack = "recipes/gpu-box", repo = "ert485/xenia-2026" }
  }
}

# The GPU box's host, us-east-1 (this stack's us-east-1 provider, named for what it hosts).
# personal-admin hosts it in the management account instead (deviation 9).
provider "aws" {
  alias   = "gpu"
  region  = "us-east-1"
  profile = var.gpu_host_profile
  default_tags {
    tags = { kit = "true", stack = "recipes/gpu-box", repo = "ert485/xenia-2026" }
  }
}
