#!/bin/bash

# Install Cloudsmith CLI for the rocky user via pip --user
# Source: https://help.cloudsmith.io/docs/cli
# Installs to: /home/rocky/.local/bin/cloudsmith

set -euo pipefail

echo "Executing system_add_cloudsmith_cli.sh..."

/usr/bin/python3 -m pip install --user cloudsmith-cli

# Verify installation (skip --version: current cloudsmith-cli has broken output)
if [[ -x "/home/rocky/.local/bin/cloudsmith" ]]; then
  echo "Cloudsmith CLI installed successfully at /home/rocky/.local/bin/cloudsmith"
else
  echo "ERROR: Cloudsmith CLI binary not found at /home/rocky/.local/bin/cloudsmith"
  exit 1
fi

echo "system_add_cloudsmith_cli.sh execution completed."
