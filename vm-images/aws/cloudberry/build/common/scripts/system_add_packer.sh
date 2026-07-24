#!/bin/bash

# Install Packer from the official HashiCorp RPM repository
# Source: https://rpm.releases.hashicorp.com
# (Packer's CLI is also installable as a standalone binary, but the HashiCorp
#  repo keeps it updatable via dnf, matching upstream guidance.)

set -euo pipefail

echo "Executing system_add_packer.sh..."

# dnf config-manager lives in dnf-plugins-core
sudo dnf install -y -d0 dnf-plugins-core

# Add the HashiCorp RHEL repo (idempotent: --add-repo overwrites the .repo file)
sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo

# Install Packer
sudo dnf install -y -d0 packer

# Verify
/usr/bin/packer version

echo "system_add_packer.sh execution completed."
