#!/bin/bash

# Install Node.js 22 LTS system-wide from the official nodejs.org binary tarball
# Source: https://nodejs.org/dist/
# Verifies the tarball against the published SHASUMS256.txt.
# Needed by omnigent's claude/codex/pi harnesses (require Node 22.10+).

set -euo pipefail

echo "Executing system_add_nodejs.sh..."

# Detect architecture (Node uses x64/arm64)
case "$(uname -m)" in
  x86_64)        ARCH="x64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)             echo "ERROR: Unsupported architecture: $(uname -m)"; exit 1 ;;
esac

# Determine the latest Node 22.x release from the dist index
VERSION=$(curl -fsSL https://nodejs.org/dist/index.json | \
  grep -o '"version":"v22\.[0-9.]*"' | head -1 | cut -d'"' -f4)
if [[ -z "${VERSION}" ]]; then
  echo "ERROR: Failed to determine latest Node 22.x version"
  exit 1
fi
echo "Installing Node.js ${VERSION} (linux/${ARCH})"

# Download tarball + checksums
TARBALL="node-${VERSION}-linux-${ARCH}.tar.xz"
BASE_URL="https://nodejs.org/dist/${VERSION}"
TMP_DIR=$(mktemp -d)

curl -fsSL --retry 3 --retry-delay 5 -o "${TMP_DIR}/${TARBALL}" "${BASE_URL}/${TARBALL}"
curl -fsSL --retry 3 --retry-delay 5 -o "${TMP_DIR}/SHASUMS256.txt" "${BASE_URL}/SHASUMS256.txt"

# Verify checksum
EXPECTED=$(grep "  ${TARBALL}\$" "${TMP_DIR}/SHASUMS256.txt" | awk '{print $1}')
COMPUTED=$(sha256sum "${TMP_DIR}/${TARBALL}" | awk '{print $1}')
if [[ -z "${EXPECTED}" || "${EXPECTED}" != "${COMPUTED}" ]]; then
  echo "ERROR: Checksum mismatch for ${TARBALL}"
  echo "  Expected: ${EXPECTED}"
  echo "  Computed: ${COMPUTED}"
  exit 1
fi
echo "Checksum verified: ${COMPUTED}"

# Extract into /usr/local (strip the top-level node-vX-linux-ARCH/ directory),
# placing node/npm/npx in /usr/local/bin and modules in /usr/local/lib/node_modules
tar xJf "${TMP_DIR}/${TARBALL}" -C "${TMP_DIR}"
sudo cp -a "${TMP_DIR}/node-${VERSION}-linux-${ARCH}/." /usr/local/
rm -rf "${TMP_DIR}"

# Verify
/usr/local/bin/node --version
/usr/local/bin/npm --version

echo "system_add_nodejs.sh execution completed."
