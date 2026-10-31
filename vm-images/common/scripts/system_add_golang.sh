#!/bin/bash

# Note: If the Go version is updated, remember to update the corresponding testinfra test
# script (test_golang_install.py) to verify the correct version.

# Enable strict mode for better error handling
set -euo pipefail

# Header indicating the script execution
echo "Executing system_add_golang.sh..."

# Official GO Download page - https://go.dev/dl/
# Hardcoded Go version and per-architecture SHA256 checksums
GO_VERSION="go1.26.10"
case "$(uname -m)" in
  x86_64)
    GO_ARCH="amd64"
    GO_SHA256="ccfe7ae822d2c2f41f4fe7c956199967a4dac22d0ee0d2b2bfdb440aab3b20c5"
    ;;
  aarch64|arm64)
    GO_ARCH="arm64"
    GO_SHA256="3f4227ce7b206a513e794f1393adb473a07b46e94d18bd15d1c684bbb7319797"
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
