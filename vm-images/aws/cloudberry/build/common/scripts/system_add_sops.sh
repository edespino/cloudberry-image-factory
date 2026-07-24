#!/bin/bash

# Install sops (secrets management) — official static binary
# Source: https://github.com/getsops/sops
# Pinned to v3.13.1. Verifies against the published checksums.txt.

set -euo pipefail

echo "Executing system_add_sops.sh..."

SOPS_VERSION="v3.13.1"

# Detect architecture (sops uses amd64/arm64)
case "$(uname -m)" in
  x86_64)        ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)             echo "ERROR: Unsupported architecture: $(uname -m)"; exit 1 ;;
esac

echo "Installing sops ${SOPS_VERSION} (linux/${ARCH})"

BIN_NAME="sops-${SOPS_VERSION}.linux.${ARCH}"
BASE_URL="https://github.com/getsops/sops/releases/download/${SOPS_VERSION}"
TMP_DIR=$(mktemp -d)

curl -fsSL --retry 3 --retry-delay 5 -o "${TMP_DIR}/sops" "${BASE_URL}/${BIN_NAME}"
curl -fsSL --retry 3 --retry-delay 5 -o "${TMP_DIR}/checksums.txt" "${BASE_URL}/sops-${SOPS_VERSION}.checksums.txt"

# Verify checksum (checksums.txt lists each artifact by its release name)
EXPECTED=$(grep "${BIN_NAME}\$" "${TMP_DIR}/checksums.txt" | awk '{print $1}')
COMPUTED=$(sha256sum "${TMP_DIR}/sops" | awk '{print $1}')
if [[ -z "${EXPECTED}" || "${EXPECTED}" != "${COMPUTED}" ]]; then
  echo "ERROR: Checksum mismatch for ${BIN_NAME}"
  echo "  Expected: ${EXPECTED}"
  echo "  Computed: ${COMPUTED}"
  exit 1
fi
echo "Checksum verified: ${COMPUTED}"

# Install
sudo install -m 0755 "${TMP_DIR}/sops" /usr/local/bin/sops
rm -rf "${TMP_DIR}"

# Verify (--disable-version-check skips sops's network update check)
/usr/local/bin/sops --version --disable-version-check

echo "system_add_sops.sh execution completed."
