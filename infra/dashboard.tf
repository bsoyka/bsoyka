# One dashboard covering both halves of what can go wrong: is the transform
# Lambda healthy, and is CloudFront actually serving traffic. The alarms in
# monitoring.tf catch the former two; this dashboard makes both visible
# without waiting for one to fire.

locals {
  dashboard_body = jsonencode({
    widgets = [
      {
        type       = "text"
        x          = 0, y = 0, width = 24, height = 1
        properties = { markdown = "## Infrastructure health" }
      },

      {
        type = "metric"
        x    = 0, y = 1, width = 8, height = 6
        properties = {
          title  = "Transform invocations"
          view   = "timeSeries"
          region = var.aws_region
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.transform.function_name],
          ]
        }
      },
      {
        type = "metric"
        x    = 8, y = 1, width = 8, height = 6
        properties = {
          title  = "Transform errors & throttles"
          view   = "timeSeries"
          region = var.aws_region
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.transform.function_name, { label = "Errors" }],
            ["AWS/Lambda", "Throttles", "FunctionName", aws_lambda_function.transform.function_name, { label = "Throttles" }],
          ]
        }
      },
      {
        type = "metric"
        x    = 16, y = 1, width = 8, height = 6
        properties = {
          title  = "Transform duration (p90)"
          view   = "timeSeries"
          region = var.aws_region
          period = 300
          stat   = "p90"
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.transform.function_name],
          ]
        }
      },

      # CloudFront basic metrics are free and account-wide per distribution;
      # cache hit rate needs the paid "additional metrics" opt-in, which
      # isn't enabled here, so it's not on this dashboard.
      {
        type = "metric"
        x    = 0, y = 7, width = 12, height = 6
        properties = {
          title  = "CloudFront error rate"
          view   = "timeSeries"
          region = "us-east-1"
          period = 300
          stat   = "Average"
          metrics = [
            ["AWS/CloudFront", "4xxErrorRate", "DistributionId", aws_cloudfront_distribution.assets.id, "Region", "Global", { label = "4xx" }],
            ["AWS/CloudFront", "5xxErrorRate", "DistributionId", aws_cloudfront_distribution.assets.id, "Region", "Global", { label = "5xx" }],
          ]
        }
      },
      {
        type = "alarm"
        x    = 12, y = 7, width = 12, height = 6
        properties = {
          title = "Alarm status"
          alarms = [
            aws_cloudwatch_metric_alarm.transform_errors.arn,
            aws_cloudwatch_metric_alarm.transform_throttles.arn,
            aws_cloudwatch_metric_alarm.cloudfront_5xx_rate.arn,
          ]
        }
      },

      {
        type       = "text"
        x          = 0, y = 13, width = 24, height = 1
        properties = { markdown = "## Traffic" }
      },

      {
        type = "metric"
        x    = 0, y = 14, width = 12, height = 6
        properties = {
          title  = "Requests"
          view   = "timeSeries"
          region = "us-east-1"
          period = 3600
          stat   = "Sum"
          metrics = [
            ["AWS/CloudFront", "Requests", "DistributionId", aws_cloudfront_distribution.assets.id, "Region", "Global"],
          ]
        }
      },
      {
        type = "metric"
        x    = 12, y = 14, width = 12, height = 6
        properties = {
          title  = "Bytes downloaded"
          view   = "timeSeries"
          region = "us-east-1"
          period = 3600
          stat   = "Sum"
          metrics = [
            ["AWS/CloudFront", "BytesDownloaded", "DistributionId", aws_cloudfront_distribution.assets.id, "Region", "Global"],
          ]
        }
      },
    ]
  })
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = local.name_prefix
  dashboard_body = local.dashboard_body
}
