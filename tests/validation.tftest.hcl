mock_provider "aws" {}

variables {
  name = "public-api"

  # Declared so this file's runs are isolated from the advisory checks
  # (tests/checks.tftest.hcl exercises those); flow_logs left null and a
  # single-region endpoint_groups map would otherwise fail every run here.
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
}

# ---------------------------------------------------------------------------
# name
# ---------------------------------------------------------------------------

run "rejects_a_name_with_spaces" {
  command = plan
  variables {
    name = "public api"
  }
  expect_failures = [var.name]
}

run "rejects_a_name_over_64_characters" {
  command = plan
  variables {
    name = join("", [for i in range(65) : "a"])
  }
  expect_failures = [var.name]
}

# ---------------------------------------------------------------------------
# ip_address_type
# ---------------------------------------------------------------------------

run "rejects_an_unknown_ip_address_type" {
  command = plan
  variables {
    ip_address_type = "IPV6"
  }
  expect_failures = [var.ip_address_type]
}

# ---------------------------------------------------------------------------
# flow_logs
# ---------------------------------------------------------------------------

run "rejects_an_uppercase_flow_logs_bucket_name" {
  command = plan
  variables {
    flow_logs = { bucket_name = "Ga-Flow-Logs" }
  }
  expect_failures = [var.flow_logs]
}

run "rejects_a_flow_logs_prefix_starting_with_a_slash" {
  command = plan
  variables {
    flow_logs = { bucket_name = "ga-flow-logs-example", prefix = "/leading-slash" }
  }
  expect_failures = [var.flow_logs]
}

# ---------------------------------------------------------------------------
# listeners
# ---------------------------------------------------------------------------

run "rejects_empty_listeners" {
  command = plan
  variables {
    listeners       = {}
    endpoint_groups = {}
  }
  expect_failures = [var.listeners, var.endpoint_groups]
}

run "rejects_a_listener_key_containing_a_slash" {
  command = plan
  variables {
    listeners = {
      "api/v2" = {
        port_ranges = [{ from_port = 443, to_port = 443 }]
      }
    }
  }
  expect_failures = [var.listeners]
}

run "rejects_an_unknown_listener_protocol" {
  command = plan
  variables {
    listeners = {
      primary = {
        protocol    = "HTTP"
        port_ranges = [{ from_port = 443, to_port = 443 }]
      }
    }
  }
  expect_failures = [var.listeners]
}

run "rejects_an_unknown_client_affinity" {
  command = plan
  variables {
    listeners = {
      primary = {
        client_affinity = "CLIENT_IP"
        port_ranges     = [{ from_port = 443, to_port = 443 }]
      }
    }
  }
  expect_failures = [var.listeners]
}

run "rejects_a_listener_with_no_port_ranges" {
  command = plan
  variables {
    listeners = {
      primary = { port_ranges = [] }
    }
  }
  expect_failures = [var.listeners]
}

run "rejects_a_port_range_below_1" {
  command = plan
  variables {
    listeners = {
      primary = { port_ranges = [{ from_port = 0, to_port = 443 }] }
    }
  }
  expect_failures = [var.listeners]
}

run "rejects_a_port_range_above_65535" {
  command = plan
  variables {
    listeners = {
      primary = { port_ranges = [{ from_port = 443, to_port = 70000 }] }
    }
  }
  expect_failures = [var.listeners]
}

run "rejects_a_port_range_with_from_port_greater_than_to_port" {
  command = plan
  variables {
    listeners = {
      primary = { port_ranges = [{ from_port = 443, to_port = 80 }] }
    }
  }
  expect_failures = [var.listeners]
}

# ---------------------------------------------------------------------------
# endpoint_groups
# ---------------------------------------------------------------------------

run "rejects_empty_endpoint_groups" {
  command = plan
  variables {
    endpoint_groups = {}
  }
  expect_failures = [var.endpoint_groups]
}

run "rejects_a_key_that_does_not_look_like_a_region" {
  command = plan
  variables {
    endpoint_groups = {
      "primary/not-a-region" = {
        endpoint_configurations = [
          { endpoint_id = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/primary/50dc6c495c0c9188" }
        ]
      }
    }
  }
  expect_failures = [var.endpoint_groups]
}

run "rejects_a_region_only_key_from_the_v1_0_0_interface" {
  command = plan
  variables {
    # The v1.0.0 shape: keyed by region alone. It must fail loudly at plan
    # rather than be reinterpreted, so an un-migrated caller cannot apply.
    endpoint_groups = {
      "us-east-1" = {
        endpoint_configurations = [
          { endpoint_id = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/primary/50dc6c495c0c9188" }
        ]
      }
    }
  }
  expect_failures = [var.endpoint_groups]
}

run "rejects_a_key_with_an_empty_listener_half" {
  command = plan
  variables {
    endpoint_groups = {
      "/us-east-1" = {
        endpoint_configurations = [
          { endpoint_id = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/primary/50dc6c495c0c9188" }
        ]
      }
    }
  }
  expect_failures = [var.endpoint_groups]
}

run "rejects_every_group_dialed_to_zero" {
  command = plan
  variables {
    endpoint_groups = {
      "primary/us-east-1" = {
        traffic_dial_percentage = 0
        endpoint_configurations = [
          { endpoint_id = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/primary/50dc6c495c0c9188" }
        ]
      }
      "primary/eu-west-1" = {
        traffic_dial_percentage = 0
        endpoint_configurations = [
          { endpoint_id = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:loadbalancer/app/secondary/50dc6c495c0c9188" }
        ]
      }
    }
  }
  expect_failures = [var.endpoint_groups]
}

run "rejects_a_traffic_dial_percentage_above_100" {
  command = plan
  variables {
    endpoint_groups = {
      "primary/us-east-1" = {
        traffic_dial_percentage = 150
        endpoint_configurations = [
          { endpoint_id = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/primary/50dc6c495c0c9188" }
        ]
      }
    }
  }
  expect_failures = [var.endpoint_groups]
}

run "rejects_a_negative_traffic_dial_percentage" {
  command = plan
  variables {
    endpoint_groups = {
      "primary/us-east-1" = {
        traffic_dial_percentage = -1
        endpoint_configurations = [
          { endpoint_id = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/primary/50dc6c495c0c9188" }
        ]
      }
    }
  }
  expect_failures = [var.endpoint_groups]
}

run "rejects_an_unknown_health_check_protocol" {
  command = plan
  variables {
    endpoint_groups = {
      "primary/us-east-1" = {
        health_check_protocol = "FTP"
        endpoint_configurations = [
          { endpoint_id = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/primary/50dc6c495c0c9188" }
        ]
      }
    }
  }
  expect_failures = [var.endpoint_groups]
}

run "rejects_a_health_check_port_above_65535" {
  command = plan
  variables {
    endpoint_groups = {
      "primary/us-east-1" = {
        health_check_port = 70000
        endpoint_configurations = [
          { endpoint_id = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/primary/50dc6c495c0c9188" }
        ]
      }
    }
  }
  expect_failures = [var.endpoint_groups]
}

run "rejects_a_health_check_interval_other_than_10_or_30" {
  command = plan
  variables {
    endpoint_groups = {
      "primary/us-east-1" = {
        health_check_interval_seconds = 15
        endpoint_configurations = [
          { endpoint_id = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/primary/50dc6c495c0c9188" }
        ]
      }
    }
  }
  expect_failures = [var.endpoint_groups]
}

run "rejects_a_threshold_count_of_zero" {
  command = plan
  variables {
    endpoint_groups = {
      "primary/us-east-1" = {
        threshold_count = 0
        endpoint_configurations = [
          { endpoint_id = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/primary/50dc6c495c0c9188" }
        ]
      }
    }
  }
  expect_failures = [var.endpoint_groups]
}

run "rejects_a_threshold_count_above_10" {
  command = plan
  variables {
    endpoint_groups = {
      "primary/us-east-1" = {
        threshold_count = 11
        endpoint_configurations = [
          { endpoint_id = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/primary/50dc6c495c0c9188" }
        ]
      }
    }
  }
  expect_failures = [var.endpoint_groups]
}

run "rejects_an_endpoint_group_with_no_endpoint_configurations" {
  command = plan
  variables {
    endpoint_groups = {
      "primary/us-east-1" = {
        endpoint_configurations = []
      }
    }
  }
  expect_failures = [var.endpoint_groups]
}

run "rejects_a_blank_endpoint_id" {
  command = plan
  variables {
    endpoint_groups = {
      "primary/us-east-1" = {
        endpoint_configurations = [
          { endpoint_id = "   " }
        ]
      }
    }
  }
  expect_failures = [var.endpoint_groups]
}

run "rejects_a_weight_above_255" {
  command = plan
  variables {
    endpoint_groups = {
      "primary/us-east-1" = {
        endpoint_configurations = [
          { endpoint_id = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/primary/50dc6c495c0c9188", weight = 256 }
        ]
      }
    }
  }
  expect_failures = [var.endpoint_groups]
}

run "rejects_a_negative_weight" {
  command = plan
  variables {
    endpoint_groups = {
      "primary/us-east-1" = {
        endpoint_configurations = [
          { endpoint_id = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/primary/50dc6c495c0c9188", weight = -1 }
        ]
      }
    }
  }
  expect_failures = [var.endpoint_groups]
}

# ---------------------------------------------------------------------------
# Cross-variable: the listener half of every endpoint_groups key must resolve
# ---------------------------------------------------------------------------

run "rejects_an_endpoint_group_that_references_an_unknown_listener_key" {
  command = plan
  variables {
    # Two regions, so the single_region_endpoint_groups advisory check does
    # not also fire and confuse this precondition-only assertion.
    endpoint_groups = {
      "typo/us-east-1" = {
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
  }
  expect_failures = [aws_globalaccelerator_accelerator.this]
}
