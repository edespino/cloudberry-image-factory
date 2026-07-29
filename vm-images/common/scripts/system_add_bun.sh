#!/bin/bash

# Install Bun JavaScript runtime from GitHub releases
# Source: https://bun.sh
# Downloads the latest release binary directly (no pipe-to-bash)

set -euo pipefail

echo "Executing system_add_bun.sh..."

# Detect architecture
case "$(uname -m)" in
  x86_64)        ARCH="x64" ;;
  aarch64|arm64) ARCH="aarch64" ;;
  *)             echo "ERROR: Unsupported architecture: $(uname -m)"; exit 1 ;;
esac

echo "Detected architecture: ${ARCH}"

# Download latest release
ZIPFILE="bun-linux-${ARCH}.zip"
DOWNLOAD_URL="https://github.com/oven-sh/bun/releases/latest/download/${ZIPFILE}"

echo "Downloading from: ${DOWNLOAD_URL}"
curl -fsSL -o "/tmp/${ZIPFILE}" "${DOWNLOAD_URL}"

# Extract (zip contains bun-linux-<arch>/bun)
unzip -o "/tmp/${ZIPFILE}" -d /tmp

# Install
sudo install -m 0755 "/tmp/bun-linux-${ARCH}/bun" /usr/local/bin/bun

# Cleanup
rm -rf "/tmp/${ZIPFILE}" "/tmp/bun-linux-${ARCH}"

# Verify
/usr/local/bin/bun --version

echo "system_add_bun.sh execution completed."
