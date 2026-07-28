#!/bin/bash

# Unified GitHub CLI (gh) installation script for multiple Linux distributions
# Supports: Ubuntu, Debian, Rocky Linux, Amazon Linux 2023
#
# Enable strict mode for better error handling
set -euo pipefail

# Header indicating the script execution
echo "Executing system_add_gh.sh..."

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

# Install GitHub CLI based on the detected OS
case "$OS" in
    ubuntu)
        echo "Installing GitHub CLI on Ubuntu..."

        # Download GitHub's GPG key
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
        sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg

        # Add GitHub CLI apt repository
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null

        # Update package index
        sudo apt-get update

        # Install gh
        sudo apt-get install -y gh

        # Clean up
        sudo apt-get clean
        sudo rm -rf /var/lib/apt/lists/*
        ;;

    debian)
        echo "Installing GitHub CLI on Debian..."

        # Download GitHub's GPG key
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
        sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg

        # Add GitHub CLI apt repository
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null

        # Update package index
        sudo apt-get update

        # Install gh
        sudo apt-get install -y gh

        # Clean up
        sudo apt-get clean
        sudo rm -rf /var/lib/apt/lists/*
        ;;

    rocky|rhel|centos)
        echo "Installing GitHub CLI on Rocky/RHEL/CentOS..."

        # Add GitHub CLI yum repository
        sudo dnf install -y 'dnf-command(config-manager)'
        sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo

        # Update package cache
        sudo dnf makecache

        # Install gh
        sudo dnf install -y gh

        # Clean up
        sudo dnf clean all
        ;;

    amzn)
        echo "Installing GitHub CLI on Amazon Linux..."

        # Add GitHub CLI yum repository
        sudo dnf install -y 'dnf-command(config-manager)'
        sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo

        # Update package cache
        sudo dnf makecache

        # Install gh
        sudo dnf install -y gh

        # Clean up
        sudo dnf clean all
        ;;

    *)
        echo "Unsupported operating system: $OS"
        exit 1
        ;;
esac

# Verify GitHub CLI installation
echo "Verifying GitHub CLI installation..."
gh --version

# Footer indicating the script execution is complete
echo "system_add_gh.sh execution completed."
