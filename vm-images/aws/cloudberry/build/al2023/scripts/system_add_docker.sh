#!/bin/bash

# Enable strict mode for better error handling
set -euo pipefail

# Header indicating the script execution
echo "Executing system_add_docker.sh..."

# Update the package cache
sudo dnf makecache

# Install Docker
sudo dnf install -y -d0 docker

# Enable and start Docker service
sudo systemctl enable docker
sudo systemctl start docker

# Add ec2-user to docker group
sudo usermod -aG docker ec2-user

# Add gpadmin to docker group (if user exists)
if id "gpadmin" &>/dev/null; then
    sudo usermod -aG docker gpadmin
    echo "Added gpadmin to docker group"
fi

# Add cbadmin to docker group (if user exists)
if id "cbadmin" &>/dev/null; then
    sudo usermod -aG docker cbadmin
    echo "Added cbadmin to docker group"
fi

# Verify Docker installation
docker --version

# Footer indicating the script execution is complete
echo "system_add_docker.sh execution completed."
echo "Note: Users will need to log out and back in for docker group membership to take effect."
