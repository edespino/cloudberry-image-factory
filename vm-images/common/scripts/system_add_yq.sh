#!/bin/bash

# Enable strict mode for better error handling
set -euo pipefail

# Header indicating the script execution
echo "Executing system_add_yq.sh..."

# Dynamically get the latest version using GitHub redirect
echo "Fetching latest yq version..."
LATEST_URL=$(curl -sI https://github.com/mikefarah/yq/releases/latest | \
    grep -i location | \
    awk '{print $2}' | \
    tr -d '\r')
YQ_VERSION=$(basename "$LATEST_URL" | sed 's/^v//')
echo "Latest version: ${YQ_VERSION}"

# Download checksums file
echo "Downloading checksums for verification..."
curl -sL https://github.com/mikefarah/yq/releases/download/v"${YQ_VERSION}"/checksums -o checksums

# Extract checksum for Linux AMD64 binary (SHA256 is field 19)
YQ_SHA256=$(grep "^yq_linux_amd64\s" checksums | awk '{print $19}')
echo "Expected SHA256: ${YQ_SHA256}"

# Download yq binary
echo "Downloading yq binary..."
curl -sL https://github.com/mikefarah/yq/releases/download/v"${YQ_VERSION}"/yq_linux_amd64 -o yq_linux_amd64

# Verify checksum
echo "Verifying checksum..."
echo "${YQ_SHA256}  yq_linux_amd64" | sha256sum -c -

# Install to system path
echo "Installing yq..."
sudo mv yq_linux_amd64 /usr/local/bin/yq
sudo chmod 755 /usr/local/bin/yq

# Clean up
rm -f checksums

# Verify installation
echo "Verifying installation..."
yq --version

# Footer indicating the script execution is complete
echo "system_add_yq.sh execution completed."
