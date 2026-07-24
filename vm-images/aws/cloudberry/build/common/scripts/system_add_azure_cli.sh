#!/bin/bash

# Azure CLI (az) installation script
# Installs from the official Microsoft package repository
# Supports: Rocky Linux, RHEL, CentOS

# Enable strict mode for better error handling
set -euo pipefail

# Header indicating the script execution
echo "Executing system_add_azure_cli.sh..."

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

# Install Azure CLI based on the detected OS
case "$OS" in
    rocky|rhel|centos)
        MAJOR_VERSION="${VERSION%%.*}"
        echo "Installing Azure CLI on Rocky/RHEL/CentOS ${MAJOR_VERSION}..."

        # Import the Microsoft repository GPG key (2025 key, used by the EL10 repo)
        sudo rpm --import https://packages.microsoft.com/keys/microsoft-2025.asc

        # Add the Microsoft package repository for this RHEL major version
        sudo dnf install -y "https://packages.microsoft.com/config/rhel/${MAJOR_VERSION}/packages-microsoft-prod.rpm"

        # Update package cache (-y auto-confirms the repo GPG key import
        # required by repo_gpgcheck=1 in the Microsoft repo file)
        sudo dnf makecache -y

        # Install Azure CLI
        sudo dnf install -y azure-cli

        # Clean up
        sudo dnf clean all
        ;;

    *)
        echo "Unsupported operating system: $OS"
        exit 1
        ;;
esac

# Verify Azure CLI installation
echo "Verifying Azure CLI installation..."
az version

# Footer indicating the script execution is complete
echo "system_add_azure_cli.sh execution completed."
