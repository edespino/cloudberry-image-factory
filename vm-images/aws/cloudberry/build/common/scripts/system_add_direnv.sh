#!/bin/bash

# Install direnv from the latest GitHub release and configure shell hook
# Source: https://github.com/direnv/direnv
# Dynamically detects OS and architecture

set -euo pipefail

echo "Executing system_add_direnv.sh..."

# Detect OS
case "$(uname -s)" in
  Linux)  OS="linux" ;;
  Darwin) OS="darwin" ;;
  *)      echo "ERROR: Unsupported OS: $(uname -s)"; exit 1 ;;
esac

# Detect architecture
case "$(uname -m)" in
  x86_64)       ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)            echo "ERROR: Unsupported architecture: $(uname -m)"; exit 1 ;;
esac

echo "Detected platform: ${OS}-${ARCH}"

# Fetch latest release tag
LATEST_TAG=$(curl -fsSL "https://api.github.com/repos/direnv/direnv/releases/latest" | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4)
echo "Latest direnv release: ${LATEST_TAG}"

# Download binary
BINARY="direnv.${OS}-${ARCH}"
DOWNLOAD_URL="https://github.com/direnv/direnv/releases/download/${LATEST_TAG}/${BINARY}"

echo "Downloading from: ${DOWNLOAD_URL}"
curl -fsSL -o "/tmp/direnv" "${DOWNLOAD_URL}"

# Install
sudo install -m 0755 /tmp/direnv /usr/local/bin/direnv

# Cleanup
rm -f /tmp/direnv

# Add bash hook system-wide so direnv activates for all users
echo "Configuring direnv bash hook..."
sudo tee /etc/profile.d/direnv.sh > /dev/null <<'EOF'
# direnv shell hook
eval "$(direnv hook bash)"
alias da='direnv allow'
alias dr='direnv reload'
EOF
sudo chmod 0755 /etc/profile.d/direnv.sh

# Verify
direnv version

echo "system_add_direnv.sh execution completed."
