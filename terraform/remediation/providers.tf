provider "aws" {
  region = var.primary_region
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
