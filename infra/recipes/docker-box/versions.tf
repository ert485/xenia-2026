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

provider "aws" {
  region  = "ca-central-1"
  profile = "cohack"
  default_tags {
    tags = { kit = "true", stack = "recipes/docker-box", repo = "ert485/xenia-2026" }
  }
}

# us-east-1: the gateway health-check alarm and its SNS topic (Task 7), because Route 53 health-check
# metrics are published there.
provider "aws" {
  alias   = "use1"
  region  = "us-east-1"
  profile = "cohack"
  default_tags {
    tags = { kit = "true", stack = "recipes/docker-box", repo = "ert485/xenia-2026" }
  }
}
