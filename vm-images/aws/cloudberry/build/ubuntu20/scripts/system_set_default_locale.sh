#!/bin/bash
# Enable strict mode for better error handling
set -euo pipefail

# Header indicating the script execution
echo "Executing system_set_default_locale.sh..."

# Update package lists
sudo apt-get update

# Ensure the universe repository is enabled
sudo add-apt-repository universe

# Update package lists again after adding universe repository
sudo apt-get update

# Install language-pack-en which includes locales
sudo apt-get install -y language-pack-en

# Display current locale settings
echo "Current locale settings:"
locale

# Generate en_US.UTF-8 locale
sudo locale-gen en_US.UTF-8

# Display current /etc/default/locale content
echo "Current /etc/default/locale content:"
cat /etc/default/locale

# Set system-wide locale to en_US.UTF-8
sudo update-locale LANG=en_US.UTF-8

# Display updated /etc/default/locale content
echo "Updated /etc/default/locale content:"
cat /etc/default/locale

# Footer indicating the script execution is complete
echo "system_set_default_locale.sh execution completed."
