locals {
  name_prefix = "bsoyka-${var.project_name}"

  # Only this prefix is transformed on request; everything else is served from
  # S3 byte-for-byte.
  image_path_pattern = "/photo/*"

  common_tags = merge(
    {
      Project   = var.project_name
      ManagedBy = "terraform"
      Service   = "brand"
    },
    var.tags
  )
}
