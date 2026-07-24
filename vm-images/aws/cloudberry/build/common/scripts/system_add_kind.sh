#!/bin/bash

# Install kind (Kubernetes IN Docker) from the latest GitHub release
# Source: https://github.com/kubernetes-sigs/kind
# Verifies the binary against the published SHA256 checksum.

set -euo pipefail

echo "Executing system_add_kind.sh..."

# Detect architecture
case "$(uname -m)" in
  x86_64)        ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)             echo "ERROR: Unsupported architecture: $(uname -m)"; exit 1 ;;
esac

# Fetch latest release tag
LATEST_TAG=$(curl -fsSL "https://api.github.com/repos/kubernetes-sigs/kind/releases/latest" | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4)
if [[ -z "${LATEST_TAG}" ]]; then
  echo "ERROR: Failed to determine latest kind release"
  exit 1
fi
echo "Installing kind ${LATEST_TAG} (linux/${ARCH})"

# Download binary + sha256
BIN_NAME="kind-linux-${ARCH}"
BASE_URL="https://github.com/kubernetes-sigs/kind/releases/download/${LATEST_TAG}"
TMP_DIR=$(mktemp -d)

curl -fsSL --retry 3 --retry-delay 5 -o "${TMP_DIR}/${BIN_NAME}" "${BASE_URL}/${BIN_NAME}"
curl -fsSL --retry 3 --retry-delay 5 -o "${TMP_DIR}/${BIN_NAME}.sha256sum" "${BASE_URL}/${BIN_NAME}.sha256sum"

# Verify checksum
EXPECTED=$(awk '{print $1}' "${TMP_DIR}/${BIN_NAME}.sha256sum")
COMPUTED=$(sha256sum "${TMP_DIR}/${BIN_NAME}" | awk '{print $1}')
if [[ "${EXPECTED}" != "${COMPUTED}" ]]; then
  echo "ERROR: Checksum mismatch for ${BIN_NAME}"
  echo "  Expected: ${EXPECTED}"
  echo "  Computed: ${COMPUTED}"
  exit 1
fi
echo "Checksum verified: ${COMPUTED}"

# Install
sudo install -m 0755 "${TMP_DIR}/${BIN_NAME}" /usr/local/bin/kind
rm -rf "${TMP_DIR}"

# Verify
/usr/local/bin/kind version

echo "system_add_kind.sh execution completed."
