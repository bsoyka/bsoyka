variable "project_name" {
  type        = string
  default     = "brand"
  description = "Project name."
}

variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region. CloudFront requires its ACM certificate in us-east-1."
}

variable "assets_domain" {
  type        = string
  default     = "assets.bensoyka.com"
  description = "Custom domain the assets CDN is served from."
}

variable "github_repository" {
  type        = string
  default     = "bsoyka/bsoyka"
  description = "GitHub repository allowed to assume the asset sync role."
}

variable "cloudfront_price_class" {
  type        = string
  default     = "PriceClass_100"
  description = "CloudFront price class. PriceClass_100 covers North America and Europe."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags."
}
