variable "member_account_id" { type = string }
variable "management_account_id" { type = string }
variable "zone_id" {
  description = "Existing hosted zone, imported (never created) by this stack"
  type        = string
}
variable "zone_name" {
  type    = string
  default = "26.cohack.tetl.ca"
}
variable "state_bucket" { type = string }
variable "allowed_repos" {
  description = "owner/repo => deploy workflow files trusted to assume that repo's deploy role from main"
  type        = map(list(string))
}
variable "oidc_sub_prefixes" {
  description = <<-EOT
    owner/repo => the repo segment GitHub puts at the start of that repo's OIDC sub claim. Repos
    created after 2026-07-15 get immutable subject claims that GitHub will not let you turn off:
    the segment is repo:OWNER@OWNER_ID/REPO@REPO_ID, not repo:OWNER/REPO. Every key in
    allowed_repos needs an entry. scripts/onboard-repo.sh fills this in from
    gh api repos/OWNER/REPO/actions/oidc/customization/sub (the .sub_claim_prefix field).
  EOT
  type        = map(string)
}
