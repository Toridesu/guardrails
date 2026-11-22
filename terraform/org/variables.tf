variable "primary_region" {
  type    = string
  default = "ap-northeast-1"
}

variable "admin_role_name" {
  description = "メンバーアカウントに作られる管理者ロール。SCP の例外にする"
  type        = string
  default     = "OrganizationAccountAccessRole"
}

variable "security_account_email" {
  type = string
}

variable "workload_account_email" {
  type = string
}

variable "notification_email" {
  description = "Budgets と各種通知の送り先"
  type        = string
}

variable "monthly_budget_usd" {
  type    = string
  default = "20"
}

variable "sso_admin_user_id" {
  description = "Identity Center のユーザー ID。空なら権限セットを作らない"
  type        = string
  default     = ""
}
