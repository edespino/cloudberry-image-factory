#!/bin/bash

# Install nvtop - GPU process monitor (Ubuntu universe)
# btop is already on the base image; nvtop adds the per-GPU view.

set -euo pipefail

echo "Executing system_add_nvtop.sh..."

export DEBIAN_FRONTEND=noninteractive

# Refresh lists in case they were cleaned between steps
sudo apt-get update

sudo apt-get install -y nvtop

# Verify
/usr/bin/nvtop --version

echo "system_add_nvtop.sh execution completed."
