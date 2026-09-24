variable "account_id" {
  description = "Member account the guard rails protect"
  type        = string
}
variable "zone_id" {
  description = "Hosted zone whose deletion is denied"
  type        = string
}
variable "allowed_regions" {
  type    = list(string)
  default = ["ca-central-1", "us-east-1"]
}
