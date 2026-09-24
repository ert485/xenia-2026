# Imported from the zone Erik created on 2026-09-23; see step 4. Never destroyed.
resource "aws_route53_zone" "this" {
  name    = var.zone_name
  comment = "Co.Hack 2026 kit"
  lifecycle {
    prevent_destroy = true
  }
}
