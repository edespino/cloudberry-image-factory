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

This is a Packer-based infrastructure project for building development-optimized, private-only Amazon Machine Images (AMIs) on AWS. It is organized by **family** — a family is a product line (`cloudberry`, `synxdb-cloud`, `agentic`) that builds AMIs across one or more OS targets, with automated Goss testing and dynamic CI/CD workflows.

## Repository Layout

```
vm-images/
├── scripts/                          # Harness trio (shared by every family)
│   ├── packer-build-and-test.sh      # Build, test, PASSED/FAILED tag, cleanup
│   ├── private-runtime-key.py        # Temporary SSH key handling
│   └── validate-ami-metadata.py      # Confirms AMI is not-publicly-shared
├── common/
│   ├── scripts/                      # Shared provisioners (58 scripts)
│   └── tests/                        # Shared Goss fragments (gossfile includes)
└── aws/
    ├── cloudberry/build/{rocky9,rocky10}/
    ├── synxdb-cloud/build/{al2023,rocky9,rocky10,ubuntu24}/
    └── agentic/build/{ubuntu26,ubuntu26-arm64,ubuntu26-gpu}/
        # Each build directory contains:
        #   main.pkr.hcl   - Packer configuration
        #   scripts/       - OS-specific scripts
        #   tests/goss.yaml - Validation tests
```

Identity (`FAMILY`, `OS_NAME`) is derived by `packer-build-and-test.sh` directly
from the path it is run from: `vm-images/<cloud>/<family>/build/<os>`. There is
no registry file to update when adding a target — the path *is* the
configuration.

## Current Platforms (9 targets)

| Family | OS Target | Package Manager | Notes |
|--------|-----------|-----------------|-------|
| cloudberry | rocky9 | RPM (dnf) | Full-featured, primary |
| cloudberry | rocky10 | RPM (dnf) | Latest Rocky |
| synxdb-cloud | al2023 | RPM (dnf) | SynxDB Cloud ops image |
| synxdb-cloud | rocky9 | RPM (dnf) | SynxDB Cloud ops image |
| synxdb-cloud | rocky10 | RPM (dnf) | SynxDB Cloud workstation image |
| synxdb-cloud | ubuntu24 | APT | SynxDB Cloud workstation image |
| agentic | ubuntu26 | APT | Standalone from stock Ubuntu 26.04; AI tooling |
| agentic | ubuntu26-arm64 | APT | arm64/Graviton sibling of ubuntu26; no dysk |
| agentic | ubuntu26-gpu | APT | x86_64 NVIDIA L4 image chained from the ubuntu26 `-PASSED` AMI; g6.xlarge builder; CI manual dispatch only (`MANUAL_DISPATCH_ONLY` marker) |

Archived 2026-07-24 (recoverable from git history): al2023, centos10, debian12, ubuntu20, ubuntu22.
Retired 2026-07-27 (recoverable from git history): al2023-synxdb-elastic, rocky8.

**AI tooling is agentic-only.** Scripts such as `system_add_claude.sh`,
`system_add_ai_toolchain.sh`, `system_add_omnigent.sh`, `system_add_herdr.sh`,
and `system_add_beads.sh` must never be referenced by a `cloudberry` or
`synxdb-cloud` template — a repository policy test enforces this boundary.

## Build Harness

Run from inside a target directory:

```bash
cd vm-images/aws/<family>/build/<os>
../../../../scripts/packer-build-and-test.sh
```

AMIs are named `<family>-packer-<os>-<timestamp>`, then renamed with a
`-PASSED` or `-FAILED` suffix once Goss testing completes. All builds are
private-only (never publicly shared).

## Adding a New Family

A new family needs no workflow edits — the CI build matrix is computed
dynamically from the directory layout (see `.github/scripts/compute-build-matrix.sh`).

1. Create `vm-images/aws/<family>/build/<os>/` with `main.pkr.hcl`, `scripts/`, `tests/goss.yaml`.
2. Decide whether the family ships AI tooling. Only `agentic` may.
3. Update the Current Platforms table above and the Repository Structure/Supported Builds sections in `README.md`.
4. Build and test locally before pushing: `../../../../scripts/packer-build-and-test.sh`.

## Adding a New Target to an Existing Family

Follow this checklist to avoid common mistakes:

### 1. Directory Structure
```
vm-images/aws/<family>/build/{osname}/
├── main.pkr.hcl
├── scripts/
│   └── system_add_cbdb_build_{rpm|deb}_dependencies.sh   # (or family-appropriate OS deps script)
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

**No workflow edits needed.** The build matrix is computed dynamically by
`.github/scripts/compute-build-matrix.sh` from the directory layout:

- A change under `vm-images/aws/<family>/build/<os>/**` selects that one target.
- A change to `vm-images/common/scripts/X.sh` selects every target whose
  `main.pkr.hcl` references `X.sh` (grep-matched, not a hardcoded map).
- A change under `vm-images/scripts/**` or `vm-images/common/tests/**`
  selects every target.
- Manual dispatch (`ami-build-manual.yml`) takes `all` or a comma-separated
  `family/os` list, e.g. `cloudberry/rocky9,agentic/ubuntu26`.
- A target directory containing a `MANUAL_DISPATCH_ONLY` file is skipped by
  the change-driven matrix under every rule and builds only via manual
  dispatch (currently `agentic/ubuntu26-gpu`).
- `ami-cleanup-old.yml` needs no changes — cleanup runs per-family against
  the `<family>-packer-*` naming pattern.

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
- [ ] README.md updated (Repository Structure + Supported Builds table)
- [ ] Local build test passes: `packer validate` and `../../../../scripts/packer-build-and-test.sh`

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

### Workflow doesn't trigger for a script/target change
**Cause:** Rare — the matrix is computed dynamically from the directory layout and HCL references, not a hardcoded map.
**Solution:** Check `.github/scripts/compute-build-matrix.sh`; verify the changed script's basename appears in the target's `main.pkr.hcl`.

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

- `vm-images/common/scripts/` - Shared provisioners (58 scripts)
- `vm-images/scripts/packer-build-and-test.sh` - Main build orchestrator (harness trio)
- `.github/scripts/compute-build-matrix.sh` - Dynamic CI build matrix
- `.github/workflows/` - CI/CD automation
- Each target's `main.pkr.hcl` - Build definition
- Each target's `tests/goss.yaml` - Validation tests

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
