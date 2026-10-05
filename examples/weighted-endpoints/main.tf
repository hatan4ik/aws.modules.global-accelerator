provider "aws" {
  region = var.region
}

# One region, one endpoint group, two weighted endpoints: a canary split.
# Global Accelerator divides the group's traffic between its endpoints in
# proportion to their weights, so a low canary_weight against a much larger
# stable weight sends only a small, adjustable share of traffic to the
# canary release without a second listener or a second endpoint group.
module "global_accelerator" {
  source = "../../"

  name = var.name

  listeners = {
    primary = {
      port_ranges = [{ from_port = 443, to_port = 443 }]
    }
  }

  endpoint_groups = {
    "primary/${var.region}" = {
      endpoint_configurations = [
        { endpoint_id = var.stable_alb_arn, weight = 255 - var.canary_weight },
        { endpoint_id = var.canary_alb_arn, weight = var.canary_weight },
      ]
    }
  }
}
