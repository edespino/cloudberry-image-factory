#!/bin/bash

# Unified script to install Claude CLI for database admin user
# Supports both gpadmin and cbadmin users
#
# Usage:
#   system_add_claude.sh [username]
#   DB_USERNAME=gpadmin system_add_claude.sh
#
# Enable strict mode for better error handling
set -euo pipefail

# Accept username as parameter or environment variable, default to gpadmin
DB_USERNAME="${1:-${DB_USERNAME:-gpadmin}}"

# Validate username (alphanumeric and underscore only)
if ! [[ "${DB_USERNAME}" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
  echo "ERROR: Invalid username '${DB_USERNAME}'. Must start with lowercase letter or underscore and contain only lowercase letters, numbers, underscores, or hyphens."
  exit 1
fi

# Verify user exists
if ! id -u "${DB_USERNAME}" > /dev/null 2>&1; then
  echo "ERROR: User '${DB_USERNAME}' does not exist. Please create the user first."
  exit 1
fi

# Header indicating the script execution
echo "Executing system_add_claude.sh for user '${DB_USERNAME}'..."

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

# Create directory for global npm packages for the database admin user
echo "Configuring npm for global packages for user '${DB_USERNAME}'..."
sudo -u "${DB_USERNAME}" mkdir -p "/home/${DB_USERNAME}/.npm-global"

# Configure npm to use this directory for database admin user
echo "Configuring npm for ${DB_USERNAME} user..."
sudo -u "${DB_USERNAME}" npm config set prefix "/home/${DB_USERNAME}/.npm-global" --userconfig "/home/${DB_USERNAME}/.npmrc"

# Add npm global bin to database admin user's PATH
echo "Configuring PATH for ${DB_USERNAME} user..."
sudo -u "${DB_USERNAME}" tee -a "/home/${DB_USERNAME}/.bashrc" > /dev/null <<'EOF'

# Add npm global bin to PATH
export PATH="$HOME/.npm-global/bin:$PATH"
EOF

# Disable npm fund messages for database admin user
echo "Disabling npm fund messages..."
sudo -u "${DB_USERNAME}" npm config set fund false --userconfig "/home/${DB_USERNAME}/.npmrc"

# Install Claude Code globally for database admin user
echo "Installing Claude Code for user '${DB_USERNAME}'..."
sudo -u "${DB_USERNAME}" npm install -g @anthropic-ai/claude-code

# Verify installation
echo "Verifying Claude Code installation..."
sudo -u "${DB_USERNAME}" "/home/${DB_USERNAME}/.npm-global/bin/claude" --version || {
    echo "Warning: Claude CLI verification failed, but installation may still be successful"
}

# Create system-wide wrapper script for easy access
echo "Creating system-wide Claude CLI wrapper..."
sudo tee /usr/local/bin/claude > /dev/null <<WRAPPER_EOF
#!/bin/bash
# System-wide wrapper for Claude CLI
exec sudo -u ${DB_USERNAME} /home/${DB_USERNAME}/.npm-global/bin/claude "\$@"
WRAPPER_EOF

sudo chmod +x /usr/local/bin/claude

# Verify system-wide access
echo "Verifying system-wide Claude CLI access..."
claude --version 2>/dev/null || echo "Claude CLI installed for ${DB_USERNAME} user"

# Footer indicating the script execution is complete
echo "system_add_claude.sh execution completed for user '${DB_USERNAME}'."
