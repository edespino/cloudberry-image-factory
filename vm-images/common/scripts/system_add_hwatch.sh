#!/bin/bash

# Install hwatch - a modern alternative to the watch command
# Source: https://github.com/blacknon/hwatch
# Dynamically detects architecture, installs from latest GitHub release

set -euo pipefail

echo "Executing system_add_hwatch.sh..."

# Detect architecture
case "$(uname -m)" in
  x86_64)        ARCH="x86_64" ;;
  aarch64|arm64) ARCH="aarch64" ;;
  *)             echo "ERROR: Unsupported architecture: $(uname -m)"; exit 1 ;;
esac

echo "Detected architecture: ${ARCH}"

# Fetch latest release tag
LATEST_TAG=$(curl -fsSL "https://api.github.com/repos/blacknon/hwatch/releases/latest" | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4)
if [ -z "${LATEST_TAG}" ]; then
  echo "ERROR: Failed to fetch latest release tag (possible GitHub API rate limit)"
  exit 1
fi
echo "Latest hwatch release: ${LATEST_TAG}"

# Download binary
TARBALL="hwatch-${LATEST_TAG}.${ARCH}-unknown-linux-musl.tar.gz"
BASE_URL="https://github.com/blacknon/hwatch/releases/download/${LATEST_TAG}"

echo "Downloading: ${BASE_URL}/${TARBALL}"
curl -fSL -o "/tmp/${TARBALL}" "${BASE_URL}/${TARBALL}"

# Extract and install
tar -xzf "/tmp/${TARBALL}" -C /tmp bin/hwatch --strip-components=1
sudo install -m 0755 /tmp/hwatch /usr/local/bin/hwatch

# Cleanup
rm -f "/tmp/${TARBALL}" /tmp/hwatch

# Verify
/usr/local/bin/hwatch --version

echo "system_add_hwatch.sh execution completed."
