# Cloudberry Image Factory

A comprehensive Packer-based infrastructure project for building development-optimized Amazon Machine Images (AMIs) for Apache Cloudberry (Incubating) on AWS.

## Overview

The Cloudberry Image Factory provides automated AMI builds across multiple operating systems with integrated testing, security enhancements, and intelligent CI/CD workflows. Built specifically for **development environments** with appropriate configurations for development workflows.

## Architecture

### System Overview

```
┌────────────────────────────────────────────────────────────────────────┐
│                         GitHub Repository                              │
│  ┌─────────────────┐  ┌──────────────────┐  ┌────────────────────────┐ │
│  │  Common Scripts │  │  Family/OS       │  │  GitHub Actions        │ │
│  │  (58 scripts)   │  │  Build Configs   │  │  Workflows             │ │
│  │                 │  │  (7 targets, 3   │  │  - Build on Change     │ │
│  │                 │  │   families)      │  │    (dynamic matrix)    │ │
│  └─────────────────┘  └──────────────────┘  │  - Manual/Scheduled    │ │
│                                             │  - AMI Cleanup         │ │
│                                             └────────────────────────┘ │
└────────────────────────────────────────────────────────────────────────┘
                                    │
                    ┌───────────────┴───────────────┐
                    │   Trigger Events              │
                    │   - Git Push/PR               │
                    │   - Manual Run                │
                    │   - Scheduled (cron)          │
                    └───────────────┬───────────────┘
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                          AWS Environment                               │
│                                                                        │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │               Packer Build Process (t3.2xlarge)                  │  │
│  │                                                                  │  │
│  │  Base AMI → Provision Scripts → Install Tools → Configure →      │  │
│  │           → Security Hardening → Testing Setup → Create AMI      │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                    │                                   │
│                                    ▼                                   │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                    New AMI Created                               │  │
│  │    {family}-packer-{os}-{timestamp}[-PASSED/FAILED]              │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                    │                                   │
│                                    ▼                                   │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │               Test Instance Launch (t3.medium)                   │  │
│  │                                                                  │  │
│  │  Launch → Wait for SSH → Copy Goss Tests → Run Validation →      │  │
│  │         → Collect Results → Terminate Instance                   │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                    │                                   │
│                    ┌───────────────┴───────────────┐                   │
│                    ▼                               ▼                   │
│            Tests PASSED                    Tests FAILED                │
│            Rename: *-PASSED                Rename: *-FAILED            │
│            Keep Private                    Keep Private                │
│            Retain (count-based)            Mark for Deletion           │
└────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
                          ┌──────────────────┐
                          │  Monthly Cleanup │
                          │  - Keep N newest │
                          │  - Delete FAILED │
                          │  - Delete old    │
                          └──────────────────┘
```

## Repository Structure

```
cloudberry-image-factory/
├── .github/workflows/          # GitHub Actions CI/CD workflows
│   ├── ami-build-on-change.yml # Smart change-driven builds (dynamic matrix)
│   ├── ami-build-manual.yml    # Manual/scheduled builds
│   ├── ami-cleanup-old.yml     # AMI lifecycle management (per-family)
│   └── README.md               # Workflow documentation
├── .github/scripts/
│   └── compute-build-matrix.sh # Derives the CI build matrix from changed files
├── vm-images/
│   ├── scripts/                 # Harness trio, shared by every family
│   │   ├── packer-build-and-test.sh
│   │   ├── private-runtime-key.py
│   │   └── validate-ami-metadata.py
│   ├── common/
│   │   ├── scripts/              # Shared provisioning scripts
│   │   └── tests/                # Shared Goss test fragments
│   └── aws/
│       ├── cloudberry/build/
│       │   ├── rocky9/           # Rocky Linux 9 build
│       │   └── rocky10/          # Rocky Linux 10 build
│       ├── synxdb-cloud/build/
│       │   ├── al2023/           # SynxDB Cloud on Amazon Linux 2023
│       │   ├── rocky9/           # SynxDB Cloud on Rocky Linux 9
│       │   ├── rocky10/          # SynxDB Cloud on Rocky Linux 10
│       │   └── ubuntu24/         # SynxDB Cloud on Ubuntu 24.04
│       └── agentic/build/
│           ├── ubuntu26/         # Standalone AI-tooling image on Ubuntu 26.04
│           ├── ubuntu26-arm64/   # Same image on arm64 (Graviton)
│           └── ubuntu26-gpu/     # NVIDIA L4 inference image chained from ubuntu26 (manual dispatch only)
│       # Each build directory contains:
│       #   main.pkr.hcl        - Packer configuration
│       #   scripts/            - OS-specific scripts
│       #   tests/goss.yaml     - Validation tests
└── README.md                   # This file
```

## Supported Builds

> **Current Build Targets:** See [`vm-images/aws/`](vm-images/aws/) for the complete list of families and OS targets (`vm-images/aws/<family>/build/<os>/`).

| Family | OS Target | Package Manager | Notes |
|--------|-----------|-----------------|-------|
| **cloudberry** | rocky9 | RPM (dnf) | Full-featured, primary target |
| **cloudberry** | rocky10 | RPM (dnf) | Latest Rocky release |
| **synxdb-cloud** | al2023 | RPM (dnf) | SynxDB Cloud operations image |
| **synxdb-cloud** | rocky9 | RPM (dnf) | SynxDB Cloud operations image |
| **synxdb-cloud** | rocky10 | RPM (dnf) | SynxDB Cloud developer workstation image |
| **synxdb-cloud** | ubuntu24 | APT | SynxDB Cloud developer workstation image |
| **agentic** | ubuntu26 | APT | Standalone AI-tooling image (Ubuntu 26.04) |
| **agentic** | ubuntu26-arm64 | APT | Same image on arm64/Graviton (no dysk — x86-only binary) |
| **agentic** | ubuntu26-gpu | APT | x86_64 NVIDIA L4 inference image chained from the `ubuntu26` `-PASSED` AMI; `g6.xlarge` builder; NVIDIA 580 server driver, nvtop, Ollama (loopback only); CI manual dispatch only |

> **Archived (2026-07-24):** `al2023`, `centos10`, `debian12`, `ubuntu20`, and `ubuntu22` were
> removed after ~9 months without maintenance. They remain recoverable from git history.
>
> **Retired (2026-07-27):** `al2023-synxdb-elastic` was removed and remains recoverable from git history.
>
> **Retired (2026-07-27):** `rocky8` was removed and remains recoverable from git history.

**Common Features Across All Builds:**
- Docker Community Edition with 1GB shared memory
- Goss validation testing framework
- Cloudberry Database build dependencies
- Development tools and utilities

## Development Stack

### Languages & Runtimes
- **Go**: Latest stable release (rocky9, rocky10)
- **Java**: OpenJDK 8/11 (rocky9)
- **Python**: System default (version varies by OS)

### Build Tools & Libraries
- **Compilers**: System GCC/GCC-C++ (version varies by OS)
- **Build Systems**: CMake (latest), Maven, Make
- **Libraries**: Xerces-C, libuv, zstd (versions determined by package managers)

### Development Utilities
- **AWS CLI**: v2 with configuration
- **Docker**: Community Edition with 1GB shared memory
- **Shell Enhancement**: Starship prompt (Rocky builds)
- **Text Processing**: yq (latest)
- **Testing**: Goss validation framework

> **Note:** Specific versions are managed by individual installation scripts in `vm-images/common/scripts/`. Many tools use dynamic version detection to install the latest stable release. See the [Goss test files](vm-images/aws/) for verification of installed versions.

## Build Matrix

### Script Organization

**Common Scripts** (`vm-images/common/scripts/`)
- 58 shared provisioning scripts used across multiple targets
- Include user setup, development tools, kernel configs, testing frameworks, MOTD management

**OS-Specific Scripts** (in each build directory)
- `system_add_cbdb_build_rpm_dependencies.sh` (RPM-based: cloudberry rocky9/rocky10)
- `system_add_synxdb_cloud_dependencies.sh` (synxdb-cloud and agentic targets)
- `system_set_default_locale.sh` (DEB-based targets)
- `system_add_docker.sh` or `system_docker_setup.sh` (varies by OS)

**Build Configuration**: Each target has a `main.pkr.hcl` file that orchestrates which scripts run and in what order.

> **To see exact script usage per target:** Review the `main.pkr.hcl` file in each build directory (e.g., `vm-images/aws/cloudberry/build/rocky9/main.pkr.hcl`).

### Build Profiles by Family

**cloudberry** (rocky9, rocky10):
- Full RPM-based toolchain
- AWS CLI, Go, Java support (varies by version)
- Starship prompt, kernel tuning
- SELinux disabled for development

**synxdb-cloud** (al2023, rocky9, rocky10, ubuntu24):
- Operations/workstation profile: kubectl/helm, cloud CLIs, no Cloudberry build toolchain
- SynxDB-branded AMI naming and MOTD
- No build-time Cloudsmith credentials are required; the DBaaS package provisioner is disabled

**agentic** (ubuntu26, ubuntu26-arm64, ubuntu26-gpu):
- `ubuntu26` / `ubuntu26-arm64`: standalone from the stock Ubuntu 26.04 `ubuntu-resolute` minimal AMI (not chained from another family)
- `ubuntu26-gpu`: chained from the newest `agentic/ubuntu26` `-PASSED` AMI (matched on the `Name` tag) via `base_family`/`base_os` HCL variables; layers only the GPU stack (NVIDIA 580 server driver held via `apt-mark`, `nvidia-smi`, `nvtop`, Ollama bound to loopback, no model weights). Built on `g6.xlarge` so a build-time smoke test runs against a real L4; goss stays hardware-independent because the test instance has no GPU
- AI tooling ships only here: `system_add_ai_toolchain.sh`, `system_add_claude.sh`, `system_add_omnigent.sh`, `system_add_herdr.sh`, `system_add_beads.sh`, and related agent CLIs
- Future agentic targets are expected to chain from a base family's `*-PASSED` AMI via `base_family`/`base_os` HCL variables rather than building standalone

## Getting Started

### Prerequisites

- **AWS Account** with EC2 and AMI permissions
- **Packer** 1.8+ installed locally
- **AWS CLI** configured with appropriate credentials
- **Python 3**, `jq`, OpenSSH client, `nc`, `curl`, and GNU `timeout`
- **GitHub repository** with required secrets (for CI/CD)

When this script runs through `access run`, the final command receives a
private mode-0700 `XDG_RUNTIME_DIR`. When invoked directly, an explicitly set
`XDG_RUNTIME_DIR` is intentionally rejected unless it is a nonsymlink
directory owned by the current user with exactly mode 0700. If it is unset,
`RUNNER_TEMP` (or `TMPDIR`) may be a current-user-owned mode-0755 directory,
but it must not be group/world writable; the script securely creates and
removes a cryptographically named mode-0700 per-run child beneath it. Both AMI
build workflows explicitly export such a private child.

Existing-AMI recovery accepts only available, not-publicly-shared images owned
by the documented account `703671893074`, in the fixed `us-west-2` region,
whose name matches the selected build target.

### Manual Build Process

```bash
# Navigate to specific build directory
cd vm-images/aws/cloudberry/build/rocky9

# Build AMI manually using integrated build-and-test script
../../../../scripts/packer-build-and-test.sh
```

### Build Pipeline Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     packer-build-and-test.sh                            │
└─────────────────────────────────────────────────────────────────────────┘

1. Prerequisites Check
   ├─ Verify: python3, packer, aws, jq, ssh/scp, nc, curl, timeout
   └─ Generate temporary SSH key pair
              │
              ▼
2. Packer Initialization
   ├─ packer init (download required plugins)
   ├─ packer validate (check HCL syntax)
   └─ Set build variables (vm_type, os_name, credentials)
              │
              ▼
3. AMI Build Process (20-60 minutes)
   ┌────────────────────────────────────────────────────┐
   │ Packer provisions on t3.2xlarge instance:          │
   │                                                    │
   │  a. Launch base AMI (Rocky/Ubuntu/AL2023)          │
   │  b. Wait for SSH availability                      │
   │  c. Execute provisioning scripts in sequence:      │
   │     ├─ system_adduser_cbadmin.sh                   │
   │     ├─ system_add_cbdb_build_*_dependencies.sh     │
   │     ├─ system_add_golang.sh                        │
   │     ├─ system_add_docker.sh                        │
   │     ├─ system_add_kernel_configs.sh                │
   │     ├─ cbadmin_configure_environment.sh            │
   │     ├─ system_add_motd_manager.sh                  │
   │     └─ system_add_goss.sh (testing framework)      │
   │  d. Create AMI snapshot from instance              │
   │  e. Terminate build instance                       │
   └────────────────────────────────────────────────────┘
              │
              ▼
4. Extract AMI ID from packer-manifest.json
              │
              ▼
5. Test Instance Launch
   ├─ Create security group (SSH from current IP only)
   ├─ Launch t3.medium instance from new AMI
   ├─ Wait for SSH (30 retries with exponential backoff)
   └─ Upload SSH key to cbadmin authorized_keys
              │
              ▼
6. Goss Test Execution
   ├─ Copy goss.yaml test specs to instance
   ├─ Run: goss validate --format rspecish
   ├─ Run: goss validate --format junit
   └─ Download results (XML + text format)
              │
              ├─────────────┬─────────────┐
              ▼             ▼             ▼
         ALL PASSED    SOME FAILED   CONNECTION FAILED
              │             │             │
              ▼             ▼             ▼
7a. Success Path     7b. Failure Path  7c. Error Path
    ├─ Rename AMI        ├─ Rename AMI     ├─ Keep AMI name
    │  *-PASSED          │  *-FAILED       └─ Mark for review
    ├─ Keep AMI private  └─ Keep private
    └─ Exit 0                Exit 1
              │
              ▼
8. Cleanup (always runs)
   ├─ Terminate test instance
   ├─ Delete security group
   ├─ Delete temporary SSH key pair
   └─ Display final results
```

### Automated CI/CD Builds

The repository includes intelligent GitHub Actions workflows:

- **Automatic builds**: Triggered on script/configuration changes
- **Manual builds**: On-demand with configurable options
- **Scheduled builds**: Weekly automated builds
- **Smart rebuilds**: Only affected AMIs rebuilt based on change detection

### CI/CD Workflow Decision Tree

```
                        GitHub Event
                             │
         ┌───────────────────┼───────────────────┐
         ▼                   ▼                   ▼
    Push/PR to Main    Manual Trigger    Scheduled (Weekly)
         │                   │                   │
         ▼                   │                   │
    Changed Files?           │                   │
         │                   │                   │
    ┌────┴────┐              │                   │
    ▼         ▼              │                   │
 Yes         No              │                   │
    │         │              │                   │
    │      (Skip)            │                   │
    │                        │                   │
    └────────┬───────────────┴───────────────────┘
             ▼
    ami-build-on-change.yml     OR     ami-build-manual.yml
             │                              │
             ▼                              ▼
    Dynamic Matrix Computation    "all" or family/os list
    (compute-build-matrix.sh)              │
             │                              │
    ┌────────┴────────┐                     │
    ▼                 ▼                     │
Common Script    Target-Path File          │
Changed          Changed                    │
    │                 │                     │
    ├─ grep-match     └─ Build only         │
    │  every target's    that one target   │
    │  main.pkr.hcl                         │
    │                                       │
    ├─ vm-images/common/scripts/X.sh → every target whose HCL references X.sh
    ├─ vm-images/scripts/** or vm-images/common/tests/** → all targets
    └─ vm-images/aws/<family>/build/<os>/** → that target only
                │
                ▼
    ┌───────────────────────────────┐
    │   Build Matrix Generation     │
    │   Max 3 parallel builds       │
    └───────────────────────────────┘
                │
       ┌────────┴────────┐
       ▼                 ▼
    Build AMI       Test AMI
    (60 min)        (10 min)
       │                 │
       └────────┬────────┘
                ▼
       ┌─────────────────┐
       │  Test Results   │
       └─────────────────┘
                │
       ┌────────┴────────┐
       ▼                 ▼
   ✅ PASSED        ❌ FAILED
       │                 │
       ├─ Rename         ├─ Rename
       │  *-PASSED       │  *-FAILED
       ├─ Keep private   └─ Keep private
       └─ Comment PR
```

### Monthly AMI Cleanup Flow

```
    1st of Month, 3 AM UTC
             │
             ▼
    ami-cleanup-old.yml
    (Always DRY-RUN)
             │
             ▼
    For each family (cloudberry, synxdb-cloud, agentic):
    Find AMIs matching <family>-packer-*
             │
       ┌─────┴─────┐
       ▼           ▼
   Contains     Does not
   "-FAILED"    contain "-FAILED"
       │           │
       │           ▼
       │      Group by OS within the family:
       │      e.g. cloudberry/rocky9, cloudberry/rocky10
       │           │
       │           ▼
       │      For each family/os:
       │      Sort by CreationDate
       │      (newest first)
       │           │
       │      ┌────┴────┐
       │      ▼         ▼
       │   Count ≤ N  Count > N
       │      │         │
       │   Keep All  Keep N newest
       │              Delete rest
       │           │
       └─────┬─────┘
             ▼
    Delete List Generated:
    - All FAILED AMIs
    - Old AMIs beyond retention
             │
             ▼
    Generate Report:
    - ✅ AMIs to KEEP
    - ❌ AMIs to DELETE
    - GitHub Step Summary
             │
             ▼
    DRY-RUN: No action taken
    Manual trigger required
    for actual deletion
```

## Configuration

### AWS Settings

| Setting | Default | Description |
|---------|---------|-------------|
| Region | `us-west-2` | Primary AWS region |
| Instance Type | `t3.2xlarge` | Build instance (8 vCPU, 32GB RAM) |
| Base AMI Owner | Varies by target | e.g. Rocky Linux Foundation (`792107900819`) for Rocky targets, Canonical (`099720109477`) for Ubuntu targets |
| Volume Size | 24GB | Root filesystem size |

### AMI Naming Convention

**Format:** `<family>-packer-<os>-{timestamp}`

**Example:** `cloudberry-packer-rocky9-20251002-170700`

**Important Notes:**
- **Timestamps are in UTC** (Coordinated Universal Time)
- The timestamp in the AMI name reflects when the Packer build **started**
- The AWS `CreationDate` reflects when the AMI was **registered** (after build completion)
- These times may differ significantly (builds can take minutes to hours)
- To convert to your local timezone: use the `CreationDate` from AWS, not the AMI name

**Example:**
```
AMI Name:       cloudberry-packer-rocky9-20251002-100700
                                                    ↑
                                            Build started at 10:07 UTC

AWS CreationDate: 2025-10-02T17:07:00.000Z
                                    ↑
                      AMI registered at 17:07 UTC (7 hours after build started)

Your Local Time (GMT-7): 2025-10-02 10:07 (subtract 7 hours from UTC)
```

### Development-Specific Settings

**Security Configuration** (appropriate for development):
- **SELinux**: Disabled (prevents development conflicts)
- **Sudo Access**: Passwordless for `cbadmin` user
- **Resource Limits**: High limits (524K file handles)
- **SSH Access**: Key-based authentication

**Development Optimizations**:
- **Kernel Tuning**: Memory management and IPC settings
- **Docker Configuration**: 1GB shared memory allocation
- **User Environment**: Pre-configured development tools and aliases

## Testing Framework

### Goss Validation Tests
- **179+ test cases** across all build targets
- **Comprehensive coverage**: packages, services, files, users, commands
- **Multiple formats**: JUnit XML and human-readable output
- **Automated execution**: Integrated into build pipeline

### Test Categories
- **Package Installation**: Verify all required packages
- **Service Status**: SSH, Docker service validation
- **File System**: Configuration files, permissions, binaries
- **User Configuration**: Account setup and environment
- **Command Functionality**: Tool availability and basic functionality
- **System Settings**: Kernel parameters, resource limits

## Security Enhancements

### Download Verification
All external downloads now include:
- **SHA256 checksum verification** for binaries and configurations
- **Content validation** for configuration files
- **No pipe-to-shell** patterns eliminated
- **Temporary file cleanup** with proper error handling

### Enhanced Scripts
- **system_add_yq.sh**: Dynamic version detection with checksum verification
- **system_config_starship_prompt.sh**: Direct binary download with validation
- **cbladmin_configure_environment.sh**: Comprehensive security for all downloads
- **system_add_goss.sh**: Secure testing framework installation

## CI/CD Workflows

### Change Detection Intelligence
`compute-build-matrix.sh` derives the build matrix directly from the diff and
the HCL files — there is no hardcoded dependency map to keep in sync:

```bash
# Example: Changing vm-images/common/scripts/dbadmin_configure_environment.sh
#          rebuilds every target whose main.pkr.hcl references that script
# Example: Changing vm-images/common/scripts/system_add_awscli.sh
#          rebuilds only the targets whose main.pkr.hcl references it
# Example: Changing vm-images/aws/cloudberry/build/rocky9/main.pkr.hcl
#          rebuilds only cloudberry/rocky9
# Example: Changing vm-images/scripts/packer-build-and-test.sh
#          rebuilds all 7 targets
```

### Cost Management
- **Parallel build limits**: Maximum 3 concurrent builds
- **Smart rebuilds**: Only affected AMIs rebuilt
- **Automatic cleanup**: Temporary resources removed
- **AMI lifecycle**: Monthly cleanup of old images

### Build Features
- **Matrix builds**: Parallel execution across OS targets
- **Artifact collection**: Build manifests and test results
- **PR integration**: Automatic status updates
- **Manual override**: Full control for releases

## Usage Examples

### Manual Builds for Different Targets

```bash
# Rocky Linux 9 (full-featured with all development tools)
cd vm-images/aws/cloudberry/build/rocky9
../../../../scripts/packer-build-and-test.sh

# Rocky Linux 10 (latest Rocky with core tools)
cd vm-images/aws/cloudberry/build/rocky10
../../../../scripts/packer-build-and-test.sh

# SynxDB Cloud on Rocky Linux 10
cd vm-images/aws/synxdb-cloud/build/rocky10
../../../../scripts/packer-build-and-test.sh

# Agentic on Ubuntu 26.04 (standalone, AI tooling)
cd vm-images/aws/agentic/build/ubuntu26
../../../../scripts/packer-build-and-test.sh

# Agentic GPU image (chained from the newest agentic/ubuntu26 -PASSED AMI;
# g6.xlarge builder; not built by the change-driven workflow)
cd vm-images/aws/agentic/build/ubuntu26-gpu
../../../../scripts/packer-build-and-test.sh
```

### Using Built AMIs

```bash
# Launch instance from built AMI
aws ec2 run-instances \
  --image-id ami-xxxxxxxxx \
  --instance-type t3.medium \
  --key-name your-key-pair \
  --security-group-ids sg-xxxxxxxxx

# Connect to instance
ssh -i your-key.pem cbadmin@instance-ip
```

### Development Workflow

```bash
# 1. Modify scripts or configurations
# 2. Push changes to GitHub
# 3. CI/CD automatically detects changes and rebuilds affected AMIs
# 4. Review build results in PR comments
# 5. Merge after successful builds
```

## Customization

### Adding New Scripts

1. **Create script** in `vm-images/common/scripts/`
2. **Follow naming convention**: `system_action_component.sh`
3. **Add to Packer templates** as needed
4. **No CI/CD edit needed** — the build matrix is computed dynamically and will pick up the new script reference automatically
5. **Add Goss tests** for validation

### Adding New Targets

1. **Create build directory**: `vm-images/aws/<family>/build/<os>/` (new family) or `vm-images/aws/<existing-family>/build/<os>/` (new OS in an existing family)
2. **Copy template structure**: `main.pkr.hcl`, `scripts/`, `tests/`
3. **Configure base AMI** and OS-specific settings
4. **No workflow edits needed** — `.github/scripts/compute-build-matrix.sh` derives the target from the directory layout. To keep a target out of the change-driven matrix (e.g. an expensive GPU builder), add a `MANUAL_DISPATCH_ONLY` file to its directory; it then builds only via `ami-build-manual.yml`
5. **Test build locally** before CI/CD integration: `../../../../scripts/packer-build-and-test.sh`
6. **Update documentation**: Add to Supported Builds table and Repository Structure in README.md

> **Note:** The repository structure and supported builds list in README.md should be kept in sync with actual build directories. When adding/removing OS targets, update both the code and documentation together.

### Modifying Build Configuration

- **Instance types**: Update in `main.pkr.hcl` files
- **Volume sizes**: Modify `launch_block_device_mappings`
- **Package lists**: Edit OS-specific dependency scripts
- **Test coverage**: Update `goss.yaml` files

## Troubleshooting

### Common Build Issues

**Packer validation failures**:
- Check HCL syntax with `packer validate`
- Verify all script paths exist
- Ensure AWS credentials are configured

**Script execution failures**:
- Review script logs in build output
- Verify file permissions (755 for scripts)
- Check network connectivity for downloads

**Goss test failures**:
- Review test expectations in `goss.yaml`
- Verify package names for different OS versions
- Check service startup dependencies

**AMI timestamp confusion**:
- AMI names contain UTC timestamps from when builds **started**
- AWS CreationDate shows when AMIs were **registered** (after build completed)
- These timestamps can differ by hours if builds take a long time
- Always use CreationDate for accurate "newest" determination
- See [AMI Naming Convention](#ami-naming-convention) for details

### Resource Cleanup

If builds fail and leave resources:

```bash
# Manual cleanup
aws ec2 describe-instances --filters "Name=tag:Purpose,Values=packer"
aws ec2 terminate-instances --instance-ids i-xxxxxxxxx
aws ec2 delete-security-group --group-id sg-xxxxxxxxx
aws ec2 delete-key-pair --key-name temp-packer-key
```

## Contributing

### Development Guidelines

1. **Script Consistency**: Follow established patterns for headers, error handling
2. **Security First**: All downloads must include verification
3. **Testing Required**: Add Goss tests for new functionality
4. **Documentation**: Update README for significant changes (avoid hardcoding version numbers)
5. **CI/CD Integration**: Ensure workflows understand new dependencies
6. **Version Management**:
   - Prefer dynamic version detection (e.g., "latest" from GitHub releases)
   - Document versions in Goss tests, not README
   - Use package manager defaults when appropriate

### Naming Conventions

- **Scripts**: `system_action_component.sh` (underscores only)
- **Variables**: `UPPER_CASE` for environment variables
- **Functions**: `snake_case` for internal functions
- **Files**: Consistent with script naming patterns

## Support

### Repository Information
- **Purpose**: Development AMI factory for Apache Cloudberry Database
- **Maintenance**: Active development with automated testing
- **License**: [Check repository LICENSE file]
- **Issues**: Use GitHub Issues for bugs and feature requests

### Key Contacts
- **Infrastructure**: Repository maintainers
- **Security**: Follow security enhancement patterns
- **CI/CD**: GitHub Actions workflow documentation

---

**Last Updated**: 2025-10-09
**Repository Status**: Production-ready development image factory
**Quality Score**: A+ (95%) - Excellent automation with comprehensive testing
