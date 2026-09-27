# Security policy

## Supported versions

| Version | Supported |
| --- | --- |
| 1.x | Yes. Security fixes and functional fixes on the latest minor release. |
| Unreleased `main` | Not supported for production use. |

## Reporting a vulnerability

Use GitHub private vulnerability reporting on this repository: open the Security tab and choose "Report a vulnerability". Do not open a public issue, pull request, or discussion for a security problem.

Include the module version or commit SHA, the inputs that reproduce the problem, the resulting plan, and the impact you see. Redact ARNs and account IDs.

## What counts

- A module default that weakens security: flow logs written to a bucket the module does not confirm the caller supplied, `client_ip_preservation_enabled` defaulting to a value that would hide the real client IP from an origin's own security controls, or a health check default that would let an unhealthy endpoint keep receiving traffic.
- A validation bypass: an input the module claims to reject at plan time but that reaches the provider (an out-of-range weight or traffic-dial percentage, a malformed region key, a `listener_key` that names no listener).
- A dependency problem in the release pipeline that could publish unverified code.

Findings in the endpoints a caller points the module at (an ALB, NLB, or Elastic IP the caller chose to make an accelerator endpoint) or in AWS Global Accelerator itself are out of scope here; report the latter to AWS.

## Response

We acknowledge a report within 5 business days and keep you informed while we confirm, fix, and release. A fix ships as a patch release with a `CHANGELOG.md` entry that credits the reporter unless they ask otherwise. Please give us a reasonable window before disclosing publicly.

## Security design

The module is secure by default: flow logs off until a caller supplies a bucket they own, with an advisory check while they are off; every endpoint, port range, weight, and traffic-dial input validated at plan time against the bounds Global Accelerator itself enforces; the one cross-variable rule Terraform 1.7 cannot express as a variable validation (`endpoint_groups[*].listener_key` must name a real listener) enforced as a precondition instead of left to fail obscurely at apply; no data sources; no IAM resources. Every claim is enforced by a validation, a precondition, or a `check` block with a `terraform test` case behind it. The full description is in [docs/DESIGN.md](docs/DESIGN.md).
