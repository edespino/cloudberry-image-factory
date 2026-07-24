#!/bin/bash

# Install k9s from the latest GitHub release
# Source: https://github.com/derailed/k9s
# Dynamically detects OS and architecture

set -euo pipefail

echo "Executing system_add_k9s.sh..."

# Detect OS
case "$(uname -s)" in
  Linux)  OS="Linux" ;;
  Darwin) OS="Darwin" ;;
  *)      echo "ERROR: Unsupported OS: $(uname -s)"; exit 1 ;;
esac

# Detect architecture
case "$(uname -m)" in
  x86_64)       ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)            echo "ERROR: Unsupported architecture: $(uname -m)"; exit 1 ;;
esac

echo "Detected platform: ${OS}_${ARCH}"

# Fetch latest release tag
LATEST_TAG=$(curl -fsSL "https://api.github.com/repos/derailed/k9s/releases/latest" | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4)
echo "Latest k9s release: ${LATEST_TAG}"

# Download and extract
TARBALL="k9s_${OS}_${ARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/derailed/k9s/releases/download/${LATEST_TAG}/${TARBALL}"

echo "Downloading from: ${DOWNLOAD_URL}"
curl -fsSL -o "/tmp/${TARBALL}" "${DOWNLOAD_URL}"
tar xzf "/tmp/${TARBALL}" -C /tmp k9s

# Install
sudo install -m 0755 /tmp/k9s /usr/local/bin/k9s

# Cleanup
rm -f "/tmp/${TARBALL}" /tmp/k9s

# Verify
k9s version --short

echo "system_add_k9s.sh execution completed."
