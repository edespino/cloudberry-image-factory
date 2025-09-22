#!/bin/bash

# Note: If the Go version is updated, remember to update the corresponding testinfra test
# script (test_golang_install.py) to verify the correct version.

# Enable strict mode for better error handling
set -euo pipefail

# Header indicating the script execution
echo "Executing system_add_golang.sh..."

# Official GO Download page - https://go.dev/dl/
# Hardcoded Go version and SHA256 checksum
GO_VERSION="go1.25.1"
GO_SHA256="7716a0d940a0f6ae8e1f3b3f4f36299dc53e31b16840dbd171254312c41ca12e"
GO_URL="https://go.dev/dl/${GO_VERSION}.linux-amd64.tar.gz"

echo "GO_VERSION=${GO_VERSION}"

# Download Go tarball
wget -nv "${GO_URL}"

# Verify the checksum
echo "${GO_SHA256}  ${GO_VERSION}.linux-amd64.tar.gz" | sha256sum -c -

# Extract and move Go
tar xf "${GO_VERSION}.linux-amd64.tar.gz"
sudo mv go "/opt/${GO_VERSION}"
rm -f "${GO_VERSION}.linux-amd64.tar.gz"

# Update the symbolic link
sudo rm -rf /opt/go
sudo ln -s "/opt/${GO_VERSION}" /opt/go

# Ensure /opt/go/bin is in the PATH for all users
echo 'export PATH=$PATH:/opt/go/bin' | sudo tee -a /etc/profile.d/go.sh > /dev/null

# Apply the new PATH to the current session
export PATH=$PATH:/opt/go/bin

# Verify installation
/opt/go/bin/go version

# Footer indicating the script execution is complete
echo "system_add_golang.sh execution completed."
