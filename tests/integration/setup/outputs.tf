output "allocation_id" {
  description = "Allocation ID of the disposable Elastic IP: the endpoint_id under test."
  value       = aws_eip.endpoint.id
}

output "region" {
  description = "Region the fixture (and the provider under test) resolved to, used as the endpoint_groups key."
  value       = data.aws_region.current.region
}

output "tags" {
  description = "Identifying tags applied to the fixture and, by the caller, to the accelerator under test."
  value       = local.tags
}
