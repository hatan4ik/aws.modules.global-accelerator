# Integration suite: real apply in the caller's own account.
#
# REVIEW BEFORE DISPATCHING. Global Accelerator bills hourly from the moment
# the accelerator is created, whether or not it carries traffic, and deleting
# one takes noticeably longer than most resources this series creates
# (AWS's own guidance is to expect several minutes for the accelerator to
# leave DEPLOYED state before it can be disabled and deleted). This suite
# creates one accelerator, one TCP listener, and one endpoint group with one
# real endpoint (a disposable Elastic IP from ./setup), asserts what the real
# API reports, and destroys everything at the end of the file — but the
# accelerator bills for however long that end-to-end run takes. Do not add
# this suite to any workflow that runs on a schedule or on every push; the
# `integration` workflow that can run it is dispatch-only for this reason.
#
# Requires AWS credentials and a region from the environment (for example
# AWS_PROFILE and AWS_REGION, or the OIDC role assumed by the integration
# workflow).
#
# Run: terraform init -backend=false -test-directory=tests/integration
#      terraform test -test-directory=tests/integration -filter=tests/integration/smoke.tftest.hcl

provider "aws" {}

run "setup" {
  module {
    source = "./tests/integration/setup"
  }

  variables {
    name_prefix = "ga-it"
  }
}

run "smoke" {
  variables {
    name = "ga-it-smoke"

    listeners = {
      primary = {
        port_ranges = [{ from_port = 443, to_port = 443 }]
      }
    }

    endpoint_groups = {
      "primary/${run.setup.region}" = {
        endpoint_configurations = [
          { endpoint_id = run.setup.allocation_id },
        ]
      }
    }

    tags = run.setup.tags
  }

  assert {
    condition     = can(regex("^arn:aws:globalaccelerator::[0-9]{12}:accelerator/", output.accelerator_arn))
    error_message = "accelerator_arn must be a real Global Accelerator ARN."
  }

  assert {
    condition     = endswith(output.accelerator_dns_name, ".awsglobalaccelerator.com")
    error_message = "accelerator_dns_name must be a real Global Accelerator DNS name."
  }

  assert {
    condition     = output.accelerator_hosted_zone_id == "Z2BJ6XQ5FK7U4H"
    error_message = "accelerator_hosted_zone_id must be Global Accelerator's fixed Route 53 alias hosted zone ID, documented by AWS as constant across every accelerator."
  }

  assert {
    condition     = length(output.ip_sets) > 0 && alltrue([for ip in output.ip_sets : can(cidrhost("${ip}/32", 0))])
    error_message = "ip_sets must list at least one real anycast IPv4 address."
  }

  assert {
    condition     = can(regex("^arn:aws:globalaccelerator::[0-9]{12}:accelerator/[^/]+/listener/", output.listener_arns["primary"]))
    error_message = "listener_arns must expose the primary listener's real ARN."
  }

  assert {
    condition     = aws_globalaccelerator_accelerator.this.ip_address_type == "IPV4" && aws_globalaccelerator_accelerator.this.enabled == true
    error_message = "The real API must accept the defaults: IPV4, enabled."
  }

  assert {
    condition     = aws_globalaccelerator_listener.this["primary"].protocol == "TCP" && aws_globalaccelerator_listener.this["primary"].client_affinity == "NONE"
    error_message = "The real API must accept the listener defaults: TCP, NONE client affinity."
  }

  assert {
    condition     = aws_globalaccelerator_endpoint_group.this["primary/${run.setup.region}"].traffic_dial_percentage == 100 && aws_globalaccelerator_endpoint_group.this["primary/${run.setup.region}"].health_check_protocol == "TCP"
    error_message = "The real API must accept the endpoint group defaults: fully dialed, TCP health check."
  }
}
