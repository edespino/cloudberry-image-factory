#!/bin/bash

# Install omnistrate-ctl from the latest GitHub release
# Source: https://github.com/omnistrate-oss/omnistrate-ctl
# Dynamically detects OS and architecture

set -euo pipefail

echo "Executing system_add_omnistrate_ctl.sh..."

# Detect OS
case "$(uname -s)" in
  Linux)  OS="linux" ;;
  Darwin) OS="darwin" ;;
  *)      echo "ERROR: Unsupported OS: $(uname -s)"; exit 1 ;;
esac

# Detect architecture
case "$(uname -m)" in
  x86_64)       ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)            echo "ERROR: Unsupported architecture: $(uname -m)"; exit 1 ;;
esac

echo "Detected platform: ${OS}-${ARCH}"

# Fetch latest release tag
LATEST_TAG=$(curl -fsSL "https://api.github.com/repos/omnistrate-oss/omnistrate-ctl/releases/latest" | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4)
echo "Latest omnistrate-ctl release: ${LATEST_TAG}"

# Download and extract
TARBALL="omnistrate-ctl-${OS}-${ARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/omnistrate-oss/omnistrate-ctl/releases/download/${LATEST_TAG}/${TARBALL}"

echo "Downloading from: ${DOWNLOAD_URL}"
curl -fsSL -o "/tmp/${TARBALL}" "${DOWNLOAD_URL}"
tar xzf "/tmp/${TARBALL}" -C /tmp

# Install
sudo install -m 0755 "/tmp/omnistrate-ctl-${OS}-${ARCH}" /usr/local/bin/omnistrate-ctl

# Add `omctl` symlink — that's the upstream binary's canonical name,
# and several omnistrate commands (e.g. `omctl mcp start`) assume it.
sudo ln -sf /usr/local/bin/omnistrate-ctl /usr/local/bin/omctl

# Cleanup
rm -f "/tmp/${TARBALL}" "/tmp/omnistrate-ctl-${OS}-${ARCH}"

# Verify
omnistrate-ctl --version

echo "system_add_omnistrate_ctl.sh execution completed."
