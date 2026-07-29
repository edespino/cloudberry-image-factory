#!/bin/bash

# Install Packer from the official HashiCorp package repository
# Sources: https://rpm.releases.hashicorp.com / https://apt.releases.hashicorp.com
# (Packer's CLI is also installable as a standalone binary, but the HashiCorp
#  repo keeps it updatable via dnf/apt, matching upstream guidance.)

set -euo pipefail

echo "Executing system_add_packer.sh..."

# Detect the operating system
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "Cannot detect operating system"
    exit 1
fi

case "$OS" in
    rocky|rhel|centos|amzn)
        # dnf config-manager lives in dnf-plugins-core
        sudo dnf install -y -d0 dnf-plugins-core

        # Add the HashiCorp RHEL repo (idempotent: --add-repo overwrites the .repo file)
        sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo

        # Install Packer
        sudo dnf install -y -d0 packer
        ;;
    ubuntu|debian)
        export DEBIAN_FRONTEND=noninteractive

        # Add the HashiCorp APT repo (per https://developer.hashicorp.com/packer/install)
        curl -fsSL https://apt.releases.hashicorp.com/gpg | \
            sudo gpg --dearmor --yes -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

        # HashiCorp does not always publish a dists/<codename>/Release file the
        # day a new Ubuntu codename ships (e.g. 26.04 "resolute"). Probe the
        # detected codename first and fall back to the newest Ubuntu LTS
        # codename HashiCorp does publish (noble) if it 404s, rather than
        # blindly writing a sources entry that breaks apt-get update.
        DETECTED_DIST=$(lsb_release -cs)
        HC_DIST=""
        for candidate in "$DETECTED_DIST" noble; do
            if curl -fsSI "https://apt.releases.hashicorp.com/dists/${candidate}/Release" \
                >/dev/null 2>&1; then
                HC_DIST="$candidate"
                break
            fi
        done
        if [ -z "$HC_DIST" ]; then
            echo "ERROR: no usable HashiCorp apt codename found among: ${DETECTED_DIST} noble"
            exit 1
        fi
        echo "Using HashiCorp apt codename: ${HC_DIST} (detected: ${DETECTED_DIST})"

        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com ${HC_DIST} main" | \
            sudo tee /etc/apt/sources.list.d/hashicorp.list > /dev/null

        sudo apt-get update
        sudo apt-get install -y packer
        ;;
    *)
        echo "Unsupported operating system: $OS"
        exit 1
        ;;
esac

# Verify
/usr/bin/packer version

echo "system_add_packer.sh execution completed."
