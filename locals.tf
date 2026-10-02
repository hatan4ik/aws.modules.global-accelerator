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

  # Listener keys that can actually receive traffic: at least one of their
  # endpoint groups is dialed above zero AND has at least one endpoint with a
  # non-zero weight. A listener absent from this list routes nowhere, whether
  # because it has no endpoint groups, every group is dialed to 0%, or every
  # dialed group's endpoints all carry weight 0. The per-listener precondition
  # in listeners.tf rejects it.
  serving_listener_keys = distinct([
    for group in values(local.endpoint_groups) : group.listener_key
    if group.group.traffic_dial_percentage > 0 && anytrue([
      for endpoint in group.group.endpoint_configurations : endpoint.weight > 0
    ])
  ])

  # Endpoint groups whose endpoints are all load balancers (ARNs) yet which
  # set any health-check argument away from its default. Global Accelerator
  # ignores endpoint-group health-check settings for ALB and NLB endpoints and
  # uses the load balancer's own target-group health instead, so these
  # settings do nothing; the advisory check in checks.tf names the groups.
  health_check_ignored_groups = sort([
    for key, group in var.endpoint_groups : key
    if alltrue([for endpoint in group.endpoint_configurations : startswith(endpoint.endpoint_id, "arn:")]) && (
      group.health_check_path != null ||
      group.health_check_port != null ||
      group.health_check_protocol != "TCP" ||
      group.health_check_interval_seconds != 30 ||
      group.threshold_count != 3
    )
  ])

  # Endpoint groups that set a health_check_path while health_check_protocol
  # is TCP: a path only means anything to an HTTP or HTTPS health check.
  health_check_path_on_tcp_groups = sort([
    for key, group in var.endpoint_groups : key
    if group.health_check_path != null && group.health_check_protocol == "TCP"
  ])

  # The anycast IP addresses AWS assigned, flattened out of the accelerator's
  # ip_sets blocks (one per IP address family) into the single sorted list the
  # output promises.
  ip_addresses = sort(flatten([
    for ip_set in aws_globalaccelerator_accelerator.this.ip_sets : ip_set.ip_addresses
  ]))
}
