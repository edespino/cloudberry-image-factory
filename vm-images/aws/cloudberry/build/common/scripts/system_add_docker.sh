#!/bin/bash

# Unified Docker installation script for multiple Linux distributions
# Supports: Ubuntu, Rocky Linux, Amazon Linux 2023
#
# Enable strict mode for better error handling
set -euo pipefail

# Header indicating the script execution
echo "Executing system_add_docker.sh..."

# Detect the operating system
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
else
    echo "Cannot detect operating system"
    exit 1
fi

echo "Detected OS: $OS $VERSION"

# Install Docker based on the detected OS
case "$OS" in
    ubuntu)
        echo "Installing Docker on Ubuntu..."

        # Update package index
        sudo apt-get update

        # Install prerequisites
        sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common

        # Add Docker's official GPG key
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

        # Set up the stable Docker repository
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

        # Update package index again
        sudo apt-get update

        # Install Docker
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io

        # Clean up
        sudo apt-get clean
        sudo rm -rf /var/lib/apt/lists/*
        ;;

    rocky|rhel|centos)
        echo "Installing Docker on Rocky/RHEL/CentOS..."

        # Update package cache
        sudo dnf makecache

        # Add Docker CE repository
        sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

        # Update package cache again
        sudo dnf makecache

        # Install Docker
        sudo dnf install -y docker-ce docker-ce-cli containerd.io

        # Clean up
        sudo dnf clean all
        ;;

    amzn)
        echo "Installing Docker on Amazon Linux..."

        # Update package cache
        sudo dnf makecache

        # Install Docker (from Amazon Linux repos)
        sudo dnf install -y docker
        ;;

    *)
        echo "Unsupported operating system: $OS"
        exit 1
        ;;
esac

# Configure Docker daemon with shared memory size
echo "Configuring Docker daemon..."
echo '{"default-shm-size": "1G"}' | sudo tee /etc/docker/daemon.json > /dev/null

# Enable and start Docker service
echo "Starting Docker service..."
sudo systemctl enable docker
sudo systemctl start docker
sudo systemctl status docker || true

# Add current user to docker group
echo "Adding users to docker group..."
sudo usermod -aG docker $(whoami) || true

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
echo "Verifying Docker installation..."
docker --version

# Footer indicating the script execution is complete
echo "system_add_docker.sh execution completed."
echo "Note: Users will need to log out and back in for docker group membership to take effect."
