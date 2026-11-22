variable "primary_region" {
  type    = string
  default = "ap-northeast-1"
}

variable "admin_role_name" {
  type    = string
  default = "OrganizationAccountAccessRole"
}

variable "security_account_id" {
  type = string
}

variable "workload_account_id" {
  type = string
}

variable "workloads_ou_id" {
  description = "Security Hub CSPM の設定ポリシーを配る OU"
  type        = string
}

variable "log_bucket_name" {
  type = string
}

variable "notification_email" {
  description = "管理者ロールの使用を通知する送り先"
  type        = string
}

variable "config_resource_types" {
  description = "Config で記録するリソースの種類"
  type        = list(string)
  default = [
    "AWS::CloudTrail::Trail",
    "AWS::EC2::SecurityGroup",
    "AWS::EC2::Volume",
    "AWS::IAM::Policy",
    "AWS::IAM::Role",
    "AWS::IAM::User",
    "AWS::S3::AccountPublicAccessBlock",
    "AWS::S3::Bucket",
  ]
}

variable "securityhub_controls" {
  description = "有効にする Security Hub CSPM のコントロール（controls.yaml と対応）"
  type        = list(string)
  default = [
    "CloudTrail.1", # C02 マルチリージョンの証跡
    "CloudTrail.4", # C02 ログファイルの検証
    "Config.1",     # C03 Config の有効化
    "EC2.7",        # C04 EBS の既定の暗号化
    "EC2.13",       # C10 SSH の全開放
    "IAM.4",        # C09 ルートのアクセスキー
    "S3.1",         # C05 アカウント単位のパブリックアクセスブロック
    "S3.5",         # C06 TLS 必須
  ]
}
