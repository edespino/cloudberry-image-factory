#!/bin/bash

# Enable strict mode for better error handling
set -euo pipefail

# Header indicating the script execution
echo "Executing system_add_goss.sh..."

# Function to verify file checksum
verify_checksum() {
    local file="$1"
    local expected_hash="$2"
    local computed_hash
    
    computed_hash=$(sha256sum "$file" | cut -d' ' -f1)
    if [ "$computed_hash" != "$expected_hash" ]; then
        echo "ERROR: Checksum verification failed for $file"
        echo "Expected: $expected_hash"
        echo "Computed: $computed_hash"
        exit 1
    fi
    echo "Checksum verified for $file"
}

# Install Goss for testing
if ! command -v goss &>/dev/null; then
    echo "Installing Goss testing framework..."
    
    # Dynamically get the latest Goss version
    echo "Fetching latest Goss version..."
    LATEST_URL=$(curl -sI https://github.com/goss-org/goss/releases/latest | \
        grep -i location | \
        awk '{print $2}' | \
        tr -d '\r')
    GOSS_VERSION=$(basename "$LATEST_URL" | sed 's/^v//')
    echo "Latest version: ${GOSS_VERSION}"
    
    # Download the Goss binary
    GOSS_URL="https://github.com/goss-org/goss/releases/download/v${GOSS_VERSION}/goss-linux-amd64"
    echo "Downloading Goss ${GOSS_VERSION}..."
    curl -sL "$GOSS_URL" -o goss-linux-amd64
    
    # Download SHA256 checksums for verification
    echo "Downloading checksums for verification..."
    curl -sL "https://github.com/goss-org/goss/releases/download/v${GOSS_VERSION}/goss-linux-amd64.sha256" -o goss.sha256
    
    # Verify checksum (file already contains hash and filename)
    echo "Verifying checksum..."
    sha256sum -c goss.sha256
    
    # Install Goss
    echo "Installing Goss..."
    sudo mv goss-linux-amd64 /usr/local/bin/goss
    sudo chmod +x /usr/local/bin/goss
    
    # Clean up
    rm -f goss.sha256
    
    # Verify installation
    echo "Verifying Goss installation..."
    goss --version
    
    echo "Goss installation completed successfully."
else
    echo "Goss is already installed: $(goss --version)"
fi

# Footer indicating the script execution is complete
echo "system_add_goss.sh execution completed."