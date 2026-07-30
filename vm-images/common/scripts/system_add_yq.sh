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

# Detect architecture (yq uses amd64/arm64)
case "$(uname -m)" in
  x86_64)        ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)             echo "ERROR: Unsupported architecture: $(uname -m)"; exit 1 ;;
esac

# Download checksums file
echo "Downloading checksums for verification..."
curl -sL https://github.com/mikefarah/yq/releases/download/v"${YQ_VERSION}"/checksums -o checksums

# Extract checksum for the Linux binary (SHA256 is field 19)
YQ_SHA256=$(grep "^yq_linux_${ARCH}\s" checksums | awk '{print $19}')
echo "Expected SHA256: ${YQ_SHA256}"

# Download yq binary
echo "Downloading yq binary..."
curl -sL https://github.com/mikefarah/yq/releases/download/v"${YQ_VERSION}"/yq_linux_"${ARCH}" -o "yq_linux_${ARCH}"

# Verify checksum
echo "Verifying checksum..."
echo "${YQ_SHA256}  yq_linux_${ARCH}" | sha256sum -c -

# Install to system path
echo "Installing yq..."
sudo mv "yq_linux_${ARCH}" /usr/local/bin/yq
sudo chmod 755 /usr/local/bin/yq

# Clean up
rm -f checksums

# Verify installation
echo "Verifying installation..."
yq --version

# Footer indicating the script execution is complete
echo "system_add_yq.sh execution completed."
