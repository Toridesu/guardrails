# SCP の例外にしている管理者ロールが使われたら通知する（workload）。
# 例外を1つに絞り、その使用を必ず人が知るようにするため。

resource "aws_sns_topic" "alerts" {
  provider = aws.workload

  name = "guardrails-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  provider = aws.workload

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

resource "aws_cloudwatch_event_rule" "admin_role_used" {
  provider = aws.workload

  name        = "guardrails-admin-role-used"
  description = "AssumeRole into the SCP-exempt admin role"
  # AssumeRole は読み取り系として扱われることがあるので、読み取り系の管理イベントも受け取る
  state = "ENABLED_WITH_ALL_CLOUDTRAIL_MANAGEMENT_EVENTS"

  event_pattern = jsonencode({
    source        = ["aws.sts"]
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = ["AssumeRole"]
      requestParameters = {
        roleArn = [{ suffix = ":role/${var.admin_role_name}" }]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "admin_role_used" {
  provider = aws.workload

  rule = aws_cloudwatch_event_rule.admin_role_used.name
  arn  = aws_sns_topic.alerts.arn
}

data "aws_iam_policy_document" "alerts_topic" {
  statement {
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.admin_role_used.arn]
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  provider = aws.workload

  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.alerts_topic.json
}
