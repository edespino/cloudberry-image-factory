#!/bin/bash

# Install nvtop - GPU process monitor (Ubuntu universe)
# btop is already on the base image; nvtop adds the per-GPU view.

set -euo pipefail

echo "Executing system_add_nvtop.sh..."

# Refresh lists in case they were cleaned between steps
sudo apt-get update

sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nvtop

# Verify
/usr/bin/nvtop --version

echo "system_add_nvtop.sh execution completed."
