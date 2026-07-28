#!/bin/bash

# Unified script to configure system limits (ulimits) for database admin user
# Supports both gpadmin and cbadmin users
#
# Usage:
#   system_add_dbadmin_ulimits.sh [username]
#   DB_USERNAME=gpadmin system_add_dbadmin_ulimits.sh
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
echo "Executing system_add_dbadmin_ulimits.sh for user '${DB_USERNAME}'..."

# Create the limits configuration file for database admin user
echo "Creating limits configuration for '${DB_USERNAME}'..."
cat <<EOF | sudo tee "/etc/security/limits.d/90-db-${DB_USERNAME}-limits.conf" > /dev/null
# /etc/security/limits.d/90-db-${DB_USERNAME}-limits.conf

# Core dump file size limits for ${DB_USERNAME}
${DB_USERNAME} soft core unlimited
${DB_USERNAME} hard core unlimited

# Open file limits for ${DB_USERNAME}
${DB_USERNAME} soft nofile 524288
${DB_USERNAME} hard nofile 524288

# Process limits for ${DB_USERNAME}
${DB_USERNAME} soft nproc 131072
${DB_USERNAME} hard nproc 131072
EOF

# Set ownership and permissions for the limits configuration file
echo "Setting permissions on limits configuration file..."
sudo chown root:root "/etc/security/limits.d/90-db-${DB_USERNAME}-limits.conf"
sudo chmod 644 "/etc/security/limits.d/90-db-${DB_USERNAME}-limits.conf"

# Footer indicating the script execution is complete
echo "system_add_dbadmin_ulimits.sh execution completed for user '${DB_USERNAME}'."
