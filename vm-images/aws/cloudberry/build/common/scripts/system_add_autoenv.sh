#!/bin/bash

# Install autoenv for automatic .env file sourcing on directory change
# Source: https://github.com/hyperupcall/autoenv
# Unlike direnv, autoenv can source functions (no subprocess isolation)

set -euo pipefail

echo "Executing system_add_autoenv.sh..."

# Clone autoenv to /opt/autoenv
if [ -d /opt/autoenv ]; then
  echo "autoenv already exists at /opt/autoenv, updating..."
  cd /opt/autoenv && sudo git pull
else
  echo "Cloning autoenv..."
  sudo git clone https://github.com/hyperupcall/autoenv.git /opt/autoenv
fi

# Create profile.d hook for all users
echo "Configuring autoenv shell hook..."
sudo tee /etc/profile.d/autoenv.sh > /dev/null <<'EOF'
# autoenv - automatic .env file sourcing
# Skip for Claude Code shells: the snapshot replay calls `cd` without
# the autoenv function definition, emitting spurious "command not found" noise.
[ -n "$CLAUDECODE" ] && return 0
export AUTOENV_ENV_FILENAME=".env"
export AUTOENV_ENV_LEAVE_FILENAME=".env.leave"
export AUTOENV_ENABLE_LEAVE="yes"
source /opt/autoenv/activate.sh
EOF
sudo chmod 0755 /etc/profile.d/autoenv.sh

# Verify activation script exists
if [ ! -f /opt/autoenv/activate.sh ]; then
  echo "ERROR: /opt/autoenv/activate.sh not found after clone"
  exit 1
fi

echo "system_add_autoenv.sh execution completed."
