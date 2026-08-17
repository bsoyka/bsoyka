# No email/SNS wiring here — these alarms exist purely so the dashboard's
# alarm-status widget shows red/green without having to eyeball graphs. If
# paging is wanted later, add an SNS topic and set alarm_actions/ok_actions.

resource "aws_cloudwatch_metric_alarm" "transform_errors" {
  alarm_name          = "${local.name_prefix}-transform-errors"
  alarm_description   = "The transform Lambda threw an unhandled error. It only throws for genuine failures (S3, sharp) — expected 400s and 404s return normally, so this is a clean signal."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.transform.function_name }
  statistic           = "Sum"
  period              = 3600
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "transform_throttles" {
  alarm_name          = "${local.name_prefix}-transform-throttles"
  alarm_description   = "The transform Lambda is being throttled, so some image requests are failing outright."
  namespace           = "AWS/Lambda"
  metric_name         = "Throttles"
  dimensions          = { FunctionName = aws_lambda_function.transform.function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  tags = local.common_tags
}

# The one that would have caught both bugs found while building this: the
# missing InvokeFunction permission (every /photo/* request 403ing) and the
# AccessDenied-not-NoSuchKey bug (missing images 502ing). Both are origin
# failures CloudFront reports as 5xx regardless of which origin caused them.
resource "aws_cloudwatch_metric_alarm" "cloudfront_5xx_rate" {
  alarm_name          = "${local.name_prefix}-cloudfront-5xx-rate"
  alarm_description   = "Over 5% of requests are getting a 5xx from CloudFront — likely an origin misconfiguration (S3 bucket policy, Lambda permission) rather than a bad client request."
  namespace           = "AWS/CloudFront"
  metric_name         = "5xxErrorRate"
  dimensions          = { DistributionId = aws_cloudfront_distribution.assets.id, Region = "Global" }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 5
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  tags = local.common_tags
}
