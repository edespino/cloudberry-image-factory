#!/bin/bash

# Enable strict mode for better error handling
set -euo pipefail

# Header indicating the script execution
echo "Executing system_disable_selinux.sh..."

# Permanently disable SELinux by modifying the configuration file
sudo sed -i -e "s/^SELINUX=.*/SELINUX=disabled/" /etc/selinux/config

# Set SELinux mode to permissive until next reboot
sudo setenforce 0

# Footer indicating the script execution is complete
echo "system_disable_selinux.sh execution completed."
