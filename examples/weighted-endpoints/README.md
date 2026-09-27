# Weighted endpoints (canary split)

One region, one endpoint group, two endpoints at different weights: a canary
release pattern. Global Accelerator divides an endpoint group's traffic
between its endpoints in proportion to their `weight` (0-255), so a canary
endpoint with a small weight next to a much larger stable weight receives a
small, adjustable share of the group's traffic without a second listener or a
second endpoint group.

Weight is relative **within the group**, not a percentage: with the default
`canary_weight = 26` against a stable weight of `255 - 26 = 229`, the canary
receives `26 / (26 + 229)` ≈ 10% of the traffic this group's
`traffic_dial_percentage` sends its way. Raise `canary_weight` to shift more
traffic to the canary, or lower it toward 0 to pull back without removing the
endpoint.

This composes with [`examples/two-region-alb`](../two-region-alb): a real
canary rollout runs a weighted group like this one in each region.

## Run

```sh
terraform init
terraform plan \
  -var stable_alb_arn=arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/stable/50dc6c495c0c9188 \
  -var canary_alb_arn=arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/canary/50dc6c495c0c9188 \
  -var canary_weight=26
```

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
| <a name="input_canary_alb_arn"></a> [canary\_alb\_arn](#input\_canary\_alb\_arn) | ARN of the ALB serving the canary release. | `string` | n/a | yes |
| <a name="input_canary_weight"></a> [canary\_weight](#input\_canary\_weight) | Weight given to the canary endpoint, 0-255. The stable endpoint receives the remainder of the traffic split proportionally: with a canary weight of 26 against a stable weight of 230, roughly 10% of the group's traffic reaches the canary. Weight is relative within the group, not a percentage. | `number` | `26` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the accelerator. | `string` | `"canary-example"` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region the accelerator's control-plane resources are created in, and the region the weighted endpoint group is created in. | `string` | `"us-east-1"` | no |
| <a name="input_stable_alb_arn"></a> [stable\_alb\_arn](#input\_stable\_alb\_arn) | ARN of the ALB serving the stable release. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_accelerator_arn"></a> [accelerator\_arn](#output\_accelerator\_arn) | ARN of the accelerator. |
| <a name="output_accelerator_dns_name"></a> [accelerator\_dns\_name](#output\_accelerator\_dns\_name) | DNS name to point a Route 53 alias record at. |
<!-- END_TF_DOCS -->
