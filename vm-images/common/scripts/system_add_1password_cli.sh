#!/bin/bash

# Install 1Password CLI (op) from the official repository
# Source: https://developer.1password.com/docs/cli/get-started/
# Supports RPM-based and DEB-based systems

set -euo pipefail

echo "Executing system_add_1password_cli.sh..."

# Detect the operating system
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "Cannot detect operating system"
    exit 1
fi

case "$OS" in
    rocky|rhel|centos|amzn)
        echo "Installing 1Password CLI via RPM repository..."

        # Add 1Password RPM repository
        sudo rpm --import https://downloads.1password.com/linux/keys/1password.asc
        sudo tee /etc/yum.repos.d/1password.repo > /dev/null <<'REPO'
[1password]
name=1Password Stable Channel
baseurl=https://downloads.1password.com/linux/rpm/stable/$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://downloads.1password.com/linux/keys/1password.asc
REPO

        sudo dnf install -y -d0 1password-cli
        ;;

    ubuntu|debian)
        echo "Installing 1Password CLI via APT repository..."

        # Add 1Password APT repository
        curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
            sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/amd64 stable main" | \
            sudo tee /etc/apt/sources.list.d/1password.list > /dev/null
        sudo apt-get update
        sudo apt-get install -y 1password-cli
        ;;

    *)
        echo "Unsupported operating system: $OS"
        exit 1
        ;;
esac

# Verify installation
echo "Verifying 1Password CLI installation..."
op --version

echo "system_add_1password_cli.sh execution completed."
