#!/bin/bash

# Install Dolt from the latest GitHub release
# Source: https://github.com/dolthub/dolt
# Dynamically detects OS and architecture

set -euo pipefail

echo "Executing system_add_dolt.sh..."

# Detect OS
case "$(uname -s)" in
  Linux)  OS="linux" ;;
  Darwin) OS="darwin" ;;
  *)      echo "ERROR: Unsupported OS: $(uname -s)"; exit 1 ;;
esac

# Detect architecture
case "$(uname -m)" in
  x86_64)        ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)             echo "ERROR: Unsupported architecture: $(uname -m)"; exit 1 ;;
esac

echo "Detected platform: ${OS}-${ARCH}"

# Fetch latest release tag
LATEST_TAG=$(curl -fsSL "https://api.github.com/repos/dolthub/dolt/releases/latest" | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4)
echo "Latest dolt release: ${LATEST_TAG}"

# Download and extract
TARBALL="dolt-${OS}-${ARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/dolthub/dolt/releases/download/${LATEST_TAG}/${TARBALL}"

echo "Downloading from: ${DOWNLOAD_URL}"
curl -fsSL -o "/tmp/${TARBALL}" "${DOWNLOAD_URL}"
tar xzf "/tmp/${TARBALL}" -C /tmp

# Install - tarball extracts to dolt-<os>-<arch>/bin/dolt
sudo install -m 0755 "/tmp/dolt-${OS}-${ARCH}/bin/dolt" /usr/local/bin/dolt

# Cleanup
rm -rf "/tmp/${TARBALL}" "/tmp/dolt-${OS}-${ARCH}"

# Verify
dolt version

echo "system_add_dolt.sh execution completed."
