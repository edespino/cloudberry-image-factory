#!/bin/bash

# Install glow - terminal-based markdown viewer, from Charm's official
# package repositories (APT on Debian/Ubuntu, YUM/DNF on RPM platforms)
# Source: https://github.com/charmbracelet/glow
#
# Installs to: /usr/bin/glow

set -euo pipefail

echo "Executing system_add_glow.sh..."

# Detect the operating system
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=${VERSION_ID:-unknown}
else
    echo "Cannot detect operating system"
    exit 1
fi

echo "Detected OS: $OS $VERSION"

case "$OS" in
    ubuntu|debian)
        echo "Installing glow from the Charm APT repository..."

        # Download the key from the official package repo URL
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor --yes -o /etc/apt/keyrings/charm.gpg

        # Wire the official source list configuration file
        echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list > /dev/null

        # Synchronize package manifests and install the tool
        sudo apt-get update
        sudo apt-get install -y glow

        # Clean up
        sudo apt-get clean
        sudo rm -rf /var/lib/apt/lists/*
        ;;

    rocky|rhel|centos|amzn|fedora)
        echo "Installing glow from the Charm YUM repository..."

        # Wire the official repo configuration (gpgcheck against Charm's key)
        sudo tee /etc/yum.repos.d/charm.repo > /dev/null <<'EOF'
[charm]
name=Charm
baseurl=https://repo.charm.sh/yum/
enabled=1
gpgcheck=1
gpgkey=https://repo.charm.sh/yum/gpg.key
EOF

        # Install the tool
        sudo dnf install -y glow
        ;;

    *)
        echo "ERROR: Unsupported operating system: $OS"
        exit 1
        ;;
esac

# Verify
/usr/bin/glow --version

echo "system_add_glow.sh execution completed."
