#!/bin/bash

# Install Omnigent for a specified user via uv tool install
# Source: https://github.com/omnigent-ai/omnigent
#
# Usage:
#   system_add_omnigent.sh [username]
#   DB_USERNAME=gpadmin system_add_omnigent.sh
#
# Requires uv (system_add_uv.sh) and Node 22+ (system_add_nodejs.sh) for the
# claude/codex/pi harnesses. Installs to: ~/.local/bin/omnigent (per-user).

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

# Verify uv is available (installed system-wide to /usr/local/bin)
if ! command -v /usr/local/bin/uv > /dev/null 2>&1; then
  echo "ERROR: uv is not installed. Install uv first (system_add_uv.sh)."
  exit 1
fi

echo "Executing system_add_omnigent.sh for user '${DB_USERNAME}'..."

USER_HOME=$(eval echo "~${DB_USERNAME}")

# Install Omnigent (published PyPI wheel; bundles the prebuilt web UI, no npm build).
# uv tool install drops the omnigent/omni console scripts in ~/.local/bin.
sudo -u "${DB_USERNAME}" env HOME="${USER_HOME}" PATH="/usr/local/bin:${USER_HOME}/.local/bin:/usr/bin:/bin" \
  uv tool install --force -q --python 3.12 omnigent || {
  echo "ERROR: Omnigent install failed for user '${DB_USERNAME}'"
  exit 1
}

# Ensure ~/.local/bin is on PATH for the user's interactive shell
if ! sudo -u "${DB_USERNAME}" grep -q '\.local/bin' "${USER_HOME}/.bashrc" 2>/dev/null; then
  sudo -u "${DB_USERNAME}" tee -a "${USER_HOME}/.bashrc" > /dev/null <<'EOF'

# uv tool binaries (omnigent, etc.)
export PATH="$HOME/.local/bin:$PATH"
EOF
  echo "Added ~/.local/bin to PATH in .bashrc"
fi

# Verify installation (check binary; --version/interactive run could block)
if [[ -x "${USER_HOME}/.local/bin/omnigent" ]]; then
  echo "Omnigent installed successfully for user '${DB_USERNAME}'"
else
  echo "ERROR: Omnigent binary not found at ${USER_HOME}/.local/bin/omnigent"
  exit 1
fi

echo "system_add_omnigent.sh execution completed for user '${DB_USERNAME}'."
