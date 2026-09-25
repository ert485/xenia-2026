variable "member_account_id" { type = string }
variable "management_account_id" { type = string }
variable "state_bucket" { type = string }
variable "gpu_host_profile" {
  description = "AWS profile of the account hosting the GPU box: cohack (member, default) or personal-admin (management)"
  type        = string
  default     = "cohack"
}
variable "instance_type" {
  description = "g6e.xlarge (L40S 48 GB); fallbacks g6e.2xlarge, then g5.xlarge with model gpt-oss-20b (spec section 18)"
  type        = string
  default     = "g6e.xlarge"
}
variable "availability_zone" {
  description = "Try another zone (us-east-1a to 1d offer g6e) on InsufficientInstanceCapacity"
  type        = string
  default     = "us-east-1a"
}
variable "kit_repo" {
  type    = string
  default = "ert485/xenia-2026"
}
variable "kit_ref" {
  type    = string
  default = "main"
}
variable "model" {
  description = "Key in models.yaml served at first boot; switch later with scripts/gpu.sh model"
  type        = string
  default     = "qwen3-coder-awq"
}
