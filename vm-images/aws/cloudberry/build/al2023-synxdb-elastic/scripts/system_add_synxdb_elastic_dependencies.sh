#!/bin/bash

# Enable strict mode for better error handling
set -euxo pipefail

# Header indicating the script execution
echo "Executing system_add_synxdb_elastic_dependencies.sh..."

# Update the package cache
sudo dnf makecache

# Install basic utilities
sudo dnf install -y -d0 git vim tmux wget time tree htop
sudo dnf install -y -d0 postgresql16

# Cleanup
sudo dnf clean all

# Footer indicating the script execution is complete
echo "system_add_synxdb_elastic_dependencies.sh execution completed."
