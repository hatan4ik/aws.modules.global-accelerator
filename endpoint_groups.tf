# Keyed "<listener_key>/<region>" (the endpoint_groups map key itself), which
# is exactly the identity Global Accelerator gives an endpoint group: one per
# listener per region. Both halves come from the key, split in locals.tf, so
# neither the listener nor the region can drift from what the key says. The
# accelerator precondition (accelerator.tf) rejects an unknown listener key
# before this for_each would otherwise fail with Terraform's own
# "Invalid index" error.

resource "aws_globalaccelerator_endpoint_group" "this" {
  for_each = local.endpoint_groups

  listener_arn = aws_globalaccelerator_listener.this[each.value.listener_key].arn

  endpoint_group_region         = each.value.region
  traffic_dial_percentage       = each.value.group.traffic_dial_percentage
  health_check_port             = each.value.group.health_check_port
  health_check_protocol         = each.value.group.health_check_protocol
  health_check_path             = each.value.group.health_check_path
  health_check_interval_seconds = each.value.group.health_check_interval_seconds
  threshold_count               = each.value.group.threshold_count

  dynamic "endpoint_configuration" {
    for_each = each.value.group.endpoint_configurations

    content {
      endpoint_id                    = endpoint_configuration.value.endpoint_id
      weight                         = endpoint_configuration.value.weight
      client_ip_preservation_enabled = endpoint_configuration.value.client_ip_preservation_enabled
    }
  }
}
