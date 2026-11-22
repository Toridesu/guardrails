# Security Hub CSPM。security を委任管理者にし、中央設定で Workloads OU に配る。
# 標準を丸ごと有効にすると費用が増えるので、NIST SP 800-53 Rev.5 の標準のうち、使うコントロールだけを有効にする。

resource "aws_securityhub_account" "management" {
  enable_default_standards = false
}

resource "aws_securityhub_organization_admin_account" "security" {
  admin_account_id = var.security_account_id

  depends_on = [aws_securityhub_account.management]
}

# 中央設定にはホームリージョンの集約設定が要る。他のリージョンは集約しない
resource "aws_securityhub_finding_aggregator" "home" {
  provider = aws.security

  linking_mode = "NO_REGIONS"

  depends_on = [aws_securityhub_organization_admin_account.security]
}

resource "aws_securityhub_organization_configuration" "this" {
  provider = aws.security

  auto_enable           = false
  auto_enable_standards = "NONE"

  organization_configuration {
    configuration_type = "CENTRAL"
  }

  depends_on = [aws_securityhub_finding_aggregator.home]
}

resource "aws_securityhub_configuration_policy" "guardrails" {
  provider = aws.security

  name        = "guardrails"
  description = "NIST SP 800-53 Rev.5, selected controls only"

  configuration_policy {
    service_enabled = true
    enabled_standard_arns = [
      "arn:aws:securityhub:${var.primary_region}::standards/nist-800-53/v/5.0.0",
    ]
    security_controls_configuration {
      enabled_control_identifiers = var.securityhub_controls
    }
  }

  depends_on = [aws_securityhub_organization_configuration.this]
}

resource "aws_securityhub_configuration_policy_association" "workloads" {
  provider = aws.security

  target_id = var.workloads_ou_id
  policy_id = aws_securityhub_configuration_policy.guardrails.id
}
