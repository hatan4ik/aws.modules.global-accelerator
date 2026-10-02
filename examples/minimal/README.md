# Minimal accelerator

The smallest working call of `aws.modules.global-accelerator`: one listener,
one region, one endpoint. Everything else keeps the module's defaults: TCP on
the declared port range, `NONE` client affinity, a `traffic_dial_percentage`
of 100, a TCP health check every 30 seconds with a threshold of 3, an endpoint
weight of 128 with client IP preservation enabled, and flow logs off.

This is a starting point to see exactly what an accelerator needs before
adding a second region (see [`examples/two-region-alb`](../two-region-alb),
the shape ADR 0004 actually calls for) or a weighted split within one region
(see [`examples/weighted-endpoints`](../weighted-endpoints)).

## Run

```sh
terraform init
terraform plan \
  -var name=minimal-example \
  -var endpoint_id=arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/example/50dc6c495c0c9188
```

`endpoint_id` is an existing ALB or NLB ARN in `region`, an Elastic IP allocation ID, or an EC2 instance ID; the module does not create it, but rejects a malformed ID at plan time.

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
| <a name="input_endpoint_id"></a> [endpoint\_id](#input\_endpoint\_id) | ARN or Elastic IP allocation ID of the single endpoint to accelerate, such as an existing ALB's ARN. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name of the accelerator. | `string` | `"minimal-example"` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region the accelerator's control-plane resources are created in. Global Accelerator itself is a global service; this is where the Terraform provider operates. | `string` | `"us-east-1"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_accelerator_arn"></a> [accelerator\_arn](#output\_accelerator\_arn) | ARN of the accelerator. |
| <a name="output_accelerator_dns_name"></a> [accelerator\_dns\_name](#output\_accelerator\_dns\_name) | DNS name to point a Route 53 alias record at. |
| <a name="output_ip_sets"></a> [ip\_sets](#output\_ip\_sets) | Static anycast IP addresses AWS assigned. |
<!-- END_TF_DOCS -->
