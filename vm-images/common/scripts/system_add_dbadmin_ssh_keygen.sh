#!/bin/bash

# Enable strict mode for better error handling
set -euo pipefail

# Header indicating the script execution
echo "Executing system_add_dbadmin_ssh_keygen.sh..."

# Installs cloudberry-dbadmin-ssh-keygen.service, a first-boot oneshot that
# gives gpadmin and cbadmin a per-instance Ed25519 key pair. The image ships
# no key pair for them (it would be shared by every instance); cluster nodes
# trust each other once the launcher's lkeyx exchanges the public keys.
#
# Contract with cloudberry-dev-env-launcher (lkeyx):
# - /home/<user>/.ssh/id_ed25519 (no passphrase, 0600, owned by the user) is
#   generated only if missing and never rotated; id_ed25519.pub is a regular
#   file.
# - authorized_keys exists (0600) and starts empty.
# - /var/lib/cloudberry/dbadmin-ssh-keys.ready is written when both users are
#   done. Users that do not exist are skipped.
# The unit runs after cloud-init, so an image builder chained from this image
# (ubuntu26-gpu) can create the marker in user_data and never generate keys
# on the builder. system_prepare_image_capture.sh also removes the keys and
# the marker before capture.

sudo install -d -m 0755 /usr/local/sbin
sudo tee /usr/local/sbin/cloudberry-dbadmin-ssh-keygen > /dev/null <<'SCRIPT'
#!/bin/bash
# Generate per-instance SSH keys for gpadmin and cbadmin (first boot only).
set -euo pipefail

marker="${CLOUDBERRY_DBADMIN_SSH_MARKER:-/var/lib/cloudberry/dbadmin-ssh-keys.ready}"

for user in gpadmin cbadmin; do
  if ! id -u "${user}" > /dev/null 2>&1; then
    echo "cloudberry-dbadmin-ssh-keygen: ${user} does not exist; skipping."
    continue
  fi
  home="$(getent passwd "${user}" | cut -d: -f6)"
  uid="$(id -u "${user}")"
  ssh_dir="${home}/.ssh"
  # Existing paths must be what the contract says: no symlinks, the
  # directory a directory, the rest regular files, all owned by the user.
  for path in "${ssh_dir}" "${ssh_dir}/id_ed25519" "${ssh_dir}/id_ed25519.pub" "${ssh_dir}/authorized_keys"; do
    if [ -L "${path}" ]; then
      echo "cloudberry-dbadmin-ssh-keygen: refusing symlink ${path}" >&2
      exit 1
    fi
    [ -e "${path}" ] || continue
    if [ "${path}" = "${ssh_dir}" ]; then
      [ -d "${path}" ] || { echo "cloudberry-dbadmin-ssh-keygen: ${path} is not a directory" >&2; exit 1; }
    elif [ ! -f "${path}" ]; then
      echo "cloudberry-dbadmin-ssh-keygen: ${path} is not a regular file" >&2
      exit 1
    fi
    if [ -z "$(find "${path}" -maxdepth 0 -uid "${uid}")" ]; then
      echo "cloudberry-dbadmin-ssh-keygen: ${path} is not owned by ${user}" >&2
      exit 1
    fi
  done
  runuser -u "${user}" -- install -d -m 0700 "${ssh_dir}"
  if [ ! -f "${ssh_dir}/id_ed25519" ]; then
    runuser -u "${user}" -- ssh-keygen -q -t ed25519 -N "" \
      -C "${user}@$(hostname -s)" -f "${ssh_dir}/id_ed25519"
  elif [ ! -f "${ssh_dir}/id_ed25519.pub" ]; then
    runuser -u "${user}" -- sh -c 'ssh-keygen -y -f "$1" > "$2"' sh \
      "${ssh_dir}/id_ed25519" "${ssh_dir}/id_ed25519.pub"
  fi
  if [ ! -f "${ssh_dir}/authorized_keys" ]; then
    runuser -u "${user}" -- touch "${ssh_dir}/authorized_keys"
  fi
  chmod 0600 "${ssh_dir}/id_ed25519" "${ssh_dir}/authorized_keys"
  chmod 0644 "${ssh_dir}/id_ed25519.pub"
done

install -d -m 0755 "$(dirname "${marker}")"
touch "${marker}"
SCRIPT
sudo chmod 0755 /usr/local/sbin/cloudberry-dbadmin-ssh-keygen

sudo tee /etc/systemd/system/cloudberry-dbadmin-ssh-keygen.service > /dev/null <<'UNIT'
[Unit]
Description=Generate per-instance SSH keys for gpadmin and cbadmin
After=local-fs.target cloud-init.service
Before=ssh.service sshd.service
ConditionPathExists=!/var/lib/cloudberry/dbadmin-ssh-keys.ready

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/cloudberry-dbadmin-ssh-keygen

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable cloudberry-dbadmin-ssh-keygen.service

# Footer indicating the script execution is complete
echo "system_add_dbadmin_ssh_keygen.sh execution completed."
