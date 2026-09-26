# Should tier (spec section 9): an on-demand DynamoDB table with TTL. PITR and deletion protection default
# on (the realistic weekend risk is an agent wiping a table, D15); previews turn both off.
# A module: no backend and no provider block; the calling stack's default tags apply.
terraform {
  required_version = "~> 1.5.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

locals {
  table_name = var.name_suffix == "" ? var.name : "${var.name}-${var.name_suffix}"
}

resource "aws_dynamodb_table" "this" {
  name                        = local.table_name
  billing_mode                = "PAY_PER_REQUEST"
  hash_key                    = var.hash_key
  range_key                   = var.range_key
  deletion_protection_enabled = var.deletion_protection

  attribute {
    name = var.hash_key
    type = "S"
  }

  dynamic "attribute" {
    for_each = var.range_key == null ? [] : [var.range_key]
    content {
      name = attribute.value
      type = "S"
    }
  }

  dynamic "ttl" {
    for_each = var.ttl_attribute == null ? [] : [var.ttl_attribute]
    content {
      attribute_name = ttl.value
      enabled        = true
    }
  }

  point_in_time_recovery {
    enabled = var.point_in_time_recovery
  }

  tags = {
    Name = local.table_name
  }
}
