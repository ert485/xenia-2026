variable "member_account_id" { type = string }
variable "state_bucket" { type = string }
variable "instance_type" {
  description = "Docker box size (D24); resizing is this one variable"
  type        = string
  default     = "t4g.large"
}
variable "kit_repo" {
  description = "owner/repo the box clones its scripts from"
  type        = string
  default     = "ert485/xenia-2026"
}
variable "kit_ref" {
  description = "Branch the box clones at first boot; /etc/xenia.env KIT_REF can be changed later"
  type        = string
  default     = "main"
}
variable "app_port" {
  description = "Port the team's web service listens on inside its container"
  type        = number
  default     = 3000
}
variable "alert_email" {
  description = "Gateway health alarm email (Task 7)"
  type        = string
}
variable "alert_sms" {
  description = "Gateway health alarm SMS, E.164, verified in the member account's ca-central-1 SMS sandbox (Task 7; us-east-1 has no SMS origination identity in this account)"
  type        = string
}
