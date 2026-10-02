# Changelog

All notable changes to this module are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Consumers pin the commit SHA of a release tag; see [Versioning and releases](README.md#versioning-and-releases).

## [Unreleased]

Breaking release: the next version is **v2.0.0**. Read "Upgrading from v1.0.0" before bumping the pinned SHA.

### Changed (BREAKING)

- **`endpoint_groups` is now keyed `"<listener_key>/<region>"`, and the `listener_key` attribute is removed.** v1.0.0 keyed the map by region alone, which allowed at most one endpoint group per region for the whole accelerator: a TCP listener and a UDP listener could never both have an endpoint group in the same region, contradicting the documented `M` listeners × `N` regions composition. Global Accelerator's actual rule is one endpoint group per (listener, region) pair, and the key now says exactly that. Both halves are parsed from the key, so neither the listener nor the region can drift from it. A region-only key (the v1.0.0 shape) now fails the plan with a validation error rather than being reinterpreted.
- `listeners` keys may no longer contain `/`, which separates the two halves of an `endpoint_groups` key.
- `aws_globalaccelerator_endpoint_group.this` instances are now addressed by the composite key (`this["api/us-east-1"]` instead of `this["us-east-1"]`).
- The advisory `single_region_endpoint_groups` check now counts distinct regions rather than `endpoint_groups` entries, so two listeners sharing one region still count as one region. It remains advisory.

- **Every listener must now be able to serve traffic** (a per-listener `precondition` on `aws_globalaccelerator_listener.this`). v1.0.0 only required one non-zero `traffic_dial_percentage` anywhere in the map, so a listener with every group dialed to 0%, a listener whose only dialed groups hold weight-0 endpoints, or a listener with no endpoint group at all passed the plan and silently routed nowhere. Each now fails the plan naming the listener. Zero-dialed or zero-weighted standby groups beside a serving group are unaffected.

- **`endpoint_id` is now validated by shape**, not just for non-emptiness: it must be an ALB or NLB ARN (any partition), an Elastic IP allocation ID (`eipalloc-` plus 8 or 17 hex characters), or an EC2 instance ID (`i-` plus 8 or 17 hex characters), and a load balancer ARN must be in the same region as its endpoint group. v1.0.0's README claimed every input was validated, but a load balancer name, a target group ARN, a Gateway Load Balancer ARN, or a cross-region ARN passed the plan and failed only at apply. A value that previously applied successfully is a real, correctly shaped ID and still passes.

### Fixed

- Health-check settings are no longer silently inert for load balancer endpoints. The `endpoint_groups` description, README, and DESIGN now state that `health_check_*` and `threshold_count` apply only to Elastic IP and EC2 instance endpoints, and that for ALB/NLB endpoints Global Accelerator ignores them in favour of the load balancer's target-group health. Two new advisory `check` blocks (warn, never block): `health_check_settings_ignored_for_load_balancer_endpoints` (a group whose endpoints are all load balancers sets any health-check argument away from its default) and `health_check_path_requires_http_protocol` (`health_check_path` set with a `TCP` health check).

### Upgrading from v1.0.0

1. Rewrite every `endpoint_groups` entry: move `listener_key` into the map key and delete the attribute.

   ```hcl
   # v1.0.0
   endpoint_groups = {
     "us-east-1" = {
       listener_key            = "api"
       endpoint_configurations = [{ endpoint_id = module.alb_us_east_1.arn }]
     }
   }

   # v2.0.0
   endpoint_groups = {
     "api/us-east-1" = {
       endpoint_configurations = [{ endpoint_id = module.alb_us_east_1.arn }]
     }
   }
   ```

2. In the **same change**, add one `moved` block per existing endpoint group in the calling root module, so Terraform re-addresses the existing groups instead of destroying and recreating them. Without it, the plan destroys each endpoint group and creates a new one for the same listener and region, which drops traffic to that region for the duration and can fail outright, since AWS allows only one group per listener and region.

   ```hcl
   moved {
     from = module.global_accelerator.aws_globalaccelerator_endpoint_group.this["us-east-1"]
     to   = module.global_accelerator.aws_globalaccelerator_endpoint_group.this["api/us-east-1"]
   }
   ```

   (`terraform state mv` with the same two addresses is the alternative where `moved` blocks are not wanted.)

3. Plan and confirm the endpoint groups show only `has moved to` lines with no `destroy` or `create` for any `aws_globalaccelerator_endpoint_group`, then apply. The `moved` blocks can be deleted after every state that used v1.0.0 has applied them.

### Added

- `tests/wiring.tftest.hcl` now attaches a TCP listener and a UDP listener to endpoint groups in the same region (`primary/us-east-1` and `secondary/us-east-1`) and proves each resolves to its own listener ARN: the case the v1.0.0 key made unrepresentable.
- Validation tests for the per-listener serving precondition: all groups dialed to zero on one listener while another serves, a dialed group with only weight-0 endpoints, weighted endpoints only in a zero-dialed group, and a listener with no endpoint group.
- Validation tests for endpoint ID shape: a bare name, a target group ARN, a Gateway Load Balancer ARN, a truncated allocation ID, a malformed instance ID, and a load balancer ARN from another region are rejected; every supported shape (ALB, NLB, `aws-us-gov` partition, both allocation-ID and instance-ID lengths) is accepted.
- Check tests for both new health-check advisories, including a negative case (settings on an Elastic IP endpoint group do not warn).
- Validation tests rejecting a region-only (v1.0.0-shaped) key, a key with an empty listener half, and a listener key containing `/`; a check test proving two listeners in one region still trigger `single_region_endpoint_groups`.

## [1.0.0] - 2026-09-27

Initial release. One module call provisions one AWS Global Accelerator, its listeners, and its endpoint groups, pointed at ALB/NLB ARNs or Elastic IP allocation IDs a caller supplies. There is no prior version and no migration.

### Added

- `aws_globalaccelerator_accelerator.this`: `name`, `ip_address_type` (`IPV4` or `DUAL_STACK`, default `IPV4`), `enabled` (default `true`), and `flow_logs` (an optional `{ bucket_name, prefix }` pointed at a caller-owned S3 bucket; `null` by default).
- `aws_globalaccelerator_listener.this`, one per entry in the `listeners` map (keyed by a short logical name): `protocol` (default `TCP`), one or more `port_ranges`, `client_affinity` (default `NONE`).
- `aws_globalaccelerator_endpoint_group.this`, one per entry in the `endpoint_groups` map (keyed by the AWS region it is created in): `listener_key` (resolved to the listener's ARN), `traffic_dial_percentage` (default `100`), health check settings (`health_check_port`, `health_check_protocol` default `TCP`, `health_check_path`, `health_check_interval_seconds` default `30`, `threshold_count` default `3`), and `endpoint_configurations` (`endpoint_id`, `weight` default `128`, `client_ip_preservation_enabled` default `true`).
- Outputs `accelerator_arn`, `accelerator_dns_name`, `accelerator_hosted_zone_id` (for a Route 53 alias record through `aws.modules.route53`), `ip_sets` (the anycast IP addresses, sorted), and `listener_arns` (keyed the same as `listeners`).
- Plan-time validation of every input: `name` shape, `ip_address_type` enum, `flow_logs.bucket_name` and `.prefix` shape, listener protocol/client-affinity/port-range bounds, endpoint-group region-key shape, traffic-dial bounds (and at least one group non-zero across the map), health-check protocol/port/interval/threshold bounds, and endpoint weight (0-255) and non-empty ID.
- A `precondition` on the accelerator resolving the one cross-variable rule Terraform 1.7's per-variable `validation` blocks cannot express: every `endpoint_groups[*].listener_key` must name a key in `listeners`.
- Advisory `check` blocks: `flow_logs_disabled` (flow logs are off) and `single_region_endpoint_groups` (fewer than two regions are present, short of ADR 0004's two-region shape).
- Mock-provider contract tests: `tests/defaults.tftest.hcl` (secure defaults, weight and traffic-dial boundaries), `tests/validation.tftest.hcl` (every validation and the cross-variable precondition with a failing case), `tests/checks.tftest.hcl` (both advisory checks on and off), and the apply-mode `tests/wiring.tftest.hcl` (the listener-key-to-ARN lookup resolving correctly across multiple listeners, and every output).
- Examples `minimal` (one listener, one region, one endpoint), `two-region-alb` (the ADR's shape: one listener, two regional endpoint groups, each pointed at a placeholder ALB ARN shaped like `aws.modules.alb`'s outputs), and `weighted-endpoints` (a canary split across two weighted endpoints in one group).
- `docs/DESIGN.md`, `CONTRIBUTING.md`, `SECURITY.md`, `LICENSE`, the `Makefile` quality gate, pre-commit, tflint, and terraform-docs configuration, Dependabot, issue and pull request templates, and the `module-release` workflow.
- A `tests/integration/smoke` suite that applies the module for real in the caller's own account, marked in its README as requiring review before it is dispatched: Global Accelerator bills hourly from creation and teardown can be slow.

[Unreleased]: https://github.com/hatan4ik/aws.modules.global-accelerator/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/hatan4ik/aws.modules.global-accelerator/releases/tag/v1.0.0
