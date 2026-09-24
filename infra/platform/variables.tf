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
