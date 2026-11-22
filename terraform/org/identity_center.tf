# C08: 人のログインは IAM Identity Center に寄せる。
# Identity Center の有効化と MFA の設定はコンソールでしかできないので手順書で扱う（README 参照）。
# sso_admin_user_id を空にしておけば、ここは何も作らない。

locals {
  manage_identity_center = var.sso_admin_user_id != ""
  member_accounts = {
    security = aws_organizations_account.security.id
    workload = aws_organizations_account.workload.id
  }
}

data "aws_ssoadmin_instances" "this" {
  count = local.manage_identity_center ? 1 : 0
}

resource "aws_ssoadmin_permission_set" "admin" {
  count = local.manage_identity_center ? 1 : 0

  name             = "GuardrailsAdmin"
  description      = "Admin for demos. Still subject to SCPs."
  instance_arn     = tolist(data.aws_ssoadmin_instances.this[0].arns)[0]
  session_duration = "PT4H"
}

resource "aws_ssoadmin_managed_policy_attachment" "admin" {
  count = local.manage_identity_center ? 1 : 0

  instance_arn       = aws_ssoadmin_permission_set.admin[0].instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.admin[0].arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_ssoadmin_account_assignment" "admin" {
  for_each = local.manage_identity_center ? local.member_accounts : {}

  instance_arn       = aws_ssoadmin_permission_set.admin[0].instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.admin[0].arn
  principal_id       = var.sso_admin_user_id
  principal_type     = "USER"
  target_id          = each.value
  target_type        = "AWS_ACCOUNT"
}
