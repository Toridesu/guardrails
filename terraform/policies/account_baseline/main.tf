terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

# C04: EBS の既定の暗号化（リージョン単位の設定。リソースを置く東京だけで有効にする）
resource "aws_ebs_encryption_by_default" "this" {
  enabled = true
}

# C05: S3 のパブリックアクセスブロック（アカウント単位）
resource "aws_s3_account_public_access_block" "this" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# C12: IAM のパスワードポリシー。
# C07 で IAM ユーザーは作らせないので守る対象はないが、残す場合は NIST SP 800-63B-4 に合わせて
# 文字種の組み合わせ規則と定期変更を求めず、長さを重視する。
resource "aws_iam_account_password_policy" "this" {
  minimum_password_length        = 15
  require_lowercase_characters   = false
  require_uppercase_characters   = false
  require_numbers                = false
  require_symbols                = false
  allow_users_to_change_password = true
}
