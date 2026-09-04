# Common Goss Tests

This directory contains shared Goss test files that are included by platform-specific tests across all AMI builds.

## Purpose

Centralize common tests to follow the DRY (Don't Repeat Yourself) principle. When a dependency version or configuration changes, you only need to update it in one place rather than across multiple platform-specific test files.

## Structure

```
common/tests/
├── README.md
├── common-golang.yaml      # Go installation and version tests (version must match GO_VERSION in system_add_golang.sh)
├── common-users.yaml       # gpadmin/cbadmin user configuration and SSH setup
├── common-security.yaml    # System limits, sudoers, sysctl, and kernel parameters
├── common-docker.yaml      # Docker service, configuration, and GitHub CLI
└── common-motd.yaml        # MOTD manager system with template switching
```

## Usage in Platform Tests

Platform-specific `goss.yaml` files include common tests using the `gossfile` directive:

```yaml
---
# Include common tests
gossfile:
  ../../common/tests/common-golang.yaml: {}
  ../../common/tests/common-users.yaml: {}
  ../../common/tests/common-security.yaml: {}
  ../../common/tests/common-docker.yaml: {}
  ../../common/tests/common-motd.yaml: {}

# Platform-specific tests follow...
package:
  git: {installed: true}
  # ...
```

## Directory Structure on Test Instances

During testing, the `packer-build-and-test.sh` script creates this structure on the EC2 instance:

```
~/{os_name}/tests/goss.yaml           # Platform-specific tests
~/common/tests/
  ├── common-golang.yaml              # Common Go tests
  ├── common-users.yaml               # Common user tests
  ├── common-security.yaml            # Common security tests
  ├── common-docker.yaml              # Common Docker tests
  └── common-motd.yaml                # Common MOTD manager tests
```

This matches the relative path `../../common/tests/` used in the platform test files.

## Common Test File Contents

### common-golang.yaml
- Go binary and installation directory checks (`/opt/go<version>`)
- Go symlink verification (`/opt/go`)
- Environment configuration (`/etc/profile.d/go.sh`)
- Go version validation (must match `GO_VERSION` in `system_add_golang.sh`)

### common-users.yaml (211 lines)
- **User accounts**: gpadmin and cbadmin existence, home directories, shells
- **Environment files**: .bashrc, .vimrc, .tmux.conf with proper ownership
- **SSH configuration**: id_ed25519 keys, authorized_keys with correct permissions
- **Tools**: just command installation in ~/bin
- **Access tests**: SSH key functionality, sudo access (NOPASSWD:ALL), Docker group membership

### common-security.yaml (94 lines)
- **Resource limits**: nofile (524288), nproc (131072), core (unlimited) for both users
- **Sudoers**: NOPASSWD:ALL configuration for gpadmin and cbadmin
- **Sysctl settings**: kernel.msgmax, vm.overcommit_memory, net.core.somaxconn
- **Kernel parameters**: vm.overcommit_memory, vm.overcommit_ratio, net.core.somaxconn, tcp_congestion_control

### common-docker.yaml (46 lines)
- **Docker service**: Enabled state verification
- **Configuration**: /etc/docker/daemon.json with default-shm-size
- **Functionality**: Docker version check
- **GitHub CLI**: gh version check

### common-motd.yaml (69 lines)
- **MOTD manager executable**: /usr/local/sbin/motd-manager (755 permissions)
- **MOTD switcher utility**: /usr/local/bin/motd-switch (755 permissions)
- **Configuration**: /etc/motd.conf with MOTD_TEMPLATE setting
- **Templates**: cloudberry.txt and synx.txt in /usr/local/share/motd-templates/
- **Profile hook**: /etc/profile.d/10-motd.sh integration
- **Functionality tests**: motd-manager execution, motd-switch --help

## Adding New Common Tests

To add a new common test file:

1. Create the test file in this directory (e.g., `common-ssh.yaml`)
2. Add it to all platform `goss.yaml` files:
   ```yaml
   gossfile:
     ../../common/tests/common-golang.yaml: {}
     ../../common/tests/common-users.yaml: {}
     ../../common/tests/common-security.yaml: {}
     ../../common/tests/common-docker.yaml: {}
     ../../common/tests/common-ssh.yaml: {}       # New file
   ```
3. The `packer-build-and-test.sh` script automatically copies all `*.yaml` files from this directory

## Benefits

- **Massive code reduction**: Removed 1,093 lines of duplicate test code (67% reduction)
- **Single source of truth**: Update configurations once across all platforms
- **Consistency**: All platforms test identical common features
- **Easier maintenance**: Clear separation of common vs platform-specific tests
- **Faster updates**: Version changes require editing only one file
- **Better quality**: Comprehensive testing discovered missing tests in some platforms
- **Reduced errors**: No risk of platform test files diverging over time

## Impact Statistics

**Before refactoring:**
- 4 platform test files with extensive duplication
- ~400-450 lines per platform test file
- Total: ~1,700 lines across all platforms

**After Phase 1 refactoring:**
- 4 common test files (golang, users, security, docker): 365 lines
- 4 streamlined platform test files: ~135-160 lines each
- Total: ~900 lines (47% overall reduction)
- Eliminated 1,093 lines of duplicate code

## Example Updates

### Example 1: Updating Go Version

To update the Go version from 1.25.2 to 1.25.3:

1. Edit `common-golang.yaml`:
   ```yaml
   file:
     /opt/go1.25.3:  # Update version-specific directory
       exists: true
       filetype: directory

   command:
     "/opt/go/bin/go version":
       stdout: ["go1.25.3"]  # Update version check
   ```

2. All platforms that include `common-golang.yaml` automatically test the new version

### Example 2: Changing Resource Limits

To increase nofile limit from 524288 to 1048576:

1. Edit `common-security.yaml`:
   ```yaml
   /etc/security/limits.d/90-db-gpadmin-limits.conf:
     contents:
       - "gpadmin soft nofile 1048576"  # Update both lines
       - "gpadmin hard nofile 1048576"
   ```

2. All platforms will validate the new limit in their tests

### Example 3: Adding New User Tests

To add a new test for gpadmin's Git configuration:

1. Edit `common-users.yaml`:
   ```yaml
   file:
     /home/gpadmin/.gitconfig:
       exists: true
       owner: gpadmin
       group: gpadmin
       filetype: file
   ```

2. All platforms automatically include the new test

## Platforms Using These Common Tests

**Current build targets** (`vm-images/aws/<family>/build/<os>/`):
- cloudberry: rocky9, rocky10
- synxdb-cloud: al2023, rocky9, rocky10, ubuntu24
- agentic: ubuntu26, ubuntu26-arm64, ubuntu26-gpu

Not every target includes every common test file — e.g. the `synxdb-cloud`
and `agentic` operations/workstation targets intentionally omit
`common-security.yaml` (ulimits and kernel params they don't set). Check each
target's `tests/goss.yaml` `gossfile:` block for its actual includes.

**Archived 2026-07-24 (recoverable from git history):** al2023, ubuntu22,
centos10, debian12, ubuntu20 — these platforms are no longer active build
targets; historical references to their use of these common test files
remain accurate only as history.

## Future Enhancement Plans

**Phase 2** (Planned):
- common-ssh.yaml: SSH service, port 22 listening, sshd process checks
- Consolidate remaining sysctl and kernel parameter tests

**Phase 3** (Planned):
- common-tools.yaml: yq, goss, and other common utilities
- common-starship.yaml: Starship prompt (Rocky 9 only)
