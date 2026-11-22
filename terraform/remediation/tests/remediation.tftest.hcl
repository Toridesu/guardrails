# remediation フォルダのテスト。AWS には接続しない。
# 実行：terraform -chdir=terraform/remediation init -backend=false && terraform -chdir=terraform/remediation test
#
# ロールのポリシー文書の中身を確かめたいので、logging と同じく、本物のプロバイダーを
# 「認証も通信もしない設定」で使い、plan だけを行う。
#
# 確かめること（C10）
# - 修復用ロールは SSM だけが引き受けられ、権限はセキュリティグループの参照と規則の削除だけ
# - 自動修復が、detection の Config ルール（c10-restricted-ssh）と、AWS が用意した SSM ドキュメントにつながっている

provider "aws" {
  region                      = "ap-northeast-1"
  access_key                  = "offline-test"
  secret_key                  = "offline-test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}

provider "aws" {
  alias                       = "workload"
  region                      = "ap-northeast-1"
  access_key                  = "offline-test"
  secret_key                  = "offline-test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}

variables {
  workload_account_id = "222222222222"
}

run "least_privilege" {
  command = plan

  assert {
    condition = (
      jsondecode(data.aws_iam_policy_document.ssm_assume.json).Statement[0].Principal.Service == "ssm.amazonaws.com"
      && jsondecode(data.aws_iam_policy_document.ssm_assume.json).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "222222222222"
    )
    error_message = "修復用ロールを引き受けられるのが、workload アカウントの SSM だけになっていない"
  }
  assert {
    condition = toset(flatten([
      for s in jsondecode(data.aws_iam_policy_document.c10_remediation.json).Statement : s.Action
    ])) == toset(["ec2:DescribeSecurityGroups", "ec2:RevokeSecurityGroupIngress"])
    error_message = "修復用ロールの権限が、セキュリティグループの参照と規則の削除だけになっていない"
  }
}

run "remediation_config" {
  command = plan

  assert {
    condition = (
      aws_config_remediation_configuration.c10.config_rule_name == "c10-restricted-ssh"
      && aws_config_remediation_configuration.c10.target_type == "SSM_DOCUMENT"
      && aws_config_remediation_configuration.c10.target_id == "AWS-DisablePublicAccessForSecurityGroup"
    )
    error_message = "自動修復が、c10-restricted-ssh と AWS-DisablePublicAccessForSecurityGroup につながっていない"
  }
  assert {
    condition = (
      aws_config_remediation_configuration.c10.automatic
      && aws_config_remediation_configuration.c10.maximum_automatic_attempts == 3
      && aws_config_remediation_configuration.c10.retry_attempt_seconds == 60
    )
    error_message = "自動修復が有効になっていない（または、やり直しの回数と間隔が違う）"
  }
  assert {
    condition     = one([for p in aws_config_remediation_configuration.c10.parameter : p.resource_value if p.name == "GroupId"]) == "RESOURCE_ID"
    error_message = "違反したセキュリティグループの ID が、SSM ドキュメントに渡っていない"
  }
}
