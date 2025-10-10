#!/bin/bash
# dnf_robust_install.sh - Robust DNF package installation with retry logic
#
# This library provides a wrapper function for dnf install operations that
# handles transient mirror synchronization issues common with Rocky Linux and
# RHEL-based distributions.
#
# Usage:
#   source /path/to/dnf_robust_install.sh
#   dnf_robust_install package1 package2 package3

set -e

dnf_robust_install() {
    local args="$@"
    local max_attempts=5
    local attempt=1

    if [ -z "$args" ]; then
        echo "ERROR: No packages or arguments specified for dnf_robust_install"
        return 1
    fi

    echo "==> Installing with retry logic: $args"

    while [ $attempt -le $max_attempts ]; do
        echo "==> Attempt $attempt/$max_attempts"

        # Clean potentially stale metadata on each attempt
        sudo dnf clean metadata >/dev/null 2>&1 || true

        # Attempt installation with increased timeouts and retries
        if sudo dnf install -y \
            --setopt=retries=3 \
            --setopt=timeout=120 \
            --setopt=metadata_expire=1h \
            $args 2>&1 | tee /tmp/dnf_install_attempt_${attempt}.log; then
            echo "==> ✓ Successfully installed: $args"
            rm -f /tmp/dnf_install_attempt_*.log 2>/dev/null || true
            return 0
        fi

        # Installation failed, check if we should retry
        if [ $attempt -lt $max_attempts ]; then
            sleep_time=$((attempt * 45))
            echo "==> ⚠ Attempt $attempt/$max_attempts failed. Waiting ${sleep_time}s before retry..."
            sleep $sleep_time

            # On 3rd attempt, perform aggressive metadata refresh
            if [ $attempt -eq 3 ]; then
                echo "==> Performing full metadata refresh (attempt 3)..."
                sudo dnf clean all >/dev/null 2>&1 || true
                sudo dnf makecache --refresh >/dev/null 2>&1 || true
            fi
        else
            # All attempts failed
            echo "==> ✗ FAILED to install $args after $max_attempts attempts"
            echo "==> Last attempt log:"
            cat /tmp/dnf_install_attempt_${attempt}.log
            rm -f /tmp/dnf_install_attempt_*.log 2>/dev/null || true
            return 1
        fi

        ((attempt++))
    done

    # Should never reach here, but just in case
    return 1
}

# Export the function so it's available to scripts that source this file
export -f dnf_robust_install

echo "==> dnf_robust_install library loaded"
