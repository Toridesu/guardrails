variable "primary_region" {
  type    = string
  default = "ap-northeast-1"
}

variable "admin_role_name" {
  type    = string
  default = "OrganizationAccountAccessRole"
}

variable "organization_id" {
  type = string
}

variable "security_account_id" {
  type = string
}

variable "workload_account_id" {
  description = "Config の配信を許可するアカウント"
  type        = string
}

variable "log_bucket_name" {
  type = string
}

variable "trail_name" {
  type    = string
  default = "guardrails-org-trail"
}

variable "object_lock_days" {
  description = "Object Lock（ガバナンスモード）の保持日数"
  type        = number
  default     = 1
}

variable "log_retention_days" {
  type    = number
  default = 30
}
