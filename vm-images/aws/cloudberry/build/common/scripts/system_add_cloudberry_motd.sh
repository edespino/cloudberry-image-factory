#!/bin/bash

# Enable strict mode for better error handling
set -euo pipefail

# Header indicating the script execution
echo "Executing system_add_cloudberry_motd.sh..."

# 1. Install the MOTD generator
cat <<'EOF' | sudo tee /usr/local/sbin/cloudberry-motd >/dev/null
#!/usr/bin/env bash
hr1() { printf '%*s\n' "${COLUMNS:-80}" '' | tr ' ' '='; }
hr() { printf '%*s\n' "${COLUMNS:-80}" '' | tr ' ' '-'; }

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

hr1
cat << 'LOGO'

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

LOGO
echo
echo "  Apache Cloudberry (Incubating) – Public VM"
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
echo "  Docs: https://cloudberry.apache.org  |  User: ${USER}"
hr1

EOF

sudo chmod +x /usr/local/sbin/cloudberry-motd

# 2. Add a profile.d hook so interactive shells show it
cat <<'EOF' | sudo tee /etc/profile.d/10-cloudberry-motd.sh >/dev/null
# Show dynamic MOTD for interactive logins
[ -t 1 ] && /usr/local/sbin/cloudberry-motd
EOF

sudo chmod 644 /etc/profile.d/10-cloudberry-motd.sh

# Footer indicating the script execution is complete
echo "system_add_cloudberry_motd.sh execution completed."
