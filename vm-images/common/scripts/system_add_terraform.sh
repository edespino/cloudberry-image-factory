#!/bin/bash

# Install Terraform from the official HashiCorp releases server
# Source: https://releases.hashicorp.com/terraform/
# Verifies the binary against the published SHA256SUMS.

set -euo pipefail

echo "Executing system_add_terraform.sh..."

# Detect architecture (HashiCorp uses amd64/arm64)
case "$(uname -m)" in
  x86_64)        ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)             echo "ERROR: Unsupported architecture: $(uname -m)"; exit 1 ;;
esac

# Determine latest version via HashiCorp checkpoint API
VERSION=$(curl -fsSL "https://checkpoint-api.hashicorp.com/v1/check/terraform" | grep -o '"current_version":"[^"]*"' | cut -d'"' -f4)
if [[ -z "${VERSION}" ]]; then
  echo "ERROR: Failed to determine latest Terraform version"
  exit 1
fi
echo "Installing Terraform ${VERSION} (linux/${ARCH})"

# Download zip + checksums
ZIP="terraform_${VERSION}_linux_${ARCH}.zip"
BASE_URL="https://releases.hashicorp.com/terraform/${VERSION}"
TMP_DIR=$(mktemp -d)

curl -fsSL --retry 3 --retry-delay 5 -o "${TMP_DIR}/${ZIP}" "${BASE_URL}/${ZIP}"
curl -fsSL --retry 3 --retry-delay 5 -o "${TMP_DIR}/SHA256SUMS" "${BASE_URL}/terraform_${VERSION}_SHA256SUMS"

# Verify checksum
EXPECTED=$(grep "  ${ZIP}\$" "${TMP_DIR}/SHA256SUMS" | awk '{print $1}')
COMPUTED=$(sha256sum "${TMP_DIR}/${ZIP}" | awk '{print $1}')
if [[ -z "${EXPECTED}" || "${EXPECTED}" != "${COMPUTED}" ]]; then
  echo "ERROR: Checksum mismatch for ${ZIP}"
  echo "  Expected: ${EXPECTED}"
  echo "  Computed: ${COMPUTED}"
  exit 1
fi
echo "Checksum verified: ${COMPUTED}"

# Install
unzip -o "${TMP_DIR}/${ZIP}" -d "${TMP_DIR}"
sudo install -m 0755 "${TMP_DIR}/terraform" /usr/local/bin/terraform
rm -rf "${TMP_DIR}"

# Verify
/usr/local/bin/terraform version

echo "system_add_terraform.sh execution completed."
