#!/bin/bash

# Unified Docker installation script for multiple Linux distributions
# Supports: Ubuntu, Debian, Rocky Linux, Amazon Linux 2023
#
# Enable strict mode for better error handling
set -euo pipefail

# dnf_robust_install - Robust DNF package installation with retry logic
# Handles transient mirror synchronization issues common with Rocky Linux
dnf_robust_install() {
    local args="$@"
    local max_attempts=5
    local attempt=1

    if [ -z "$args" ]; then
        echo "ERROR: No packages or arguments specified for dnf_robust_install"
        return 1
    fi

    echo "==> Installing with retry logic: $args"

    while [ $attempt -le $max_attempts ]; do
        echo "==> Attempt $attempt/$max_attempts"

        # Clean potentially stale metadata on each attempt
        sudo dnf clean metadata >/dev/null 2>&1 || true

        # Attempt installation with increased timeouts and retries
        if sudo dnf install -y \
            --setopt=retries=3 \
            --setopt=timeout=120 \
            --setopt=metadata_expire=1h \
            $args 2>&1 | tee /tmp/dnf_install_attempt_${attempt}.log; then
            echo "==> ✓ Successfully installed: $args"
            rm -f /tmp/dnf_install_attempt_*.log 2>/dev/null || true
            return 0
        fi

        # Installation failed, check if we should retry
        if [ $attempt -lt $max_attempts ]; then
            sleep_time=$((attempt * 45))
            echo "==> ⚠ Attempt $attempt/$max_attempts failed. Waiting ${sleep_time}s before retry..."
            sleep $sleep_time

            # On 3rd attempt, perform aggressive metadata refresh
            if [ $attempt -eq 3 ]; then
                echo "==> Performing full metadata refresh (attempt 3)..."
                sudo dnf clean all >/dev/null 2>&1 || true
                sudo dnf makecache --refresh >/dev/null 2>&1 || true
            fi
        else
            # All attempts failed
            echo "==> ✗ FAILED to install $args after $max_attempts attempts"
            echo "==> Last attempt log:"
            cat /tmp/dnf_install_attempt_${attempt}.log
            rm -f /tmp/dnf_install_attempt_*.log 2>/dev/null || true
            return 1
        fi

        ((attempt++))
    done

    # Should never reach here, but just in case
    return 1
}

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

    debian)
        echo "Installing Docker on Debian..."

        # Update package index
        sudo apt-get update

        # Install prerequisites (including lsb-release for codename detection)
        sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common gnupg lsb-release

        # Add Docker's official GPG key
        curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

        # Set up the stable Docker repository
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

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

        # Add Docker CE repository (RHEL repo for version 10+, CentOS repo for older)
        MAJOR_VERSION=$(echo "$VERSION" | cut -d. -f1)
        if [ "$MAJOR_VERSION" -ge 10 ]; then
            echo "Using Docker RHEL repository for version $MAJOR_VERSION..."
            sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
        else
            sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        fi

        # Update package cache again
        sudo dnf makecache

        # Install Docker with retry logic
        dnf_robust_install docker-ce docker-ce-cli containerd.io

        # Clean up
        sudo dnf clean all
        ;;

    amzn)
        echo "Installing Docker on Amazon Linux..."

        # Update package cache
        sudo dnf makecache

        # Install Docker (from Amazon Linux repos) with retry logic
        dnf_robust_install docker
        ;;

    *)
        echo "Unsupported operating system: $OS"
        exit 1
        ;;
esac

# Configure Docker daemon with shared memory size
echo "Configuring Docker daemon..."
echo '{"default-shm-size": "1G"}' | sudo tee /etc/docker/daemon.json > /dev/null

# Load kernel modules required by Docker networking (needed on RHEL 10+ where
# iptables modules live in kernel-modules-extra and may not be loaded yet)
echo "Loading Docker-required kernel modules..."
sudo modprobe xt_addrtype || true
sudo modprobe br_netfilter || true
sudo modprobe overlay || true

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
