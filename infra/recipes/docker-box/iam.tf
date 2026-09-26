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
  # DNS-01 only: the box may change _acme-challenge TXT records in the kit zone and nothing else
  # (spec section 6). Both conditions apply (a statement's conditions are ANDed): the record name
  # must match _acme-challenge.* AND its type must be TXT, so an A/CNAME/etc. under that name, or a
  # differently-named TXT record, is denied.
  statement {
    sid       = "AcmeChallengeRecordsOnly"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = [local.zone]
    condition {
      test     = "ForAllValues:StringLike"
      variable = "route53:ChangeResourceRecordSetsNormalizedRecordNames"
      values   = ["_acme-challenge.*"]
    }
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "route53:ChangeResourceRecordSetsRecordTypes"
      values   = ["TXT"]
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
      # GetParametersByPath is authorised against the path itself, not its children: without this
      # entry the box can read /xenia/app/<NAME> one by one but cannot list them (verified on the
      # box, 2026-09-26), and deploy.sh lists them to hand a team's secrets to compose.
      "arn:aws:ssm:ca-central-1:${local.acct}:parameter/xenia/app",
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
  # box/gpu-capacity-probe.sh (Task 7 follow-up problem 2): create-then-immediately-cancel a
  # 1-instance capacity reservation, us-east-1 only, so the box can tell whether g6e capacity exists
  # without a human SSO session. Nothing here is broader than that one workflow: Describe actions are
  # region-locked to us-east-1 (describe actions, which EC2 doesn't support resource-level ARNs for);
  # Create is region-locked, restricted to the two g6e sizes the probe uses, and requires the
  # purpose=capacity-probe tag on the request itself — without that tag condition, anything holding
  # the box role could create an untagged (real, billing) reservation the box then could not cancel,
  # since Cancel below requires that same tag on the resource. CreateTags is allowed only inside the
  # same CreateCapacityReservation call and only when tagging purpose=capacity-probe; Cancel is
  # allowed only against a reservation already carrying that same tag.
  statement {
    sid       = "GpuCapacityProbeDescribe"
    actions   = ["ec2:DescribeCapacityReservations", "ec2:DescribeInstanceTypeOfferings"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = ["us-east-1"]
    }
  }
  statement {
    sid       = "GpuCapacityProbeCreate"
    actions   = ["ec2:CreateCapacityReservation"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = ["us-east-1"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/purpose"
      values   = ["capacity-probe"]
    }
    condition {
      test     = "StringEquals"
      variable = "ec2:InstanceType"
      values   = ["g6e.xlarge", "g6e.2xlarge"]
    }
  }
  statement {
    sid       = "GpuCapacityProbeTagOnCreate"
    actions   = ["ec2:CreateTags"]
    resources = ["arn:aws:ec2:us-east-1:${local.acct}:capacity-reservation/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = ["us-east-1"]
    }
    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["CreateCapacityReservation"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/purpose"
      values   = ["capacity-probe"]
    }
  }
  statement {
    sid       = "GpuCapacityProbeCancelOwnReservations"
    actions   = ["ec2:CancelCapacityReservation"]
    resources = ["arn:aws:ec2:us-east-1:${local.acct}:capacity-reservation/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = ["us-east-1"]
    }
    condition {
      test     = "StringEquals"
      variable = "ec2:ResourceTag/purpose"
      values   = ["capacity-probe"]
    }
  }
}

resource "aws_iam_role_policy" "box" {
  name   = "xenia-docker-box"
  role   = aws_iam_role.box.id
  policy = data.aws_iam_policy_document.box.json
}
