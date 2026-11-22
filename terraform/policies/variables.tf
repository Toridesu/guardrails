variable "primary_region" {
  description = "リソースを置くリージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "secondary_region" {
  description = "Bedrock の推論先としてだけ許可するリージョン"
  type        = string
  default     = "ap-northeast-3"
}

variable "admin_role_name" {
  description = "SCP の例外にする管理者ロール（Terraform がメンバーアカウントで使うロール）"
  type        = string
  default     = "OrganizationAccountAccessRole"
}

variable "security_account_id" {
  type = string
}

variable "workload_account_id" {
  type = string
}

variable "log_bucket_name" {
  description = "security アカウントのログバケット名（C02 で保護する）"
  type        = string
}
