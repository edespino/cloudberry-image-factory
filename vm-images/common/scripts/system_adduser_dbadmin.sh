#!/bin/bash

# Unified script to create database admin user with sudo privileges
# Supports both gpadmin and cbadmin users
#
# Usage:
#   system_adduser_dbadmin.sh [username]
#   DB_USERNAME=gpadmin system_adduser_dbadmin.sh
#
# Enable strict mode for better error handling
set -euo pipefail

# Accept username as parameter or environment variable, default to gpadmin
DB_USERNAME="${1:-${DB_USERNAME:-gpadmin}}"

# Validate username (alphanumeric and underscore only)
if ! [[ "${DB_USERNAME}" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
  echo "ERROR: Invalid username '${DB_USERNAME}'. Must start with lowercase letter or underscore and contain only lowercase letters, numbers, underscores, or hyphens."
  exit 1
fi

# Header indicating the script execution
echo "Executing system_adduser_dbadmin.sh for user '${DB_USERNAME}'..."

# Create a group and user for database admin with sudo privileges
if ! getent group "${DB_USERNAME}" > /dev/null 2>&1; then
  echo "Creating group '${DB_USERNAME}'..."
  sudo groupadd "${DB_USERNAME}"
else
  echo "Group '${DB_USERNAME}' already exists, skipping creation."
fi

if ! id -u "${DB_USERNAME}" > /dev/null 2>&1; then
  echo "Creating user '${DB_USERNAME}'..."
  sudo useradd -m -g "${DB_USERNAME}" -s /bin/bash "${DB_USERNAME}"
else
  echo "User '${DB_USERNAME}' already exists, skipping creation."
fi

# Set correct home directory permissions
echo "Setting home directory permissions for '${DB_USERNAME}'..."
sudo chmod 0700 "/home/${DB_USERNAME}"

# Grant sudo privileges to database admin user without requiring a password
echo "Granting sudo privileges to '${DB_USERNAME}'..."
echo "${DB_USERNAME} ALL=(ALL) NOPASSWD:ALL" | sudo tee "/etc/sudoers.d/90-${DB_USERNAME}" > /dev/null
sudo chmod 440 "/etc/sudoers.d/90-${DB_USERNAME}"

# Footer indicating the script execution is complete
echo "system_adduser_dbadmin.sh execution completed for user '${DB_USERNAME}'."
