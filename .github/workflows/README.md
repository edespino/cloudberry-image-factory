# GitHub Workflows for Cloudberry AMI Factory

This directory contains GitHub Actions workflows that automate the building, testing, and management of AMIs across all families (`cloudberry`, `synxdb-cloud`, `agentic`) in this repository.

## Workflows Overview

### 1. `ami-build-on-change.yml` - Automated Change-Driven Builds

**Trigger:** Automatically runs when changes are pushed to scripts or build configurations.

**Features:**
- **Smart Change Detection**: Analyzes git diff to determine which AMIs need rebuilding
- **Dependency-Aware**: Only rebuilds AMIs affected by changed scripts
- **Parallel Execution**: Builds multiple AMIs concurrently (max 3 at once)
- **PR Comments**: Adds build results to pull request comments
- **Automatic Cleanup**: Cleans up temporary AWS resources

**Change Detection Logic** (implemented by `.github/scripts/compute-build-matrix.sh`):
```
vm-images/common/scripts/X.sh change  → Rebuild every target whose main.pkr.hcl references X.sh
vm-images/scripts/** or vm-images/common/tests/** change → Rebuild all targets
vm-images/aws/<family>/build/<os>/** change → Rebuild only that target
Documentation-only change → No builds triggered
```

### 2. `ami-build-manual.yml` - Manual and Scheduled Builds

**Triggers:**
- **Manual:** `workflow_dispatch` with customizable options
- **Scheduled:** Weekly builds every Sunday at 2 AM UTC

**Features:**
- **Flexible Targeting**: Choose specific AMIs or build all
- **Extended Timeouts**: 90 minutes per build for complex operations
- **Enhanced Tagging**: Adds build metadata to AMIs
- **Artifact Retention**: Keeps build artifacts for 90 days

**Manual Options:**
- `build_targets`: `all` or a comma-separated `family/os` list (e.g. `cloudberry/rocky9,agentic/ubuntu26`)

### 3. `ami-cleanup-old.yml` - AMI Lifecycle Management

**Triggers:**
- **Scheduled:** Monthly on the 1st at 3 AM UTC (always in dry-run mode)
- **Manual:** `workflow_dispatch` with full parameter control

**Features:**
- **Per-Family Discovery**: AMIs are found per family using the `<family>-packer-*` naming pattern (`cloudberry-packer-*`, `synxdb-cloud-packer-*`, `agentic-packer-*`)
- **Count-Based Retention**: Keep N newest AMIs per family/os configuration (default: 3)
- **Dry Run Mode**: Preview deletions without actual cleanup (default: enabled)
- **Snapshot Cleanup**: Automatically removes associated EBS snapshots
- **No Age Limit**: AMIs never deleted based on age alone (ensures availability)
- **Orphan Detection**: Identifies orphaned snapshots for manual review

**Retention Policy:**
With `retention_count: 3` (default), the workflow keeps the 3 newest AMIs for
each family/os configuration, e.g.:
- cloudberry/rocky9: Keep 3 newest
- cloudberry/rocky10: Keep 3 newest
- synxdb-cloud/ubuntu24: Keep 3 newest
- agentic/ubuntu26: Keep 3 newest

This ensures you always have N working AMIs per target, regardless of their age.

## Dynamic Build Matrix

There is no hardcoded dependency map. `.github/scripts/compute-build-matrix.sh`
computes the build matrix from the changed-file list on every run:

| Changed path | Targets selected |
|--------------|-------------------|
| `vm-images/aws/<family>/build/<os>/**` | That one target |
| `vm-images/common/scripts/X.sh` | Every target whose `main.pkr.hcl` references `X.sh` (found by `grep`, not a lookup table) |
| `vm-images/scripts/**` or `vm-images/common/tests/**` | All targets (shared harness/tests affect every build) |
| Anything else (docs, other paths) | No targets — no build triggered |

A target directory containing a `MANUAL_DISPATCH_ONLY` marker file is never
selected by any of these rules (currently `agentic/ubuntu26-gpu`, whose
builder is a `g6.xlarge` GPU instance chained from the newest
`agentic/ubuntu26` `-PASSED` AMI).

Manual dispatch (`ami-build-manual.yml`) does not use the script above; it
accepts `all` or a comma-separated `family/os` list (e.g.
`cloudberry/rocky9,agentic/ubuntu26`) and builds the matrix directly from that
input. Marker-file targets are included in `all` and can be named explicitly
(`agentic/ubuntu26-gpu`); manual dispatch is the only CI path that builds them.

## Setup Requirements

### GitHub Repository Secrets

Add these secrets to your GitHub repository:

```
AWS_ACCESS_KEY_ID     # AWS access key for AMI building
AWS_SECRET_ACCESS_KEY # AWS secret key for AMI building
```

The build region is fixed to `us-west-2`; workflows do not expose a
cross-region override.

### AWS IAM Permissions

Least-privilege policy for the CI user (e.g. `github-actions-packer-user`).
It covers the Packer amazon-ebs builder, the build-and-test script (test
instance lifecycle and private AMI result tagging), and the cleanup workflows. No IAM
actions are required — the Packer templates do not use instance profiles.
`sts:GetCallerIdentity` needs no permission.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PackerBuildAndTest",
      "Effect": "Allow",
      "Action": [
        "ec2:AttachVolume",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:CreateImage",
        "ec2:CreateKeyPair",
        "ec2:CreateSecurityGroup",
        "ec2:CreateSnapshot",
        "ec2:CreateTags",
        "ec2:CreateVolume",
        "ec2:DeleteKeyPair",
        "ec2:DeleteSecurityGroup",
        "ec2:DeleteSnapshot",
        "ec2:DeleteVolume",
        "ec2:DeregisterImage",
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeImageAttribute",
        "ec2:DescribeImages",
        "ec2:DescribeInstanceStatus",
        "ec2:DescribeInstances",
        "ec2:DescribeKeyPairs",
        "ec2:DescribeRegions",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSnapshots",
        "ec2:DescribeSubnets",
        "ec2:DescribeTags",
        "ec2:DescribeVolumes",
        "ec2:DescribeVpcs",
        "ec2:DetachVolume",
        "ec2:ModifyInstanceAttribute",
        "ec2:RegisterImage",
        "ec2:RunInstances",
        "ec2:StopInstances",
        "ec2:TerminateInstances"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": { "aws:RequestedRegion": "us-west-2" }
      }
    }
  ]
}
```

Notes:
- The `aws:RequestedRegion` condition pins mutating access to us-west-2.
  The build and test script deliberately does not support other regions.

## Build Process Flow

### Automated Builds (on push/PR)

1. **Change Detection** → Analyze modified files
2. **Matrix Generation** → Create build matrix based on dependencies
3. **Parallel Validation** → Validate Packer templates
4. **Parallel Building** → Build affected AMIs (max 3 concurrent)
5. **Testing** → Run Goss tests on each AMI
6. **Result Tagging** → Keep successful AMIs private and tag PASSED
7. **Cleanup** → Remove temporary resources
8. **Reporting** → Comment on PRs with results

### Manual Builds

1. **Input Processing** → Parse manual workflow inputs
2. **Matrix Setup** → Generate build matrix from selections
3. **Enhanced Building** → Build with extended timeouts and tagging
4. **Artifact Collection** → Store build results for 90 days
5. **Notification** → Generate detailed summary reports

### Cleanup Process

1. **Discovery** → For each family, find its AMIs (`<family>-packer-*`)
2. **Grouping** → Group each family's AMIs by os (rocky9, rocky10, etc.)
3. **Analysis** → For each family/os, identify oldest AMIs beyond retention count
4. **Safety Checks** → Verify AMI ownership and naming patterns
5. **Deregistration** → Remove old AMIs from AWS (if not dry-run)
6. **Snapshot Cleanup** → Delete associated EBS snapshots
7. **Orphan Detection** → Identify any orphaned snapshots for manual review
8. **Reporting** → Document cleanup actions with detailed summary

## Cost Management

### Build Optimization
- **Parallel Limits**: Max 3 concurrent builds to control costs
- **Smart Rebuilds**: Only rebuild AMIs affected by changes
- **Resource Cleanup**: Automatic cleanup of temporary resources
- **Build Timeouts**: Prevent runaway builds from incurring charges

### AMI Management
- **Automated Cleanup**: Monthly dry-run reports (manual trigger for actual deletion)
- **Count-Based Retention**: Keep N newest AMIs per configuration (default: 3)
- **Predictable Costs**: Maximum of N × 7 targets (e.g., 3 × 7 = 21 AMIs max)
- **Snapshot Management**: Automatic cleanup of associated storage costs
- **Build Tagging**: Cost allocation through resource tagging
- **No Age-Based Deletion**: AMIs kept regardless of age (ensures availability)

## Monitoring and Troubleshooting

### Build Status
- **GitHub Actions UI**: View build progress and logs
- **PR Comments**: Automatic status updates on pull requests
- **Job Summaries**: Detailed reports in GitHub Actions
- **Artifact Storage**: Build manifests and test results

### Common Issues

**Build Failures:**
- Check AWS credential permissions
- Verify Packer template syntax
- Review Goss test failures
- Check AWS service limits

**Resource Cleanup Issues:**
- Security groups may have dependencies
- Key pairs might be in use by running instances
- Check AWS CloudTrail for detailed error information

**Change Detection Problems:**
- Verify file path patterns in workflow
- Check dependency matrix accuracy
- Review git diff output in workflow logs

## Customization

### Modifying Build Matrix Behavior
There is no dependency map to edit — the matrix is derived from
`.github/scripts/compute-build-matrix.sh`. To change what a script change
affects, change which templates reference that script, or edit the
rules in `compute-build-matrix.sh` itself.

### Adding New AMI Builds
1. Create a new build directory under `vm-images/aws/<family>/build/<os>/`
   (new family) or `vm-images/aws/<existing-family>/build/<os>/` (new OS)
2. No workflow edits needed — the dynamic matrix picks it up automatically
3. Update this documentation and the root `README.md`/`CLAUDE.md` if the
   target set changes

### Changing Retention Policies
Modify default values in `ami-cleanup-old.yml`:

```yaml
retention_count:
  default: '3'  # Keep 3 newest AMIs per configuration
```

**Examples:**
- `retention_count: 1` - Keep only the latest AMI per OS (minimal storage)
- `retention_count: 3` - Keep 3 newest per OS (recommended for rollback capability)
- `retention_count: 5` - Keep 5 newest per OS (extended rollback history)

**Testing:** Use `retention_count: 1` with `dry_run: true` to test the cleanup logic without deleting anything.

## Best Practices

### Development Workflow
1. Create feature branch for AMI changes
2. Test changes in PR (automated builds)
3. Review build results in PR comments
4. Merge after successful builds

### Production Management
1. Use manual builds for releases
2. Tag AMIs with version information
3. Monitor cleanup processes
4. Regular review of AWS costs

### Security Considerations
1. Rotate AWS credentials regularly
2. Use least privilege IAM policies
3. Verify private-only AMI sharing controls
4. Monitor AWS CloudTrail for access

## Support

For issues with the workflows:
1. Check GitHub Actions logs
2. Review AWS CloudTrail events
3. Verify IAM permissions
4. Check AWS service status

For AMI build issues:
1. Review Packer validation errors
2. Check Goss test failures
3. Verify script dependencies
4. Test build scripts locally
