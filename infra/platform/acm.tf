# Kit-site certificate for CloudFront: must live in us-east-1.
resource "aws_acm_certificate" "apex" {
  provider          = aws.use1
  domain_name       = var.zone_name
  validation_method = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}

locals {
  apex_dvo = { for o in aws_acm_certificate.apex.domain_validation_options : o.domain_name => o }
}

resource "aws_route53_record" "apex_validation" {
  # Keys come from config, not the certificate, so `terraform import` can evaluate for_each before the cert exists.
  for_each        = toset([var.zone_name])
  zone_id         = aws_route53_zone.this.zone_id
  name            = local.apex_dvo[each.key].resource_record_name
  type            = local.apex_dvo[each.key].resource_record_type
  ttl             = 60
  records         = [local.apex_dvo[each.key].resource_record_value]
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "apex" {
  provider                = aws.use1
  certificate_arn         = aws_acm_certificate.apex.arn
  validation_record_fqdns = [for r in aws_route53_record.apex_validation : r.fqdn]
}
