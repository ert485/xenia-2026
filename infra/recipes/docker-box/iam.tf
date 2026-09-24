data "aws_iam_policy_document" "box_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "box" {
  name               = "xenia-docker-box"
  assume_role_policy = data.aws_iam_policy_document.box_trust.json
}

resource "aws_iam_instance_profile" "box" {
  name = "xenia-docker-box"
  role = aws_iam_role.box.name
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.box.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

locals {
  acct = var.member_account_id
  zone = "arn:aws:route53:::hostedzone/${local.zone_id}"
}

data "aws_iam_policy_document" "box" {
  statement {
    sid       = "ContainerLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
    resources = ["arn:aws:logs:ca-central-1:${local.acct}:log-group:${local.platform.log_group_name}", "arn:aws:logs:ca-central-1:${local.acct}:log-group:${local.platform.log_group_name}:*"]
  }
  statement {
    sid       = "WriteBackups"
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${local.platform.backup_bucket}/*"]
  }
  statement {
    sid       = "Route53Lookups"
    actions   = ["route53:ListHostedZones", "route53:ListHostedZonesByName", "route53:GetChange"]
    resources = ["*"]
  }
  # DNS-01 only: the box may change _acme-challenge records in the kit zone and nothing else (spec section 6).
  statement {
    sid       = "AcmeChallengeRecordsOnly"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = [local.zone]
    condition {
      test     = "ForAllValues:StringLike"
      variable = "route53:ChangeResourceRecordSetsNormalizedRecordNames"
      values   = ["_acme-challenge.*"]
    }
  }
  statement {
    sid       = "ReadZoneRecords"
    actions   = ["route53:ListResourceRecordSets"]
    resources = [local.zone]
  }
  statement {
    sid     = "ReadKitParameters"
    actions = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
    resources = [
      "arn:aws:ssm:ca-central-1:${local.acct}:parameter/xenia/gateway/*",
      "arn:aws:ssm:ca-central-1:${local.acct}:parameter/xenia/gpu/*",
      "arn:aws:ssm:ca-central-1:${local.acct}:parameter/xenia/app/*",
    ]
  }
  statement {
    sid       = "BedrockQwen"
    actions   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
    resources = ["arn:aws:bedrock:us-east-1::foundation-model/qwen.*"]
  }
  statement {
    sid       = "PullAppImages"
    actions   = ["ecr:GetAuthorizationToken", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "box" {
  name   = "xenia-docker-box"
  role   = aws_iam_role.box.id
  policy = data.aws_iam_policy_document.box.json
}
