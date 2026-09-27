locals {
  # The caller's Name tag wins; the module only fills the gap.
  tags = merge({ Name = var.name }, var.tags)

  flow_logs_enabled = var.flow_logs != null

  # Every listener_key an endpoint group references that names no key in
  # listeners, gathered so the precondition on the accelerator can name every
  # offending value at once rather than whichever one Terraform's own
  # "Invalid index" error happens to trip over first.
  unknown_listener_keys = distinct([
    for group in values(var.endpoint_groups) : group.listener_key
    if !contains(keys(var.listeners), group.listener_key)
  ])

  # The anycast IP addresses AWS assigned, flattened out of the accelerator's
  # ip_sets blocks (one per IP address family) into the single sorted list the
  # output promises.
  ip_addresses = sort(flatten([
    for ip_set in aws_globalaccelerator_accelerator.this.ip_sets : ip_set.ip_addresses
  ]))
}
