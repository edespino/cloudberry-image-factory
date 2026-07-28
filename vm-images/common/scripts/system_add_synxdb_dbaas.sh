#!/bin/bash

# Script to download and install SynxDB DBaaS offline package
# Requires CLOUDSMITH_USER and CLOUDSMITH_TOKEN environment variables
#
# Usage:
#   CLOUDSMITH_USER=user CLOUDSMITH_TOKEN=token system_add_synxdb_dbaas.sh
#   CLOUDSMITH_USER=user CLOUDSMITH_TOKEN=token INSTALL_USER=gpadmin system_add_synxdb_dbaas.sh
#
# Enable strict mode for better error handling
set -euo pipefail

# Timestamped logger function
log() {
  echo "[$(date -Iseconds)] $*"
}

# Function to verify file integrity
verify_archive() {
    local file="$1"
    local min_size="${2:-1048576}"  # Default minimum size: 1MB

    # Check file exists
    if [ ! -f "$file" ]; then
        log "ERROR: Archive file not found: $file"
        exit 1
    fi

    # Check file size (reasonable sanity check)
    local file_size
    file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)

    if [ "$file_size" -lt "$min_size" ]; then
        log "ERROR: Archive file too small ($file_size bytes). Expected at least $min_size bytes."
        log "This may indicate a failed or incomplete download."
        exit 1
    fi

    log "✓ Archive size verified: $file_size bytes"

    # Verify it's actually a gzip file
    if ! file "$file" | grep -q "gzip compressed"; then
        log "ERROR: File does not appear to be a valid gzip archive"
        log "File type: $(file "$file")"
        exit 1
    fi

    log "✓ Archive format verified: gzip compressed data"
}

# Function to safely extract archive
safe_extract() {
    local archive="$1"
    local dest_dir="$2"
    local owner="$3"

    log "Extracting archive contents..."

    # List contents first for visibility (limit to first 50 files)
    log "Archive contents preview (first 50 files):"
    tar tzf "$archive" | head -n 50

    # Extract with verbose output
    if [ "$owner" != "$(whoami)" ] && [ -n "$owner" ]; then
        log "Extracting directly to $dest_dir with sudo (owner: '$owner')"

        # Use sudo to extract directly to destination
        # This requires temporary read permission on the archive
        sudo tar xzf "$archive" -C "$dest_dir"
    else
        log "Extracting to: $dest_dir"
        tar xzf "$archive" -C "$dest_dir"
    fi

    log "✓ Extraction completed successfully"
}

# Header indicating the script execution
log "Executing system_add_synxdb_dbaas.sh..."

################################
# Validate Environment Variables
################################
log "Validating required environment variables..."

# Check for required credentials
if [ -z "${CLOUDSMITH_USER:-}" ]; then
    log "ERROR: CLOUDSMITH_USER environment variable is not set"
    log "Usage: CLOUDSMITH_USER=user CLOUDSMITH_TOKEN=token $0"
    exit 1
fi

if [ -z "${CLOUDSMITH_TOKEN:-}" ]; then
    log "ERROR: CLOUDSMITH_TOKEN environment variable is not set"
    log "Usage: CLOUDSMITH_USER=user CLOUDSMITH_TOKEN=token $0"
    exit 1
fi

log "✓ Cloudsmith credentials found (user: ${CLOUDSMITH_USER})"

# Optional: specify installation user (defaults to gpadmin, can be cbadmin or current user)
INSTALL_USER="${INSTALL_USER:-gpadmin}"
log "Target installation user: ${INSTALL_USER}"

# Validate target user exists
if ! id -u "${INSTALL_USER}" >/dev/null 2>&1; then
    log "WARNING: User '${INSTALL_USER}' does not exist"
    log "Falling back to current user: $(whoami)"
    INSTALL_USER="$(whoami)"
fi

# Set installation directory
INSTALL_DIR="/home/${INSTALL_USER}"
if [ ! -d "$INSTALL_DIR" ]; then
    log "ERROR: Installation directory does not exist: $INSTALL_DIR"
    exit 1
fi

log "Installation directory: $INSTALL_DIR"

################################
# Create Temporary Working Directory
################################
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"
log "Working in temporary directory: $TEMP_DIR"

################################
# Download SynxDB DBaaS Offline Package
################################
PACKAGE_FILENAME="synxdb-dbaas-offline-package.tar.gz"
CLOUDSMITH_URL="https://dl.cloudsmith.io/basic/synx/internal-releng/raw/files/${PACKAGE_FILENAME}"

log "Downloading SynxDB DBaaS offline package..."
log "Source: Cloudsmith (synx/internal-releng)"

# Download with authentication
# Note: curl progress bar is used, but errors will still be visible
if ! curl -u "${CLOUDSMITH_USER}:${CLOUDSMITH_TOKEN}" \
     -fL --progress-bar \
     -o "$PACKAGE_FILENAME" \
     "$CLOUDSMITH_URL"; then
    log "ERROR: Failed to download package from Cloudsmith"
    log "Possible causes:"
    log "  - Invalid credentials"
    log "  - Package not found"
    log "  - Network issues"
    log "  - Insufficient permissions"
    cd "$HOME"
    rm -rf "$TEMP_DIR"
    exit 1
fi

log "✓ Download completed: $PACKAGE_FILENAME"

################################
# Verify Downloaded Package
################################
log "Verifying downloaded package..."
verify_archive "$PACKAGE_FILENAME" 1048576  # Minimum 1MB

################################
# Extract Package
################################
log "Extracting SynxDB DBaaS offline package..."

# Get list of top-level items before extraction (for ownership setting)
EXTRACTED_FILES=$(tar tzf "$PACKAGE_FILENAME" | cut -d/ -f1 | sort -u)

safe_extract "$PACKAGE_FILENAME" "$INSTALL_DIR" "$INSTALL_USER"

# Free up space immediately by removing the archive after extraction
log "Removing archive to free up disk space..."
rm -f "$PACKAGE_FILENAME"
log "✓ Archive removed"

################################
# Set Correct Ownership
################################
if [ "$INSTALL_USER" != "$(whoami)" ]; then
    log "Setting ownership to ${INSTALL_USER}..."
    # Set ownership on extracted files
    for item in $EXTRACTED_FILES; do
        if [ -e "${INSTALL_DIR}/${item}" ]; then
            log "Setting ownership: ${INSTALL_DIR}/${item}"
            sudo chown -R "${INSTALL_USER}:${INSTALL_USER}" "${INSTALL_DIR}/${item}"
        fi
    done
fi

################################
# Cleanup
################################
log "Cleaning up temporary files..."
cd "$HOME"
rm -rf "$TEMP_DIR"
log "✓ Cleaned up temporary directory"

################################
# Summary
################################
log "Installation summary:"
log "  Package: SynxDB DBaaS offline package"
log "  Installed to: ${INSTALL_DIR}"
log "  Owner: ${INSTALL_USER}"
log "  Extracted files:"

# List top-level items that were extracted (use sudo if needed)
if [ "$INSTALL_USER" != "$(whoami)" ]; then
    EXTRACTED_ITEMS=$(sudo find "$INSTALL_DIR" -maxdepth 1 -type d -o -type f 2>/dev/null | grep -v "^${INSTALL_DIR}$" | head -n 20)
else
    EXTRACTED_ITEMS=$(find "$INSTALL_DIR" -maxdepth 1 -type d -o -type f 2>/dev/null | grep -v "^${INSTALL_DIR}$" | head -n 20)
fi

if [ -n "$EXTRACTED_ITEMS" ]; then
    echo "$EXTRACTED_ITEMS" | while read -r item; do
        log "    - $(basename "$item")"
    done
else
    log "    (Could not enumerate extracted files)"
fi

# Footer indicating the script execution is complete
log "system_add_synxdb_dbaas.sh execution completed."
