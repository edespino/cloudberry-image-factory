#!/bin/bash

# Enable strict mode for better error handling
set -euo pipefail

# Header indicating the script execution
echo "Executing system_set_timezone.sh..."

sudo timedatectl set-timezone America/Los_Angeles

# Footer indicating the script execution is complete
echo "system_set_timezone.sh execution completed."
