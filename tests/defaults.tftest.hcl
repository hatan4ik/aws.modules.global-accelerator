mock_provider "aws" {}

# flow_logs is set here so this file's assertions are isolated from the
# advisory checks (tests/checks.tftest.hcl exercises flow_logs left at its
# true default of null, and a single-region endpoint_groups map).
variables {
  name = "public-api"

  flow_logs = { bucket_name = "ga-flow-logs-example" }

  listeners = {
    primary = {
      port_ranges = [{ from_port = 443, to_port = 443 }]
    }
  }

  endpoint_groups = {
    "primary/us-east-1" = {
      endpoint_configurations = [
        { endpoint_id = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/primary/50dc6c495c0c9188" }
      ]
    }
    "primary/eu-west-1" = {
      endpoint_configurations = [
        { endpoint_id = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:loadbalancer/app/secondary/50dc6c495c0c9188" }
      ]
    }
  }

  tags = { Environment = "test", Owner = "platform" }
}

run "creates_one_accelerator_with_secure_defaults" {
  command = plan

  assert {
    condition     = aws_globalaccelerator_accelerator.this.name == "public-api" && aws_globalaccelerator_accelerator.this.ip_address_type == "IPV4" && aws_globalaccelerator_accelerator.this.enabled == true
    error_message = "The accelerator must carry the declared name, default to IPV4, and be enabled by default."
  }

  assert {
    condition     = aws_globalaccelerator_accelerator.this.tags["Name"] == "public-api" && aws_globalaccelerator_accelerator.this.tags["Owner"] == "platform" && aws_globalaccelerator_accelerator.this.tags["Environment"] == "test"
    error_message = "The accelerator must carry a Name tag derived from name and every caller tag."
  }

  assert {
    condition     = length(aws_globalaccelerator_accelerator.this.attributes) == 1 && aws_globalaccelerator_accelerator.this.attributes[0].flow_logs_enabled == true && aws_globalaccelerator_accelerator.this.attributes[0].flow_logs_s3_bucket == "ga-flow-logs-example" && aws_globalaccelerator_accelerator.this.attributes[0].flow_logs_s3_prefix == null
    error_message = "Declaring flow_logs must render one attributes block with the bucket and no prefix."
  }
}

run "keeps_a_caller_supplied_name_tag" {
  command = plan

  variables {
    tags = { Name = "custom", Owner = "platform" }
  }

  assert {
    condition     = aws_globalaccelerator_accelerator.this.tags["Name"] == "custom" && aws_globalaccelerator_accelerator.this.tags["Owner"] == "platform"
    error_message = "A caller Name tag must never be overridden."
  }
}

run "creates_the_declared_listener_with_secure_defaults" {
  command = plan

  assert {
    condition     = length(aws_globalaccelerator_listener.this) == 1 && contains(keys(aws_globalaccelerator_listener.this), "primary")
    error_message = "Exactly one listener keyed \"primary\" must be planned."
  }

  assert {
    condition     = aws_globalaccelerator_listener.this["primary"].protocol == "TCP" && aws_globalaccelerator_listener.this["primary"].client_affinity == "NONE"
    error_message = "A listener with no protocol or client_affinity declared must default to TCP and NONE."
  }

  assert {
    # port_range is a set-typed nested block: no addressable index, so its
    # single element is matched with a for expression instead of [0].
    condition     = length(aws_globalaccelerator_listener.this["primary"].port_range) == 1 && anytrue([for pr in aws_globalaccelerator_listener.this["primary"].port_range : pr.from_port == 443 && pr.to_port == 443])
    error_message = "The declared port range must render exactly."
  }
}

run "creates_one_endpoint_group_per_listener_and_region_with_secure_defaults" {
  command = plan

  assert {
    condition     = length(aws_globalaccelerator_endpoint_group.this) == 2 && contains(keys(aws_globalaccelerator_endpoint_group.this), "primary/us-east-1") && contains(keys(aws_globalaccelerator_endpoint_group.this), "primary/eu-west-1")
    error_message = "One endpoint group per declared (listener, region) pair must be planned, keyed \"<listener_key>/<region>\"."
  }

  assert {
    condition     = aws_globalaccelerator_endpoint_group.this["primary/us-east-1"].endpoint_group_region == "us-east-1" && aws_globalaccelerator_endpoint_group.this["primary/eu-west-1"].endpoint_group_region == "eu-west-1"
    error_message = "Each endpoint group's region must equal the region half of its map key."
  }

  # listener_arn is a cross-resource reference and is unknown under
  # command = plan; the listener-key-to-ARN lookup is proven under
  # command = apply in tests/wiring.tftest.hcl instead.

  assert {
    condition     = aws_globalaccelerator_endpoint_group.this["primary/us-east-1"].traffic_dial_percentage == 100 && aws_globalaccelerator_endpoint_group.this["primary/us-east-1"].health_check_protocol == "TCP" && aws_globalaccelerator_endpoint_group.this["primary/us-east-1"].health_check_interval_seconds == 30 && aws_globalaccelerator_endpoint_group.this["primary/us-east-1"].threshold_count == 3
    error_message = "An endpoint group with no health check settings declared must use the documented defaults."
  }

  # health_check_port is Optional+Computed in the provider schema (AWS falls
  # back to the listener's port when it is left unset), so leaving it null is
  # itself unknown at plan time under any provider, mock or real; there is
  # nothing to assert about it before an apply.

  assert {
    # endpoint_configuration is a set-typed nested block: no addressable
    # index, so its single element is matched with a for expression.
    condition     = length(aws_globalaccelerator_endpoint_group.this["primary/us-east-1"].endpoint_configuration) == 1 && anytrue([for endpoint in aws_globalaccelerator_endpoint_group.this["primary/us-east-1"].endpoint_configuration : endpoint.weight == 128 && endpoint.client_ip_preservation_enabled == true])
    error_message = "An endpoint with no weight or client IP preservation declared must default to weight 128 and preservation enabled."
  }
}

run "accepts_boundary_weights_and_a_zero_dialed_group" {
  command = plan

  variables {
    endpoint_groups = {
      "primary/us-east-1" = {
        traffic_dial_percentage = 0
        endpoint_configurations = [
          { endpoint_id = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/standby/50dc6c495c0c9188", weight = 0 },
        ]
      }
      "primary/eu-west-1" = {
        endpoint_configurations = [
          { endpoint_id = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:loadbalancer/app/active-a/50dc6c495c0c9188", weight = 0 },
          { endpoint_id = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:loadbalancer/app/active-b/50dc6c495c0c9188", weight = 255 },
        ]
      }
    }
  }

  assert {
    condition     = aws_globalaccelerator_endpoint_group.this["primary/us-east-1"].traffic_dial_percentage == 0 && aws_globalaccelerator_endpoint_group.this["primary/eu-west-1"].traffic_dial_percentage == 100
    error_message = "A group dialed to zero is valid as long as another group in the same accelerator is non-zero."
  }

  assert {
    # A set has no guaranteed order, so the two weights are compared as a set
    # rather than a positional list.
    condition     = toset([for endpoint in aws_globalaccelerator_endpoint_group.this["primary/eu-west-1"].endpoint_configuration : endpoint.weight]) == toset([0, 255])
    error_message = "Weights 0 and 255, the Global Accelerator bounds, must render exactly as declared."
  }
}
