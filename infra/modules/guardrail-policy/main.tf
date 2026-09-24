# The deny list from spec section 5. A guard rail against expensive mistakes, not a security boundary.
data "aws_iam_policy_document" "deny" {
  statement {
    sid       = "DenyOrgBillingIdentityQuota"
    effect    = "Deny"
    actions   = ["organizations:*", "sso:*", "sso-directory:*", "budgets:*", "ce:*", "account:*", "aws-portal:*", "servicequotas:RequestServiceQuotaIncrease"]
    resources = ["*"]
  }
  statement {
    sid       = "DenyUnboundedPurchases"
    effect    = "Deny"
    actions   = ["shield:CreateSubscription", "route53domains:*", "aws-marketplace:Subscribe", "ec2:PurchaseReservedInstancesOffering", "ec2:PurchaseHostReservation", "savingsplans:*"]
    resources = ["*"]
  }
  statement {
    sid       = "DenyLongLivedCredentials"
    effect    = "Deny"
    actions   = ["iam:CreateUser", "iam:CreateAccessKey", "iam:CreateLoginProfile"]
    resources = ["*"]
  }
  statement {
    sid       = "DenyKitBucketMutation"
    effect    = "Deny"
    actions   = ["s3:DeleteBucket", "s3:PutBucketPolicy", "s3:DeleteBucketPolicy", "s3:PutBucketVersioning", "s3:PutLifecycleConfiguration", "s3:PutBucketPublicAccessBlock", "s3:PutBucketOwnershipControls", "s3:DeleteObjectVersion"]
    resources = ["arn:aws:s3:::xenia-tfstate-*", "arn:aws:s3:::xenia-backups-*"]
  }
  statement {
    sid     = "DenyKitIamMutation"
    effect  = "Deny"
    actions = ["iam:Delete*", "iam:Update*", "iam:Put*", "iam:Attach*", "iam:Detach*", "iam:TagRole", "iam:UntagRole", "iam:AddClientIDToOpenIDConnectProvider", "iam:RemoveClientIDFromOpenIDConnectProvider"]
    resources = [
      "arn:aws:iam::${var.account_id}:oidc-provider/token.actions.githubusercontent.com",
      "arn:aws:iam::${var.account_id}:role/xenia-deploy-*",
      "arn:aws:iam::${var.account_id}:role/xenia-preview-*",
      "arn:aws:iam::${var.account_id}:role/xenia-docker-box",
      "arn:aws:iam::${var.account_id}:role/xenia-gpu-box",
    ]
  }
  statement {
    sid       = "DenyZoneAndCertDeletion"
    effect    = "Deny"
    actions   = ["route53:DeleteHostedZone", "route53:UpdateHostedZoneComment", "route53:ChangeTagsForResource", "acm:DeleteCertificate", "acm:RemoveTagsFromCertificate"]
    resources = ["arn:aws:route53:::hostedzone/${var.zone_id}", "arn:aws:acm:us-east-1:${var.account_id}:certificate/*"]
  }
  statement {
    sid       = "DenyKitBoxSessions"
    effect    = "Deny"
    actions   = ["ssm:StartSession"]
    resources = ["arn:aws:ec2:*:${var.account_id}:instance/*"]
    condition {
      test     = "StringEquals"
      variable = "ssm:resourceTag/kit"
      values   = ["true"]
    }
  }
  statement {
    sid       = "DenyGatewayAndGpuSecrets"
    effect    = "Deny"
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParameterHistory", "ssm:GetParametersByPath", "ssm:PutParameter", "ssm:DeleteParameter"]
    resources = ["arn:aws:ssm:*:${var.account_id}:parameter/xenia/gateway/*", "arn:aws:ssm:*:${var.account_id}:parameter/xenia/gpu/*"]
  }
  statement {
    sid         = "DenyOtherRegions"
    effect      = "Deny"
    not_actions = ["iam:*", "sts:*", "organizations:*", "route53:*", "route53domains:*", "cloudfront:*", "support:*", "budgets:*", "ce:*", "health:*", "account:*", "tag:*", "resource-explorer-2:*", "s3:ListAllMyBuckets", "s3:GetBucketLocation", "servicequotas:*", "access-analyzer:*", "trustedadvisor:*", "pricing:*", "wafv2:*", "shield:*", "globalaccelerator:*"]
    resources   = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestedRegion"
      values   = var.allowed_regions
    }
  }
}
