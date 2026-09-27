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
}
