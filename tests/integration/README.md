# Integration suites

**Review before dispatching.** The suite in this directory applies the module
for real in **your** AWS account and destroys everything afterwards, like
every other module in this series — but Global Accelerator is not like the
other resources this series creates:

- **It bills hourly from the moment `CreateAccelerator` succeeds**, whether
  or not it carries any traffic, until it is deleted. There is no free tier
  and no per-second proration below the hour.
- **Teardown is slow.** An accelerator must leave `IN_PROGRESS`/`DEPLOYED`
  state and be disabled before AWS accepts `DeleteAccelerator`; AWS's own
  guidance is to expect this to take several minutes, longer than almost
  everything else this series tears down in a `terraform test` run. The
  `smoke` suite handles the disable-then-delete sequence through the
  provider's own resource lifecycle, but the run's wall-clock time — and the
  hourly charge — is measured in minutes, not seconds.
- **It needs a real endpoint to be meaningfully tested.** An endpoint group
  is not fully exercised by a placeholder ARN the way a certificate request
  or a bucket policy can be; `./setup` creates one real (and separately,
  trivially cheap) Elastic IP so the endpoint group has something genuine to
  attach to and health-check.

None of this makes the suite unsafe to run — it applies for real, asserts
against the real API, and destroys everything at the end of the file, exactly
like every sibling module's `smoke` suite — but unlike those suites, an
accidental or repeated run here has a cost and a duration worth pausing on
first. Do not wire this suite into anything that runs unattended (a schedule,
every push, every merge); the `integration` workflow that can run it is
`workflow_dispatch`-only for exactly this reason, and this README exists so a
human reviews the suite before typing the command that runs it.

Nothing here is tied to an account, region, or landing zone. Credentials and
the region come from the environment, and the accelerator's one endpoint is a
disposable Elastic IP the suite creates and releases itself — no fixture
references a real ALB, NLB, or production IP.

| Suite | What it proves | Needs | Typical time |
| --- | --- | --- | --- |
| `smoke.tftest.hcl` | One accelerator, one listener, and one endpoint group with a real endpoint are accepted by the API; the documented outputs (`accelerator_arn`, `accelerator_dns_name`, `accelerator_hosted_zone_id`, `ip_sets`, `listener_arns`) resolve to real values; the defaults (IPV4, enabled, TCP listener, `NONE` affinity, fully dialed, TCP health check) survive the real API. | credentials, region | several minutes, dominated by accelerator provisioning and teardown |

## Run it in your account

```bash
export AWS_PROFILE=<your profile>   # or AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN
export AWS_REGION=<region>
make integration-smoke              # terraform init -test-directory=tests/integration && terraform test -test-directory=tests/integration -filter=tests/integration/smoke.tftest.hcl
```

The credentials need the permissions in
[`iam/integration-permissions-policy.json`](iam/integration-permissions-policy.json)
(replace `<ACCOUNT_ID>`): the Global Accelerator actions to create, describe,
tag, and delete the accelerator, its listener, and its endpoint group (the
Global Accelerator API does not support resource-level ARN scoping on its
create actions, so those are `Resource: "*"`), and the EC2 Elastic IP actions
`./setup` needs for its one fixture. Nothing else is touched.

`terraform test` runs `tests/` only by default, so this suite never runs in
the credential-free quality pipeline.

## Run it from GitHub Actions (owner lane)

The `integration` workflow (`.github/workflows/integration.yml`) is
dispatch-only and assumes a role through GitHub OIDC. It reads everything
account-specific from the protected `integration` environment of the
repository, so the code stays universal:

| Environment variable | Meaning |
| --- | --- |
| `AWS_INTEGRATION_ROLE_ARN` | Role the workflow assumes. Trust policy: [`iam/github-oidc-trust-policy.json`](iam/github-oidc-trust-policy.json) with `<OWNER>/<REPO>` set to this repository; permissions: the policy above. |
| `AWS_INTEGRATION_REGION` | Region the accelerator's fixture and resources are created in. |

Dispatch with `gh workflow run integration.yml -f suite=smoke`, and only after
reading the cost and duration notes above. Protect the environment with
required reviewers so a run cannot be started from a pull request by anyone
with write access.

For this repository's owner the environment is prepared with the sandbox
region; the role ARN is added once the role exists in the sandbox account,
created through the platform's delivery IAM module with the trust policy
above and the subject
`repo:hatan4ik/aws.modules.global-accelerator:environment:integration`.
