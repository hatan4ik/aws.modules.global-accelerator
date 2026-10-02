provider "aws" {
  region = var.region
}

# ADR 0004's actual shape: one listener, two regional endpoint groups, each
# pointed at a regional public ALB. See variables.tf for how the two ARNs
# below would be produced by two aws.modules.alb calls in a real composition.
module "global_accelerator" {
  source = "../../"

  name = var.name

  flow_logs = var.flow_logs_bucket_name == null ? null : {
    bucket_name = var.flow_logs_bucket_name
  }

  listeners = {
    api = {
      port_ranges = [{ from_port = 443, to_port = 443 }]
    }
  }

  endpoint_groups = {
    "api/us-east-1" = {
      endpoint_configurations = [
        { endpoint_id = var.us_east_1_alb_arn },
      ]
    }
    "api/eu-west-1" = {
      endpoint_configurations = [
        { endpoint_id = var.eu_west_1_alb_arn },
      ]
    }
  }
}
