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
    LATEST_URL=$(curl -fsI https://github.com/goss-org/goss/releases/latest | \
        grep -i location | \
        awk '{print $2}' | \
        tr -d '\r')
    GOSS_VERSION=$(basename "$LATEST_URL" | sed 's/^v//')
    echo "Latest version: ${GOSS_VERSION}"

    # As of v0.4.10 releases ship tarballs (goss_<ver>_linux_x86_64.tar.gz)
    # plus a combined goss_<ver>_SHA256SUMS file; the raw goss-linux-amd64
    # binary and per-file .sha256 assets no longer exist.
    TARBALL="goss_${GOSS_VERSION}_linux_x86_64.tar.gz"
    BASE_URL="https://github.com/goss-org/goss/releases/download/v${GOSS_VERSION}"

    echo "Downloading Goss ${GOSS_VERSION}..."
    curl -fsSL "${BASE_URL}/${TARBALL}" -o "${TARBALL}"

    # Download SHA256 checksums for verification
    echo "Downloading checksums for verification..."
    curl -fsSL "${BASE_URL}/goss_${GOSS_VERSION}_SHA256SUMS" -o goss_SHA256SUMS

    # Verify checksum (only the line for our tarball)
    echo "Verifying checksum..."
    grep " ${TARBALL}\$" goss_SHA256SUMS | sha256sum -c -

    # Extract and install Goss (tarball contains goss, LICENSE, README.md)
    echo "Installing Goss..."
    tar -xzf "${TARBALL}" goss
    sudo mv goss /usr/local/bin/goss
    sudo chmod 0755 /usr/local/bin/goss

    # Clean up
    rm -f "${TARBALL}" goss_SHA256SUMS
    
    # Verify installation
    echo "Verifying Goss installation..."
    goss --version
    
    echo "Goss installation completed successfully."
else
    echo "Goss is already installed: $(goss --version)"
fi

# Footer indicating the script execution is complete
echo "system_add_goss.sh execution completed."