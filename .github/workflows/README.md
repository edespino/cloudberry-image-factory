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
- **Scheduled:** Monthly on the 1st at 3 AM UTC
- **Manual:** `workflow_dispatch` with dry-run support

**Features:**
- **Retention Policy**: Configurable retention period (default: 90 days)
- **Dry Run Mode**: Preview deletions without actual cleanup
- **Snapshot Cleanup**: Removes associated EBS snapshots
- **Orphan Detection**: Identifies orphaned snapshots

## Dependency Matrix

The workflows understand the following build dependencies:

| Common Script | Affected Builds |
|---------------|-----------------|
| `cbadmin_configure_environment.sh` | All builds |
| `system_add_goss.sh` | All builds |
| `system_add_awscli.sh` | Rocky builds only |
| `system_add_golang.sh` | rocky8, rocky9, ubuntu22 |
| `system_disable_selinux.sh` | Rocky builds only |
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

The AWS credentials need permissions for:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "iam:PassRole",
        "iam:CreateInstanceProfile",
        "iam:DeleteInstanceProfile",
        "iam:GetRole",
        "iam:GetInstanceProfile",
        "iam:DeleteRole",
        "iam:CreateRole",
        "iam:PutRolePolicy",
        "iam:AddRoleToInstanceProfile",
        "iam:RemoveRoleFromInstanceProfile",
        "iam:DeleteRolePolicy",
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    }
  ]
}
```

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

1. **Discovery** → Find AMIs older than retention period
2. **Safety Checks** → Verify AMI ownership and naming patterns
3. **Deregistration** → Remove old AMIs from AWS
4. **Snapshot Cleanup** → Delete associated EBS snapshots
5. **Reporting** → Document cleanup actions

## Cost Management

### Build Optimization
- **Parallel Limits**: Max 3 concurrent builds to control costs
- **Smart Rebuilds**: Only rebuild AMIs affected by changes
- **Resource Cleanup**: Automatic cleanup of temporary resources
- **Build Timeouts**: Prevent runaway builds from incurring charges

### AMI Management
- **Automated Cleanup**: Monthly removal of old AMIs
- **Retention Policy**: Configurable retention periods
- **Snapshot Management**: Cleanup of associated storage costs
- **Build Tagging**: Cost allocation through resource tagging

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
retention_days:
  default: '90'  # Change default retention period
```

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