#!/bin/bash

# Install OpenTofu from the latest GitHub release
# Source: https://github.com/opentofu/opentofu
# Verifies the binary against the published SHA256SUMS.

set -euo pipefail

echo "Executing system_add_tofu.sh..."

# Detect architecture (OpenTofu uses amd64/arm64)
case "$(uname -m)" in
  x86_64)        ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)             echo "ERROR: Unsupported architecture: $(uname -m)"; exit 1 ;;
esac

# Fetch latest release tag
LATEST_TAG=$(curl -fsSL "https://api.github.com/repos/opentofu/opentofu/releases/latest" | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4)
if [[ -z "${LATEST_TAG}" ]]; then
  echo "ERROR: Failed to determine latest OpenTofu release"
  exit 1
fi
VERSION="${LATEST_TAG#v}"
echo "Installing OpenTofu ${LATEST_TAG} (linux/${ARCH})"

# Download tarball + checksums
TARBALL="tofu_${VERSION}_linux_${ARCH}.tar.gz"
BASE_URL="https://github.com/opentofu/opentofu/releases/download/${LATEST_TAG}"
TMP_DIR=$(mktemp -d)

curl -fsSL --retry 3 --retry-delay 5 -o "${TMP_DIR}/${TARBALL}" "${BASE_URL}/${TARBALL}"
curl -fsSL --retry 3 --retry-delay 5 -o "${TMP_DIR}/SHA256SUMS" "${BASE_URL}/tofu_${VERSION}_SHA256SUMS"

# Verify checksum
EXPECTED=$(grep "  ${TARBALL}\$" "${TMP_DIR}/SHA256SUMS" | awk '{print $1}')
COMPUTED=$(sha256sum "${TMP_DIR}/${TARBALL}" | awk '{print $1}')
if [[ -z "${EXPECTED}" || "${EXPECTED}" != "${COMPUTED}" ]]; then
  echo "ERROR: Checksum mismatch for ${TARBALL}"
  echo "  Expected: ${EXPECTED}"
  echo "  Computed: ${COMPUTED}"
  exit 1
fi
echo "Checksum verified: ${COMPUTED}"

# Install
tar xzf "${TMP_DIR}/${TARBALL}" -C "${TMP_DIR}"
sudo install -m 0755 "${TMP_DIR}/tofu" /usr/local/bin/tofu
rm -rf "${TMP_DIR}"

# Verify
/usr/local/bin/tofu version

echo "system_add_tofu.sh execution completed."
