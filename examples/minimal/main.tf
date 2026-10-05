provider "aws" {
  region = var.region
}

module "global_accelerator" {
  source = "../../"

  name = var.name

  listeners = {
    primary = {
      port_ranges = [{ from_port = 443, to_port = 443 }]
    }
  }

  # One region, one endpoint: the smallest working call. A real deployment
  # following ADR 0004 adds a second regional endpoint group; see
  # examples/two-region-alb.
  endpoint_groups = {
    "primary/${var.region}" = {
      endpoint_configurations = [
        { endpoint_id = var.endpoint_id },
      ]
    }
  }
}
