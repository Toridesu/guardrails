# SCP と RCP を作り、組織のルートに付ける。
# ルートに付けると、Security OU と Workloads OU の両方に効く（management アカウントには効かない）。
# 1つの対象に付けられるのは5つまで（FullAWSAccess を含む）なので、統制はファイル単位でまとめている。

locals {
  policy_vars = {
    primary_region   = var.primary_region
    secondary_region = var.secondary_region
    admin_role_name  = var.admin_role_name
    log_bucket_name  = var.log_bucket_name
  }

  scps = {
    "guardrails-c01-region" = {
      file        = "c01-region.json"
      description = "C01 deny regions other than Tokyo and Osaka (Osaka is Bedrock only)"
    }
    "guardrails-c02-c03-logging" = {
      file        = "c02-c03-logging.json"
      description = "C02 C03 protect CloudTrail, the log bucket and AWS Config"
    }
    "guardrails-c04-c09-baseline" = {
      file        = "c04-c09-baseline.json"
      description = "C04 C05 C07 C09 EBS encryption, S3 public access, IAM users, root user"
    }
  }

  rcps = {
    "guardrails-c06-s3-tls" = {
      file        = "c06-s3-tls.json"
      description = "C06 deny S3 requests without TLS"
    }
  }
}

data "aws_organizations_organization" "this" {}

resource "aws_organizations_policy" "scp" {
  for_each = local.scps

  name        = each.key
  description = each.value.description
  type        = "SERVICE_CONTROL_POLICY"
  # jsonencode(jsondecode()) で空白を詰め、5,120文字の上限に余裕を持たせる
  content = jsonencode(jsondecode(templatefile("${path.module}/scp/${each.value.file}", local.policy_vars)))
}

resource "aws_organizations_policy_attachment" "scp" {
  for_each = local.scps

  policy_id = aws_organizations_policy.scp[each.key].id
  target_id = data.aws_organizations_organization.this.roots[0].id
}

resource "aws_organizations_policy" "rcp" {
  for_each = local.rcps

  name        = each.key
  description = each.value.description
  type        = "RESOURCE_CONTROL_POLICY"
  content     = jsonencode(jsondecode(templatefile("${path.module}/rcp/${each.value.file}", local.policy_vars)))
}

resource "aws_organizations_policy_attachment" "rcp" {
  for_each = local.rcps

  policy_id = aws_organizations_policy.rcp[each.key].id
  target_id = data.aws_organizations_organization.this.roots[0].id
}
