# Contributing

Thank you for improving `aws.modules.global-accelerator`. This guide covers the toolchain, the local quality gate, how features are tested and where they belong, commit and pull request conventions, and how releases are cut.

## Development setup

The module targets Terraform `>= 1.7.0, < 2.0.0` and is developed against 1.7.5, the version the consuming platform pins. Install the toolchain:

| Tool | Purpose | Install |
| --- | --- | --- |
| [tfenv](https://github.com/tfutils/tfenv) | Pin the Terraform version | `tfenv install 1.7.5 && tfenv use 1.7.5` |
| [tflint](https://github.com/terraform-linters/tflint) | Lint with the Terraform and AWS rulesets configured in `.tflint.hcl` | `brew install tflint && tflint --init` |
| [terraform-docs](https://terraform-docs.io) v0.20.0 | Generate the inputs and outputs tables in every README. Pinned to the version bundled by the CI docs action; newer releases change table formatting and fail the drift check (`make docs` refuses other versions). | Download the v0.20.0 binary from the [releases page](https://github.com/terraform-docs/terraform-docs/releases/tag/v0.20.0) |
| [checkov](https://www.checkov.io) | Static security policy | `pip install checkov` |
| [trivy](https://trivy.dev) | Misconfiguration scanning | `brew install trivy` |
| [pre-commit](https://pre-commit.com) | Run the gate on every commit | `pip install pre-commit && pre-commit install` |

Clone, initialise without a backend, and run the gate once to confirm the setup:

```sh
terraform init -backend=false -input=false
make check
```

## Integration suites

`tests/integration/` holds credential-driven suites that apply the module for real and destroy everything afterwards. They are never part of `make check` or the quality pipeline.

**Review before dispatching.** Global Accelerator starts billing hourly the moment the accelerator is created, regardless of whether it carries traffic, and teardown can take longer than most resources this series creates. Read `tests/integration/README.md` in full, including what the fixture creates and what it costs, before running:

```bash
export AWS_PROFILE=<profile> AWS_REGION=<region>
make integration-smoke
```

Add a suite when a feature's correctness depends on the AWS API rather than on rendering (for example a new health-check shape or a dual-stack accelerator). Keep every value derived from the environment or from disposable fixtures the suite creates, and never reference a real listener, endpoint, or account. A suite that needs fixtures keeps them in `tests/integration/setup`, which the policy scans exclude.

## The local gate

`make check` is the default target and the same gate CI runs. It stops at the first failing target and must pass before you open a pull request.

| Target | What it runs |
| --- | --- |
| `make fmt` | `terraform fmt -check -recursive -diff` from the repository root. `make fmt-fix` rewrites the files instead. |
| `make validate` | `make init` (`terraform init -backend=false`) followed by `terraform validate` in the root and every example directory. |
| `make lint` | `tflint --init` and then `tflint` in every directory with the root `.tflint.hcl`: documented and typed variables, documented outputs, snake_case naming, no unused declarations, pinned required versions and providers. |
| `make test` | `terraform test` in the root. No credentials are needed. |
| `make lock` | Refresh the committed root `.terraform.lock.hcl` with hashes for linux and macOS on amd64 and arm64 after changing the provider constraint. |
| `make docs` | `terraform-docs -c .terraform-docs.yml` in every directory, regenerating the tables between the `BEGIN_TF_DOCS` and `END_TF_DOCS` markers. Run it after touching any variable or output. |
| `make docs-check` | The same in `--output-check` mode: fails when a README is out of date. This is the variant `make check` and CI run. |
| `make security` | `checkov -d . --framework terraform`, and `trivy config --severity HIGH,CRITICAL` when trivy is on the PATH. A skip needs an inline `checkov:skip=` comment with a reason on the resource it concerns; there are none today. |
| `make check` | `fmt`, `validate`, `lint`, `test`, `docs-check`, `security`, in that order. |

## Test-first workflow

Every behaviour in this module is pinned by a test before it is implemented. Write the failing `run` block first, then the code, then run `make test`.

- Tests live in `tests/*.tftest.hcl`, one file per concern: `defaults` (secure defaults and documented boundaries), `checks` (every advisory check on and off), `validation` (every variable validation and the cross-variable precondition), and `wiring` (apply-mode: the listener-key-to-ARN lookup and every output, which are unknown under `command = plan`). Each file starts with `mock_provider "aws" {}` and a `variables` block holding a valid baseline; each `run` overrides only what it exercises.
- Use `command = plan` wherever the assertion does not depend on a cross-resource reference. Nothing here talks to AWS, so these tests run in seconds and in CI without credentials.
- `command = apply` is reserved for `tests/wiring.tftest.hcl`, in its own file because `run` blocks in one file share state and an apply leaks into later plan runs. Under `command = apply` with `mock_provider`, computed strings the module does not set explicitly (a listener's or the accelerator's own ARN, `dns_name`, `hosted_zone_id`, `ip_sets`) are random filler unless given an explicit value; `override_resource` blocks at the top of that file give every listener instance a distinct ARN, so an endpoint group that resolved to the wrong listener fails an assertion instead of accidentally passing because two listeners shared one mocked value.
- Validations and the cross-variable precondition are tested with `expect_failures`. Point it at the object that carries the check: `[var.listeners]` for a variable validation, `[aws_globalaccelerator_accelerator.this]` for the listener-key precondition, `[check.flow_logs_disabled]` for a `check` block. A run with `expect_failures` passes only if exactly those objects fail; add a positive run alongside so the happy path is covered too.
- Assertions must not depend on unknown values. Under `command = plan`, cross-resource references (`aws_globalaccelerator_listener.this[...].arn`, and every module output) and any Optional+Computed provider argument left `null` in config (`health_check_port`, which AWS defaults from the listener's port when unset) are unknown. Assert on what the module knows by construction instead: `for_each` keys, argument values that come straight from a variable, resource counts, and the advisory checks. `port_range` and `endpoint_configuration` are set-typed nested blocks — they have no addressable index, so match an element with a `for` expression (`anytrue([for pr in ... : pr.from_port == 443])`), never `[0]`, and compare unordered collections with `toset(...)` rather than a positional list.
- `flow_logs` defaults to `null`, which is itself the state the `flow_logs_disabled` check warns about, and the module's own default `endpoint_groups` shape a caller supplies could easily be one region, which `single_region_endpoint_groups` warns about. Files that are not testing the checks (`defaults`, `validation`, `wiring`) declare `flow_logs` and a two-region `endpoint_groups` map in their baseline `variables` block specifically to stay clear of both; `tests/checks.tftest.hcl` is the one file that exercises the true defaults.
- `||` and `&&` do not short-circuit in Terraform 1.7. Both operands are always evaluated, so `var.flow_logs == null || var.flow_logs.prefix == null` fails when `flow_logs` is null (accessing `.prefix` on null). Guard with a conditional instead: `var.flow_logs == null ? true : (var.flow_logs.prefix == null ? true : ...)`. This applies to validations, preconditions, and test assertions alike.
- Keep assertion `error_message` text a statement of the guaranteed behaviour. It becomes the documentation of the contract when a test fails.

## Where to add a feature

The module has no submodules; concerns are split by file, and each file has one reason to change.

| Concern | Lives in |
| --- | --- |
| An accelerator-level argument (a new `attributes` field, a new top-level setting) | `variables.tf` with a description, type, and validation; `accelerator.tf` to render it; a test in `tests/defaults.tftest.hcl` and an `expect_failures` run in `tests/validation.tftest.hcl`. |
| A listener argument | `variables.tf` (the `listeners` object type) and `listeners.tf`. |
| An endpoint-group or endpoint-configuration argument | `variables.tf` (the `endpoint_groups` object type) and `endpoint_groups.tf`. |
| Mode resolution, tag merging, the cross-variable listener-key check | `locals.tf`, with the behaviour pinned in the file matching what it feeds: `tests/wiring.tftest.hcl` for anything that needs a real ARN, `tests/validation.tftest.hcl` for the precondition. |
| Cross-input rules | A `precondition` in `accelerator.tf` when it must block the plan, or `checks.tf` when the situation is valid but usually unintended. |
| Outputs | `outputs.tf`; every output has a description, and one that needs a resolved ARN is asserted in `tests/wiring.tftest.hcl`. |

Rules that apply everywhere: no data sources (derive from inputs and the provider's region), every variable has a description, a type, and a validation where a wrong value would otherwise fail at apply time, every output has a description, defaults are the secure choice, and an optional feature stays off until declared.

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/). The scope is the file or concern the change touches.

```text
feat(endpoint_groups): accept a port_override per endpoint
fix(locals): sort ip_sets before flattening
docs: explain the two-region composition with aws.modules.alb
test(wiring): cover a third listener key
feat!: rename listener_key to listener
```

Append `!` after the type or scope for a breaking change and add a `BREAKING CHANGE:` footer explaining what consumers must do. Breaking changes ship only in a major release with an entry in an upgrade guide.

## Pull request checklist

- [ ] `make check` passes locally.
- [ ] New behaviour has a test; changed validations have both a passing and an `expect_failures` run.
- [ ] Variables and outputs have descriptions; `make docs` regenerated the README tables.
- [ ] `CHANGELOG.md` has an entry under `## [Unreleased]` in the right category.
- [ ] Breaking changes carry `!`, a `BREAKING CHANGE:` footer, and an upgrade guide.
- [ ] Examples still initialise and validate; a new feature worth showing has an example.
- [ ] No data sources, no hard-coded account, region, or partition, no new defaults that weaken security.

## Release process

Releases are cut by maintainers.

1. Move the `## [Unreleased]` entries in `CHANGELOG.md` under a new `## [X.Y.Z] - YYYY-MM-DD` heading, add its compare link, and merge that change to `main`.
2. Create a signed annotated tag on the merge commit. The signing key must be registered with GitHub so the tag shows as Verified:

   ```sh
   git tag -s vX.Y.Z -m "aws.modules.global-accelerator vX.Y.Z"
   git push origin vX.Y.Z
   ```

3. Dispatch the `module-release` workflow (`.github/workflows/module-release.yml`) from the tag with `release_tag = vX.Y.Z`: `gh workflow run module-release.yml --ref vX.Y.Z -f release_tag=vX.Y.Z`. It verifies the signed tag, formatting, validation, tests, and generated docs, then publishes the GitHub release. Never dispatch it from `main`: the workflow checks that the tag points at the revision it checked out, and a maintenance release of an older line is cut from that line's commit.
4. Announce the release with the commit SHA. Consumers pin that SHA, not the tag:

   ```hcl
   source = "git::https://github.com/hatan4ik/aws.modules.global-accelerator.git?ref=<commit-sha>" # vX.Y.Z
   ```

Tags are never moved or deleted once published. A bad release is followed by a new patch release.
