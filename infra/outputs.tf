output "assets_bucket" {
  value       = aws_s3_bucket.assets.bucket
  description = "S3 bucket the assets/ folder syncs into."
}

output "cloudfront_distribution_id" {
  value       = aws_cloudfront_distribution.assets.id
  description = "CloudFront distribution ID, used for cache invalidation."
}

output "cloudfront_domain_name" {
  value       = aws_cloudfront_distribution.assets.domain_name
  description = "CloudFront domain the custom domain should CNAME to."
}

output "github_actions_role_arn" {
  value       = aws_iam_role.github_actions.arn
  description = "Role ARN for the sync workflow's AWS_ROLE_ARN variable."
}

output "acm_validation_records" {
  value = [
    for option in aws_acm_certificate.assets.domain_validation_options : {
      name  = option.resource_record_name
      type  = option.resource_record_type
      value = option.resource_record_value
    }
  ]
  description = "DNS records to create in Cloudflare (DNS-only, not proxied) to validate the certificate."
}

output "cloudflare_cname_record" {
  value = {
    name  = var.assets_domain
    type  = "CNAME"
    value = aws_cloudfront_distribution.assets.domain_name
  }
  description = "DNS record to create in Cloudflare (DNS-only, not proxied) pointing the custom domain at CloudFront."
}

output "dashboard_url" {
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
  description = "CloudWatch dashboard for the transform Lambda and CloudFront distribution."
}
