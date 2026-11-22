# logging フォルダのテスト。AWS には接続しない。
# 実行：terraform -chdir=terraform/logging init -backend=false && terraform -chdir=terraform/logging test
#
# ここはポリシー文書（バケットポリシー、KMS のキーポリシー）の中身を確かめたい。
# 偽のプロバイダー（mock_provider）だと文書の中身まで偽物になるので、本物のプロバイダーを
# 「認証も通信もしない設定」で使い、plan だけを行う。AWS を呼ぶデータ（呼び出し元の ID）は値を決めておく。
#
# 確かめること（CloudTrail の書き込みで、いちばんハマりやすいところ）
# - バケットポリシーと KMS のキーポリシーが、同じ証跡の ARN にだけ書き込みを許している
# - CloudTrail が書き込む場所（management と組織の両方のパス）を許している
# - TLS 以外の通信を拒否している（C06）
# - Object Lock、バージョニング、証跡の設定が統制どおり（C02）

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
  alias                       = "security"
  region                      = "ap-northeast-1"
  access_key                  = "offline-test"
  secret_key                  = "offline-test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}

override_data {
  target = data.aws_caller_identity.management
  values = {
    account_id = "000000000000"
    arn        = "arn:aws:sts::000000000000:assumed-role/test/test"
    user_id    = "test"
  }
}

variables {
  organization_id     = "o-test"
  security_account_id = "111111111111"
  workload_account_id = "222222222222"
  log_bucket_name     = "guardrails-logs-test"
}

run "cloudtrail_can_write" {
  command = plan

  assert {
    condition = alltrue([
      for s in jsondecode(data.aws_iam_policy_document.bucket.json).Statement :
      toset(flatten([s.Condition.StringEquals["aws:SourceArn"]])) == toset(["arn:aws:cloudtrail:ap-northeast-1:000000000000:trail/guardrails-org-trail"])
      if startswith(s.Sid, "CloudTrail")
    ])
    error_message = "バケットポリシー：CloudTrail に許している証跡の ARN が違う"
  }
  assert {
    condition = alltrue([
      for s in jsondecode(data.aws_iam_policy_document.kms.json).Statement :
      toset(flatten([s.Condition.StringEquals["aws:SourceArn"]])) == toset(["arn:aws:cloudtrail:ap-northeast-1:000000000000:trail/guardrails-org-trail"])
      if startswith(s.Sid, "CloudTrail")
    ])
    error_message = "KMS のキーポリシー：CloudTrail に許している証跡の ARN が違う"
  }
  assert {
    condition = toset(flatten([
      for s in jsondecode(data.aws_iam_policy_document.bucket.json).Statement : s.Resource if s.Sid == "CloudTrailWrite"
      ])) == toset([
      "arn:aws:s3:::guardrails-logs-test/AWSLogs/000000000000/*",
      "arn:aws:s3:::guardrails-logs-test/AWSLogs/o-test/*",
    ])
    error_message = "CloudTrail の書き込み先に、management と組織の両方のパスを許していない"
  }
  assert {
    condition     = aws_cloudtrail.org.name == "guardrails-org-trail"
    error_message = "証跡の名前が、ポリシーで許している ARN と合っていない"
  }
}

run "trail_name_is_consistent" {
  command = plan

  # 証跡の名前を変えると、両方のポリシーが一緒に変わること（どこかに名前を直接書いていないか）
  variables {
    trail_name = "renamed-trail"
  }

  assert {
    condition = alltrue(flatten([
      for doc in [data.aws_iam_policy_document.bucket.json, data.aws_iam_policy_document.kms.json] : [
        for s in jsondecode(doc).Statement :
        toset(flatten([s.Condition.StringEquals["aws:SourceArn"]])) == toset(["arn:aws:cloudtrail:ap-northeast-1:000000000000:trail/renamed-trail"])
        if startswith(s.Sid, "CloudTrail")
      ]
    ]))
    error_message = "証跡の名前を変えても、ポリシーの ARN が変わらない（名前を直接書いている）"
  }
}

run "bucket_protection" {
  command = plan

  assert {
    condition = anytrue([
      for s in jsondecode(data.aws_iam_policy_document.bucket.json).Statement :
      s.Effect == "Deny"
      && s.Condition.Bool["aws:SecureTransport"] == "false"
      && toset(flatten([s.Resource])) == toset(["arn:aws:s3:::guardrails-logs-test", "arn:aws:s3:::guardrails-logs-test/*"])
    ])
    error_message = "C06：バケットとその中身への、TLS 以外のアクセスを拒否していない"
  }
  assert {
    condition = (
      aws_s3_bucket.logs.object_lock_enabled
      && aws_s3_bucket_versioning.logs.versioning_configuration[0].status == "Enabled"
      && aws_s3_bucket_object_lock_configuration.logs.rule[0].default_retention[0].mode == "GOVERNANCE"
      && aws_s3_bucket_object_lock_configuration.logs.rule[0].default_retention[0].days == 1
    )
    error_message = "C02：Object Lock（ガバナンスモード、1日）とバージョニングが有効になっていない"
  }
  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.logs.block_public_acls,
      aws_s3_bucket_public_access_block.logs.block_public_policy,
      aws_s3_bucket_public_access_block.logs.ignore_public_acls,
      aws_s3_bucket_public_access_block.logs.restrict_public_buckets,
    ])
    error_message = "ログバケットのパブリックアクセスブロックが、すべて有効になっていない"
  }
  assert {
    condition = (
      aws_cloudtrail.org.is_organization_trail
      && aws_cloudtrail.org.is_multi_region_trail
      && aws_cloudtrail.org.enable_log_file_validation
      && aws_cloudtrail.org.include_global_service_events
    )
    error_message = "C02：組織証跡、マルチリージョン、ログファイルの検証、グローバルサービスのどれかが無効になっている"
  }
}
