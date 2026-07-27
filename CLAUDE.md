# Cloudberry Image Factory - Claude AI Context

This file provides context and guidelines for Claude AI when working on this project.

## Interaction Model

**User provides:** Requirements, corrections, context, commands
**AI provides:** Analysis, implementation, technical details, solutions

**Treat this interaction as:**
- Command-line tool (input → output)
- Code review session (direct technical feedback)
- Engineering collaboration (skip social protocols)

**Communication guidelines:**
- No apologies, validation, or emotional language
- No "please" or "thank you" required from user
- Direct commands preferred ("Do X" not "Could you please do X")
- Skip meta-commentary about the conversation
- State facts or acknowledge uncertainty directly (no hedging with "I think", "perhaps", "maybe")
- Treat interruptions/corrections as normal input refinement
- Focus on: problem → analysis → solution
- Eliminate social pleasantries and relationship maintenance
- Do not make assumptions - verify facts by reading files/code
- When in doubt, ask
- Skip acknowledgment phrases ("Understood", "Got it", "Will do")

## Project Overview

This is a Packer-based infrastructure project for building development-optimized Amazon Machine Images (AMIs) for Apache Cloudberry (Incubating) on AWS. It supports multiple OS platforms with automated testing and CI/CD workflows.

## Adding New OS Platforms - Critical Checklist

When adding a new OS platform to this project, follow this checklist to avoid common mistakes:

### 1. Directory Structure
```
vm-images/aws/cloudberry/build/{osname}/
├── main.pkr.hcl
├── scripts/
│   └── system_add_cbdb_build_{rpm|deb}_dependencies.sh
└── tests/
    └── goss.yaml
```

### 2. main.pkr.hcl - Required Provisioners

**⚠️ CRITICAL PROVISIONERS (in order):**
1. `system_configure_dnf.sh` (RPM-based only)
2. `system_add_cbdb_build_{rpm|deb}_dependencies.sh` (OS-specific)
3. `system_set_timezone.sh`
4. `system_add_yq.sh`
5. `system_add_awscli.sh`
6. `system_add_kernel_configs.sh`
7. `system_adduser_dbadmin.sh` (gpadmin)
8. `system_add_dbadmin_ulimits.sh` (gpadmin)
9. `system_adduser_dbadmin.sh` (cbadmin)
10. `system_add_dbadmin_ulimits.sh` (cbadmin)
11. `dbadmin_configure_environment.sh` (gpadmin)
12. `dbadmin_configure_environment.sh` (cbadmin)
13. `system_add_docker.sh`
14. `system_add_motd_manager.sh`
15. **`system_add_goss.sh`** ⚠️ **DO NOT FORGET THIS!**

**Common Mistake:** Creating Goss tests without including `system_add_goss.sh` provisioner. This causes "goss: command not found" errors during testing.

### 3. OS-Specific Dependencies Script

**Minimum required packages:**
- `git`, `wget`, `tmux`, `unzip`
- **`gnupg2` (RPM) or `gnupg` (DEB)** ⚠️ Required for AWS CLI GPG verification
- `htop`, `bat`, `jq` (from EPEL on RPM systems)

### 4. Goss Tests

**Required includes in tests/goss.yaml:**
```yaml
gossfile:
  ../../common/tests/common-users.yaml: {}
  ../../common/tests/common-security.yaml: {}
  ../../common/tests/common-docker.yaml: {}
```

**Must test:**
- Package installation (git, wget, tmux, unzip, htop, jq, bat)
- System services (sshd)
- Critical files (yq, aws, goss, docker, motd)
- Command execution (verify tools work)
- Default user existence

### 5. GitHub Actions Workflows

**Files to update:**

1. `.github/workflows/ami-build-manual.yml`:
   - Add OS to `build_targets` options
   - Add OS to `all_builds` array

2. `.github/workflows/ami-build-on-change.yml`:
   - Add OS to each common script dependency mapping
   - Add OS-specific script detection case
   - Add OS to common test and build script sections

3. `.github/workflows/ami-cleanup-old.yml`:
   - No changes needed (auto-handles all AMIs)

### 6. Documentation

Update `README.md`:
- Repository structure section
- Supported Builds table

### 7. Verification Checklist

Before committing, verify:
- [ ] `system_add_goss.sh` provisioner included in main.pkr.hcl
- [ ] `gnupg2`/`gnupg` in dependencies script
- [ ] AMI filter and owner ID correct
- [ ] SSH username matches AMI default user
- [ ] All scripts executable (`chmod +x`)
- [ ] Workflow dependency mappings updated
- [ ] README.md updated
- [ ] Local build test passes: `packer validate` and `packer-build-and-test.sh`

## Platform-Specific Notes

### RPM-based Systems (CentOS, Rocky, Amazon Linux)
- Use `dnf` package manager
- Include `system_configure_dnf.sh` provisioner
- Install from EPEL: `--enablerepo=epel`
- May need SELinux configuration
- Default user varies: `ec2-user` (AL2023), `rocky` (Rocky), `centos` (CentOS)

### DEB-based Systems (Ubuntu, Debian)
- Use `apt` package manager
- Include locale configuration script
- May need `system_set_default_locale.sh`
- Default user: `ubuntu` (Ubuntu), `admin` (Debian)

## Current Platforms

| Platform | Package Manager | Default User | Notes |
|----------|----------------|--------------|-------|
| rocky8 | RPM (dnf) | rocky | Stable enterprise |
| rocky9 | RPM (dnf) | rocky | Full-featured, primary |
| rocky10 | RPM (dnf) | rocky | Latest Rocky |
| al2023-synxdb-cloud | RPM (dnf) | ec2-user | SynxDB Cloud ops image |
| rocky9-synxdb-cloud | RPM (dnf) | rocky | SynxDB Cloud ops image |
| rocky10-synxdb-cloud | RPM (dnf) | rocky | SynxDB Cloud workstation image |
| ubuntu24-synxdb-cloud | APT | ubuntu | SynxDB Cloud workstation image |

Archived 2026-07-24 (recoverable from git history): al2023, centos10, debian12, ubuntu20, ubuntu22.
Retired 2026-07-27 (recoverable from git history): al2023-synxdb-elastic.

## Common Errors and Solutions

### "goss: command not found"
**Cause:** Missing `system_add_goss.sh` provisioner in main.pkr.hcl
**Solution:** Add provisioner before post-processors section

### "gpg: command not found"
**Cause:** Missing `gnupg2` or `gnupg` package
**Solution:** Add to OS-specific dependencies script

### AMI renamed to "*-FAILED"
**Cause:** Goss tests failed or couldn't run
**Solution:** Check test results XML, verify all tested packages/tools are installed

### Workflow doesn't trigger for OS changes
**Cause:** OS not added to workflow dependency mappings
**Solution:** Update `.github/workflows/ami-build-on-change.yml` COMMON_SCRIPT_DEPS

## Important Patterns

1. **Two database admin users:** Always create both `gpadmin` and `cbadmin` with identical configurations
2. **User environment configuration:** Must run `dbadmin_configure_environment.sh` for both users
3. **Test framework last:** `system_add_goss.sh` should be near the end, after all tools are installed
4. **Goss tests match reality:** Only test packages/tools that are actually installed by provisioners

## Build Process Flow

```
Packer Build → Provisioners Execute → AMI Created → Test Instance Launched
→ Goss Tests Run → PASSED/FAILED → AMI Renamed → Test Instance Terminated
```

## Key Files

- `vm-images/aws/cloudberry/build/common/scripts/` - Shared provisioners (21 scripts)
- `vm-images/aws/cloudberry/scripts/packer-build-and-test.sh` - Main build orchestrator
- `.github/workflows/` - CI/CD automation
- Each platform's `main.pkr.hcl` - Build definition
- Each platform's `tests/goss.yaml` - Validation tests

## Development Workflow

1. Make changes to scripts or configurations
2. Test locally: `packer validate` and `packer-build-and-test.sh`
3. Push to GitHub
4. CI/CD detects changes and rebuilds affected AMIs
5. Tests run automatically
6. AMIs tagged as PASSED/FAILED
7. Monthly cleanup removes old AMIs

## Critical Success Factors

- **Dependencies first:** Install all tools before testing them
- **Test what you install:** Goss tests should match provisioners
- **Consistency:** Follow patterns from existing platforms
- **Validation:** Always test locally before pushing
