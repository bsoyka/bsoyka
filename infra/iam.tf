// Transform Lambda execution role

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"

    principals {
      identifiers = ["lambda.amazonaws.com"]
      type        = "Service"
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "transform_lambda" {
  name               = "${local.name_prefix}-lambda-transform"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "transform_lambda_basic_execution" {
  role       = aws_iam_role.transform_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "transform_lambda" {
  statement {
    sid    = "AllowReadSourceImages"
    effect = "Allow"

    actions = ["s3:GetObject"]

    # The Lambda only ever transforms images; the CV and logos never pass
    # through it.
    resources = ["${aws_s3_bucket.assets.arn}/photo/*"]
  }
}

resource "aws_iam_role_policy" "transform_lambda" {
  name   = "transform-lambda"
  role   = aws_iam_role.transform_lambda.id
  policy = data.aws_iam_policy_document.transform_lambda.json
}

// GitHub Actions asset sync role

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    effect = "Allow"

    principals {
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
      type        = "Federated"
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${local.name_prefix}-github-actions"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json
}

data "aws_iam_policy_document" "github_actions" {
  statement {
    sid    = "AllowListBucket"
    effect = "Allow"

    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.assets.arn]
  }

  statement {
    sid    = "AllowSyncObjects"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]

    resources = ["${aws_s3_bucket.assets.arn}/*"]
  }

  statement {
    sid    = "AllowCacheInvalidation"
    effect = "Allow"

    actions   = ["cloudfront:CreateInvalidation"]
    resources = [aws_cloudfront_distribution.assets.arn]
  }
}

resource "aws_iam_role_policy" "github_actions" {
  name   = "github-actions-sync"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions.json
}
