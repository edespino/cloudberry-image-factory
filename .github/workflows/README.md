# GitHub Workflows for Cloudberry AMI Factory

This directory contains GitHub Actions workflows that automate the building, testing, and management of Cloudberry Database AMIs.

## Workflows Overview

### 1. `ami-build-on-change.yml` - Automated Change-Driven Builds

**Trigger:** Automatically runs when changes are pushed to scripts or build configurations.

**Features:**
- **Smart Change Detection**: Analyzes git diff to determine which AMIs need rebuilding
- **Dependency-Aware**: Only rebuilds AMIs affected by changed scripts
- **Parallel Execution**: Builds multiple AMIs concurrently (max 3 at once)
- **PR Comments**: Adds build results to pull request comments
- **Automatic Cleanup**: Cleans up temporary AWS resources

**Change Detection Logic:**
```
Common Script Change → Rebuild all dependent AMIs
OS-Specific Script → Rebuild all AMIs in that OS family
Build-Specific File → Rebuild only that specific AMI
Documentation Change → No builds triggered
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
- Build targets (all, specific OS, individual AMIs)
- AWS region selection
- Public AMI setting
- Force rebuild option

### 3. `ami-cleanup-old.yml` - AMI Lifecycle Management

**Triggers:**
- **Scheduled:** Monthly on the 1st at 3 AM UTC (always in dry-run mode)
- **Manual:** `workflow_dispatch` with full parameter control

**Features:**
- **Count-Based Retention**: Keep N newest AMIs per configuration (default: 3)
- **Per-Configuration Logic**: Separate retention for rocky8, rocky9, rocky10, etc.
- **Dry Run Mode**: Preview deletions without actual cleanup (default: enabled)
- **Snapshot Cleanup**: Automatically removes associated EBS snapshots
- **No Age Limit**: AMIs never deleted based on age alone (ensures availability)
- **Orphan Detection**: Identifies orphaned snapshots for manual review

**Retention Policy:**
With `retention_count: 3` (default), the workflow keeps the 3 newest AMIs for each configuration:
- rocky8: Keep 3 newest
- rocky9: Keep 3 newest
- rocky10: Keep 3 newest
- etc.

This ensures you always have N working AMIs per OS, regardless of their age.

## Dependency Matrix

The workflows understand the following build dependencies:

| Common Script | Affected Builds |
|---------------|-----------------|
| `dbadmin_configure_environment.sh` | rocky8, rocky9, rocky10 |
| `system_add_goss.sh` | rocky8, rocky9, rocky10 |
| `system_add_awscli.sh` | rocky8, rocky9, rocky10 |
| `system_add_golang.sh` | rocky8, rocky9, rocky10 |
| `system_disable_selinux.sh` | rocky8, rocky9, rocky10 |
| ... | (see workflow file for complete matrix) |

## Setup Requirements

### GitHub Repository Secrets

Add these secrets to your GitHub repository:

```
AWS_ACCESS_KEY_ID     # AWS access key for AMI building
AWS_SECRET_ACCESS_KEY # AWS secret key for AMI building
```

### Optional GitHub Variables

```
AWS_REGION           # Default AWS region (defaults to us-west-2)
```

### AWS IAM Permissions

Least-privilege policy for the CI user (e.g. `github-actions-packer-user`).
It covers the Packer amazon-ebs builder, the build-and-test script (test
instance lifecycle, AMI rename/publish), and the cleanup workflows. No IAM
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
        "ec2:ModifyImageAttribute",
        "ec2:ModifyInstanceAttribute",
        "ec2:ModifySnapshotAttribute",
        "ec2:RegisterImage",
        "ec2:RunInstances",
        "ec2:StopInstances",
        "ec2:TerminateInstances"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": { "aws:RequestedRegion": "us-west-2" }
      }
    },
    {
      "Sid": "ImageBlockPublicAccessToggle",
      "Effect": "Allow",
      "Action": [
        "ec2:GetImageBlockPublicAccessState",
        "ec2:DisableImageBlockPublicAccess",
        "ec2:EnableImageBlockPublicAccess"
      ],
      "Resource": "*"
    }
  ]
}
```

Notes:
- The `aws:RequestedRegion` condition pins mutating access to us-west-2.
  Remove it only if builds in other regions are actually needed
  (`ami-build-manual.yml` exposes an `aws_region` input).
- `ImageBlockPublicAccessToggle` is an account-level grant, needed only
  because the build script publishes public AMIs. If public AMIs are ever
  dropped, remove this statement.

## Build Process Flow

### Automated Builds (on push/PR)

1. **Change Detection** → Analyze modified files
2. **Matrix Generation** → Create build matrix based on dependencies
3. **Parallel Validation** → Validate Packer templates
4. **Parallel Building** → Build affected AMIs (max 3 concurrent)
5. **Testing** → Run Goss tests on each AMI
6. **Publishing** → Make successful AMIs public
7. **Cleanup** → Remove temporary resources
8. **Reporting** → Comment on PRs with results

### Manual Builds

1. **Input Processing** → Parse manual workflow inputs
2. **Matrix Setup** → Generate build matrix from selections
3. **Enhanced Building** → Build with extended timeouts and tagging
4. **Artifact Collection** → Store build results for 90 days
5. **Notification** → Generate detailed summary reports

### Cleanup Process

1. **Discovery** → Find all Cloudberry AMIs (cloudberry-packer-build-*)
2. **Grouping** → Group AMIs by configuration (rocky8, rocky9, rocky10, etc.)
3. **Analysis** → For each configuration, identify oldest AMIs beyond retention count
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
- **Predictable Costs**: Maximum of N × 6 configurations (e.g., 3 × 6 = 18 AMIs max)
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

### Modifying Build Matrix
Edit the dependency mapping in `ami-build-on-change.yml`:

```yaml
declare -A COMMON_SCRIPT_DEPS=(
  ["your-script.sh"]="build1,build2,build3"
)
```

### Adding New AMI Builds
1. Create new build directory under `vm-images/aws/cloudberry/build/`
2. Add to dependency matrix in workflows
3. Update this documentation

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
3. Review public AMI sharing policies
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