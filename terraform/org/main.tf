# Organizations、OU、メンバーアカウント、委任管理者、Budgets。
# 組織をコンソールで作り済みなら、aws_organizations_organization を import してから apply する。

resource "aws_organizations_organization" "this" {
  feature_set = "ALL"

  aws_service_access_principals = [
    "cloudtrail.amazonaws.com",
    "config.amazonaws.com",
    "config-multiaccountsetup.amazonaws.com",
    "iam.amazonaws.com",
    "securityhub.amazonaws.com",
    "sso.amazonaws.com",
  ]

  enabled_policy_types = [
    "SERVICE_CONTROL_POLICY",
    "RESOURCE_CONTROL_POLICY",
  ]
}

resource "aws_organizations_organizational_unit" "security" {
  name      = "Security"
  parent_id = aws_organizations_organization.this.roots[0].id
}

resource "aws_organizations_organizational_unit" "workloads" {
  name      = "Workloads"
  parent_id = aws_organizations_organization.this.roots[0].id
}

# アカウントの閉鎖には件数と期間の制限があるので、作り直す前提にしない
resource "aws_organizations_account" "security" {
  name              = "security"
  email             = var.security_account_email
  parent_id         = aws_organizations_organizational_unit.security.id
  role_name         = var.admin_role_name
  close_on_deletion = false

  lifecycle {
    ignore_changes = [role_name]
  }
}

resource "aws_organizations_account" "workload" {
  name              = "workload"
  email             = var.workload_account_email
  parent_id         = aws_organizations_organizational_unit.workloads.id
  role_name         = var.admin_role_name
  close_on_deletion = false

  lifecycle {
    ignore_changes = [role_name]
  }
}

# C09: ルートアクセスの一元管理（メンバーアカウントのルートの認証情報を消せるようにする）
resource "aws_iam_organizations_features" "root_access" {
  enabled_features = [
    "RootCredentialsManagement",
    "RootSessions",
  ]

  depends_on = [aws_organizations_organization.this]
}

# Config アグリゲーターを security アカウントに置くための委任
resource "aws_organizations_delegated_administrator" "config" {
  account_id        = aws_organizations_account.security.id
  service_principal = "config.amazonaws.com"
}

resource "aws_budgets_budget" "monthly" {
  name         = "guardrails-monthly"
  budget_type  = "COST"
  limit_amount = var.monthly_budget_usd
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.notification_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.notification_email]
  }
}
