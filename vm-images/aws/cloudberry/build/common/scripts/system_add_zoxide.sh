#!/bin/bash

# Install zoxide - a smarter cd command
# Source: https://github.com/ajeetdsouza/zoxide
# Downloads latest release binary from GitHub, adds bash hook system-wide

set -euo pipefail

echo "Executing system_add_zoxide.sh..."

# Detect architecture
case "$(uname -m)" in
  x86_64)        ARCH="x86_64" ;;
  aarch64|arm64) ARCH="aarch64" ;;
  *)             echo "ERROR: Unsupported architecture: $(uname -m)"; exit 1 ;;
esac

echo "Detected architecture: ${ARCH}"

# Fetch latest release tag
LATEST_TAG=$(curl -fsSL "https://api.github.com/repos/ajeetdsouza/zoxide/releases/latest" | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4)
if [ -z "${LATEST_TAG}" ]; then
  echo "ERROR: Failed to fetch latest release tag (possible GitHub API rate limit)"
  exit 1
fi
VERSION="${LATEST_TAG#v}"
echo "Latest zoxide release: ${LATEST_TAG}"

# Download and extract
TARBALL="zoxide-${VERSION}-${ARCH}-unknown-linux-musl.tar.gz"
DOWNLOAD_URL="https://github.com/ajeetdsouza/zoxide/releases/download/${LATEST_TAG}/${TARBALL}"

echo "Downloading from: ${DOWNLOAD_URL}"
curl -fsSL -o "/tmp/${TARBALL}" "${DOWNLOAD_URL}"
tar -xzf "/tmp/${TARBALL}" -C /tmp zoxide completions/zoxide.bash

# Install binary
sudo install -m 0755 /tmp/zoxide /usr/local/bin/zoxide

# Install bash completions
sudo mkdir -p /etc/bash_completion.d
sudo install -m 0644 /tmp/completions/zoxide.bash /etc/bash_completion.d/zoxide

# Add bash hook system-wide so zoxide activates for all users
echo "Configuring zoxide bash hook..."
sudo tee /etc/profile.d/zoxide.sh > /dev/null <<'EOF'
# zoxide shell hook - provides 'z' and 'zi' commands
eval "$(zoxide init bash)"
EOF
sudo chmod 0755 /etc/profile.d/zoxide.sh

# Cleanup
rm -f "/tmp/${TARBALL}" /tmp/zoxide
rm -rf /tmp/completions

# Verify
/usr/local/bin/zoxide --version

echo "system_add_zoxide.sh execution completed."
