#!/bin/bash

# Configure Starship prompt globally on Rocky Linux 9

# Enable strict mode
set -euo pipefail

# Header
echo "Executing system_config_starship_prompt.sh..."

# Download and install Starship to /usr/local/bin (non-interactive)
if ! command -v starship &>/dev/null; then
  echo "Installing Starship prompt..."
  
  # Dynamically get the latest version using GitHub redirect
  echo "Fetching latest Starship version..."
  LATEST_URL=$(curl -sI https://github.com/starship/starship/releases/latest | \
      grep -i location | \
      awk '{print $2}' | \
      tr -d '\r')
  STARSHIP_VERSION=$(basename "$LATEST_URL" | sed 's/^v//')
  echo "Latest version: ${STARSHIP_VERSION}"
  
  # Download the binary directly instead of using installer script
  echo "Downloading Starship binary..."
  ARCH="x86_64"
  PLATFORM="unknown-linux-gnu"
  BINARY_URL="https://github.com/starship/starship/releases/download/v${STARSHIP_VERSION}/starship-${ARCH}-${PLATFORM}.tar.gz"
  
  curl -sL "${BINARY_URL}" -o starship.tar.gz
  
  # Download checksums for verification
  echo "Downloading checksums for verification..."
  curl -sL "https://github.com/starship/starship/releases/download/v${STARSHIP_VERSION}/starship-${ARCH}-${PLATFORM}.tar.gz.sha256" -o starship.tar.gz.sha256
  
  # Verify checksum
  echo "Verifying checksum..."
  EXPECTED_SHA256=$(cat starship.tar.gz.sha256)
  echo "${EXPECTED_SHA256}  starship.tar.gz" | sha256sum -c -
  
  # Extract and install
  echo "Installing Starship..."
  tar -xzf starship.tar.gz
  sudo mv starship /usr/local/bin/starship
  sudo chmod +x /usr/local/bin/starship
  
  # Clean up
  rm -f starship.tar.gz starship.tar.gz.sha256
  
else
  echo "Starship already installed at: $(command -v starship)"
fi

# Verify installation
if ! [ -x /usr/local/bin/starship ]; then
  echo "Error: Starship binary not found at /usr/local/bin/starship"
  exit 1
fi

# Set up global shell init for Starship via /etc/profile.d
echo "Creating /etc/profile.d/starship.sh..."
sudo tee /etc/profile.d/starship.sh > /dev/null <<'EOF'
if [ -x /usr/local/bin/starship ]; then
  eval "$(/usr/local/bin/starship init bash)"
fi
EOF

# Make profile script executable
sudo chmod +x /etc/profile.d/starship.sh

# Confirm setup
echo "Starship version:"
starship --version

# Footer
echo "system_config_starship_prompt.sh execution completed."
