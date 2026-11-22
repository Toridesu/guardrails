output "scp_ids" {
  value = { for k, p in aws_organizations_policy.scp : k => p.id }
}

output "rcp_ids" {
  value = { for k, p in aws_organizations_policy.rcp : k => p.id }
}
