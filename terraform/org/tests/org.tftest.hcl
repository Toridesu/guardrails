# org フォルダのテスト。AWS には接続しない（mock_provider が AWS の代わりに偽の値を返す）。
# 実行：terraform -chdir=terraform/org init -backend=false && terraform -chdir=terraform/org test
#
# 確かめること
# - アカウントが正しい OU に入り、OU は組織のルートの下にある
# - SCP と RCP を使えるようにし、使うサービスの信頼されたアクセスを有効にしている
# - Config の委任管理者が security アカウント。destroy してもアカウントは閉鎖しない
# - Identity Center の設定は、ユーザー ID を書いたときだけ作り、security と workload に割り当てる

mock_provider "aws" {
  # 組織のルート ID を決めておく（決めないと偽の値でルートの一覧が空になり、roots[0] が取れない）
  override_resource {
    target = aws_organizations_organization.this
    values = {
      id    = "o-test"
      roots = [{ id = "r-test", arn = "arn:aws:organizations::000000000000:root/o-test/r-test", name = "Root", policy_types = [] }]
    }
  }
  # OU とアカウントの ID も決めておく（偽の値は、AWS の ID の形式チェックを通らないため）
  override_resource {
    target = aws_organizations_organizational_unit.security
    values = { id = "ou-test-security" }
  }
  override_resource {
    target = aws_organizations_organizational_unit.workloads
    values = { id = "ou-test-workloads" }
  }
  override_resource {
    target = aws_organizations_account.security
    values = { id = "111111111111" }
  }
  override_resource {
    target = aws_organizations_account.workload
    values = { id = "222222222222" }
  }
  override_data {
    target = data.aws_ssoadmin_instances.this
    values = {
      arns               = ["arn:aws:sso:::instance/ssoins-test"]
      identity_store_ids = ["d-test"]
    }
  }
  override_resource {
    target = aws_ssoadmin_permission_set.admin
    values = { arn = "arn:aws:sso:::permissionSet/ssoins-test/ps-test" }
  }
}

variables {
  security_account_email = "security@example.com"
  workload_account_email = "workload@example.com"
  notification_email     = "alerts@example.com"
}

run "accounts_and_ous" {
  command = apply

  assert {
    condition = (
      aws_organizations_organizational_unit.security.parent_id == "r-test"
      && aws_organizations_organizational_unit.workloads.parent_id == "r-test"
    )
    error_message = "OU は組織のルートの下に作るはず"
  }
  assert {
    condition     = aws_organizations_account.security.parent_id == aws_organizations_organizational_unit.security.id
    error_message = "security アカウントが Security OU に入っていない"
  }
  assert {
    condition     = aws_organizations_account.workload.parent_id == aws_organizations_organizational_unit.workloads.id
    error_message = "workload アカウントが Workloads OU に入っていない"
  }
  assert {
    condition     = aws_organizations_delegated_administrator.config.account_id == aws_organizations_account.security.id
    error_message = "Config の委任管理者が security アカウントになっていない"
  }
  assert {
    condition     = !aws_organizations_account.security.close_on_deletion && !aws_organizations_account.workload.close_on_deletion
    error_message = "destroy でアカウントが閉鎖される設定になっている（閉鎖すると90日残り、メールアドレスも再利用できない）"
  }
}

run "organization_features" {
  command = plan

  assert {
    condition     = toset(aws_organizations_organization.this.enabled_policy_types) == toset(["SERVICE_CONTROL_POLICY", "RESOURCE_CONTROL_POLICY"])
    error_message = "SCP と RCP の両方を使えるようにするはず"
  }
  assert {
    condition = length(setsubtract(
      ["cloudtrail.amazonaws.com", "config.amazonaws.com", "config-multiaccountsetup.amazonaws.com", "securityhub.amazonaws.com", "sso.amazonaws.com", "iam.amazonaws.com"],
      aws_organizations_organization.this.aws_service_access_principals
    )) == 0
    error_message = "組織証跡、Config、Security Hub、Identity Center、ルートアクセスの一元管理に必要な信頼されたアクセスが足りない"
  }
  assert {
    condition     = toset(aws_iam_organizations_features.root_access.enabled_features) == toset(["RootCredentialsManagement", "RootSessions"])
    error_message = "C09：ルートアクセスの一元管理が有効になっていない"
  }
  assert {
    condition = toset([
      for n in aws_budgets_budget.monthly.notification : "${n.notification_type}:${n.threshold}:${join(",", n.subscriber_email_addresses)}"
    ]) == toset(["ACTUAL:80:alerts@example.com", "FORECASTED:100:alerts@example.com"])
    error_message = "予算アラートが、実績80%と予測100%で通知先に届く設定になっていない"
  }
}

run "identity_center_off_by_default" {
  command = apply

  assert {
    condition     = length(aws_ssoadmin_permission_set.admin) == 0 && length(aws_ssoadmin_account_assignment.admin) == 0
    error_message = "ユーザー ID が空なのに、Identity Center の設定を作ろうとしている"
  }
}

run "identity_center_on" {
  command = apply

  variables {
    sso_admin_user_id = "11111111-2222-3333-4444-555555555555"
  }

  assert {
    condition = toset([for a in aws_ssoadmin_account_assignment.admin : a.target_id]) == toset([
      aws_organizations_account.security.id,
      aws_organizations_account.workload.id,
    ])
    error_message = "GuardrailsAdmin は security と workload の2つだけに割り当てるはず"
  }
  assert {
    condition     = alltrue([for a in aws_ssoadmin_account_assignment.admin : a.principal_id == "11111111-2222-3333-4444-555555555555" && a.principal_type == "USER"])
    error_message = "割り当て先が、書いたユーザーになっていない"
  }
  assert {
    condition     = aws_ssoadmin_managed_policy_attachment.admin[0].managed_policy_arn == "arn:aws:iam::aws:policy/AdministratorAccess"
    error_message = "GuardrailsAdmin の権限が AdministratorAccess になっていない"
  }
}
