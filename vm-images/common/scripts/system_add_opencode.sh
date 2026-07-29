#!/bin/bash

# Install OpenCode CLI for the default SSH user (runs as current user)
# Source: https://opencode.ai
#
# Installs to: ~/.opencode/bin/opencode

set -euo pipefail

echo "Executing system_add_opencode.sh..."

curl -fsSL https://opencode.ai/install | bash

echo "system_add_opencode.sh execution completed."
