#!/bin/bash

# Install beads (bd) from the latest GitHub release
# Source: https://github.com/steveyegge/beads
# Dynamically detects OS and architecture

set -euo pipefail

echo "Executing system_add_beads.sh..."

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

# Fetch latest release tag and derive version number
LATEST_TAG=$(curl -fsSL "https://api.github.com/repos/steveyegge/beads/releases/latest" | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4)
VERSION="${LATEST_TAG#v}"
echo "Latest beads release: ${LATEST_TAG} (${VERSION})"

# Download and extract
TARBALL="beads_${VERSION}_${OS}_${ARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/steveyegge/beads/releases/download/${LATEST_TAG}/${TARBALL}"

echo "Downloading from: ${DOWNLOAD_URL}"
curl -fsSL -o "/tmp/${TARBALL}" "${DOWNLOAD_URL}"
tar xzf "/tmp/${TARBALL}" -C /tmp

# Install - binary is named "bd"
sudo install -m 0755 /tmp/bd /usr/local/bin/bd

# Cleanup
rm -f "/tmp/${TARBALL}" /tmp/bd

# Verify
bd --version

echo "system_add_beads.sh execution completed."
