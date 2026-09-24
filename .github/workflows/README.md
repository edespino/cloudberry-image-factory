# GitHub Workflows for Cloudberry AMI Factory

GitHub Actions runs offline checks only. It never builds an AMI and holds no
AWS credentials. AMIs are built and tested locally with
`vm-images/scripts/packer-build-and-test.sh` in Synx Engineering
(`260369602265`, `us-west-2`); every image stays private to that account.

## `validate.yml` - Template Validation

**Triggers:** pushes and pull requests to `main` that touch `vm-images/`,
`tests/`, or `.github/` (Markdown-only changes are ignored), and manual
`workflow_dispatch`.

**Jobs:**
1. `detect-changes` — diffs the pull request's base and head SHAs (or
   `HEAD~1..HEAD` on push) and passes the changed files to
   `.github/scripts/compute-build-matrix.sh`.
2. `validate` — for each selected target: runs the offline test suite
   (`python3 -m unittest discover -s tests`), then `packer init` and
   `packer validate` for the target's `main.pkr.hcl`.

## Target Selection

There is no hardcoded dependency map. `.github/scripts/compute-build-matrix.sh`
selects targets from the changed-file list on every run:

| Changed path | Targets selected |
|--------------|-------------------|
| `vm-images/aws/<family>/build/<os>/**` | That one target |
| `vm-images/common/scripts/X.sh` | Every target whose `main.pkr.hcl` references `X.sh` (found by `grep`, not a lookup table) |
| `vm-images/scripts/**` or `vm-images/common/tests/**` | All targets (shared harness/tests affect every build) |
| Anything else (docs, other paths) | No targets — nothing to validate |

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

The build needs the `Purpose=ami-build` subnets from
`infra/engineering-ami-build.cfn.yaml`. Old AMIs are retired by hand: a failed
build's AMI and snapshots are already removed by the harness, and older
`-PASSED` images are deregistered together with their snapshots.
