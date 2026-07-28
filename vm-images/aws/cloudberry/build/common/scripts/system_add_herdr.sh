#!/bin/bash

# Install herdr - agent multiplexer that lives in your terminal
# Source: https://github.com/ogulcancelik/herdr
# Dynamically detects architecture, installs the single static binary from
# the latest GitHub release (no checksums published upstream)
#
# Versioning policy: latest upstream release at build time, nothing pinned.
# Tradeoff: the image is not byte-reproducible across build days; the
# resolved release tag and `herdr --version` output are logged below so the
# baked version is recoverable from the build output, and the platform goss
# tests assert the version command runs.

set -euo pipefail

echo "Executing system_add_herdr.sh..."

# Detect architecture
case "$(uname -m)" in
  x86_64)        ARCH="x86_64" ;;
  aarch64|arm64) ARCH="aarch64" ;;
  *)             echo "ERROR: Unsupported architecture: $(uname -m)"; exit 1 ;;
esac

echo "Detected architecture: ${ARCH}"

# Fetch latest release tag
LATEST_TAG=$(curl -fsSL "https://api.github.com/repos/ogulcancelik/herdr/releases/latest" | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4)
if [ -z "${LATEST_TAG}" ]; then
  echo "ERROR: Failed to fetch latest release tag (possible GitHub API rate limit)"
  exit 1
fi
echo "Latest herdr release: ${LATEST_TAG}"

# Download binary (release assets are plain per-arch binaries)
BINARY="herdr-linux-${ARCH}"
BASE_URL="https://github.com/ogulcancelik/herdr/releases/download/${LATEST_TAG}"

echo "Downloading: ${BASE_URL}/${BINARY}"
curl -fSL -o /tmp/herdr "${BASE_URL}/${BINARY}"

# Install
sudo install -m 0755 /tmp/herdr /usr/local/bin/herdr

# Cleanup
rm -f /tmp/herdr

# Verify
/usr/local/bin/herdr --version

echo "system_add_herdr.sh execution completed."
