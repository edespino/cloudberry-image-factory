# GitHub Workflows for Cloudberry AMI Factory

GitHub Actions runs offline checks only. It never builds an AMI and holds no
AWS credentials. AMIs are built and tested locally with
`vm-images/scripts/packer-build-and-test.sh` in Synx Engineering
(`260369602265`, `us-west-2`); every image stays private to that account.

## `validate.yml` - Template Validation

**Triggers:** pushes and pull requests to `main` that touch `vm-images/`,
`tests/`, `.github/`, or `infra/` (Markdown-only changes are ignored), and
manual `workflow_dispatch`.

**Jobs:**
1. `unit-tests` — always runs the offline test suite
   (`python3 -m unittest discover -s tests`), including the repository
   policy tests, whether or not any template is selected.
2. `detect-changes` — selects targets with
   `.github/scripts/compute-build-matrix.sh`: a pull request diffs its base and
   head SHAs; a push diffs the whole push (`github.event.before` to
   `github.sha`) and validates every target when that base is unknown (new
   branch); a manual dispatch validates every target (`--all`).
3. `validate` — for each selected target, `packer init` and `packer validate`
   for its `main.pkr.hcl`.

Checkouts use `persist-credentials: false`, and the workflow has
`permissions: contents: read`.

## Target Selection

There is no hardcoded dependency map. `.github/scripts/compute-build-matrix.sh`
selects targets from the changed-file list on every run:

| Changed path | Targets selected |
|--------------|-------------------|
| `vm-images/aws/<family>/build/<os>/**` | That one target |
| `vm-images/common/scripts/X.sh` | Every target whose `main.pkr.hcl` references `X.sh` (found by `grep`, not a lookup table) |
| `vm-images/scripts/**` or `vm-images/common/tests/**` | All targets (shared harness/tests affect every build) |
| Anything else (docs, other paths) | No targets — nothing to validate |

Deleted paths are classified too: deleting a common script selects every
template that still references it, so the broken reference fails validation.

## Setup Requirements

None. The workflow needs no secrets or repository variables. A repository
policy test (`tests/test_repository_policy.py`) fails if any workflow gains AWS
credentials, secrets, OIDC token access, or a build step.

## Building AMIs

```bash
aws sso login --sso-session synx
cd vm-images/aws/<family>/build/<os>
AWS_PROFILE=synx-engineering ../../../../scripts/packer-build-and-test.sh
```

The build needs the Session Manager plugin locally and the private
`Purpose=ami-build` subnets, NAT gateway (`NatEnabled=true`) and
`ami-build-ssm` instance profile from
`infra/engineering-ami-build.cfn.yaml`. Old AMIs are retired by hand: a failed
build's AMI and snapshots are already removed by the harness, and older
`-PASSED` images are deregistered together with their snapshots.
