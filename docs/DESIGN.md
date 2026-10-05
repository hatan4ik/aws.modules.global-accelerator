# Design: aws.modules.global-accelerator v1

Status: accepted 2026-09-27; revised for v2.0.0 on 2026-10-01 (endpoint
groups keyed by `"<listener_key>/<region>"`, see "Why keyed maps, not lists").
There is no live consumer yet.

## Purpose

`aws.modules.global-accelerator` provisions **one** AWS Global Accelerator per
module call: the accelerator itself, its listeners, and the endpoint groups
that steer each listener's traffic into one or more AWS regions.

This is the anycast ingress layer ADR 0004 (Separate static edge delivery,
dynamic API acceleration, and conditional egress inspection) assigns to
dynamic API traffic: "Dynamic API requests use Global Accelerator to
two regional public ALBs... Anycast API ingress and ALB health endpoints
provide predictable regional steering." The module creates the accelerator,
its listeners, and its endpoint groups; it does **not** create, know about, or
import `aws.modules.alb`. Every endpoint is a plain string the caller
supplies — an ALB or NLB ARN, an Elastic IP allocation ID, or an EC2 instance
ID, each checked by shape at plan time — the same
"external dependency is an identifier the caller passes in" pattern as every
bring-your-own-resource input in this series (compare `aws.modules.acm`'s
`certificate_authority_arn`, or `aws.modules.route53`'s zone IDs). This keeps
the module usable in front of anything Global Accelerator supports, not
hard-coupled to one sibling module: a caller composes it with `aws.modules.alb`
outputs today and with a different origin tomorrow without the module
changing.

The module deliberately does **not** create the endpoints themselves (ALBs,
NLBs, Elastic IPs), the flow-log destination bucket, or a Route 53 record
aliasing the accelerator's DNS name. Those have separate lifecycles and
owners; the module consumes an existing bucket name and exposes
`accelerator_dns_name` and `accelerator_hosted_zone_id` for a caller to alias
with `aws.modules.route53`.

## Interface

- `name`, `ip_address_type` (default `IPV4`), `enabled` (default `true`).
- `flow_logs`: optional `{ bucket_name, prefix }`. `null` by default; a
  `check` block advises turning it on. The caller owns and creates the
  bucket, exactly as `aws.modules.alb`'s `access_logs` and
  `aws.modules.cloudfront`'s `logging` do.
- `listeners`: a map keyed by a short logical name (`primary`, `api`, `vpn`,
  ...), each with `protocol` (default `TCP`), one or more `port_ranges`, and
  `client_affinity` (default `NONE`). At least one entry required.
- `endpoint_groups`: a map keyed `"<listener_key>/<region>"` — the part
  before the slash names the `listeners` entry the group attaches to, the
  part after it is the AWS region it is created in (validated to look like
  one). Each entry carries a `traffic_dial_percentage` (default `100`),
  health check settings, and a list of `endpoint_configurations` (an
  `endpoint_id`, a `weight`, and `client_ip_preservation_enabled`). At least
  one entry required, and every listener must have at least one group with a
  non-zero `traffic_dial_percentage` holding at least one non-zero-weight
  endpoint.
- `tags`, applied to the accelerator. Listeners and endpoint groups are not
  taggable resources in the Global Accelerator API.

## Why keyed maps, not lists

Both `listeners` and `endpoint_groups` are maps, not lists, for the same
reason `aws.modules.vpc`'s subnet tiers and `aws.modules.acm`'s
`route53_zones` are maps: a list index is not a stable identity. Two
consequences follow directly from that choice:

- **`endpoint_groups` is keyed `"<listener_key>/<region>"` because that pair
  is the identity.** Global Accelerator allows exactly one endpoint group per
  listener per region — not one per region for the whole accelerator. Making
  the pair the map key means a caller cannot declare two groups for the same
  listener and region by accident (the map literal itself would collide),
  while two different listeners can each have a group in the same region.
  Both halves are split from the key once in `locals.endpoint_groups`, so
  `listener_arn` and `endpoint_group_region` in `endpoint_groups.tf` cannot
  drift from what the key says. Listener keys may not contain `/`, so the
  split is unambiguous.

  v1.0.0 keyed this map by region alone, with `listener_key` as a field. That
  shape allowed at most one endpoint group per region for the whole
  accelerator, so two listeners could never both steer into the same region —
  contradicting the `M×N` composition below. v2.0.0 replaced it; see
  CHANGELOG.md for the upgrade.
- **`listeners` is keyed by a caller-chosen logical name, and the listener
  half of each `endpoint_groups` key references that name**, rather than
  either structure nesting the other. A listener commonly fans out to every
  region (the ADR's shape: one listener, two regional endpoint groups), so
  nesting endpoint groups under listeners would force a caller to repeat
  identical endpoint groups per listener, or nesting listeners under regions
  would force identical listeners per region. A flat cross-reference by key
  lets `M` listeners and `N` regions compose freely as `M` listener resources
  and up to `M×N` endpoint groups, with each endpoint group naming exactly the
  one listener it belongs to. The `tests/wiring.tftest.hcl` fixture proves
  it with a TCP and a UDP listener that both have a group in `us-east-1`.

The reference by key is a plain string, not a resource reference, so it is
knowable at plan time — but it is also therefore not validated by Terraform's
own type system the way a direct reference would be. A caller can type a
listener key that names no listener. Section "Cross-variable validation"
below explains how the module still catches that at plan time.

## Cross-variable validation

Terraform 1.7 variable validation blocks may only reference the variable they
are attached to (cross-variable references in `validation` blocks arrived in
a later Terraform minor version, and this module's floor is 1.7). Every rule
that needs only one variable's own data — region-key shape, port range
bounds, weight and traffic-dial bounds, at least one non-zero dial — is
therefore a `validation` block on that variable in `variables.tf`.

The one rule that inherently crosses variables — the listener half of every
`endpoint_groups` key must name a key in `listeners` — cannot be
expressed that way. It is instead a `precondition` on
`aws_globalaccelerator_accelerator.this` in `accelerator.tf`, evaluated from
`local.unknown_listener_keys` in `locals.tf`. Attaching it to the accelerator
resource rather than to the endpoint group it concerns follows
`aws.modules.acm`'s precedent (`certificate.tf`'s preconditions cover rules
that belong to `validation.tf`'s records too): one precondition collects and
names every unresolved listener key in one message, rather than failing on
whichever `for_each` key Terraform's own "Invalid index" error happens to
reach first.

The same applies to the per-listener serving rule: every listener must have at
least one endpoint group dialed above zero that contains at least one endpoint
with a non-zero weight. The per-variable `validation` on `endpoint_groups`
only sees that variable, so it can only require one non-zero dial somewhere in
the whole map — it cannot tell that a second listener's groups are all dialed
to zero, or that a fully dialed group's endpoints all carry weight 0. The
per-listener rule is a `precondition` on `aws_globalaccelerator_listener.this`
(evaluated per instance, so the error names the listener), fed by
`local.serving_listener_keys`. It is a hard precondition rather than an
advisory `check` because a listener that routes nowhere is never a useful
applied state: a listener being drained is removed, and a whole accelerator
being stopped uses `enabled = false`; zero-dialed standby groups beside a
serving one remain valid.

## What to build (resources)

- `aws_globalaccelerator_accelerator.this` — one per call, with a
  `dynamic "attributes"` block for flow logs, rendered only when `flow_logs`
  is set so the API default (`flow_logs_enabled = false`) applies otherwise.
- `aws_globalaccelerator_listener.this` — one per `listeners` entry, with a
  `dynamic "port_range"` block per `port_ranges` entry.
- `aws_globalaccelerator_endpoint_group.this` — one per `endpoint_groups`
  entry, its `listener_arn` resolved from the key's listener half through
  `aws_globalaccelerator_listener.this[each.value.listener_key].arn` and its
  region from the key's region half, with a
  `dynamic "endpoint_configuration"` block per `endpoint_configurations`
  entry.

## Health checks: when they apply

Endpoint-group health-check settings (`health_check_port`,
`health_check_protocol`, `health_check_path`, `health_check_interval_seconds`,
`threshold_count`) only apply to Elastic IP and EC2 instance endpoints. For ALB
and NLB endpoints, Global Accelerator ignores them and uses the load
balancer's own target-group health. Since ALBs are this module's primary use
case (ADR 0004), silently accepting the settings would mislead: a caller could
tune a health check that never runs. The module keeps the inputs (they are
real for EIP and instance endpoints), documents the rule in the variable
description and README, and adds two advisory checks rather than validations,
because neither state is harmful — it is just inert:
`health_check_settings_ignored_for_load_balancer_endpoints` (a group of only
load balancer ARNs with any health-check argument off its default) and
`health_check_path_requires_http_protocol` (a path with a TCP health check).

## Security defaults

- Flow logs are off until a caller supplies a bucket they own; the
  `flow_logs_disabled` check warns on every plan while they are.
- `client_ip_preservation_enabled` defaults to `true`, matching AWS's own
  console default: origins see the real client IP rather than the
  accelerator's, which most WAF and rate-limiting rules at the origin expect.
- No data sources, no IAM resources, no default egress: the module only
  creates the accelerator, its listeners, and its endpoint groups.
- Every input is validated at plan time: region-key shape, port range and
  health-check bounds, the 0-255 weight bound and 0-100 traffic-dial bound
  Global Accelerator itself enforces, and the cross-variable listener-key
  check above.

## Testing strategy

- Contract tests use `mock_provider` with `command = plan`; no credentials.
  `tests/defaults.tftest.hcl` covers secure defaults and the documented
  weight/traffic-dial boundaries (0 and 255, a zero-dialed group beside a
  non-zero one); `tests/validation.tftest.hcl` covers every validation and the
  cross-variable precondition with a failing case; `tests/checks.tftest.hcl`
  covers every advisory check on and off.
- `listener_arn` and every module output are cross-resource references,
  unknown under `command = plan` regardless of provider. They are proven
  under `command = apply` in `tests/wiring.tftest.hcl`, isolated in its own
  file because `run` blocks in one file share state and an apply leaks into
  later plan runs. Two listeners each get a distinct ARN through
  `override_resource`, so an endpoint group that resolved to the wrong
  listener fails an assertion instead of accidentally passing because both
  listeners shared one mocked value.
- The `tests/integration/smoke` suite applies the module for real in the
  caller's own account. Global Accelerator bills hourly from creation and
  teardown can be slow, so it is not wired into anything that runs it
  automatically; `tests/integration/README.md` says so explicitly and the
  `integration` workflow stays dispatch-only.

## Quotas

The `M×N` composition is bounded by Global Accelerator's default service
quotas: 10 listeners per accelerator, 10 port ranges per listener, and 10
endpoints per endpoint group, plus the fixed API rule of one endpoint group
per listener per region (which the `"<listener_key>/<region>"` key enforces by
construction). The first three are account-level defaults that can differ per
account, so the module documents them (README, "Compatibility and scope")
rather than validating them: hard-coding 10 would reject a caller whose quota
has been raised.

## Compatibility

- Terraform `>= 1.7.0, < 2.0.0`. AWS provider `>= 6.35.0, < 7.0.0`.
- `ip_address_type = "DUAL_STACK"` is accepted and validated by name; the
  module does not yet expose an input for the dual-stack-specific listener
  behaviour AWS added afterward, since ADR 0004 specifies IPv4 ALBs. A
  dual-stack caller today gets the accelerator-level setting and nothing
  more; extending this is an additive, non-breaking follow-up.

## Migration

v1.0.0 to v2.0.0 is a breaking change: `endpoint_groups` keys move from
`"<region>"` to `"<listener_key>/<region>"` (the `listener_key` attribute is
removed), and the `ip_sets` output is replaced by `ip_addresses`. Existing
endpoint groups must be re-addressed with `moved` blocks in the calling root
module, or Terraform plans a destroy and recreate of every group. The full
procedure, with an example `moved` block, is in CHANGELOG.md under
"Upgrading from v1.0.0".
