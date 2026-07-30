#!/bin/bash

# Note: If the Go version is updated, remember to update the corresponding testinfra test
# script (test_golang_install.py) to verify the correct version.

# Enable strict mode for better error handling
set -euo pipefail

# Header indicating the script execution
echo "Executing system_add_golang.sh..."

# Official GO Download page - https://go.dev/dl/
# Hardcoded Go version and per-architecture SHA256 checksums
GO_VERSION="go1.26.1"
case "$(uname -m)" in
  x86_64)
    GO_ARCH="amd64"
    GO_SHA256="031f088e5d955bab8657ede27ad4e3bc5b7c1ba281f05f245bcc304f327c987a"
    ;;
  aarch64|arm64)
    GO_ARCH="arm64"
    GO_SHA256="a290581cfe4fe28ddd737dde3095f3dbeb7f2e4065cab4eae44dfc53b760c2f7"
    ;;
  *)
    echo "ERROR: Unsupported architecture: $(uname -m)"; exit 1
    ;;
esac
GO_TARBALL="${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
GO_URL="https://go.dev/dl/${GO_TARBALL}"

echo "GO_VERSION=${GO_VERSION}"

# Download Go tarball
wget -nv "${GO_URL}"

# Verify the checksum
echo "${GO_SHA256}  ${GO_TARBALL}" | sha256sum -c -

# Extract and move Go
tar xf "${GO_TARBALL}"
sudo mv go "/opt/${GO_VERSION}"
rm -f "${GO_TARBALL}"

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
