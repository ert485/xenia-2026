# app. (demo), llm. (gateway), *.box. (previews): all on the box's Elastic IP.
resource "aws_route53_record" "box" {
  for_each = toset(["app", "llm", "*.box"])
  zone_id  = local.zone_id
  name     = "${each.key}.${local.zone_name}"
  type     = "A"
  ttl      = 60
  records  = [aws_eip.box.public_ip]
}
