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
        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
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
