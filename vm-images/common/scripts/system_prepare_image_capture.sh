#!/bin/bash

# Enable strict mode for better error handling
set -euo pipefail

# Header indicating the script execution
echo "Executing system_prepare_image_capture.sh..."

# Runs as the last provisioner, just before Packer captures the AMI. Removes
# state the build instance wrote that would otherwise ship in every image:
# the SSM agent's logs and instance registration, cloud-init's per-instance
# data and logs, and the machine ID. Configuration (/etc/amazon/ssm,
# /etc/cloud) is left in place, and the agent stays enabled so it starts on
# first boot.

# Stop the SSM agent (a snap on Ubuntu, a systemd unit elsewhere) so it
# writes nothing after the cleanup.
if command -v snap >/dev/null 2>&1 && snap list amazon-ssm-agent >/dev/null 2>&1; then
  sudo snap stop amazon-ssm-agent
elif systemctl cat amazon-ssm-agent.service >/dev/null 2>&1; then
  sudo systemctl stop amazon-ssm-agent
else
  echo "No SSM agent installed; skipping agent cleanup."
fi

# Build-time agent logs and state: registration, instance directories,
# IPC channels and the vault. The agent recreates them on first boot. The
# directories are root-only, so the contents are listed and deleted under
# sudo (a shell glob here would expand as the unprivileged build user).
for ssm_dir in /var/log/amazon/ssm /var/lib/amazon/ssm; do
  if sudo test -d "${ssm_dir}"; then
    sudo find "${ssm_dir}" -mindepth 1 -delete
  fi
done

# cloud-init: instance data, semaphores and logs, so first boot runs as a
# new instance. The machine ID is reset too, so instances launched from the
# image (and images chained from it) do not share the build instance's
# identity; an empty /etc/machine-id makes systemd generate one on first boot.
# The help text is captured first: piping it into grep -q under pipefail
# could fail the check with SIGPIPE.
cloud_init_clean_help=""
if command -v cloud-init >/dev/null 2>&1; then
  cloud_init_clean_help="$(cloud-init clean --help 2>&1 || true)"
fi
if [[ "${cloud_init_clean_help}" == *"--machine-id"* ]]; then
  sudo cloud-init clean --logs --machine-id
else
  if command -v cloud-init >/dev/null 2>&1; then
    sudo cloud-init clean --logs
  else
    echo "cloud-init not installed; skipping cloud-init cleanup."
  fi
  sudo truncate -s 0 /etc/machine-id
fi

# Footer indicating the script execution is complete
echo "system_prepare_image_capture.sh execution completed."
