#!/bin/bash

# Install zellij terminal multiplexer from the latest GitHub release
# Source: https://github.com/zellij-org/zellij
# Dynamically detects architecture, verifies SHA256 checksum

set -euo pipefail

echo "Executing system_add_zellij.sh..."

# Detect architecture
case "$(uname -m)" in
  x86_64)        ARCH="x86_64" ;;
  aarch64|arm64) ARCH="aarch64" ;;
  *)             echo "ERROR: Unsupported architecture: $(uname -m)"; exit 1 ;;
esac

echo "Detected architecture: ${ARCH}"

# Fetch latest release tag
LATEST_TAG=$(curl -fsSL "https://api.github.com/repos/zellij-org/zellij/releases/latest" | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4)
if [ -z "${LATEST_TAG}" ]; then
  echo "ERROR: Failed to fetch latest release tag (possible GitHub API rate limit)"
  exit 1
fi
echo "Latest zellij release: ${LATEST_TAG}"

# Download binary and checksum
TARBALL="zellij-${ARCH}-unknown-linux-musl.tar.gz"
CHECKSUM_FILE="zellij-${ARCH}-unknown-linux-musl.sha256sum"
BASE_URL="https://github.com/zellij-org/zellij/releases/download/${LATEST_TAG}"

echo "Downloading: ${BASE_URL}/${TARBALL}"
curl -fSL -o "/tmp/${TARBALL}" "${BASE_URL}/${TARBALL}"
curl -fSL -o "/tmp/${CHECKSUM_FILE}" "${BASE_URL}/${CHECKSUM_FILE}"

# Extract binary
tar -xzf "/tmp/${TARBALL}" -C /tmp zellij

# Verify SHA256 checksum against extracted binary
# The upstream sha256sum references the build path — rewrite to match our extracted path
echo "Verifying checksum..."
EXPECTED_HASH=$(awk '{print $1}' "/tmp/${CHECKSUM_FILE}")
ACTUAL_HASH=$(sha256sum /tmp/zellij | awk '{print $1}')
if [ "${EXPECTED_HASH}" != "${ACTUAL_HASH}" ]; then
  echo "ERROR: SHA256 checksum mismatch"
  echo "  Expected: ${EXPECTED_HASH}"
  echo "  Actual:   ${ACTUAL_HASH}"
  exit 1
fi
echo "Checksum verified: ${ACTUAL_HASH}"

# Install
sudo install -m 0755 /tmp/zellij /usr/local/bin/zellij

# Cleanup
rm -f "/tmp/${TARBALL}" "/tmp/${CHECKSUM_FILE}" /tmp/zellij

# Verify
/usr/local/bin/zellij --version

echo "system_add_zellij.sh execution completed."
