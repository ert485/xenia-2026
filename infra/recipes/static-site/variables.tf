variable "domain" {
  description = "Hostname the site answers on, for example 26.cohack.tetl.ca or web.26.cohack.tetl.ca"
  type        = string
}
variable "zone_id" {
  description = "Route 53 zone that holds var.domain"
  type        = string
}
variable "certificate_arn" {
  description = "ACM certificate in us-east-1 covering var.domain (CloudFront reads certificates only from there)"
  type        = string
}
variable "name" {
  description = "Short name used in the bucket and distribution names"
  type        = string
}
