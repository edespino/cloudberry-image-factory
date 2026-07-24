#!/bin/bash

# Install PI (pi-coding-agent) for a specified user via npm
# Source: https://www.npmjs.com/package/@earendil-works/pi-coding-agent
# Requires Node 22.19+ (system_add_nodejs.sh).
#
# Usage:
#   system_add_pi.sh [username]
#   DB_USERNAME=rocky system_add_pi.sh
#
# Installs to: ~/.local/bin/pi (per-user npm prefix ~/.local)
#
# A per-user prefix (instead of a root-owned global install to /usr/local)
# keeps the install path writable by the user, so `pi update` can
# self-update. A root-owned install fails with:
#   "error: pi cannot self-update this installation."

set -euo pipefail

# Accept username as parameter or environment variable
DB_USERNAME="${1:-${DB_USERNAME:?Set DB_USERNAME or pass a username argument}}"

# Validate username (lowercase alphanumeric, underscore, hyphen)
if ! [[ "${DB_USERNAME}" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
  echo "ERROR: Invalid username '${DB_USERNAME}'."
  exit 1
fi

# Verify user exists
if ! id -u "${DB_USERNAME}" > /dev/null 2>&1; then
  echo "ERROR: User '${DB_USERNAME}' does not exist. Please create the user first."
  exit 1
fi

echo "Executing system_add_pi.sh for user '${DB_USERNAME}'..."

# Verify npm is available (Node installed system-wide to /usr/local)
if ! command -v /usr/local/bin/npm > /dev/null 2>&1; then
  echo "ERROR: npm is not installed. Install Node.js first (system_add_nodejs.sh)."
  exit 1
fi

echo "Using Node: $(/usr/local/bin/node --version), npm: $(/usr/local/bin/npm --version)"

USER_HOME=$(eval echo "~${DB_USERNAME}")
sudo -u "${DB_USERNAME}" mkdir -p "${USER_HOME}/.local/bin"

# Add ~/.local/bin to PATH in .bashrc if not already present
if ! sudo -u "${DB_USERNAME}" grep -q '\.local/bin' "${USER_HOME}/.bashrc" 2>/dev/null; then
  sudo -u "${DB_USERNAME}" tee -a "${USER_HOME}/.bashrc" > /dev/null <<'EOF'

# User-local binaries (npm --prefix ~/.local installs, etc.)
export PATH="$HOME/.local/bin:$PATH"
EOF
  echo "Added ~/.local/bin to PATH in .bashrc"
fi

# Install into the user's own prefix so the install path stays user-writable.
# PATH is passed explicitly: npm's `#!/usr/bin/env node` shebang needs to find
# node, and sudo resets PATH to secure_path (no /usr/local/bin).
sudo -u "${DB_USERNAME}" env PATH="/usr/local/bin:${PATH}" \
  /usr/local/bin/npm install -g --prefix "${USER_HOME}/.local" @earendil-works/pi-coding-agent

# Verify installation (binary check; --version run non-fatally with a timeout
# so a hang can't stall the bake)
PI_BIN="${USER_HOME}/.local/bin/pi"
if sudo -u "${DB_USERNAME}" test -x "${PI_BIN}"; then
  echo "PI installed successfully at ${PI_BIN} for user '${DB_USERNAME}'"
  sudo -u "${DB_USERNAME}" env PATH="/usr/local/bin:${PATH}" timeout 15 "${PI_BIN}" --version \
    || echo "Note: 'pi --version' did not print within 15s (binary is installed)"
else
  echo "ERROR: pi binary not found at ${PI_BIN}"
  exit 1
fi

echo "system_add_pi.sh execution completed."
