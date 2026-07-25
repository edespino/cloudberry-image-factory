#!/bin/bash

# Install Hermes Agent for a specified user using the official installer
# Source: https://github.com/NousResearch/hermes-agent
#
# Usage:
#   system_add_hermes.sh [username]
#   DB_USERNAME=ubuntu system_add_hermes.sh
#
# Installs to: ~/.hermes (code + venv), command link at ~/.local/bin/hermes
# (per-user, so `hermes update` can self-update).
#
# Bake profile: --skip-setup (auth/config wizard is a runtime concern),
# --skip-browser (Playwright/Chromium adds hundreds of MB; install later
# with `hermes` --ensure browser if needed), --non-interactive.

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

echo "Executing system_add_hermes.sh for user '${DB_USERNAME}'..."

USER_HOME=$(eval echo "~${DB_USERNAME}")
sudo -u "${DB_USERNAME}" mkdir -p "${USER_HOME}/.local/bin"

# Run the official installer as the target user. The installer itself adds
# ~/.local/bin to the user's shell config when missing. PATH is passed
# through so the installer can find system-wide uv/node in /usr/local/bin.
echo "Installing Hermes Agent for user '${DB_USERNAME}'..."
sudo -u "${DB_USERNAME}" env PATH="/usr/local/bin:${PATH}" HOME="${USER_HOME}" bash -c \
  'curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --skip-setup --skip-browser --non-interactive' || {
  echo "ERROR: Hermes Agent installer failed for user '${DB_USERNAME}'"
  exit 1
}

# Verify installation (binary check; --version run non-fatally with a timeout
# so a hang can't stall the bake)
HERMES_BIN="${USER_HOME}/.local/bin/hermes"
if sudo -u "${DB_USERNAME}" test -x "${HERMES_BIN}"; then
  echo "Hermes Agent installed successfully at ${HERMES_BIN} for user '${DB_USERNAME}'"
  sudo -u "${DB_USERNAME}" env HOME="${USER_HOME}" timeout 30 "${HERMES_BIN}" --version \
    || echo "Note: 'hermes --version' did not print within 30s (binary is installed)"
else
  echo "ERROR: hermes binary not found at ${HERMES_BIN}"
  exit 1
fi

echo "system_add_hermes.sh execution completed."
