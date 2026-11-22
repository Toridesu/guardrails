# C03、C04、C06、C10、C12: workload の AWS Config と、security のアグリゲーター。

# ---- 記録（workload） ----

resource "aws_iam_service_linked_role" "config" {
  provider = aws.workload

  aws_service_name = "config.amazonaws.com"
}

# 記録する種類は統制に要るものに絞る（全種類だと費用が読めない）。
# Security Hub の Config.1 は、有効なコントロールが使う種類を記録しているかを見る。
resource "aws_config_configuration_recorder" "workload" {
  provider = aws.workload

  name     = "default"
  role_arn = aws_iam_service_linked_role.config.arn

  recording_group {
    all_supported                 = false
    include_global_resource_types = false
    resource_types                = var.config_resource_types
    recording_strategy {
      use_only = "INCLUSION_BY_RESOURCE_TYPES"
    }
  }

  # C10 の自動修復を速くするため、連続記録にする（日次にすると最大24時間遅れる）
  recording_mode {
    recording_frequency = "CONTINUOUS"
  }
}

data "aws_kms_alias" "logs" {
  provider = aws.security

  name = "alias/guardrails-logs"
}

resource "aws_config_delivery_channel" "workload" {
  provider = aws.workload

  name           = "default"
  s3_bucket_name = var.log_bucket_name
  s3_key_prefix  = "config"
  s3_kms_key_arn = data.aws_kms_alias.logs.target_key_arn

  depends_on = [aws_config_configuration_recorder.workload]
}

resource "aws_config_configuration_recorder_status" "workload" {
  provider = aws.workload

  name       = aws_config_configuration_recorder.workload.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.workload]
}

# ---- ルール（workload） ----
# ルール名の先頭に統制 ID を付ける。controls.yaml はこの名前で参照する。

locals {
  config_rules = {
    "c04-encrypted-volumes" = {
      source = "ENCRYPTED_VOLUMES"
      params = null
    }
    # RCP で防いでいても、このルールはバケットポリシーしか見ない。
    # ログバケットにはバケットポリシーでも TLS 必須を書いてあるので通る想定（実機で確認）
    "c06-s3-bucket-ssl-requests-only" = {
      source = "S3_BUCKET_SSL_REQUESTS_ONLY"
      params = null
    }
    "c10-restricted-ssh" = {
      source = "INCOMING_SSH_DISABLED"
      params = null
    }
    # C12: 既定値は大文字・小文字・数字・記号を求める。NIST SP 800-63B-4 に合わせて文字種は求めず、長さを見る
    "c12-iam-password-policy" = {
      source = "IAM_PASSWORD_POLICY"
      params = {
        RequireUppercaseCharacters = "false"
        RequireLowercaseCharacters = "false"
        RequireSymbols             = "false"
        RequireNumbers             = "false"
        MinimumPasswordLength      = "15"
      }
    }
  }
}

resource "aws_config_config_rule" "this" {
  for_each = local.config_rules
  provider = aws.workload

  name             = each.key
  input_parameters = each.value.params == null ? null : jsonencode(each.value.params)

  source {
    owner             = "AWS"
    source_identifier = each.value.source
  }

  depends_on = [aws_config_configuration_recorder_status.workload]
}

# ---- アグリゲーター（security） ----
# 委任管理者の登録は terraform/org で行う

data "aws_iam_policy_document" "config_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "config_aggregator" {
  provider = aws.security

  name               = "guardrails-config-aggregator"
  assume_role_policy = data.aws_iam_policy_document.config_assume.json
}

resource "aws_iam_role_policy_attachment" "config_aggregator" {
  provider = aws.security

  role       = aws_iam_role.config_aggregator.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSConfigRoleForOrganizations"
}

resource "aws_config_configuration_aggregator" "org" {
  provider = aws.security

  name = "guardrails-org"

  organization_aggregation_source {
    all_regions = false
    regions     = [var.primary_region]
    role_arn    = aws_iam_role.config_aggregator.arn
  }

  depends_on = [aws_iam_role_policy_attachment.config_aggregator]
}
