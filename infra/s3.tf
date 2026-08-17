resource "aws_s3_bucket" "assets" {
  bucket = local.name_prefix
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket = aws_s3_bucket.assets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Assets are public through CloudFront only, so the bucket itself stays private
# and grants read to the distribution. Scoping to a service principal with a
# SourceArn condition is not a "public" grant, so the block settings above stay
# fully enabled.
data "aws_iam_policy_document" "assets" {
  statement {
    sid    = "AllowCloudFrontRead"
    effect = "Allow"

    principals {
      identifiers = ["cloudfront.amazonaws.com"]
      type        = "Service"
    }

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.assets.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.assets.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "assets" {
  bucket = aws_s3_bucket.assets.id
  policy = data.aws_iam_policy_document.assets.json

  depends_on = [aws_s3_bucket_public_access_block.assets]
}
