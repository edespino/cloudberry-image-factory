#!/bin/bash

# Install Cloudsmith CLI for the default (Packer SSH) user via pip --user
# Source: https://help.cloudsmith.io/docs/cli
# Installs to: ${HOME}/.local/bin/cloudsmith

set -euo pipefail

echo "Executing system_add_cloudsmith_cli.sh..."

# --break-system-packages is required on PEP 668 "externally managed"
# Python installs (Debian/Ubuntu); it is accepted (and a no-op) by any
# pip >= 23 elsewhere, and absent on older pips, so add it only when supported.
PIP_FLAGS=(--user)
if /usr/bin/python3 -m pip install --help 2>/dev/null | grep -q 'break-system-packages'; then
  PIP_FLAGS+=(--break-system-packages)
fi

/usr/bin/python3 -m pip install "${PIP_FLAGS[@]}" cloudsmith-cli

# Verify installation (skip --version: current cloudsmith-cli has broken output)
if [[ -x "${HOME}/.local/bin/cloudsmith" ]]; then
  echo "Cloudsmith CLI installed successfully at ${HOME}/.local/bin/cloudsmith"
else
  echo "ERROR: Cloudsmith CLI binary not found at ${HOME}/.local/bin/cloudsmith"
  exit 1
fi

echo "system_add_cloudsmith_cli.sh execution completed."
