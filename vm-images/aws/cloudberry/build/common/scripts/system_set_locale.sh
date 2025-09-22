#!/bin/bash

# Note: If the Go version is updated, remember to update the corresponding testinfra test
# script (test_golang_install.py) to verify the correct version.

# Enable strict mode for better error handling
set -euo pipefail

# Header indicating the script execution
echo "Executing system_set-locale.sh..."

sudo localectl set-locale LANG=en_US.UTF-8

# Footer indicating the script execution is complete
echo "system_set-locale.sh execution completed."
