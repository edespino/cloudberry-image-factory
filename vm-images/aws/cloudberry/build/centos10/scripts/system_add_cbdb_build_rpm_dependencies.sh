#!/bin/bash

# Enable strict mode for better error handling
set -euo pipefail

# Header indicating the script execution
echo "Executing system_add_cbdb_build_rpm_dependencies.sh..."

# Update the package cache
sudo dnf makecache

# Install EPEL repository and import GPG keys for EPEL
sudo dnf install -y -d0 epel-release
sudo rpm --import http://download.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-10

# Update the package cache again to include the new repository
sudo dnf makecache

# Disable EPEL repositories to avoid conflicts
sudo dnf config-manager --disable epel

# Install basic utilities
sudo dnf install -y -d0 git wget tmux unzip gnupg2

# Install additional tools from EPEL repository
sudo dnf install -y -d0 --enablerepo=epel htop bat jq

#Cleanup
sudo dnf clean all

# Footer indicating the script execution is complete
echo "system_add_cbdb_build_rpm_dependencies.sh execution completed."
