#!/bin/bash

# Install ansible-core (Rocky AppStream / Ubuntu universe) plus the
# community.sops collection installed system-wide so all users can use it.
# Sources: Rocky AppStream repo; Ubuntu universe; https://galaxy.ansible.com/community/sops

set -euo pipefail

echo "Executing system_add_ansible.sh..."

# Detect the operating system
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "Cannot detect operating system"
    exit 1
fi

case "$OS" in
    rocky|rhel|centos|amzn)
        # ansible-core ships in Rocky AppStream — no EPEL needed
        sudo dnf install -y -d0 ansible-core
        ;;
    ubuntu|debian)
        # ansible-core ships in the Ubuntu universe / Debian main archive.
        # --no-install-recommends: ansible-core Recommends the full 'ansible'
        # community bundle, which pre-installs community.sops under
        # /usr/lib/python3/dist-packages/ansible_collections and makes the
        # ansible-galaxy install below a silent no-op ("Nothing to do").
        export DEBIAN_FRONTEND=noninteractive
        sudo apt-get update
        sudo apt-get install -y --no-install-recommends ansible-core
        ;;
    *)
        echo "Unsupported operating system: $OS"
        exit 1
        ;;
esac

# Install community.sops collection system-wide (default collection search path).
# The upstream requirements.yml lives in a repo cloned at runtime, which does not
# exist during the bake, so install the collection directly.
sudo /usr/bin/ansible-galaxy collection install community.sops \
  -p /usr/share/ansible/collections

# Verify — fail the build if the collection did not land at the system-wide
# path (ansible-galaxy exits 0 when it skips an already-satisfied collection,
# which goss then catches only after the AMI is baked)
/usr/bin/ansible --version
test -d /usr/share/ansible/collections/ansible_collections/community/sops
/usr/bin/ansible-galaxy collection list community.sops 2>/dev/null | grep -i community.sops || \
  echo "Warning: community.sops not listed (check collection path)"

echo "system_add_ansible.sh execution completed."
