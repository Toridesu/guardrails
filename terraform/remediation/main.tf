# C10: restricted-ssh の違反を SSM Automation で自動修復する（workload）。
# Config ルール本体は terraform/detection にある。

data "aws_iam_policy_document" "ssm_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ssm.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.workload_account_id]
    }
  }
}

resource "aws_iam_role" "c10_remediation" {
  provider = aws.workload

  name               = "guardrails-c10-remediation"
  assume_role_policy = data.aws_iam_policy_document.ssm_assume.json
}

data "aws_iam_policy_document" "c10_remediation" {
  statement {
    actions = [
      "ec2:DescribeSecurityGroups",
      "ec2:RevokeSecurityGroupIngress",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "c10_remediation" {
  provider = aws.workload

  name   = "revoke-public-ssh"
  role   = aws_iam_role.c10_remediation.id
  policy = data.aws_iam_policy_document.c10_remediation.json
}

# AWS 管理の Runbook。22番と3389番の 0.0.0.0/0 と ::/0 のルールを消す。
# ポート範囲（0-65535 など）で開けたルールは消えない可能性がある（実機で確認する）
resource "aws_config_remediation_configuration" "c10" {
  provider = aws.workload

  config_rule_name = var.restricted_ssh_rule_name
  target_type      = "SSM_DOCUMENT"
  target_id        = "AWS-DisablePublicAccessForSecurityGroup"

  parameter {
    name         = "AutomationAssumeRole"
    static_value = aws_iam_role.c10_remediation.arn
  }

  parameter {
    name           = "GroupId"
    resource_value = "RESOURCE_ID"
  }

  automatic                  = true
  maximum_automatic_attempts = 3
  retry_attempt_seconds      = 60
}
