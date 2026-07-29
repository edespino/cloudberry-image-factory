#!/bin/bash

# Configure SSH agent forwarding persistence for tmux sessions
# Problem: each SSH connection creates a new agent socket at a random path.
# Tmux sessions cache the old SSH_AUTH_SOCK, so reconnected SSH breaks agent forwarding.
# Fix: symlink the live socket to a stable path that survives tmux reattach.
#
# Two layers needed:
#   /etc/profile.d/ — login shells (initial SSH connections)
#   /etc/bashrc     — non-login shells (tmux windows)

set -euo pipefail

echo "Executing system_configure_ssh_agent_tmux.sh..."

SSH_AGENT_SNIPPET='# Persist SSH agent socket for tmux reattach
if [ -n "$SSH_AUTH_SOCK" ] && [ "$SSH_AUTH_SOCK" != "$HOME/.ssh/ssh_auth_sock" ]; then
    ln -sf "$SSH_AUTH_SOCK" "$HOME/.ssh/ssh_auth_sock"
    export SSH_AUTH_SOCK="$HOME/.ssh/ssh_auth_sock"
fi'

# Layer 1: login shells via /etc/profile.d/
echo "Installing /etc/profile.d/ssh-agent-tmux.sh..."
echo "${SSH_AGENT_SNIPPET}" | sudo tee /etc/profile.d/ssh-agent-tmux.sh > /dev/null
sudo chmod 0755 /etc/profile.d/ssh-agent-tmux.sh

# Layer 2: non-login shells via /etc/bashrc (system-wide)
if ! grep -q 'ssh_auth_sock' /etc/bashrc 2>/dev/null; then
  echo "Appending SSH agent snippet to /etc/bashrc..."
  printf '\n%s\n' "${SSH_AGENT_SNIPPET}" | sudo tee -a /etc/bashrc > /dev/null
fi

echo "system_configure_ssh_agent_tmux.sh execution completed."
