#!/bin/bash

# Unified script to configure environment for database admin user
# Supports both gpadmin and cbadmin users
#
# Enhanced with Security Verification:
# - SHA256 checksum verification for all downloads
# - Content validation for configuration files
# - Removed dangerous pipe-to-shell execution patterns
# - Dynamic latest version detection for 'just' binary with SHA256SUMS verification
# - Ed25519 SSH keys instead of RSA
# - Temporary directory usage with cleanup
#
# Usage:
#   dbadmin_configure_environment.sh [username]
#   DB_USERNAME=gpadmin dbadmin_configure_environment.sh
#
# Enable strict mode for better error handling
set -euo pipefail

# Accept username as parameter or environment variable, default to gpadmin
DB_USERNAME="${1:-${DB_USERNAME:-gpadmin}}"

# Validate username (alphanumeric and underscore only)
if ! [[ "${DB_USERNAME}" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
  echo "ERROR: Invalid username '${DB_USERNAME}'. Must start with lowercase letter or underscore and contain only lowercase letters, numbers, underscores, or hyphens."
  exit 1
fi

# Verify user exists
if ! id -u "${DB_USERNAME}" > /dev/null 2>&1; then
  echo "ERROR: User '${DB_USERNAME}' does not exist. Please create the user first."
  exit 1
fi

# Header indicating the script execution
echo "Executing dbadmin_configure_environment.sh for user '${DB_USERNAME}'..."

# Execute the following commands as the database admin user
sudo -u "${DB_USERNAME}" bash <<EOF
set -euo pipefail

# Create temporary directory for downloads
TEMP_DIR=\$(mktemp -d)
cd "\$TEMP_DIR"

# Function to verify file checksum
verify_checksum() {
    local file="\$1"
    local expected_hash="\$2"
    local computed_hash

    computed_hash=\$(sha256sum "\$file" | cut -d' ' -f1)
    if [ "\$computed_hash" != "\$expected_hash" ]; then
        echo "ERROR: Checksum verification failed for \$file"
        echo "Expected: \$expected_hash"
        echo "Computed: \$computed_hash"
        exit 1
    fi
    echo "Checksum verified for \$file"
}

# Function to validate configuration file content
validate_config_file() {
    local file="\$1"
    local file_type="\$2"

    # Check for suspicious patterns
    if grep -E "(curl.*\|.*sh|wget.*\|.*sh|bash.*-c|eval|system|exec)" "\$file" >/dev/null 2>&1; then
        echo "WARNING: Suspicious command patterns found in \$file_type configuration"
        echo "Review the file content before using"
    fi

    # Check file size (reasonable limits)
    local size=\$(stat -f%z "\$file" 2>/dev/null || stat -c%s "\$file" 2>/dev/null)
    if [ "\$size" -gt 102400 ]; then  # 100KB limit
        echo "WARNING: \$file_type configuration file unusually large (\$size bytes)"
    fi

    echo "Basic validation passed for \$file_type configuration"
}

# Download and verify .vimrc configuration
echo "Downloading and verifying .vimrc..."
VIMRC_URL="https://gist.githubusercontent.com/simonista/8703722/raw/d08f2b4dc10452b97d3ca15386e9eed457a53c61/.vimrc"
VIMRC_SHA256="86e6aa922456180f9e154aa49813ac0b5c749f33041e895a2a0f1d3c9ef93a49"

wget -nv -q "\$VIMRC_URL" -O vimrc.tmp
verify_checksum "vimrc.tmp" "\$VIMRC_SHA256"
validate_config_file "vimrc.tmp" "vimrc"
cp vimrc.tmp "/home/${DB_USERNAME}/.vimrc"

# Download and verify .tmux.conf configuration
echo "Downloading and verifying .tmux.conf..."
TMUX_URL="https://raw.githubusercontent.com/tony/tmux-config/master/.tmux.conf"
TMUX_SHA256="c166f0934de53dc1e50109262626bde2ef7c1fd534e129040b7a9199ccbf02fc"

wget -nv -q "\$TMUX_URL" -O tmux.conf.tmp
verify_checksum "tmux.conf.tmp" "\$TMUX_SHA256"
validate_config_file "tmux.conf.tmp" "tmux.conf"
cp tmux.conf.tmp "/home/${DB_USERNAME}/.tmux.conf"

# Install 'just' command runner with verification
echo "Installing 'just' command runner..."
mkdir -p ~/bin

# Dynamically get the latest just version using GitHub redirect
echo "Fetching latest just version..."
LATEST_URL=\$(curl -sI https://github.com/casey/just/releases/latest | \\
    grep -i location | \\
    awk '{print \$2}' | \\
    tr -d '\r')
JUST_VERSION=\$(basename "\$LATEST_URL" | sed 's/^v//')
echo "Latest version: \${JUST_VERSION}"

# Download checksums file for verification
echo "Downloading checksums for verification..."
CHECKSUMS_URL="https://github.com/casey/just/releases/download/\${JUST_VERSION}/SHA256SUMS"
wget -nv -q "\$CHECKSUMS_URL" -O SHA256SUMS

# Detect architecture (just ships x86_64/aarch64 musl builds)
case "\$(uname -m)" in
  x86_64)        JUST_ARCH="x86_64" ;;
  aarch64|arm64) JUST_ARCH="aarch64" ;;
  *)             echo "ERROR: Unsupported architecture: \$(uname -m)"; exit 1 ;;
esac

# Extract the SHA256 hash for the specific binary
JUST_FILENAME="just-\${JUST_VERSION}-\${JUST_ARCH}-unknown-linux-musl.tar.gz"
JUST_SHA256=\$(grep "\$JUST_FILENAME" SHA256SUMS | awk '{print \$1}')
echo "Expected SHA256: \${JUST_SHA256}"

# Download the binary
JUST_URL="https://github.com/casey/just/releases/download/\${JUST_VERSION}/\${JUST_FILENAME}"
echo "Downloading just \${JUST_VERSION}..."
wget -nv -q "\$JUST_URL" -O just.tar.gz

# Verify checksum
verify_checksum "just.tar.gz" "\$JUST_SHA256"

# Extract and install
tar -xzf just.tar.gz
chmod +x just
mv just ~/bin/just

# Clean up temporary directory
cd "/home/${DB_USERNAME}"
rm -rf "\$TEMP_DIR"

# Add Apache Cloudberry (Incubating) entries to database admin user's .bashrc
echo "Configuring .bashrc for Apache Cloudberry (Incubating)..."
echo -e '\n# Add Apache Cloudberry (Incubating) entries' >> "/home/${DB_USERNAME}/.bashrc"
echo -e 'if [ -f /usr/local/cloudberry/cloudberry-env.sh ]; then\n  source /usr/local/cloudberry/cloudberry-env.sh\nfi' >> "/home/${DB_USERNAME}/.bashrc"
echo -e 'if [ -f /usr/local/cloudberry/greenplum_path.sh ]; then\n  source /usr/local/cloudberry/greenplum_path.sh\nfi' >> "/home/${DB_USERNAME}/.bashrc"
echo -e 'if [ -f /usr/local/cloudberry-db/cloudberry-env.sh ]; then\n  source /usr/local/cloudberry-db/cloudberry-env.sh\nfi' >> "/home/${DB_USERNAME}/.bashrc"
echo -e 'if [ -f /usr/local/cloudberry-db/greenplum_path.sh ]; then\n  source /usr/local/cloudberry-db/greenplum_path.sh\nfi' >> "/home/${DB_USERNAME}/.bashrc"

echo -e 'export GOPATH=~/go' >> "/home/${DB_USERNAME}/.bashrc"
echo -e 'export PATH=\${GOPATH}/bin:\${PATH}' >> "/home/${DB_USERNAME}/.bashrc"

# Configure git defaults
echo "Configuring git defaults..."
git config --global init.defaultBranch main

# Ensure the .ssh directory exists
mkdir -p "/home/${DB_USERNAME}/.ssh"

# Generate SSH key pair for database admin user if it doesn't already exist
# Using Ed25519 for better security than RSA
if [ ! -f "/home/${DB_USERNAME}/.ssh/id_ed25519" ]; then
  echo "Generating Ed25519 SSH key pair for ${DB_USERNAME}..."
  ssh-keygen -t ed25519 -f "/home/${DB_USERNAME}/.ssh/id_ed25519" -N "" -C "${DB_USERNAME}@cloudberry-build-\$(date +%Y%m%d)"
fi

# Add the public key to authorized_keys to enable passwordless SSH access
# Note: This enables passwordless access - consider if this is necessary for your use case
echo "Configuring passwordless SSH access..."
cat "/home/${DB_USERNAME}/.ssh/id_ed25519.pub" >> "/home/${DB_USERNAME}/.ssh/authorized_keys"

# Set appropriate permissions for the .ssh directory and files
chmod 700 "/home/${DB_USERNAME}/.ssh"
chmod 600 "/home/${DB_USERNAME}/.ssh/authorized_keys"
chmod 600 "/home/${DB_USERNAME}/.ssh/id_ed25519"
chmod 644 "/home/${DB_USERNAME}/.ssh/id_ed25519.pub"

# Remove any duplicate entries in authorized_keys
sort "/home/${DB_USERNAME}/.ssh/authorized_keys" | uniq > "/home/${DB_USERNAME}/.ssh/authorized_keys.tmp"
mv "/home/${DB_USERNAME}/.ssh/authorized_keys.tmp" "/home/${DB_USERNAME}/.ssh/authorized_keys"
chmod 600 "/home/${DB_USERNAME}/.ssh/authorized_keys"

echo "Environment setup and passwordless SSH configuration for ${DB_USERNAME} completed successfully."
EOF

# Footer indicating the script execution is complete
echo "dbadmin_configure_environment.sh execution completed for user '${DB_USERNAME}'."
