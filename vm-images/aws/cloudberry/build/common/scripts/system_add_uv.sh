#!/bin/bash

# Install uv (Python package/tool manager) system-wide from the latest GitHub release
# Source: https://github.com/astral-sh/uv
# Verifies the binary against the published .sha256.

set -euo pipefail

echo "Executing system_add_uv.sh..."

# Detect architecture (uv uses GNU triple naming)
case "$(uname -m)" in
  x86_64)        TRIPLE="x86_64-unknown-linux-gnu" ;;
  aarch64|arm64) TRIPLE="aarch64-unknown-linux-gnu" ;;
  *)             echo "ERROR: Unsupported architecture: $(uname -m)"; exit 1 ;;
esac

# Fetch latest release tag
LATEST_TAG=$(curl -fsSL "https://api.github.com/repos/astral-sh/uv/releases/latest" | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4)
if [[ -z "${LATEST_TAG}" ]]; then
  echo "ERROR: Failed to determine latest uv release"
  exit 1
fi
echo "Installing uv ${LATEST_TAG} (${TRIPLE})"

# Download tarball + checksum
TARBALL="uv-${TRIPLE}.tar.gz"
BASE_URL="https://github.com/astral-sh/uv/releases/download/${LATEST_TAG}"
TMP_DIR=$(mktemp -d)

curl -fsSL --retry 3 --retry-delay 5 -o "${TMP_DIR}/${TARBALL}" "${BASE_URL}/${TARBALL}"
curl -fsSL --retry 3 --retry-delay 5 -o "${TMP_DIR}/${TARBALL}.sha256" "${BASE_URL}/${TARBALL}.sha256"

# Verify checksum (the .sha256 references the artifact by name)
EXPECTED=$(awk '{print $1}' "${TMP_DIR}/${TARBALL}.sha256")
COMPUTED=$(sha256sum "${TMP_DIR}/${TARBALL}" | awk '{print $1}')
if [[ -z "${EXPECTED}" || "${EXPECTED}" != "${COMPUTED}" ]]; then
  echo "ERROR: Checksum mismatch for ${TARBALL}"
  echo "  Expected: ${EXPECTED}"
  echo "  Computed: ${COMPUTED}"
  exit 1
fi
echo "Checksum verified: ${COMPUTED}"

# Extract and install uv + uvx (tarball contains a uv-${TRIPLE}/ directory)
tar xzf "${TMP_DIR}/${TARBALL}" -C "${TMP_DIR}"
sudo install -m 0755 "${TMP_DIR}/uv-${TRIPLE}/uv"  /usr/local/bin/uv
sudo install -m 0755 "${TMP_DIR}/uv-${TRIPLE}/uvx" /usr/local/bin/uvx
rm -rf "${TMP_DIR}"

# Verify
/usr/local/bin/uv --version

echo "system_add_uv.sh execution completed."
