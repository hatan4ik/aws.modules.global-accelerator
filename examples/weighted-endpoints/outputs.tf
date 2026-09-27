output "accelerator_arn" {
  description = "ARN of the accelerator."
  value       = module.global_accelerator.accelerator_arn
}

output "accelerator_dns_name" {
  description = "DNS name to point a Route 53 alias record at."
  value       = module.global_accelerator.accelerator_dns_name
}
