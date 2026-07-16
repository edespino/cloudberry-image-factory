#!/bin/bash

# Install dysk - a better df alternative for filesystem information
# Source: https://github.com/Canop/dysk
# Downloads pre-built binary from dystroy.org (x86_64 only)

set -euo pipefail

echo "Executing system_add_dysk.sh..."

# Only install on x86_64
ARCH="$(uname -m)"
if [ "${ARCH}" != "x86_64" ]; then
  echo "SKIP: dysk binary only available for x86_64 (detected: ${ARCH})"
  exit 0
fi

# Download binary
DOWNLOAD_URL="https://dystroy.org/dysk/download/x86_64-linux/dysk"
echo "Downloading from: ${DOWNLOAD_URL}"
curl -fsSL -o /tmp/dysk "${DOWNLOAD_URL}"

# Install
sudo install -m 0755 /tmp/dysk /usr/local/bin/dysk

# Cleanup
rm -f /tmp/dysk

# Verify
/usr/local/bin/dysk --version

echo "system_add_dysk.sh execution completed."
