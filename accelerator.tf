# One Global Accelerator per module call. Its listeners (listeners.tf) and
# endpoint groups (endpoint_groups.tf) attach to it by ARN.

resource "aws_globalaccelerator_accelerator" "this" {
  name            = var.name
  ip_address_type = var.ip_address_type
  enabled         = var.enabled

  # Omitted entirely when flow_logs is null, so the API default
  # (flow_logs_enabled = false) applies: off until declared.
  dynamic "attributes" {
    for_each = local.flow_logs_enabled ? [var.flow_logs] : []

    content {
      flow_logs_enabled   = true
      flow_logs_s3_bucket = attributes.value.bucket_name
      flow_logs_s3_prefix = attributes.value.prefix
    }
  }

  tags = local.tags

  lifecycle {
    # This is a cross-variable rule (endpoint_groups against listeners), which
    # a variable validation block cannot express under Terraform 1.7: a
    # variable's own validation may only reference that variable. Attaching it
    # here, rather than to the endpoint group it concerns, gives one place
    # that names every unresolved listener_key instead of failing on whichever
    # for_each key Terraform's own "Invalid index" error reaches first.
    precondition {
      condition     = length(local.unknown_listener_keys) == 0
      error_message = "Every endpoint_groups[*].listener_key must reference a key in listeners. Unknown listener_key value(s): ${join(", ", local.unknown_listener_keys)}."
    }
  }
}
