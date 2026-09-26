# The access kill switch (spec D40). Enabling SCPs on the root makes AWS attach FullAWSAccess to every
# root, OU, and account, so nothing changes until scripts/lockdown.sh attaches xenia-lockdown to the
# member account. SCPs never apply to the management account.
#
# The organization was created by hand (runbook 00) and is imported (step 17). Terraform can enable a
# policy type only through this resource, so it manages enabled_policy_types and nothing else: trusted
# access (Identity Center and IAM root access management depend on it) and the feature set are ignored,
# and the organization can never be destroyed from here (plan deviation 13).
resource "aws_organizations_organization" "this" {
  feature_set          = "ALL"
  enabled_policy_types = ["SERVICE_CONTROL_POLICY"]
  lifecycle {
    prevent_destroy = true
    ignore_changes  = [aws_service_access_principals, feature_set]
  }
}

# Deny everything unless the caller is Erik's admin Identity Center role, OrganizationAccountAccessRole
# (assumable only from the management account: Erik's second way in while locked), or a kit box instance role
# (the gateway, Bedrock failover, backups, and DNS-01 keep running). Service-linked roles are never
# affected by SCPs. Sessions already issued are cut too: SCPs are evaluated on every request.
data "aws_iam_policy_document" "lockdown" {
  statement {
    sid       = "XeniaLockdown"
    effect    = "Deny"
    actions   = ["*"]
    resources = ["*"]
    condition {
      test     = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values = [
        "arn:aws:iam::*:role/aws-reserved/sso.amazonaws.com/*AWSReservedSSO_admin_*",
        "arn:aws:iam::*:role/OrganizationAccountAccessRole",
        "arn:aws:iam::*:role/xenia-docker-box",
        "arn:aws:iam::*:role/xenia-gpu-box",
      ]
    }
  }
}

resource "aws_organizations_policy" "lockdown" {
  name        = "xenia-lockdown"
  description = "Break-glass access kill switch: deny everything in the member account except Erik's admin role, OrganizationAccountAccessRole, and the kit box roles. Never attached in normal operation; scripts/lockdown.sh attaches it."
  type        = "SERVICE_CONTROL_POLICY"
  content     = data.aws_iam_policy_document.lockdown.json
  depends_on  = [aws_organizations_organization.this]
}
