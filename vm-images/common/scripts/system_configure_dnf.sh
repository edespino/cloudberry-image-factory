#!/bin/bash
# system_configure_dnf.sh - Configure DNF for more resilient package operations
#
# This script configures DNF/YUM package managers on RHEL-based systems
# (Rocky Linux, RHEL, CentOS, Amazon Linux) to be more resilient when
# dealing with mirror synchronization issues.
#
# This script should run early in the AMI build process, before any
# package installation operations.

set -e

echo "Executing system_configure_dnf.sh..."

# Detect if this is a RHEL-based system
if ! command -v dnf &> /dev/null && ! command -v yum &> /dev/null; then
    echo "==> Not a RHEL-based system (no dnf/yum found). Skipping DNF configuration."
    echo "system_configure_dnf.sh execution completed (skipped)."
    exit 0
fi

# Determine package manager
if command -v dnf &> /dev/null; then
    PKG_MGR="dnf"
    CONFIG_DIR="/etc/dnf/dnf.conf.d"
elif command -v yum &> /dev/null; then
    PKG_MGR="yum"
    CONFIG_DIR="/etc/yum/pluginconf.d"
else
    echo "==> ERROR: No package manager found"
    exit 1
fi

echo "==> Detected package manager: $PKG_MGR"

# Create configuration directory if it doesn't exist
sudo mkdir -p "$CONFIG_DIR"

# Create DNF/YUM configuration for AMI builds
echo "==> Creating resilient package manager configuration..."

if [ "$PKG_MGR" = "dnf" ]; then
    sudo tee /etc/dnf/dnf.conf.d/99-ami-build-resilience.conf > /dev/null <<'EOF'
# DNF Configuration for AMI Build Resilience
# This configuration helps handle transient mirror synchronization issues
# that can occur during Rocky Linux repository updates

[main]
# Retry failed downloads up to 10 times
retries=10

# Increase timeout to 120 seconds for slow mirrors
timeout=120

# Don't skip repositories even if unavailable (fail explicitly)
skip_if_unavailable=False

# Cache metadata for 1 hour to avoid repeated failures
metadata_expire=1h

# Use fastest mirror plugin to select best mirrors
fastestmirror=True

# Maximum simultaneous downloads
max_parallel_downloads=3

# Keep cache for debugging if needed
keepcache=False
EOF
    echo "==> Created /etc/dnf/dnf.conf.d/99-ami-build-resilience.conf"
else
    # YUM configuration
    sudo tee /etc/yum.conf.d/99-ami-build-resilience.conf > /dev/null <<'EOF'
# YUM Configuration for AMI Build Resilience

[main]
retries=10
timeout=120
skip_if_unavailable=0
metadata_expire=1h
EOF
    echo "==> Created /etc/yum.conf.d/99-ami-build-resilience.conf"
fi

# Perform initial metadata refresh
echo "==> Performing initial metadata refresh..."
sudo $PKG_MGR clean all
sudo $PKG_MGR makecache --refresh || {
    echo "==> WARNING: Initial metadata refresh failed, continuing anyway..."
    echo "==> This may indicate mirror sync issues that will be handled by retry logic"
}

echo "==> DNF/YUM configuration completed successfully"
echo "system_configure_dnf.sh execution completed."
