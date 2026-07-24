#!/bin/bash

# Install git-profile selector command and default profile configuration
# Allows users to switch between predefined git identity profiles
#
# Usage: Called once during image build (system-wide install)
# User invokes: git-profile

set -euo pipefail

echo "Executing system_add_git_profiles.sh..."

# Deploy profile definitions
sudo tee /etc/git-profiles.yaml > /dev/null <<'EOF'
# Git identity profiles
# Format: profile_name: "Display Name <email>"
# Add new profiles here — they will appear in the git-profile selector
apache: "Ed Espino <espino@apache.org>"
EOF
sudo chmod 0644 /etc/git-profiles.yaml

# Deploy selector script
sudo tee /usr/local/bin/git-profile > /dev/null <<'SCRIPT'
#!/bin/bash

# git-profile — switch between predefined git identity profiles
# Profiles defined in /etc/git-profiles.yaml

set -euo pipefail

PROFILES_FILE="/etc/git-profiles.yaml"

if [ ! -f "$PROFILES_FILE" ]; then
  echo "ERROR: $PROFILES_FILE not found"
  exit 1
fi

# Parse profiles into arrays
declare -a NAMES=()
declare -a VALUES=()

while IFS= read -r line; do
  # Skip comments and empty lines
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line// }" ]] && continue

  name="${line%%:*}"
  value="${line#*: }"
  # Strip surrounding quotes
  value="${value#\"}"
  value="${value%\"}"

  NAMES+=("$name")
  VALUES+=("$value")
done < "$PROFILES_FILE"

if [ ${#NAMES[@]} -eq 0 ]; then
  echo "No profiles found in $PROFILES_FILE"
  exit 1
fi

# Display current config
current_name=$(git config --global user.name 2>/dev/null || echo "(not set)")
current_email=$(git config --global user.email 2>/dev/null || echo "(not set)")
echo "Current: ${current_name} <${current_email}>"
echo ""

# Show menu
echo "Select a git profile:"
for i in "${!NAMES[@]}"; do
  echo "  $((i+1))) ${NAMES[$i]} — ${VALUES[$i]}"
done
echo ""

read -rp "#? " choice

# Validate input
if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#NAMES[@]} ]; then
  echo "Invalid selection"
  exit 1
fi

idx=$((choice-1))
selected="${VALUES[$idx]}"

# Parse "Display Name <email>" format
display_name="${selected%% <*}"
email="${selected#*<}"
email="${email%>}"

git config --global user.name "$display_name"
git config --global user.email "$email"

echo "Git config set: ${display_name} <${email}>"
SCRIPT
sudo chmod 0755 /usr/local/bin/git-profile

echo "system_add_git_profiles.sh execution completed."
