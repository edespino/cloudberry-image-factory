#!/bin/bash

# Install PI (pi-coding-agent) globally via npm
# Source: https://www.npmjs.com/package/@earendil-works/pi-coding-agent
# Requires Node 22.19+ (system_add_nodejs.sh). Installs the `pi` CLI to
# /usr/local/bin/pi (Node's global prefix is /usr/local).

set -euo pipefail

echo "Executing system_add_pi.sh..."

# Verify npm is available (Node installed system-wide to /usr/local)
if ! command -v /usr/local/bin/npm > /dev/null 2>&1; then
  echo "ERROR: npm is not installed. Install Node.js first (system_add_nodejs.sh)."
  exit 1
fi

echo "Using Node: $(/usr/local/bin/node --version), npm: $(/usr/local/bin/npm --version)"

# Install globally (writes into /usr/local/lib/node_modules, symlinks bin to /usr/local/bin).
# Pass PATH explicitly through sudo: sudo resets PATH to secure_path (no /usr/local/bin),
# and npm's `#!/usr/bin/env node` shebang then can't find node.
sudo env PATH="/usr/local/bin:${PATH}" /usr/local/bin/npm install -g @earendil-works/pi-coding-agent

# Verify installation (binary check; --version run non-fatally with a timeout
# so a hang can't stall the bake)
if [[ -x /usr/local/bin/pi ]]; then
  echo "PI installed successfully at /usr/local/bin/pi"
  PATH="/usr/local/bin:${PATH}" timeout 15 /usr/local/bin/pi --version || echo "Note: 'pi --version' did not print within 15s (binary is installed)"
else
  echo "ERROR: pi binary not found at /usr/local/bin/pi"
  exit 1
fi

echo "system_add_pi.sh execution completed."
