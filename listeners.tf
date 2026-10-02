resource "aws_globalaccelerator_listener" "this" {
  for_each = var.listeners

  accelerator_arn = aws_globalaccelerator_accelerator.this.arn
  client_affinity = each.value.client_affinity
  protocol        = each.value.protocol

  dynamic "port_range" {
    for_each = each.value.port_ranges

    content {
      from_port = port_range.value.from_port
      to_port   = port_range.value.to_port
    }
  }

  lifecycle {
    # Cross-variable (listeners against endpoint_groups), so a precondition
    # rather than a variable validation under Terraform 1.7; see
    # docs/DESIGN.md. Evaluated per listener, so in a multi-listener
    # accelerator one dead listener is caught even while another serves. To
    # stop a listener deliberately, remove it (or set enabled = false to stop
    # the whole accelerator) rather than leaving it attached to nothing.
    precondition {
      condition     = contains(local.serving_listener_keys, each.key)
      error_message = "Listener \"${each.key}\" would serve no traffic. It needs at least one endpoint_groups entry keyed \"${each.key}/<region>\" with a traffic_dial_percentage above 0 and at least one endpoint whose weight is above 0. Today it has no endpoint group, every group is dialed to 0%, or every dialed group's endpoints all have weight 0."
    }
  }
}
