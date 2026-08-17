locals {
  build_script = "${path.module}/../scripts/build_lambda.sh"

  transform_source_files = concat(
    [for f in fileset("${path.module}/../lambda/transform", "**") : "${path.module}/../lambda/transform/${f}"],
    [local.build_script],
  )
  transform_source_hash = sha1(join("", [for f in sort(local.transform_source_files) : filesha1(f)]))
}

# sharp ships platform-specific native binaries, so the zip is built from a
# staged directory whose dependencies are resolved for Lambda's arm64 Linux
# target rather than for whatever machine runs terraform.
resource "terraform_data" "transform_build" {
  triggers_replace = {
    source_hash = local.transform_source_hash
  }

  provisioner "local-exec" {
    command     = "./scripts/build_lambda.sh"
    working_dir = "${path.module}/.."
  }
}

data "archive_file" "transform" {
  type        = "zip"
  source_dir  = "${path.module}/../build/staging/transform"
  output_path = "${path.module}/../build/transform.zip"

  depends_on = [terraform_data.transform_build]
}

resource "aws_lambda_function" "transform" {
  function_name = "${local.name_prefix}-transform"
  role          = aws_iam_role.transform_lambda.arn

  runtime          = "nodejs22.x"
  architectures    = ["arm64"]
  filename         = data.archive_file.transform.output_path
  source_code_hash = data.archive_file.transform.output_base64sha256
  handler          = "index.handler"
  timeout          = 30

  # sharp is CPU-bound and Lambda scales CPU with memory, so a larger size cuts
  # both cold-start decode time and per-request duration.
  memory_size = 1536

  environment {
    variables = {
      ASSETS_BUCKET = aws_s3_bucket.assets.bucket
    }
  }
}

resource "aws_cloudwatch_log_group" "transform" {
  name              = "/aws/lambda/${aws_lambda_function.transform.function_name}"
  retention_in_days = 14
}

resource "aws_lambda_function_url" "transform" {
  function_name      = aws_lambda_function.transform.function_name
  authorization_type = "AWS_IAM"

  # Buffered responses cap at 6 MB and are base64-encoded on the way out, which
  # left an effective ~4 MB ceiling that full-size PNGs blew past. Streaming
  # raises that to 200 MB and sends raw bytes.
  invoke_mode = "RESPONSE_STREAM"
}

# CloudFront signs its origin requests with SigV4, so the function URL is not
# reachable directly and can't be used to bypass the cache.
#
# OAC needs BOTH statements below. Granting only InvokeFunctionUrl makes every
# request through the distribution fail with a 403 AccessDeniedException that
# never reaches the function, so nothing shows up in its logs.
resource "aws_lambda_permission" "cloudfront_invoke_url" {
  statement_id           = "AllowCloudFrontInvokeFunctionUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.transform.function_name
  principal              = "cloudfront.amazonaws.com"
  source_arn             = aws_cloudfront_distribution.assets.arn
  function_url_auth_type = "AWS_IAM"
}

resource "aws_lambda_permission" "cloudfront_invoke_function" {
  statement_id  = "AllowCloudFrontInvokeFunction"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.transform.function_name
  principal     = "cloudfront.amazonaws.com"
  source_arn    = aws_cloudfront_distribution.assets.arn
}
