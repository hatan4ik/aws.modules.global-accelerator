locals {
  # The caller's Name tag wins; the module only fills the gap.
  tags = merge({ Name = var.name }, var.tags)

  flow_logs_enabled = var.flow_logs != null

  # endpoint_groups is keyed "<listener_key>/<region>", the (listener, region)
  # pair Global Accelerator itself allows exactly one endpoint group for. The
  # key is split once here so every consumer reads named fields instead of
  # re-parsing it. try() keeps a malformed key (already rejected by the
  # variable's own validation) from also surfacing as an index error.
  endpoint_groups = {
    for key, group in var.endpoint_groups : key => {
      listener_key = try(split("/", key)[0], "")
      region       = try(split("/", key)[1], "")
      group        = group
    }
  }

  # Distinct regions with at least one endpoint group, for the advisory
  # single-region check: two listeners in one region are still one region.
  endpoint_group_regions = distinct([for group in values(local.endpoint_groups) : group.region])

  # Every listener key an endpoint_groups key references that names no key in
  # listeners, gathered so the precondition on the accelerator can name every
  # offending value at once rather than whichever one Terraform's own
  # "Invalid index" error happens to trip over first.
  unknown_listener_keys = distinct([
    for group in values(local.endpoint_groups) : group.listener_key
    if !contains(keys(var.listeners), group.listener_key)
  ])

  # The anycast IP addresses AWS assigned, flattened out of the accelerator's
  # ip_sets blocks (one per IP address family) into the single sorted list the
  # output promises.
  ip_addresses = sort(flatten([
    for ip_set in aws_globalaccelerator_accelerator.this.ip_sets : ip_set.ip_addresses
  ]))
}
