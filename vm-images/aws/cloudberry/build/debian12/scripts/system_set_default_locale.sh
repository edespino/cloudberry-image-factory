#!/bin/bash
# Enable strict mode for better error handling
set -euo pipefail

# Header indicating the script execution
echo "Executing system_set_default_locale.sh..."

# Update package lists
sudo apt-get update

# Install locales package (Debian-specific)
sudo apt-get install -y locales

# Display current locale settings
echo "Current locale settings:"
locale

# Enable en_US.UTF-8 in /etc/locale.gen (Debian requires this)
sudo sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen

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
