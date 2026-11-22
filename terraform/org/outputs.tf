# apply 後、これらの値を terraform/shared.tfvars に書き写す

output "organization_id" {
  value = aws_organizations_organization.this.id
}

output "root_id" {
  value = aws_organizations_organization.this.roots[0].id
}

output "security_ou_id" {
  value = aws_organizations_organizational_unit.security.id
}

output "workloads_ou_id" {
  value = aws_organizations_organizational_unit.workloads.id
}

output "security_account_id" {
  value = aws_organizations_account.security.id
}

output "workload_account_id" {
  value = aws_organizations_account.workload.id
}
