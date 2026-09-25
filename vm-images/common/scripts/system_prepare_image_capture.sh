#!/bin/bash

# Enable strict mode for better error handling
set -euo pipefail

# Header indicating the script execution
echo "Executing system_prepare_image_capture.sh..."

# Runs as the last provisioner, just before Packer captures the AMI. Removes
# state the build instance wrote that would otherwise ship in every image:
# the SSM agent's logs and instance registration, and cloud-init's
# per-instance data and logs. Configuration (/etc/amazon/ssm, /etc/cloud) is
# left in place, and the agent stays enabled so it starts on first boot.

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
# IPC channels and the vault. The agent recreates them on first boot.
sudo rm -rf /var/log/amazon/ssm/* /var/lib/amazon/ssm/*

# cloud-init: instance data, semaphores and logs, so first boot runs as a
# new instance.
if command -v cloud-init >/dev/null 2>&1; then
  sudo cloud-init clean --logs
else
  echo "cloud-init not installed; skipping cloud-init cleanup."
fi

# Footer indicating the script execution is complete
echo "system_prepare_image_capture.sh execution completed."
