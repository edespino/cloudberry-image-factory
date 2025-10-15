# Common Goss Tests

This directory contains shared Goss test files that are included by platform-specific tests.

## Purpose

Centralize common tests to follow the DRY (Don't Repeat Yourself) principle. When a dependency version changes (like Go), you only need to update it in one place.

## Structure

```
common/tests/
├── README.md
└── common-golang.yaml        # Go installation and version tests
```

## Usage in Platform Tests

Platform-specific `goss.yaml` files include common tests using the `gossfile` directive:

```yaml
---
# Include common tests
gossfile:
  ../../common/tests/common-golang.yaml: {}

# Platform-specific tests follow...
package:
  git: {installed: true}
  # ...
```

## Directory Structure on Test Instances

During testing, the `packer-build-and-test.sh` script creates this structure on the EC2 instance:

```
~/{os_name}/tests/goss.yaml      # Platform-specific tests
~/common/tests/common-golang.yaml # Common tests
```

This matches the relative path `../../common/tests/` used in the platform test files.

## Adding New Common Tests

To add a new common test file:

1. Create the test file in this directory (e.g., `common-docker.yaml`)
2. Add it to platform `goss.yaml` files:
   ```yaml
   gossfile:
     ../../common/tests/common-golang.yaml: {}
     ../../common/tests/common-docker.yaml: {}
   ```
3. The `packer-build-and-test.sh` script automatically copies all `*.yaml` files from this directory

## Benefits

- **Single Source of Truth**: Update versions once (e.g., Go 1.25.2)
- **Consistency**: All platforms test identical common features
- **Maintainability**: Clear separation of common vs platform-specific tests
- **Quality**: Comprehensive testing (discovered missing tests in some platforms)

## Example: Updating Go Version

To update the Go version from 1.25.2 to 1.25.3:

1. Edit `common-golang.yaml`:
   ```yaml
   file:
     /opt/go1.25.3:  # Update this line
       exists: true
       filetype: directory

   command:
     "/opt/go/bin/go version":
       stdout: ["go1.25.3"]  # Update this line
   ```

2. All 4+ platforms automatically use the new version in their tests
