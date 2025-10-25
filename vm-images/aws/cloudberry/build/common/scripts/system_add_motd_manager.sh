#!/bin/bash

# Enable strict mode for better error handling
set -euo pipefail

# Header indicating the script execution
echo "Executing system_add_motd_manager.sh..."

# 1. Create template storage directory
sudo mkdir -p /usr/local/share/motd-templates

# 2. Install Cloudberry template
cat <<'EOF' | sudo tee /usr/local/share/motd-templates/cloudberry.txt >/dev/null

                ++++++++++       ++++++
              ++++++++++++++   +++++++
             ++++        +++++ ++++
            ++++          +++++++++
         =+====         =============+
       ========       =====+      =====
      ====  ====     ====           ====
     ====    ===     ===             ====
     ====            === ===         ====
     ====            ===  ==--       ===
      =====          ===== --       ====
       =====================     ======
         ============================
                           =-----=

  Apache Cloudberry (Incubating) – Public VM
EOF

# 3. Install Synx template
cat <<'EOF' | sudo tee /usr/local/share/motd-templates/synx.txt >/dev/null

    ███████████░  █               █        ███████        █               █
  ▓█              ▓█              █     ██         ██     █              █░
  █                █▒            █     █             █    ░█            ▓█
  ░█                ░█░        ██     █░             ░█     ██        ▒█
    ▒████████          ░██████        █               █        ██████░
             ░█           █           █               █     ██        ▒█
              █░          █           █               █    █            ▓█
              █           █           █               █   █              █░
  ███████████▒            █           █               █   █               █

  Synx Data Labs - Public VM
  Powered by Apache Cloudberry (Incubating)
EOF

sudo chmod 644 /usr/local/share/motd-templates/*.txt

# 4. Create default configuration file
cat <<'EOF' | sudo tee /etc/motd.conf >/dev/null
# MOTD Manager Configuration
# Valid values: cloudberry, synx
MOTD_TEMPLATE=cloudberry
EOF

sudo chmod 644 /etc/motd.conf

# 5. Install the main MOTD manager script
cat <<'EOF' | sudo tee /usr/local/sbin/motd-manager >/dev/null
#!/usr/bin/env bash

# MOTD Manager - Template-based dynamic MOTD generator
set -euo pipefail

# Load configuration
MOTD_TEMPLATE="cloudberry"
if [[ -f /etc/motd.conf ]]; then
  source /etc/motd.conf
fi

# Helper functions
hr1() { printf '%*s\n' "${COLUMNS:-80}" '' | tr ' ' '='; }
hr() { printf '%*s\n' "${COLUMNS:-80}" '' | tr ' ' '-'; }

# Gather system information
HOST="$(hostname -f 2>/dev/null || hostname)"
OS="$(. /etc/os-release; echo "$PRETTY_NAME")"
KERNEL="$(uname -r)"
UPTIME="$(uptime -p | sed 's/^up //')"
LOAD="$(cut -d' ' -f1-3 </proc/loadavg)"
MEM="$(free -h | awk '/Mem:/ {print $3 "/" $2 " used"}')"
DISK="$(df -h --output=used,size,pcent,target -x tmpfs -x devtmpfs | \
  awk 'NR>1 && $4=="/" {printf "%s/%s (%s)", $1, $2, $3}')"
IPV4="$(hostname -I 2>/dev/null | awk '{print $1}')"
SESTATE="$(getenforce 2>/dev/null || echo N/A)"

# OS-aware package counting
if command -v rpm >/dev/null 2>&1; then
    PKGCOUNT="$(rpm -qa | wc -l)"
    PKGTYPE="RPMs"
elif command -v dpkg >/dev/null 2>&1; then
    PKGCOUNT="$(dpkg -l | grep -c '^ii')"
    PKGTYPE="DEBs"
else
    PKGCOUNT="N/A"
    PKGTYPE="Pkgs"
fi

# Load and display template
TEMPLATE_FILE="/usr/local/share/motd-templates/${MOTD_TEMPLATE}.txt"
if [[ ! -f "$TEMPLATE_FILE" ]]; then
  echo "Error: Template '$MOTD_TEMPLATE' not found at $TEMPLATE_FILE" >&2
  echo "Available templates:" >&2
  ls -1 /usr/local/share/motd-templates/*.txt 2>/dev/null | xargs -n1 basename | sed 's/.txt$//' >&2
  exit 1
fi

hr1
cat "$TEMPLATE_FILE"
hr
echo "  Host:        $HOST"
echo "  OS:          $OS"
echo "  Kernel:      $KERNEL"
echo "  Uptime:      $UPTIME"
echo "  Load:        $LOAD"
echo "  Memory:      $MEM"
echo "  Root FS:     $DISK"
echo "  IPv4:        ${IPV4:-N/A}"
echo "  SELinux:     $SESTATE"
echo "  $PKGTYPE:        $PKGCOUNT"
hr

# Template-specific footer
case "$MOTD_TEMPLATE" in
  cloudberry)
    echo "  Docs: https://cloudberry.apache.org  |  User: ${USER}"
    ;;
  synx)
    echo "  Docs: https://www.synxdata.com/  |  User: ${USER}"
    ;;
  *)
    echo "  User: ${USER}"
    ;;
esac

hr1
EOF

sudo chmod +x /usr/local/sbin/motd-manager

# 6. Install the template switcher utility
cat <<'EOF' | sudo tee /usr/local/bin/motd-switch >/dev/null
#!/usr/bin/env bash

# MOTD Template Switcher
set -euo pipefail

TEMPLATE_DIR="/usr/local/share/motd-templates"
CONFIG_FILE="/etc/motd.conf"

show_help() {
  cat <<HELP
Usage: motd-switch [TEMPLATE]

Switch the MOTD template used at login.

Available templates:
$(ls -1 "$TEMPLATE_DIR"/*.txt 2>/dev/null | xargs -n1 basename | sed 's/.txt$/  - /')

Examples:
  motd-switch cloudberry    Switch to Cloudberry MOTD
  motd-switch synx          Switch to Synx MOTD
  motd-switch --help        Show this help message

Current template:
$(grep MOTD_TEMPLATE "$CONFIG_FILE" 2>/dev/null || echo "  Not configured")

To see the new MOTD immediately, run: /usr/local/sbin/motd-manager
HELP
}

if [[ $# -eq 0 ]] || [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
  show_help
  exit 0
fi

TEMPLATE="$1"
TEMPLATE_FILE="$TEMPLATE_DIR/${TEMPLATE}.txt"

if [[ ! -f "$TEMPLATE_FILE" ]]; then
  echo "Error: Template '$TEMPLATE' not found" >&2
  echo "" >&2
  show_help
  exit 1
fi

# Update configuration
sudo sed -i "s/^MOTD_TEMPLATE=.*/MOTD_TEMPLATE=$TEMPLATE/" "$CONFIG_FILE"

echo "✓ MOTD template switched to: $TEMPLATE"
echo ""
echo "Preview (will show at next login):"
echo ""
/usr/local/sbin/motd-manager
EOF

sudo chmod +x /usr/local/bin/motd-switch

# 7. Add profile.d hook for interactive shells
cat <<'EOF' | sudo tee /etc/profile.d/10-motd.sh >/dev/null
# Show dynamic MOTD for interactive logins
[ -t 1 ] && /usr/local/sbin/motd-manager
EOF

sudo chmod 644 /etc/profile.d/10-motd.sh

# Footer indicating the script execution is complete
echo "system_add_motd_manager.sh execution completed."
echo "  - Templates: cloudberry, synx"
echo "  - Default: cloudberry"
echo "  - Switch command: motd-switch [cloudberry|synx]"
