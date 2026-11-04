# One certificate for the three host names behind the shared internal ALB.
# DNS validation needs public records, so the zone is public even though the ALB is internal.
resource "aws_acm_certificate" "this" {
  domain_name               = local.hosts.gateway
  subject_alternative_names = [for k, h in local.hosts : h if k != "gateway"]
  validation_method         = "DNS"

  # A new certificate must exist before the old one is removed, or the ALB loses TLS.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "acm_validation" {
  for_each = {
    for o in aws_acm_certificate.this.domain_validation_options : o.domain_name => {
      name   = o.resource_record_name
      type   = o.resource_record_type
      record = o.resource_record_value
    }
  }

  zone_id         = data.aws_route53_zone.this.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

# Waits until ACM says ISSUED, so the ARN handed to Argo CD is usable.
resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for r in aws_route53_record.acm_validation : r.fqdn]
}
