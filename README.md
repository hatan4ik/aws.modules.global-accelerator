# aws.modules.global-accelerator

Provisions one AWS Global Accelerator per module call: the accelerator, its listeners, and the endpoint groups that steer each listener's traffic into one or more AWS regions. This is the anycast ingress layer ADR 0004 (Separate static edge delivery, dynamic API acceleration, and conditional egress inspection) assigns to dynamic API traffic — Global Accelerator to regional public ALBs, with predictable regional steering from anycast IP addresses and ALB health endpoints. The module takes plain ARN or allocation-ID strings for its endpoints; it does not create or know about `aws.modules.alb` specifically, so it stays usable in front of anything Global Accelerator supports (an ALB, an NLB, or an Elastic IP) rather than hard-coupled to one sibling module. It is secure by default and explicit by declaration, creates nothing beyond the accelerator, its listeners, and its endpoint groups, and performs no data-source reads. Requires Terraform >= 1.7 and the AWS provider >= 6.35, < 7.

## Why this module

What you get from `name`, one listener, and one endpoint group, without setting anything else:

- One cross-reference, not nested structures. `listeners` and `endpoint_groups` are both maps — `listeners` keyed by a short logical name you choose, `endpoint_groups` keyed `"<listener_key>/<region>"` (for example `"api/us-east-1"`), since Global Accelerator allows exactly one endpoint group per listener per region and that pair is the endpoint group's identity. `M` listeners and `N` regions compose freely into up to `M×N` endpoint groups — a TCP listener and a UDP listener can each have their own group in the same region — without repeating identical endpoint groups per listener or identical listeners per region.
- A plan-time check that a typo does not become a confusing apply-time error. The listener half of every `endpoint_groups` key must name a key in `listeners`; one that does not fails the plan with every unresolved key named in one message, not Terraform's own "Invalid index" error on whichever key it reaches first.
- Every documented Global Accelerator bound enforced before you apply: port ranges 1-65535 with `from_port <= to_port`, weights 0-255, traffic-dial percentages 0-100, every listener able to serve traffic (at least one of its endpoint groups dialed above zero with at least one endpoint weighted above zero), health-check intervals restricted to the 10 or 30 seconds the API actually accepts, and a region key that looks like a real AWS region.
- Endpoints stay bring-your-own. `endpoint_id` is a plain ARN or allocation ID string; the module never creates, reads, or assumes the shape of the resource behind it, so it fits in front of an `aws.modules.alb` pair, a hand-written NLB, or a pair of Elastic IPs equally.
- Flow logs and client IP preservation default to what most callers want without being silently on: flow logs are off until you name a bucket you own (an advisory check reminds you), and `client_ip_preservation_enabled` defaults to `true` so origins see the real client IP.
- Two advisory checks that never block: one for flow logs left off, one for fewer than two regions in `endpoint_groups` (ADR 0004's shape is two regional ALBs; a single-region accelerator is valid, for example mid-rollout, but usually is not the intended end state).

## Quick start

```hcl
module "global_accelerator" {
  source = "git::https://github.com/hatan4ik/aws.modules.global-accelerator.git?ref=<commit-sha>" # v2.0.0

  name = "public-api"

  flow_logs = { bucket_name = "platform-ga-flow-logs" }

  listeners = {
    api = {
      port_ranges = [{ from_port = 443, to_port = 443 }]
    }
  }

  endpoint_groups = {
    "api/us-east-1" = {
      endpoint_configurations = [
        { endpoint_id = module.alb_us_east_1.arn },
      ]
    }
    "api/eu-west-1" = {
      endpoint_configurations = [
        { endpoint_id = module.alb_eu_west_1.arn },
      ]
    }
  }

  tags = { Environment = "prod", Owner = "platform" }
}

resource "aws_route53_record" "api" {
  zone_id = var.zone_id
  name    = "api.example.com"
  type    = "A"

  alias {
    name                   = module.global_accelerator.accelerator_dns_name
    zone_id                = module.global_accelerator.accelerator_hosted_zone_id
    evaluate_target_health = false
  }
}
```

This creates one accelerator with one TCP/443 listener and two regional endpoint groups, each pointed at an ALB from a separate composition (see [`examples/two-region-alb`](examples/two-region-alb) for the full pattern with a placeholder ARN standing in for `module.alb_us_east_1.arn`), and aliases a Route 53 record to it.

## Architecture

```text
root (one accelerator)
├── accelerator.tf      aws_globalaccelerator_accelerator.this: dynamic "attributes" for flow_logs; the cross-variable listener-key precondition
├── listeners.tf         aws_globalaccelerator_listener.this[<listener key>]: dynamic "port_range"
├── endpoint_groups.tf    aws_globalaccelerator_endpoint_group.this["<listener_key>/<region>"]: listener_arn and region from the key; dynamic "endpoint_configuration"
├── locals.tf            Tag merging, flow-log presence, endpoint-group key parsing, the unresolved-listener-key set, ip_sets flattening
├── checks.tf             flow_logs_disabled, single_region_endpoint_groups (both advisory)
└── outputs.tf            accelerator_arn/dns_name/hosted_zone_id, ip_sets, listener_arns
```

`listeners` and `endpoint_groups` are independent maps joined by the `endpoint_groups` key, not nested structures: `locals.endpoint_groups` splits each `"<listener_key>/<region>"` key once, an endpoint group's `listener_arn` is `aws_globalaccelerator_listener.this[<listener_key>].arn`, and `endpoint_group_region` is the region half, so neither can drift from what the map key says. A listener key that names no `listeners` entry is caught before Terraform ever tries that lookup: `locals.unknown_listener_keys` collects every such value and a `precondition` on the accelerator resource fails the plan naming all of them. See [docs/DESIGN.md](docs/DESIGN.md) for why this needs a precondition rather than a variable validation under Terraform 1.7.

## Usage patterns

| Example | What it shows |
| --- | --- |
| [`examples/minimal`](examples/minimal) | One listener, one region, one endpoint: every default. |
| [`examples/two-region-alb`](examples/two-region-alb) | ADR 0004's actual shape: one listener, two regional endpoint groups, each pointed at a placeholder ALB ARN shaped like `aws.modules.alb`'s output — the README shows the real composition explicitly. |
| [`examples/weighted-endpoints`](examples/weighted-endpoints) | Multiple endpoints in one group at different weights: a canary split. |

## Security model

Traffic and endpoints

- `endpoint_id` is a plain string the caller supplies (an ALB/NLB ARN or an Elastic IP allocation ID); the module never creates or inspects the resource behind it, so the security posture of the endpoint itself (its own listener protocol, WAF, security groups) is entirely the caller's, exactly as `aws.modules.acm`'s `certificate_authority_arn` and `aws.modules.route53`'s zone IDs treat their externally owned inputs.
- `client_ip_preservation_enabled` defaults to `true` so an ALB, WAF, or application-level rate limit at the origin still sees the real client IP rather than the accelerator's; set it to `false` per endpoint only when the origin cannot handle preserved IPs.
- Every listener must be able to serve traffic: at least one of its endpoint groups must have a `traffic_dial_percentage` above zero **and** at least one endpoint in that group with a `weight` above zero. A listener with no endpoint group, with every group dialed to zero, or whose dialed groups hold only weight-0 endpoints would plan and apply successfully while routing nowhere, which is far more likely to be a mistake than a deliberate state, so a per-listener `precondition` rejects it at plan time and names the listener. Zero-dialed or zero-weighted groups are fine beside a serving one (for example a standby region). To stop a listener on purpose, remove it; to stop everything, set `enabled = false`.

Observability

- `flow_logs` is `null` (off) by default; turning it on costs nothing but an S3 bucket you already own, and the `flow_logs_disabled` check reminds you on every plan while it is off.
- `single_region_endpoint_groups` warns, without blocking, when fewer than two regions are present in `endpoint_groups`. ADR 0004 specifically calls for two regional ALBs; a single region is valid (for example mid-rollout toward the second) but the check makes sure that state is a deliberate step, not an oversight.

Validation

- Every input is validated at plan time: `name` and `ip_address_type` shape, `flow_logs.bucket_name`/`.prefix` shape, listener protocol (`TCP`/`UDP`), client affinity (`NONE`/`SOURCE_IP`), port ranges (1-65535, `from_port <= to_port`), endpoint-group region-key shape, traffic-dial bounds (0-100), health-check protocol (`TCP`/`HTTP`/`HTTPS`), health-check port (1-65535), health-check interval (10 or 30 seconds — the only values Global Accelerator health checks accept), threshold count (1-10), and endpoint weight (0-255, the Global Accelerator bound) and a non-empty endpoint ID.
- The one rule that spans both `listeners` and `endpoint_groups` — the listener half of every `endpoint_groups` key must resolve — is a `precondition` on the accelerator resource, not a variable validation, because Terraform 1.7 variable validations may only reference their own variable. See [docs/DESIGN.md](docs/DESIGN.md).

Not created here

- The endpoints themselves (ALBs, NLBs, Elastic IPs), the flow-log destination bucket, and the Route 53 record that aliases `accelerator_dns_name`. Those have separate lifecycles and owners; the module consumes an existing bucket name and exposes what a Route 53 alias record needs.

## Lifecycle notes

- Listeners and endpoint groups are `for_each` over `listeners` and `endpoint_groups` respectively, keyed by the caller's own map keys (`aws_globalaccelerator_endpoint_group.this["api/us-east-1"]`). Adding a listener or an endpoint group adds exactly one resource instance; removing one removes exactly that instance. Neither resource type is taggable in the Global Accelerator API, so only the accelerator carries `tags`.
- Flow logs are added or removed by changing `flow_logs` between `null` and a value: the `dynamic "attributes"` block in `accelerator.tf` renders only when `flow_logs` is set, so there is nothing to toggle beyond the one input.
- Health-check settings and `traffic_dial_percentage` are ordinary arguments on `aws_globalaccelerator_endpoint_group`; AWS applies changes to a running endpoint group in place.
- Two `check` blocks warn without blocking: `flow_logs_disabled`, `single_region_endpoint_groups`.

## Testing

Two layers, deliberately separate:

- **Contract tests** (`tests/`, run by `make test` and by CI) use `mock_provider`: no credentials, nothing created. `tests/defaults.tftest.hcl` and `tests/checks.tftest.hcl` use `command = plan`, since everything they assert on is known by construction — resource counts, argument values that come straight from a variable, and the advisory checks. `tests/validation.tftest.hcl` exercises every variable validation and the cross-variable precondition with `expect_failures`. `tests/wiring.tftest.hcl` is the one file that uses `command = apply`: `listener_arn` and every module output are cross-resource references, unknown under a plan regardless of provider, so that file gives every listener a distinct ARN through `override_resource` and proves the listener-key-to-ARN lookup resolves to the right one.
- **Integration suite** (`tests/integration/`, run by `make integration-smoke` or the dispatch-only `integration` workflow) applies the module for real in **your** account with **your** credentials and region from the environment. **Review [tests/integration/README.md](tests/integration/README.md) before dispatching it**: Global Accelerator bills hourly from the moment the accelerator is created, whether or not it carries traffic, and teardown can take longer than most resources this series creates.

## Design principles

- Single responsibility. The module owns one accelerator, its listeners, and its endpoint groups, nothing else. Concerns are split by file: `accelerator.tf`, `listeners.tf`, `endpoint_groups.tf`, `locals.tf`, `checks.tf`.
- Open/closed. New behaviour arrives as data: another entry in `listeners` or `endpoint_groups`, another `endpoint_configurations` entry. No existing behaviour needs the module edited to add a listener, a region, or an endpoint.
- Liskov substitution. Every `endpoint_id` is treated identically regardless of what kind of resource it names (an ALB ARN, an NLB ARN, an EIP allocation ID); the module renders the same `endpoint_configuration` block for all of them.
- Interface segregation. `listeners` entries read only listener concerns (protocol, ports, affinity); `endpoint_groups` entries read only endpoint-group concerns (region, dial percentage, health check, endpoints). Neither needs to know about the other beyond the listener half of the `endpoint_groups` key.
- Dependency inversion. The module depends on identifiers (a listener key, an endpoint ARN or allocation ID, a bucket name), never on how they were produced, and performs no data-source reads.

The full rationale, including why `listeners` and `endpoint_groups` are keyed maps rather than lists and why the listener-key check is a precondition rather than a variable validation, is in [docs/DESIGN.md](docs/DESIGN.md).

## Compatibility and scope

- Terraform `>= 1.7.0, < 2.0.0`. AWS provider `>= 6.35.0, < 7.0.0`.
- `ip_address_type` accepts `IPV4` and `DUAL_STACK`; the module exposes the accelerator-level setting and does not yet add dual-stack-specific listener inputs, since ADR 0004 specifies IPv4 ALBs. Extending this is additive and non-breaking.
- Nothing in the v2 interface is scheduled to change. Additions arrive as optional inputs and outputs.

## Versioning and releases

Releases follow semantic versioning: incompatible interface changes bump the major version, new optional inputs and outputs bump the minor version, fixes bump the patch version. Every release is a signed annotated tag `vX.Y.Z`.

Pin the full commit SHA of the release tag and record the tag in a comment, so the source cannot move under you:

```hcl
module "global_accelerator" {
  source = "git::https://github.com/hatan4ik/aws.modules.global-accelerator.git?ref=<commit-sha>" # v2.0.0
}
```

The `module-release` workflow publishes an immutable GitHub release only from a GitHub-verified, signed, annotated semantic-version tag that points at the merged `main` revision; lightweight or unsigned tags are rejected before anything is published. With a GitHub-associated GPG or SSH signing key configured:

```bash
git fetch origin
git tag -s vX.Y.Z <commit> -m "vX.Y.Z"
git push origin vX.Y.Z
gh workflow run module-release.yml --ref vX.Y.Z -f release_tag=vX.Y.Z
```

Dispatch from the tag, never from `main`: the workflow verifies that the tag points at the revision it checked out.

All changes are listed in [CHANGELOG.md](CHANGELOG.md).

## Contributing

Development setup, the local quality gate, the test-first workflow, and the release process are described in [CONTRIBUTING.md](CONTRIBUTING.md). Security reports go through [SECURITY.md](SECURITY.md).

## License

Apache-2.0. See [LICENSE](LICENSE).

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
| [aws_globalaccelerator_accelerator.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/globalaccelerator_accelerator) | resource |
| [aws_globalaccelerator_endpoint_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/globalaccelerator_endpoint_group) | resource |
| [aws_globalaccelerator_listener.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/globalaccelerator_listener) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Whether the accelerator routes traffic. Setting this to false stops traffic at the static IP addresses without deleting the accelerator, its listeners, or its endpoint groups. | `bool` | `true` | no |
| <a name="input_endpoint_groups"></a> [endpoint\_groups](#input\_endpoint\_groups) | Endpoint groups keyed by the AWS region they are created in, for example "us-east-1" (the key itself is the region). listener\_key must name an entry in listeners. traffic\_dial\_percentage (default 100) is the share of listener traffic steered to this group; at least one group across the map must be non-zero, since an accelerator whose groups are all dialed to zero serves no traffic. health\_check\_port defaults to the listener's port when left null. endpoint\_configurations lists the endpoints in the group: endpoint\_id is an ALB/NLB ARN or an Elastic IP allocation ID, weight (default 128) shares traffic within the group, and client\_ip\_preservation\_enabled (default true) preserves the client's source IP to the endpoint where the endpoint type supports it. At least one entry is required, and every group needs at least one endpoint. | <pre>map(object({<br/>    listener_key                  = string<br/>    traffic_dial_percentage       = optional(number, 100)<br/>    health_check_port             = optional(number)<br/>    health_check_protocol         = optional(string, "TCP")<br/>    health_check_path             = optional(string)<br/>    health_check_interval_seconds = optional(number, 30)<br/>    threshold_count               = optional(number, 3)<br/>    endpoint_configurations = list(object({<br/>      endpoint_id                    = string<br/>      weight                         = optional(number, 128)<br/>      client_ip_preservation_enabled = optional(bool, true)<br/>    }))<br/>  }))</pre> | n/a | yes |
| <a name="input_flow_logs"></a> [flow\_logs](#input\_flow\_logs) | Flow log destination. bucket\_name is an existing S3 bucket the caller owns and creates (the same ownership boundary as aws.modules.alb's access\_logs and aws.modules.cloudfront's logging); prefix is an optional key prefix within it. null (the default) disables flow logs; a check block advises turning them on. | <pre>object({<br/>    bucket_name = string<br/>    prefix      = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_ip_address_type"></a> [ip\_address\_type](#input\_ip\_address\_type) | IP address type of the accelerator's static anycast IP addresses: IPV4 or DUAL\_STACK. | `string` | `"IPV4"` | no |
| <a name="input_listeners"></a> [listeners](#input\_listeners) | Listeners keyed by a short logical name, referenced by endpoint\_groups[*].listener\_key. protocol defaults to TCP; port\_ranges is one or more inclusive port ranges the listener accepts; client\_affinity defaults to NONE (SOURCE\_IP pins a client to one endpoint for the accelerator's stickiness window). At least one entry is required. | <pre>map(object({<br/>    protocol = optional(string, "TCP")<br/>    port_ranges = list(object({<br/>      from_port = number<br/>      to_port   = number<br/>    }))<br/>    client_affinity = optional(string, "NONE")<br/>  }))</pre> | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name of the accelerator, unique within the account and Region. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the accelerator. Listeners and endpoint groups are not taggable resources in the Global Accelerator API. The module adds a Name tag equal to name unless you set one; caller tags are never overridden. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_accelerator_arn"></a> [accelerator\_arn](#output\_accelerator\_arn) | ARN of the accelerator. |
| <a name="output_accelerator_dns_name"></a> [accelerator\_dns\_name](#output\_accelerator\_dns\_name) | DNS name AWS assigns to the accelerator's static anycast IP addresses. |
| <a name="output_accelerator_hosted_zone_id"></a> [accelerator\_hosted\_zone\_id](#output\_accelerator\_hosted\_zone\_id) | Route 53 hosted zone ID to use when aliasing a Route 53 record to accelerator\_dns\_name (see aws.modules.route53). |
| <a name="output_ip_sets"></a> [ip\_sets](#output\_ip\_sets) | Static anycast IP addresses AWS assigned to the accelerator, sorted. Useful for allow-listing at an origin firewall in front of the endpoints, if one exists. |
| <a name="output_listener_arns"></a> [listener\_arns](#output\_listener\_arns) | ARN of each listener, keyed the same as the listeners input. |
<!-- END_TF_DOCS -->
