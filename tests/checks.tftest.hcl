mock_provider "aws" {}

# flow_logs is left unset (its true default, null) and endpoint_groups
# declares one region, so this file's baseline is the state both advisory
# checks warn about; each run below flips exactly one of the two to its safe
# value to show the corresponding check stops firing.
variables {
  name = "public-api"

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
  }
}

run "warns_when_flow_logs_are_disabled" {
  command = plan

  expect_failures = [check.flow_logs_disabled, check.single_region_endpoint_groups]
}

run "stops_warning_once_flow_logs_are_declared" {
  command = plan

  variables {
    flow_logs = { bucket_name = "ga-flow-logs-example" }
  }

  expect_failures = [check.single_region_endpoint_groups]
}

run "stops_warning_once_a_second_region_is_present" {
  command = plan

  variables {
    flow_logs = { bucket_name = "ga-flow-logs-example" }
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

  # Neither check should fire: flow logs are declared and two regions are present.
}

run "still_warns_when_two_listeners_share_one_region" {
  command = plan

  # Two endpoint groups, but both in us-east-1: the check counts distinct
  # regions, not endpoint_groups entries, so this is still single-region.
  variables {
    flow_logs = { bucket_name = "ga-flow-logs-example" }
    listeners = {
      primary = {
        port_ranges = [{ from_port = 443, to_port = 443 }]
      }
      secondary = {
        protocol    = "UDP"
        port_ranges = [{ from_port = 51820, to_port = 51820 }]
      }
    }
    endpoint_groups = {
      "primary/us-east-1" = {
        endpoint_configurations = [
          { endpoint_id = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/primary/50dc6c495c0c9188" }
        ]
      }
      "secondary/us-east-1" = {
        endpoint_configurations = [
          { endpoint_id = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/net/secondary/60dc6c495c0c9188" }
        ]
      }
    }
  }

  expect_failures = [check.single_region_endpoint_groups]
}

run "warns_when_health_check_settings_target_only_load_balancer_endpoints" {
  command = plan

  # Both groups point only at ALBs, for which Global Accelerator uses the
  # load balancer's own target-group health and ignores these settings.
  variables {
    flow_logs = { bucket_name = "ga-flow-logs-example" }
    endpoint_groups = {
      "primary/us-east-1" = {
        health_check_protocol = "HTTPS"
        health_check_path     = "/healthz"
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

  expect_failures = [check.health_check_settings_ignored_for_load_balancer_endpoints]
}

run "does_not_warn_when_health_check_settings_reach_an_elastic_ip_endpoint" {
  command = plan

  variables {
    flow_logs = { bucket_name = "ga-flow-logs-example" }
    endpoint_groups = {
      "primary/us-east-1" = {
        health_check_protocol = "HTTPS"
        health_check_path     = "/healthz"
        endpoint_configurations = [
          { endpoint_id = "eipalloc-0123456789abcdef0" }
        ]
      }
      "primary/eu-west-1" = {
        endpoint_configurations = [
          { endpoint_id = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:loadbalancer/app/secondary/50dc6c495c0c9188" }
        ]
      }
    }
  }

  # No check should fire: the settings apply to the Elastic IP endpoint.
}

run "warns_when_a_health_check_path_is_paired_with_tcp" {
  command = plan

  variables {
    flow_logs = { bucket_name = "ga-flow-logs-example" }
    endpoint_groups = {
      "primary/us-east-1" = {
        health_check_path = "/healthz"
        endpoint_configurations = [
          { endpoint_id = "eipalloc-0123456789abcdef0" }
        ]
      }
      "primary/eu-west-1" = {
        endpoint_configurations = [
          { endpoint_id = "eipalloc-12345678" }
        ]
      }
    }
  }

  expect_failures = [check.health_check_path_requires_http_protocol]
}
