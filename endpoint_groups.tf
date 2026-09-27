# Keyed by AWS region (the endpoint_groups map key itself), each group
# attaches to the listener named by its listener_key. The accelerator
# precondition (accelerator.tf) rejects an unknown listener_key before this
# for_each would otherwise fail with Terraform's own "Invalid index" error.

resource "aws_globalaccelerator_endpoint_group" "this" {
  for_each = var.endpoint_groups

  listener_arn = aws_globalaccelerator_listener.this[each.value.listener_key].arn

  endpoint_group_region         = each.key
  traffic_dial_percentage       = each.value.traffic_dial_percentage
  health_check_port             = each.value.health_check_port
  health_check_protocol         = each.value.health_check_protocol
  health_check_path             = each.value.health_check_path
  health_check_interval_seconds = each.value.health_check_interval_seconds
  threshold_count               = each.value.threshold_count

  dynamic "endpoint_configuration" {
    for_each = each.value.endpoint_configurations

    content {
      endpoint_id                    = endpoint_configuration.value.endpoint_id
      weight                         = endpoint_configuration.value.weight
      client_ip_preservation_enabled = endpoint_configuration.value.client_ip_preservation_enabled
    }
  }
}
