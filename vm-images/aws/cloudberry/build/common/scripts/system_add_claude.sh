#!/bin/bash

# Install Claude Code CLI for a specified user using the native installer
# Claude Code has moved from npm to native binaries - no Node.js required
#
# Usage:
#   system_add_claude.sh [username]
#   DB_USERNAME=gpadmin system_add_claude.sh
#
# Installs to: ~/.local/bin/claude (per-user)

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

echo "Executing system_add_claude.sh for user '${DB_USERNAME}'..."

# Ensure ~/.local/bin directory exists and is in PATH
USER_HOME=$(eval echo "~${DB_USERNAME}")
sudo -u "${DB_USERNAME}" mkdir -p "${USER_HOME}/.local/bin"

# Add ~/.local/bin to PATH in .bashrc if not already present
if ! sudo -u "${DB_USERNAME}" grep -q '\.local/bin' "${USER_HOME}/.bashrc" 2>/dev/null; then
  sudo -u "${DB_USERNAME}" tee -a "${USER_HOME}/.bashrc" > /dev/null <<'EOF'

# Claude Code CLI
export PATH="$HOME/.local/bin:$PATH"
EOF
  echo "Added ~/.local/bin to PATH in .bashrc"
fi

# Install Claude Code using the native installer as the target user
echo "Installing Claude Code (native) for user '${DB_USERNAME}'..."
sudo -u "${DB_USERNAME}" bash -c 'curl -fsSL https://claude.ai/install.sh | bash' || {
  echo "ERROR: Claude Code native installer failed for user '${DB_USERNAME}'"
  exit 1
}

# Verify installation
echo "Verifying Claude Code installation..."
if sudo -u "${DB_USERNAME}" "${USER_HOME}/.local/bin/claude" --version 2>/dev/null; then
  echo "Claude Code installed successfully for user '${DB_USERNAME}'"
else
  echo "Warning: Claude CLI verification failed, but installation may still be successful"
fi

CLAUDE_BIN="${USER_HOME}/.local/bin/claude"

# Install Superpowers plugin (skills collection from obra/superpowers-marketplace).
# Scoped to the 'rocky' user only. Non-fatal: log a warning and continue on failure.
#
# claude's own `plugin marketplace add <url>` clone fails on the build instance
# (ERR_STREAM_PREMATURE_CLOSE). Pre-clone the catalog over plain HTTPS ourselves
# and register it as a LOCAL marketplace, which reads marketplace.json in place
# without a claude-driven network clone.
if [[ "${DB_USERNAME}" == "rocky" ]]; then
  echo "Installing Superpowers plugin for user '${DB_USERNAME}'..."
  SP_MARKET_DIR="${USER_HOME}/.local/share/superpowers-marketplace"

  sudo -u "${DB_USERNAME}" rm -rf "${SP_MARKET_DIR}"
  if sudo -u "${DB_USERNAME}" git clone --depth 1 https://github.com/obra/superpowers-marketplace.git "${SP_MARKET_DIR}"; then
    sudo -u "${DB_USERNAME}" env HOME="${USER_HOME}" "${CLAUDE_BIN}" plugin marketplace add "${SP_MARKET_DIR}" 2>&1 || \
      echo "Warning: failed to register local superpowers-marketplace for '${DB_USERNAME}'"
    sudo -u "${DB_USERNAME}" env HOME="${USER_HOME}" "${CLAUDE_BIN}" plugin install superpowers@superpowers-marketplace 2>&1 || \
      echo "Warning: failed to install superpowers plugin for '${DB_USERNAME}'"
  else
    echo "Warning: failed to clone superpowers-marketplace for '${DB_USERNAME}'"
  fi
fi

# Register the Omnistrate MCP server at user scope.
# Non-fatal: omctl may not be on PATH yet during early bake stages.
echo "Registering Omnistrate MCP server for user '${DB_USERNAME}'..."
sudo -u "${DB_USERNAME}" env HOME="${USER_HOME}" "${CLAUDE_BIN}" mcp add --scope user omnistrate omctl mcp start 2>&1 || \
  echo "Warning: failed to register omnistrate MCP server for '${DB_USERNAME}'"

echo "system_add_claude.sh execution completed for user '${DB_USERNAME}'."
