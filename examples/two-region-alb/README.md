# Two-region ALB accelerator

The shape ADR 0004 (Separate static edge delivery, dynamic API acceleration,
and conditional egress inspection) actually calls for: one listener and two
regional endpoint groups, each pointed at a regional public ALB, so dynamic
API traffic is steered active-active by anycast IP addresses and ALB health
checks rather than by DNS.

## Why this is a placeholder, not a live `aws.modules.alb` call

`aws.modules.global-accelerator` deliberately does not call
`aws.modules.alb`, or know that ALB is what is behind `endpoint_id` at all —
see [docs/DESIGN.md](../../docs/DESIGN.md) for why. In a real composition, the
two ARNs this example takes as plain variables would be the `arn` output of
two separate `aws.modules.alb` calls, one per region behind a provider alias:

```hcl
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

provider "aws" {
  alias  = "eu_west_1"
  region = "eu-west-1"
}

module "alb_us_east_1" {
  source    = "git::https://github.com/hatan4ik/aws.modules.alb.git?ref=<commit-sha>" # v1.0.0
  providers = { aws = aws.us_east_1 }
  # ... vpc_id, subnet_ids, listeners, target groups for this region
}

module "alb_eu_west_1" {
  source    = "git::https://github.com/hatan4ik/aws.modules.alb.git?ref=<commit-sha>" # v1.0.0
  providers = { aws = aws.eu_west_1 }
  # ... vpc_id, subnet_ids, listeners, target groups for this region
}

module "global_accelerator" {
  source = "git::https://github.com/hatan4ik/aws.modules.global-accelerator.git?ref=<commit-sha>" # v2.0.0

  name = "public-api"

  listeners = {
    api = {
      port_ranges = [{ from_port = 443, to_port = 443 }]
    }
  }

  endpoint_groups = {
    "api/us-east-1" = {
      endpoint_configurations = [{ endpoint_id = module.alb_us_east_1.arn }]
    }
    "api/eu-west-1" = {
      endpoint_configurations = [{ endpoint_id = module.alb_eu_west_1.arn }]
    }
  }
}
```

This example takes `us_east_1_alb_arn` and `eu_west_1_alb_arn` as plain
strings instead, so it plans and validates without also standing up two ALBs,
two VPCs, and their target groups just to demonstrate the accelerator.

## Run

```sh
terraform init
terraform plan \
  -var us_east_1_alb_arn=arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/primary/50dc6c495c0c9188 \
  -var eu_west_1_alb_arn=arn:aws:elasticloadbalancing:eu-west-1:123456789012:loadbalancer/app/secondary/50dc6c495c0c9188
```

Add `-var flow_logs_bucket_name=<your bucket>` to turn on flow logs; without it the `flow_logs_disabled` check warns on the plan.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.35.0, < 7.0.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_global_accelerator"></a> [global\_accelerator](#module\_global\_accelerator) | ../../ | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_eu_west_1_alb_arn"></a> [eu\_west\_1\_alb\_arn](#input\_eu\_west\_1\_alb\_arn) | ARN of the regional public ALB in eu-west-1 (what aws.modules.alb's arn output would provide). | `string` | n/a | yes |
| <a name="input_flow_logs_bucket_name"></a> [flow\_logs\_bucket\_name](#input\_flow\_logs\_bucket\_name) | Name of an existing S3 bucket the caller owns to receive flow logs. null leaves flow logs off. | `string` | `null` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the accelerator. | `string` | `"public-api"` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region the accelerator's control-plane resources are created in. Global Accelerator itself is a global service. | `string` | `"us-east-1"` | no |
| <a name="input_us_east_1_alb_arn"></a> [us\_east\_1\_alb\_arn](#input\_us\_east\_1\_alb\_arn) | ARN of the regional public ALB in us-east-1 (what aws.modules.alb's arn output would provide). | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_accelerator_arn"></a> [accelerator\_arn](#output\_accelerator\_arn) | ARN of the accelerator. |
| <a name="output_accelerator_dns_name"></a> [accelerator\_dns\_name](#output\_accelerator\_dns\_name) | DNS name to point a Route 53 alias record at. |
| <a name="output_accelerator_hosted_zone_id"></a> [accelerator\_hosted\_zone\_id](#output\_accelerator\_hosted\_zone\_id) | Hosted zone ID for the Route 53 alias record. |
| <a name="output_ip_addresses"></a> [ip\_addresses](#output\_ip\_addresses) | Static anycast IP addresses AWS assigned, split into ipv4 and ipv6 lists. |
| <a name="output_listener_arns"></a> [listener\_arns](#output\_listener\_arns) | ARN of the api listener. |
<!-- END_TF_DOCS -->
