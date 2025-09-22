#!/bin/bash

# Enable strict mode for better error handling
set -euo pipefail

# Header indicating the script execution
echo "Executing system_add_cbdb_build_dependencies.sh..."

sleep 60

export DEBIAN_FRONTEND=noninteractive

# Update package lists and upgrade existing packages
sudo apt-get update
## sudo apt-get install -y apt-utils
sudo apt-get upgrade -y

# Add universe repository
sudo sed -i 's/^# deb .*universe/deb &/' /etc/apt/sources.list

# Update package lists again after adding new repository
sudo apt-get update

# Install initial packages
sudo apt-get install -y git
