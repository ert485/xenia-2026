data "aws_ssoadmin_instances" "this" {}

locals {
  sso_arn  = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  id_store = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]
}

resource "aws_identitystore_group" "hackathon" {
  identity_store_id = local.id_store
  display_name      = "hackathon"
  description       = "Co.Hack 2026 teammates; hackathon-dev on the member account until Sunday 12:00"
}

resource "aws_ssoadmin_permission_set" "hackathon_dev" {
  instance_arn     = local.sso_arn
  name             = "hackathon-dev"
  description      = "AdministratorAccess minus the kit guard rails (spec section 5)"
  session_duration = "PT12H"
}

resource "aws_ssoadmin_managed_policy_attachment" "hackathon_admin" {
  instance_arn       = local.sso_arn
  permission_set_arn = aws_ssoadmin_permission_set.hackathon_dev.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

module "guardrail" {
  source     = "../modules/guardrail-policy"
  account_id = var.member_account_id
  zone_id    = var.zone_id
}

# Pre-flight ruling 4.3: ssm:SendCommand reaches the gateway master key the same way
# ssm:StartSession does, so the permission set (unlike the deploy role, which needs
# SendCommand to run the preview/deploy SSM documents) also denies it on kit-tagged
# instances. Merged onto the shared guardrail module's JSON rather than editing the
# module, since the deploy role must NOT carry this deny.
data "aws_iam_policy_document" "hackathon_guardrail" {
  source_policy_documents = [module.guardrail.json]

  statement {
    sid       = "DenyKitBoxSendCommand"
    effect    = "Deny"
    actions   = ["ssm:SendCommand"]
    resources = ["arn:aws:ec2:*:*:instance/*"]
    condition {
      test     = "StringEquals"
      variable = "ssm:resourceTag/kit"
      values   = ["true"]
    }
  }
}

resource "aws_ssoadmin_permission_set_inline_policy" "hackathon_guardrail" {
  instance_arn       = local.sso_arn
  permission_set_arn = aws_ssoadmin_permission_set.hackathon_dev.arn
  inline_policy      = data.aws_iam_policy_document.hackathon_guardrail.json
}

# Assigned to the group, never to individuals. Runbook 99a removes this resource on Sunday 12:00.
resource "aws_ssoadmin_account_assignment" "hackathon_member" {
  instance_arn       = local.sso_arn
  permission_set_arn = aws_ssoadmin_permission_set.hackathon_dev.arn
  principal_id       = aws_identitystore_group.hackathon.group_id
  principal_type     = "GROUP"
  target_id          = var.member_account_id
  target_type        = "AWS_ACCOUNT"
}
