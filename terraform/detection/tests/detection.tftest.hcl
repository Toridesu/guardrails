# detection フォルダのテスト。AWS には接続しない（mock_provider が AWS の代わりに偽の値を返す）。
# 実行：terraform -chdir=terraform/detection init -backend=false && terraform -chdir=terraform/detection test
#
# 確かめること
# - Config：ルール4本と、その設定値（C12 は 800-63B-4 に合わせた値）。記録は8種類に絞った連続記録。
#   配信先は logging のバケットと KMS キー
# - Security Hub CSPM：NIST 800-53 の標準と、選んだコントロールだけを、Workloads OU に一元設定する
# - 管理者ロールが引き受けられたら、SNS でメールが届く

# 偽の値は、AWS の形式チェック（ARN や JSON の形）を通らないことがあるので、通る値を決めておく。
# ポリシー文書の中身はここでは確かめない（中身は logging と remediation のテストで、本物のプロバイダーで確かめている）。
mock_provider "aws" {
  override_data {
    target = data.aws_iam_policy_document.config_assume
    values = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  override_data {
    target = data.aws_iam_policy_document.alerts_topic
    values = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}

mock_provider "aws" {
  alias = "security"
  # logging で作る KMS キー（ここでは値を決めておく）
  override_data {
    target = data.aws_kms_alias.logs
    values = {
      target_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/test-key"
    }
  }
  override_resource {
    target = aws_iam_role.config_aggregator
    values = { arn = "arn:aws:iam::111111111111:role/guardrails-config-aggregator" }
  }
  override_resource {
    target = aws_securityhub_configuration_policy.guardrails
    values = { id = "a1b2c3d4-0000-1111-2222-333344445555" }
  }
}

mock_provider "aws" {
  alias = "workload"
  override_resource {
    target = aws_iam_service_linked_role.config
    values = { arn = "arn:aws:iam::222222222222:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig" }
  }
  override_resource {
    target = aws_sns_topic.alerts
    values = { arn = "arn:aws:sns:ap-northeast-1:222222222222:guardrails-alerts" }
  }
  override_resource {
    target = aws_cloudwatch_event_rule.admin_role_used
    values = { arn = "arn:aws:events:ap-northeast-1:222222222222:rule/guardrails-admin-role-used" }
  }
}

variables {
  security_account_id = "111111111111"
  workload_account_id = "222222222222"
  workloads_ou_id     = "ou-test-workloads"
  log_bucket_name     = "guardrails-logs-test"
  notification_email  = "alerts@example.com"
}

run "config" {
  command = apply

  assert {
    condition = toset(keys(aws_config_config_rule.this)) == toset([
      "c04-encrypted-volumes", "c06-s3-bucket-ssl-requests-only", "c10-restricted-ssh", "c12-iam-password-policy",
    ])
    error_message = "Config ルールの名前が違う（remediation と controls.yaml がこの名前を使っている）"
  }
  assert {
    condition     = aws_config_config_rule.this["c10-restricted-ssh"].source[0].source_identifier == "INCOMING_SSH_DISABLED"
    error_message = "C10：SSH の全開放を見るルールになっていない"
  }
  assert {
    condition = jsondecode(aws_config_config_rule.this["c12-iam-password-policy"].input_parameters) == {
      MinimumPasswordLength      = "15"
      RequireLowercaseCharacters = "false"
      RequireUppercaseCharacters = "false"
      RequireNumbers             = "false"
      RequireSymbols             = "false"
    }
    error_message = "C12：パスワードのルールが 800-63B-4 に合わせた値（文字種なし、15文字以上）になっていない"
  }
  assert {
    condition = (
      !aws_config_configuration_recorder.workload.recording_group[0].all_supported
      && toset(aws_config_configuration_recorder.workload.recording_group[0].resource_types) == toset(var.config_resource_types)
      && aws_config_configuration_recorder.workload.recording_mode[0].recording_frequency == "CONTINUOUS"
    )
    error_message = "Config の記録が、決めた種類だけの連続記録になっていない"
  }
  assert {
    condition = (
      aws_config_delivery_channel.workload.s3_bucket_name == "guardrails-logs-test"
      && aws_config_delivery_channel.workload.s3_key_prefix == "config"
      && aws_config_delivery_channel.workload.s3_kms_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/test-key"
    )
    error_message = "Config の配信先が、ログバケットの config/ と logging の KMS キーになっていない（logging のバケットポリシーと合わない）"
  }
}

run "security_hub" {
  command = apply

  assert {
    condition = (
      aws_securityhub_configuration_policy.guardrails.configuration_policy[0].enabled_standard_arns
      == toset(["arn:aws:securityhub:ap-northeast-1::standards/nist-800-53/v/5.0.0"])
    )
    error_message = "有効にする標準が NIST 800-53 Rev.5 だけになっていない"
  }
  assert {
    condition = (
      toset(aws_securityhub_configuration_policy.guardrails.configuration_policy[0].security_controls_configuration[0].enabled_control_identifiers)
      == toset(var.securityhub_controls)
    )
    error_message = "有効にするコントロールが、選んだものだけになっていない"
  }
  assert {
    condition = (
      aws_securityhub_configuration_policy_association.workloads.target_id == "ou-test-workloads"
      && aws_securityhub_configuration_policy_association.workloads.policy_id == aws_securityhub_configuration_policy.guardrails.id
      && aws_securityhub_organization_configuration.this.organization_configuration[0].configuration_type == "CENTRAL"
    )
    error_message = "設定が、Workloads OU への一元設定になっていない"
  }
  assert {
    condition     = aws_securityhub_organization_admin_account.security.admin_account_id == "111111111111"
    error_message = "Security Hub の委任管理者が security アカウントになっていない"
  }
}

run "admin_role_alert" {
  command = apply

  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.admin_role_used.event_pattern).detail.requestParameters.roleArn[0].suffix == ":role/OrganizationAccountAccessRole"
    error_message = "通知の条件が、SCP の例外の管理者ロールになっていない"
  }
  assert {
    # AssumeRole は読み取り系の扱いなので、この設定がないと EventBridge に届かない
    condition     = aws_cloudwatch_event_rule.admin_role_used.state == "ENABLED_WITH_ALL_CLOUDTRAIL_MANAGEMENT_EVENTS"
    error_message = "読み取り系の管理イベントも受け取る設定になっていない"
  }
  assert {
    condition = (
      aws_cloudwatch_event_target.admin_role_used.arn == aws_sns_topic.alerts.arn
      && aws_cloudwatch_event_target.admin_role_used.rule == aws_cloudwatch_event_rule.admin_role_used.name
      && aws_sns_topic_subscription.email.protocol == "email"
      && aws_sns_topic_subscription.email.endpoint == "alerts@example.com"
    )
    error_message = "ルール → SNS → メールのつながりが切れている"
  }
}
