#!/bin/bash

# Install gitleaks (secret scanner) system-wide and enable a pre-commit hook
# via /etc/gitconfig's init.templatedir so new clones/inits get it automatically.
# Source: https://github.com/gitleaks/gitleaks

set -euo pipefail

echo "Executing system_add_gitleaks.sh..."

# Detect architecture (gitleaks uses x64/arm64 naming, not amd64)
case "$(uname -m)" in
  x86_64)        ARCH="x64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)             echo "ERROR: Unsupported architecture: $(uname -m)"; exit 1 ;;
esac

# Fetch latest release tag from GitHub
LATEST_TAG=$(curl -fsSL "https://api.github.com/repos/gitleaks/gitleaks/releases/latest" | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4)
if [[ -z "${LATEST_TAG}" ]]; then
  echo "ERROR: Failed to determine latest gitleaks release"
  exit 1
fi
VERSION="${LATEST_TAG#v}"
echo "Installing gitleaks ${LATEST_TAG} (linux/${ARCH})"

# Download and extract
TARBALL="gitleaks_${VERSION}_linux_${ARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/gitleaks/gitleaks/releases/download/${LATEST_TAG}/${TARBALL}"
TMP_DIR=$(mktemp -d)

curl -fsSL --retry 3 --retry-delay 5 -o "${TMP_DIR}/${TARBALL}" "${DOWNLOAD_URL}"
tar xzf "${TMP_DIR}/${TARBALL}" -C "${TMP_DIR}"

# Install binary
sudo install -m 0755 "${TMP_DIR}/gitleaks" /usr/local/bin/gitleaks
rm -rf "${TMP_DIR}"

# Create git template directory with a pre-commit hook
sudo mkdir -p /etc/git-template/hooks
sudo tee /etc/git-template/hooks/pre-commit > /dev/null <<'EOF'
#!/bin/bash
# Auto-installed by AMI bake. Bypass with `git commit --no-verify`
# or remove this file from the repo's .git/hooks/.
exec /usr/local/bin/gitleaks protect --staged --redact --verbose
EOF
sudo chmod 0755 /etc/git-template/hooks/pre-commit

# Configure git system-wide so future `git init` and `git clone` copy the hook
sudo git config --system init.templatedir /etc/git-template

# Verify
/usr/local/bin/gitleaks version
echo "init.templatedir = $(sudo git config --system --get init.templatedir)"

echo "system_add_gitleaks.sh execution completed."
