# Integration fixtures

A disposable prerequisite for the smoke suite in the parent directory: one
unattached Elastic IP to serve as the accelerator's single real endpoint, and
the region the provider under test resolved to (used as the `endpoint_groups`
key). `terraform test` evaluates this module before the module under test and
destroys it afterwards. It is not a deployable pattern and is excluded from
policy scans (see `.checkov.yml` and `trivy.yaml` at the repository root).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.35.0, < 7.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.35.0, < 7.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_eip.endpoint](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix used to tag the disposable Elastic IP fixture. | `string` | `"ga-it"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the Elastic IP fixture in addition to the identifying defaults. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_allocation_id"></a> [allocation\_id](#output\_allocation\_id) | Allocation ID of the disposable Elastic IP: the endpoint\_id under test. |
| <a name="output_region"></a> [region](#output\_region) | Region the fixture (and the provider under test) resolved to, used as the endpoint\_groups key. |
| <a name="output_tags"></a> [tags](#output\_tags) | Identifying tags applied to the fixture and, by the caller, to the accelerator under test. |
<!-- END_TF_DOCS -->
