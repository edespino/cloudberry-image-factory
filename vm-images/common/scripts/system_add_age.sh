#!/bin/bash

# Install age (modern file encryption) — official static binary
# Source: https://github.com/FiloSottile/age
# Pinned to v1.3.1. Installs age + age-keygen to /usr/local/bin.
# (age releases ship only per-file sigstore .proof bundles, no checksums.txt,
#  so no simple sha256 verification is performed here.)

set -euo pipefail

echo "Executing system_add_age.sh..."

AGE_VERSION="v1.3.1"

# Detect architecture (age uses amd64/arm64)
case "$(uname -m)" in
  x86_64)        ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)             echo "ERROR: Unsupported architecture: $(uname -m)"; exit 1 ;;
esac

echo "Installing age ${AGE_VERSION} (linux/${ARCH})"

TARBALL="age-${AGE_VERSION}-linux-${ARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/FiloSottile/age/releases/download/${AGE_VERSION}/${TARBALL}"
TMP_DIR=$(mktemp -d)

curl -fsSL --retry 3 --retry-delay 5 -o "${TMP_DIR}/age.tgz" "${DOWNLOAD_URL}"
tar xzf "${TMP_DIR}/age.tgz" -C "${TMP_DIR}"

# Install (tarball extracts to an age/ directory)
sudo install -m 0755 "${TMP_DIR}/age/age"        /usr/local/bin/age
sudo install -m 0755 "${TMP_DIR}/age/age-keygen" /usr/local/bin/age-keygen
rm -rf "${TMP_DIR}"

# Verify
/usr/local/bin/age --version
/usr/local/bin/age-keygen --version

echo "system_add_age.sh execution completed."
