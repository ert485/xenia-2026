terraform {
  required_version = "~> 1.5.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  backend "s3" {}
}

# Resources live in the management account; state lives in the member account's bucket (backend profile cohack).
provider "aws" {
  region  = "ca-central-1"
  profile = "personal-admin"
  default_tags {
    tags = { kit = "true", stack = "org", repo = "ert485/xenia-2026" }
  }
}
