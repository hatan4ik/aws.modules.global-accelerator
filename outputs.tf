output "accelerator_arn" {
  description = "ARN of the accelerator."
  value       = aws_globalaccelerator_accelerator.this.arn
}

output "accelerator_dns_name" {
  description = "DNS name AWS assigns to the accelerator's static anycast IP addresses."
  value       = aws_globalaccelerator_accelerator.this.dns_name
}

output "accelerator_hosted_zone_id" {
  description = "Route 53 hosted zone ID to use when aliasing a Route 53 record to accelerator_dns_name (see aws.modules.route53)."
  value       = aws_globalaccelerator_accelerator.this.hosted_zone_id
}

output "ip_addresses" {
  description = "Static anycast IP addresses AWS assigned to the accelerator, split by family: { ipv4 = [...], ipv6 = [...] }, each list sorted. ipv6 is empty unless ip_address_type is DUAL_STACK. Useful for allow-listing at an origin firewall in front of the endpoints, if one exists."
  value       = local.ip_addresses
}

output "listener_arns" {
  description = "ARN of each listener, keyed the same as the listeners input."
  value       = { for key, listener in aws_globalaccelerator_listener.this : key => listener.arn }
}
