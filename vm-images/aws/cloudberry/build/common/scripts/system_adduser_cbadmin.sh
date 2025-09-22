#!/bin/bash

# Enable strict mode for better error handling
set -euo pipefail

# Header indicating the script execution
echo "Executing system_adduser_cbadmin.sh..."

# Create a group and user for cbadmin with sudo privileges
sudo groupadd cbadmin
sudo useradd -m -g cbadmin -s /bin/bash cbadmin

# Set correct home directory permissions
sudo chmod 0700 /home/cbadmin

# Grant sudo privileges to cbadmin user without requiring a password
echo 'cbadmin ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/90-cbadmin

# Footer indicating the script execution is complete
echo "system_adduser_cbadmin.sh execution completed."
