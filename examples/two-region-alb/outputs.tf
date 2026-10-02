output "accelerator_arn" {
  description = "ARN of the accelerator."
  value       = module.global_accelerator.accelerator_arn
}

output "accelerator_dns_name" {
  description = "DNS name to point a Route 53 alias record at."
  value       = module.global_accelerator.accelerator_dns_name
}

output "accelerator_hosted_zone_id" {
  description = "Hosted zone ID for the Route 53 alias record."
  value       = module.global_accelerator.accelerator_hosted_zone_id
}

output "ip_addresses" {
  description = "Static anycast IP addresses AWS assigned, split into ipv4 and ipv6 lists."
  value       = module.global_accelerator.ip_addresses
}

output "listener_arns" {
  description = "ARN of the api listener."
  value       = module.global_accelerator.listener_arns
}
