# 既定の provider は management アカウント（Terraform の実行元）。
# メンバーアカウントへは admin_role_name のロールを引き受けて入る。

provider "aws" {
  region = var.primary_region
  default_tags {
    tags = local.tags
  }
}

provider "aws" {
  alias  = "security"
  region = var.primary_region
  assume_role {
    role_arn = "arn:aws:iam::${var.security_account_id}:role/${var.admin_role_name}"
  }
  default_tags {
    tags = local.tags
  }
}

provider "aws" {
  alias  = "workload"
  region = var.primary_region
  assume_role {
    role_arn = "arn:aws:iam::${var.workload_account_id}:role/${var.admin_role_name}"
  }
  default_tags {
    tags = local.tags
  }
}

locals {
  tags = {
    Project   = "guardrails"
    ManagedBy = "terraform"
  }
}
