#!/bin/bash

# Install Claude CLI on Rocky Linux 9

# Enable strict mode for better error handling
set -euo pipefail

# Header indicating the script execution
echo "Executing system_add_claude.sh..."

# Detect OS type
if [ -f /etc/rocky-release ] || [ -f /etc/redhat-release ]; then
    OS="rhel"
elif [ -f /etc/debian_version ]; then
    OS="debian"
else
    echo "Unsupported OS. This script supports RHEL/Rocky and Debian/Ubuntu."
    exit 1
fi

echo "Detected OS: $OS"

# Install Node.js 20.x and ripgrep based on OS
if [ "$OS" = "rhel" ]; then
    # Install EPEL repository if not already available
    sudo dnf install -y epel-release

    # Add NodeSource repository for latest Node.js
    curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -

    # Install Node.js 18+ (required for Claude Code)
    sudo dnf install -y -d0 nodejs
    sudo dnf install -y -d0 --enablerepo=epel ripgrep
elif [ "$OS" = "debian" ]; then
    # Add NodeSource repository for Debian/Ubuntu
    echo "Adding NodeSource repository..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash -

    # Install packages
    echo "Installing Node.js and ripgrep..."
    sudo apt-get update
    sudo apt-get install -y nsolid ripgrep
fi

# Verify Node.js installation
echo "Verifying Node.js installation..."
NODE_VERSION=$(node --version)
NPM_VERSION=$(npm --version)
echo "Node.js version: $NODE_VERSION"
echo "npm version: $NPM_VERSION"

# Verify minimum versions
NODE_MAJOR=$(echo "$NODE_VERSION" | sed 's/v//' | cut -d. -f1)
if [ "$NODE_MAJOR" -lt 18 ]; then
    echo "Error: Node.js version must be 18 or higher. Found: $NODE_VERSION"
    exit 1
fi

# Create directory for global npm packages for the cbadmin user
echo "Configuring npm for global packages..."
sudo -u cbadmin mkdir -p /home/cbadmin/.npm-global

# Configure npm to use this directory for cbadmin user
echo "Configuring npm for cbadmin user..."
sudo -u cbadmin npm config set prefix /home/cbadmin/.npm-global --userconfig /home/cbadmin/.npmrc

# Add npm global bin to cbadmin's PATH
echo "Configuring PATH for cbadmin user..."
sudo -u cbadmin tee -a /home/cbadmin/.bashrc > /dev/null <<'EOF'

# Add npm global bin to PATH
export PATH="$HOME/.npm-global/bin:$PATH"
EOF

# Disable npm fund messages for cbadmin user
echo "Disabling npm fund messages..."
sudo -u cbadmin npm config set fund false --userconfig /home/cbadmin/.npmrc

# Install Claude Code globally for cbadmin user
echo "Installing Claude Code..."
sudo -u cbadmin npm install -g @anthropic-ai/claude-code

# Verify installation
echo "Verifying Claude Code installation..."
sudo -u cbadmin /home/cbadmin/.npm-global/bin/claude --version || {
    echo "Warning: Claude CLI verification failed, but installation may still be successful"
}

# Create system-wide wrapper script for easy access
echo "Creating system-wide Claude CLI wrapper..."
sudo tee /usr/local/bin/claude > /dev/null <<'EOF'
#!/bin/bash
# System-wide wrapper for Claude CLI
exec sudo -u cbadmin /home/cbadmin/.npm-global/bin/claude "$@"
EOF

sudo chmod +x /usr/local/bin/claude

# Verify system-wide access
echo "Verifying system-wide Claude CLI access..."
claude --version 2>/dev/null || echo "Claude CLI installed for cbadmin user"

# Footer indicating the script execution is complete
echo "system_add_claude.sh execution completed."
