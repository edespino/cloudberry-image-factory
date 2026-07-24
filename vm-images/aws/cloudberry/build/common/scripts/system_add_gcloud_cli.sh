#!/bin/bash

# Google Cloud CLI (gcloud) installation script
# Installs the official versioned tarball into /usr/local and symlinks the
# gcloud/gsutil/bq entrypoints into /usr/local/bin.
#
# Why the tarball and not the RPM repo:
# Google's RPM signing key (F09C394C3E1BA8D5, 2015) carries a SHA-1 self
# signature. Rocky/RHEL 10 use the Sequoia OpenPGP backend, whose default
# crypto policy rejects SHA-1, so both `rpm --import` and gpgcheck=1 package
# verification fail with "No binding signature". The tarball has no such key
# dependency and installs cleanly. It is downloaded over HTTPS from Google's
# host; Google publishes no checksum sidecar for the archive.
#
# Supports: Rocky Linux, RHEL, CentOS

# Enable strict mode for better error handling
set -euo pipefail

# Header indicating the script execution
echo "Executing system_add_gcloud_cli.sh..."

# Detect the operating system
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
else
    echo "Cannot detect operating system"
    exit 1
fi

echo "Detected OS: $OS $VERSION"

# Install Google Cloud CLI based on the detected OS
case "$OS" in
    rocky|rhel|centos|ubuntu|debian)
        echo "Installing Google Cloud CLI on ${OS} (distro-agnostic tarball)..."

        INSTALL_ROOT="/usr/local"
        SDK_DIR="${INSTALL_ROOT}/google-cloud-sdk"
        TARBALL="google-cloud-cli-linux-x86_64.tar.gz"
        TARBALL_URL="https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/${TARBALL}"

        # gcloud runs on the system Python (Rocky 10 ships a supported python3).
        CLOUDSDK_PY="/usr/bin/python3"

        # Download the latest stable Google Cloud CLI tarball
        echo "Downloading Google Cloud CLI tarball..."
        curl -fsSL "$TARBALL_URL" -o "/tmp/${TARBALL}"

        # Extract into /usr/local (creates /usr/local/google-cloud-sdk)
        echo "Extracting to ${INSTALL_ROOT}..."
        sudo rm -rf "$SDK_DIR"
        sudo tar -xzf "/tmp/${TARBALL}" -C "$INSTALL_ROOT"

        echo "Installed google-cloud-sdk version: $(cat "${SDK_DIR}/VERSION")"

        # Finalize install: precompile, no PATH/rc edits (we symlink instead),
        # no bundled Python fetch (use system python3), no usage reporting.
        echo "Running install.sh..."
        sudo CLOUDSDK_PYTHON="$CLOUDSDK_PY" "${SDK_DIR}/install.sh" \
            --quiet \
            --usage-reporting=false \
            --path-update=false \
            --command-completion=false \
            --bash-completion=false \
            --install-python=false

        # Symlink entrypoints onto the system PATH
        echo "Symlinking gcloud/gsutil/bq into ${INSTALL_ROOT}/bin..."
        for bin in gcloud gsutil bq; do
            sudo ln -sf "${SDK_DIR}/bin/${bin}" "${INSTALL_ROOT}/bin/${bin}"
        done

        # Pin the Python interpreter for interactive shells and source the
        # bundled bash completion.
        echo "Configuring /etc/profile.d/gcloud.sh..."
        sudo tee /etc/profile.d/gcloud.sh > /dev/null << EOF
export CLOUDSDK_PYTHON=${CLOUDSDK_PY}
if [ -f ${SDK_DIR}/completion.bash.inc ]; then
    . ${SDK_DIR}/completion.bash.inc
fi
EOF
        sudo chmod 0755 /etc/profile.d/gcloud.sh

        # Clean up
        rm -f "/tmp/${TARBALL}"
        ;;

    *)
        echo "Unsupported operating system: $OS"
        exit 1
        ;;
esac

# Verify Google Cloud CLI installation
echo "Verifying Google Cloud CLI installation..."
CLOUDSDK_PYTHON=/usr/bin/python3 /usr/local/bin/gcloud version

# Footer indicating the script execution is complete
echo "system_add_gcloud_cli.sh execution completed."
