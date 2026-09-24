resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]
}

module "guardrail" {
  source     = "../modules/guardrail-policy"
  account_id = var.member_account_id
  zone_id    = var.zone_id
}

locals {
  repo_slug = { for r, _ in var.allowed_repos : r => replace(r, "/", "-") }
  # "" when missing, so the role preconditions below report it instead of an index error.
  sub_prefix = { for r, _ in var.allowed_repos : r => lookup(var.oidc_sub_prefixes, r, "") }
  # A prefix must name its own repo: repo:OWNER@<id>/REPO@<id>.
  sub_prefix_ok = {
    for r, _ in var.allowed_repos : r => (
      startswith(local.sub_prefix[r], "repo:${split("/", r)[0]}@") &&
      strcontains(local.sub_prefix[r], "/${split("/", r)[1]}@")
    )
  }
}

# deploy: trusted only from main AND only from the named workflow files (D31, D35). Requires the
# repo's OIDC sub customization: include_claim_keys = [repo, context, job_workflow_ref]. The repo
# segment uses GitHub's immutable form (var.oidc_sub_prefixes); job_workflow_ref keeps plain names.
data "aws_iam_policy_document" "deploy_trust" {
  for_each = var.allowed_repos
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for wf in each.value : "${local.sub_prefix[each.key]}:ref:refs/heads/main:job_workflow_ref:${each.key}/.github/workflows/${wf}@refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  for_each             = var.allowed_repos
  name                 = "xenia-deploy-${local.repo_slug[each.key]}"
  assume_role_policy   = data.aws_iam_policy_document.deploy_trust[each.key].json
  max_session_duration = 3600
  lifecycle {
    precondition {
      condition     = local.sub_prefix_ok[each.key]
      error_message = "oidc_sub_prefixes has no valid entry for this repo: it needs repo:OWNER@OWNER_ID/REPO@REPO_ID from gh api repos/OWNER/REPO/actions/oidc/customization/sub (.sub_claim_prefix), in infra/platform/oidc-sub-prefixes.auto.tfvars.json."
    }
  }
}
resource "aws_iam_role_policy_attachment" "deploy_admin" {
  for_each   = var.allowed_repos
  role       = aws_iam_role.deploy[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
resource "aws_iam_role_policy" "deploy_guardrail" {
  for_each = var.allowed_repos
  role     = aws_iam_role.deploy[each.key].id
  name     = "guardrail"
  policy   = module.guardrail.json
}

# preview: trusted from any ref of the repo, may only run the two preview documents on the Docker box.
data "aws_iam_policy_document" "preview_trust" {
  for_each = var.allowed_repos
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.sub_prefix[each.key]}:*"]
    }
  }
}
data "aws_iam_policy_document" "preview_permissions" {
  statement {
    sid     = "RunPreviewDocuments"
    actions = ["ssm:SendCommand"]
    resources = [
      "arn:aws:ssm:ca-central-1:${var.member_account_id}:document/xenia-preview-up",
      "arn:aws:ssm:ca-central-1:${var.member_account_id}:document/xenia-preview-down",
    ]
  }
  statement {
    sid       = "TargetDockerBoxOnly"
    actions   = ["ssm:SendCommand"]
    resources = ["arn:aws:ec2:ca-central-1:${var.member_account_id}:instance/*"]
    condition {
      test     = "StringEquals"
      variable = "ssm:resourceTag/xenia-role"
      values   = ["docker-box"]
    }
  }
  statement {
    sid       = "ReadCommandOutput"
    actions   = ["ssm:GetCommandInvocation", "ssm:ListCommandInvocations", "ssm:ListCommands", "ssm:DescribeInstanceInformation"]
    resources = ["*"]
  }
}
resource "aws_iam_role" "preview" {
  for_each             = var.allowed_repos
  name                 = "xenia-preview-${local.repo_slug[each.key]}"
  assume_role_policy   = data.aws_iam_policy_document.preview_trust[each.key].json
  max_session_duration = 3600
  lifecycle {
    precondition {
      condition     = local.sub_prefix_ok[each.key]
      error_message = "oidc_sub_prefixes has no valid entry for this repo: it needs repo:OWNER@OWNER_ID/REPO@REPO_ID from gh api repos/OWNER/REPO/actions/oidc/customization/sub (.sub_claim_prefix), in infra/platform/oidc-sub-prefixes.auto.tfvars.json."
    }
  }
}
resource "aws_iam_role_policy" "preview" {
  for_each = var.allowed_repos
  role     = aws_iam_role.preview[each.key].id
  name     = "preview-only"
  policy   = data.aws_iam_policy_document.preview_permissions.json
}
