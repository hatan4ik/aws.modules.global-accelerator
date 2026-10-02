# Apply-mode contract test, isolated in its own file because run blocks in one
# file share state and an apply would leak into later plan runs (see the
# plan-only files, which cannot see listener ARNs: those are unknown until
# apply). Every listener instance gets a distinct ARN through override_resource,
# so an endpoint group that attached to the wrong listener fails an assertion
# instead of accidentally passing because both listeners share one mocked ARN.

mock_provider "aws" {}

variables {
  name = "public-api"

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

  # Both listeners have an endpoint group in us-east-1 at the same time: the
  # (listener, region) pair is what AWS keys endpoint groups on. The v1
  # region-only map key made this unrepresentable; the composite
  # "<listener_key>/<region>" key is what makes it expressible.
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
    "secondary/eu-west-1" = {
      endpoint_configurations = [
        { endpoint_id = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:loadbalancer/net/secondary/70dc6c495c0c9188" }
      ]
    }
  }
}

override_resource {
  target = aws_globalaccelerator_accelerator.this
  values = {
    id             = "test-accelerator-1234"
    arn            = "arn:aws:globalaccelerator::123456789012:accelerator/1234abcd-1234-abcd-1234-abcd1234abcd"
    dns_name       = "a1234567890abcdef.awsglobalaccelerator.com"
    hosted_zone_id = "Z2BJ6XQ5FK7U4H"
    ip_sets = [
      { ip_addresses = ["5.6.7.8"], ip_family = "IPv4" },
      { ip_addresses = ["1.2.3.4"], ip_family = "IPv4" },
    ]
  }
}

override_resource {
  target = aws_globalaccelerator_listener.this["primary"]
  values = {
    id  = "listener-primary"
    arn = "arn:aws:globalaccelerator::123456789012:accelerator/1234abcd-1234-abcd-1234-abcd1234abcd/listener/1111111111"
  }
}

override_resource {
  target = aws_globalaccelerator_listener.this["secondary"]
  values = {
    id  = "listener-secondary"
    arn = "arn:aws:globalaccelerator::123456789012:accelerator/1234abcd-1234-abcd-1234-abcd1234abcd/listener/2222222222"
  }
}

run "resolves_each_endpoint_group_to_the_listener_named_by_its_key" {
  command = apply

  assert {
    condition     = aws_globalaccelerator_endpoint_group.this["primary/us-east-1"].listener_arn == "arn:aws:globalaccelerator::123456789012:accelerator/1234abcd-1234-abcd-1234-abcd1234abcd/listener/1111111111"
    error_message = "The primary/us-east-1 group must attach to the primary listener's ARN, not whichever listener the for_each visits first."
  }

  assert {
    condition     = aws_globalaccelerator_endpoint_group.this["secondary/us-east-1"].listener_arn == "arn:aws:globalaccelerator::123456789012:accelerator/1234abcd-1234-abcd-1234-abcd1234abcd/listener/2222222222" && aws_globalaccelerator_endpoint_group.this["secondary/eu-west-1"].listener_arn == "arn:aws:globalaccelerator::123456789012:accelerator/1234abcd-1234-abcd-1234-abcd1234abcd/listener/2222222222"
    error_message = "Both secondary/* groups must attach to the secondary listener's ARN."
  }

  assert {
    condition     = aws_globalaccelerator_endpoint_group.this["primary/us-east-1"].endpoint_group_region == "us-east-1" && aws_globalaccelerator_endpoint_group.this["secondary/us-east-1"].endpoint_group_region == "us-east-1" && aws_globalaccelerator_endpoint_group.this["secondary/eu-west-1"].endpoint_group_region == "eu-west-1"
    error_message = "Each endpoint group's region must be the region half of its composite key."
  }
}

run "two_listeners_each_have_an_endpoint_group_in_the_same_region" {
  command = apply

  # The case the v1.0.0 region-only key could not express: a TCP listener and
  # a UDP listener both steering into us-east-1 simultaneously, as two
  # distinct endpoint groups attached to two distinct listeners.
  assert {
    condition = length([
      for group in aws_globalaccelerator_endpoint_group.this : group
      if group.endpoint_group_region == "us-east-1"
    ]) == 2
    error_message = "Two endpoint groups must exist in us-east-1 at once, one per listener."
  }

  assert {
    condition = length(distinct([
      for group in aws_globalaccelerator_endpoint_group.this : group.listener_arn
      if group.endpoint_group_region == "us-east-1"
    ])) == 2
    error_message = "The two us-east-1 endpoint groups must attach to two different listeners."
  }
}

run "reports_the_documented_outputs" {
  command = apply

  assert {
    condition     = output.accelerator_arn == "arn:aws:globalaccelerator::123456789012:accelerator/1234abcd-1234-abcd-1234-abcd1234abcd"
    error_message = "accelerator_arn must be the accelerator's ARN."
  }

  assert {
    condition     = output.accelerator_dns_name == "a1234567890abcdef.awsglobalaccelerator.com" && output.accelerator_hosted_zone_id == "Z2BJ6XQ5FK7U4H"
    error_message = "accelerator_dns_name and accelerator_hosted_zone_id must be exposed as the module documents, for a Route 53 alias record (see aws.modules.route53)."
  }

  assert {
    condition     = tolist(output.ip_sets) == tolist(["1.2.3.4", "5.6.7.8"])
    error_message = "ip_sets must flatten every ip_addresses entry across the accelerator's ip_sets blocks into one sorted list of strings."
  }

  assert {
    condition     = output.listener_arns["primary"] == "arn:aws:globalaccelerator::123456789012:accelerator/1234abcd-1234-abcd-1234-abcd1234abcd/listener/1111111111" && output.listener_arns["secondary"] == "arn:aws:globalaccelerator::123456789012:accelerator/1234abcd-1234-abcd-1234-abcd1234abcd/listener/2222222222"
    error_message = "listener_arns must be keyed exactly like the listeners input."
  }
}
