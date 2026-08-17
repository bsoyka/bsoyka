resource "aws_acm_certificate" "assets" {
  domain_name       = var.assets_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# DNS lives in Cloudflare, so validation records are added by hand. See the
# acm_validation_records output; this resource waits for them to resolve.
resource "aws_acm_certificate_validation" "assets" {
  certificate_arn = aws_acm_certificate.assets.arn
}
