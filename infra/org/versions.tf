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
# The explicit profile here is load-bearing: scripts/tf.sh exports cohack (member account)
# credentials into the environment for the S3 backend, and in aws provider v6 an explicitly
# configured profile overrides those environment credentials, so this provider still runs as
# the management account.
provider "aws" {
  region  = "ca-central-1"
  profile = "personal-admin"
  default_tags {
    tags = { kit = "true", stack = "org", repo = "ert485/xenia-2026" }
  }
}
