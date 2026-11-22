variable "primary_region" {
  type    = string
  default = "ap-northeast-1"
}

variable "admin_role_name" {
  type    = string
  default = "OrganizationAccountAccessRole"
}

variable "workload_account_id" {
  type = string
}

variable "restricted_ssh_rule_name" {
  description = "terraform/detection で作った C10 の Config ルール名"
  type        = string
  default     = "c10-restricted-ssh"
}
