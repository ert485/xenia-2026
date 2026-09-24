variable "member_account_id" { type = string }
variable "management_account_id" { type = string }
variable "zone_id" { type = string }
variable "state_bucket" { type = string }
variable "alert_email" { type = string }
variable "alert_sms" {
  description = "E.164 number already verified in this account's SNS SMS sandbox (ca-central-1)"
  type        = string
}
variable "alert_tiers" {
  description = "Actual-cost notification thresholds in USD (D13)"
  type        = list(number)
  default     = [10, 25, 50, 100, 150]
}
variable "forecast_threshold" {
  type    = number
  default = 150
}
variable "bedrock_alert" {
  description = "Alert when Bedrock spend in the member account passes this (USD)"
  type        = number
  default     = 25
}
