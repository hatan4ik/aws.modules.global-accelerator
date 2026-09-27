# Changelog

All notable changes to this module are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Consumers pin the commit SHA of a release tag; see [Versioning and releases](README.md#versioning-and-releases).

## [Unreleased]

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
