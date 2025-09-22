#!/bin/bash

# Enable strict mode for better error handling
set -euo pipefail

# Configuration
SWAP_SIZE="${SWAP_SIZE:-8G}"
SWAP_FILE="${SWAP_FILE:-/swapfile}"
SWAPPINESS="${SWAPPINESS:-10}"
VFS_CACHE_PRESSURE="${VFS_CACHE_PRESSURE:-50}"

# Header indicating the script execution
echo "Executing system_add_swap.sh..."
echo "Configuring swap: size=${SWAP_SIZE}, file=${SWAP_FILE}"

# Function to check if swap is already configured
check_existing_swap() {
    if swapon --show | grep -q "${SWAP_FILE}"; then
        echo "Swap already active on ${SWAP_FILE}"
        return 0
    fi
    return 1
}

# Function to safely disable existing swap
disable_existing_swap() {
    if [ -f "${SWAP_FILE}" ]; then
        echo "Disabling existing swap file: ${SWAP_FILE}"
        if swapon --show | grep -q "${SWAP_FILE}"; then
            sudo swapoff "${SWAP_FILE}" || {
                echo "Warning: Failed to disable swap file"
                return 1
            }
        fi
        sudo rm -f "${SWAP_FILE}"
        echo "Removed existing swap file"
    fi
}

# Function to create swap file
create_swap_file() {
    echo "Creating ${SWAP_SIZE} swap file at ${SWAP_FILE}..."

    # Check available disk space
    local available_space
    available_space=$(df / | awk 'NR==2 {print $4}')
    local swap_size_kb
    swap_size_kb=$(echo "${SWAP_SIZE}" | sed 's/G$//' | awk '{print $1 * 1024 * 1024}')

    if [ "${swap_size_kb}" -gt "${available_space}" ]; then
        echo "Error: Insufficient disk space for ${SWAP_SIZE} swap file"
        exit 1
    fi

    # Create swap file - prefer fallocate for speed, fallback to dd
    if command -v fallocate >/dev/null 2>&1; then
        echo "Using fallocate to create swap file..."
        # Test if fallocate works on current filesystem (Rocky Linux 10 compatibility)
        if ! sudo fallocate -l "${SWAP_SIZE}" "${SWAP_FILE}" 2>/dev/null; then
            echo "fallocate not supported on current filesystem, using dd..."
            local count
            count=$(echo "${SWAP_SIZE}" | sed 's/G$//' | awk '{print $1 * 1024}')
            sudo dd if=/dev/zero of="${SWAP_FILE}" bs=1M count="${count}" status=progress
        fi
    else
        echo "Using dd to create swap file..."
        local count
        count=$(echo "${SWAP_SIZE}" | sed 's/G$//' | awk '{print $1 * 1024}')
        sudo dd if=/dev/zero of="${SWAP_FILE}" bs=1M count="${count}" status=progress
    fi
}

# Function to configure swap file
configure_swap() {
    echo "Configuring swap file permissions and format..."

    # Set secure permissions (only root can read/write)
    sudo chmod 600 "${SWAP_FILE}"

    # Verify file ownership
    sudo chown root:root "${SWAP_FILE}"

    # Format as swap
    echo "Formatting swap file..."
    sudo mkswap "${SWAP_FILE}"

    # Enable swap
    echo "Enabling swap..."
    sudo swapon "${SWAP_FILE}"
}

# Function to configure fstab entry
configure_fstab() {
    echo "Configuring /etc/fstab entry..."

    # Remove any existing swap entries for this file
    sudo sed -i "\|${SWAP_FILE}|d" /etc/fstab

    # Add new swap entry with systemd-compatible format
    echo "${SWAP_FILE} swap swap defaults 0 0" | sudo tee -a /etc/fstab >/dev/null

    # Verify fstab entry
    if grep -q "${SWAP_FILE}" /etc/fstab; then
        echo "Successfully added swap entry to /etc/fstab"

        # Reload systemd to recognize fstab changes (Rocky Linux 10 compatibility)
        if command -v systemctl >/dev/null 2>&1; then
            echo "Reloading systemd daemon for fstab changes..."
            sudo systemctl daemon-reload
        fi
    else
        echo "Warning: Failed to add swap entry to /etc/fstab"
        return 1
    fi
}

# Function to optimize swap settings
optimize_swap_settings() {
    echo "Optimizing swap settings..."

    # Set swappiness (lower = less likely to swap)
    echo "vm.swappiness=${SWAPPINESS}" | sudo tee /etc/sysctl.d/99-swap.conf >/dev/null
    sudo sysctl vm.swappiness="${SWAPPINESS}"

    # Set vfs_cache_pressure (lower = keep directory/inode caches longer)
    echo "vm.vfs_cache_pressure=${VFS_CACHE_PRESSURE}" | sudo tee -a /etc/sysctl.d/99-swap.conf >/dev/null
    sudo sysctl vm.vfs_cache_pressure="${VFS_CACHE_PRESSURE}"

    echo "Applied swap optimization settings"
}

# Function to display swap status
show_swap_status() {
    echo "Current swap status:"
    swapon --show --bytes
    echo ""
    echo "Memory usage:"
    free -h
    echo ""
    echo "Swap settings:"
    sysctl vm.swappiness vm.vfs_cache_pressure
}

# Main execution
main() {
    # Skip if swap is already properly configured
    if check_existing_swap; then
        echo "Swap already configured, skipping setup"
        show_swap_status
        return 0
    fi

    # Disable any existing swap
    disable_existing_swap

    # Create and configure new swap
    create_swap_file
    configure_swap
    configure_fstab
    optimize_swap_settings

    # Display final status
    echo "Swap configuration completed successfully!"
    show_swap_status
}

# Execute main function
main

echo "system_add_swap.sh execution completed."
