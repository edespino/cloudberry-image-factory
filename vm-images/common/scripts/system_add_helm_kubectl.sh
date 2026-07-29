#!/bin/bash

# Unified script to install Helm and kubectl
# Installs the latest stable versions with checksum verification
#
# Enable strict mode for better error handling
set -euo pipefail

# Timestamped logger function
log() {
  echo "[$(date -Iseconds)] $*"
}

# Function to verify file checksum
verify_checksum() {
    local file="$1"
    local expected_hash="$2"
    local computed_hash

    computed_hash=$(sha256sum "$file" | cut -d' ' -f1)
    if [ "$computed_hash" != "$expected_hash" ]; then
        log "ERROR: Checksum verification failed for $file"
        log "Expected: $expected_hash"
        log "Computed: $computed_hash"
        exit 1
    fi
    log "✓ Checksum verified for $file"
}

# Header indicating the script execution
log "Executing system_add_helm_kubectl.sh..."

# Create temporary directory for downloads
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"
log "Working in temporary directory: $TEMP_DIR"

################################
# Install Helm
################################
log "Installing Helm..."

if command -v helm &>/dev/null; then
    log "Helm is already installed: $(helm version --short 2>/dev/null || helm version)"
    log "Skipping Helm installation"
else
    # Dynamically get the latest Helm version
    log "Fetching latest Helm version..."
    LATEST_URL=$(curl -sI https://github.com/helm/helm/releases/latest | \
        grep -i location | \
        awk '{print $2}' | \
        tr -d '\r')
    HELM_VERSION=$(basename "$LATEST_URL")
    log "Latest Helm version: ${HELM_VERSION}"

    # Download Helm binary directly instead of using installer script
    HELM_ARCH="linux-amd64"
    HELM_FILENAME="helm-${HELM_VERSION}-${HELM_ARCH}.tar.gz"
    HELM_URL="https://get.helm.sh/${HELM_FILENAME}"

    log "Downloading Helm ${HELM_VERSION}..."
    curl -fsSL "$HELM_URL" -o "$HELM_FILENAME"

    # Download and verify checksum
    log "Downloading Helm checksums for verification..."
    curl -fsSL "${HELM_URL}.sha256sum" -o helm.sha256sum

    # Verify checksum
    log "Verifying Helm checksum..."
    sha256sum -c helm.sha256sum

    # Extract and install
    log "Extracting Helm binary..."
    tar -xzf "$HELM_FILENAME"

    log "Installing Helm to /usr/local/bin..."
    sudo mv ${HELM_ARCH}/helm /usr/local/bin/helm
    sudo chmod 755 /usr/local/bin/helm

    # Clean up extraction directory
    rm -rf ${HELM_ARCH}

    # Verify installation
    log "✓ Helm installation completed: $(helm version --short)"
fi

################################
# Install kubectl
################################
log "Installing kubectl..."

if command -v kubectl &>/dev/null; then
    log "kubectl is already installed: $(kubectl version --client --output=yaml 2>/dev/null | grep gitVersion || kubectl version --client --short)"
    log "Skipping kubectl installation"
else
    # Discover latest stable kubectl version
    log "Discovering latest stable kubectl version..."
    KUBECTL_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
    log "Latest kubectl version: ${KUBECTL_VERSION}"

    # Download kubectl binary
    KUBECTL_URL="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
    log "Downloading kubectl ${KUBECTL_VERSION}..."
    curl -fsSL "$KUBECTL_URL" -o kubectl

    # Download and verify checksum
    log "Downloading kubectl checksum for verification..."
    curl -fsSL "${KUBECTL_URL}.sha256" -o kubectl.sha256

    # Verify checksum
    KUBECTL_SHA256=$(cat kubectl.sha256)
    log "Verifying kubectl checksum..."
    verify_checksum "kubectl" "$KUBECTL_SHA256"

    # Install to system path
    log "Installing kubectl to /usr/local/bin..."
    sudo mv kubectl /usr/local/bin/kubectl
    sudo chmod 755 /usr/local/bin/kubectl

    # Verify installation
    log "✓ kubectl installation completed: $(kubectl version --client --output=yaml 2>/dev/null | grep gitVersion || kubectl version --client --short)"
fi

################################
# Setup bash completion (optional)
################################
log "Setting up bash completion for Helm and kubectl..."

# Create completion directory if it doesn't exist
sudo mkdir -p /etc/bash_completion.d

# Install Helm completion
if command -v helm &>/dev/null; then
    log "Installing Helm bash completion..."
    helm completion bash | sudo tee /etc/bash_completion.d/helm >/dev/null
fi

# Install kubectl completion
if command -v kubectl &>/dev/null; then
    log "Installing kubectl bash completion..."
    kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl >/dev/null
fi

################################
# Cleanup
################################
cd "$HOME"
rm -rf "$TEMP_DIR"
log "Cleaned up temporary directory"

# Display final versions
log "Installation summary:"
if command -v helm &>/dev/null; then
    log "  Helm: $(helm version --short 2>/dev/null || helm version)"
fi
if command -v kubectl &>/dev/null; then
    log "  kubectl: $(kubectl version --client --output=yaml 2>/dev/null | grep gitVersion: | awk '{print $2}' || kubectl version --client --short)"
fi

# Footer indicating the script execution is complete
log "system_add_helm_kubectl.sh execution completed."
