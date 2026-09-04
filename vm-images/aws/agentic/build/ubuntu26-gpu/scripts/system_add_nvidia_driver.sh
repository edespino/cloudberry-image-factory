#!/bin/bash

# Install the NVIDIA server driver stack for the linux-aws kernel
# Source: Ubuntu archive, `restricted` component
#
# Installs the prebuilt, signed kernel-module metapackage that tracks the
# linux-aws kernel (no DKMS), the matching server driver, and nvidia-utils
# (nvidia-smi), then holds all three so a later `apt upgrade` cannot move the
# driver branch or unmatch kernel and modules. The driver packages blacklist
# nouveau and rebuild the initramfs; the reboot that follows in main.pkr.hcl
# is what unloads nouveau and loads the nvidia module. Do not modprobe here.

set -euo pipefail

echo "Executing system_add_nvidia_driver.sh..."

# NVIDIA production branch by default; 595 is the verified alternative.
NVIDIA_BRANCH="${NVIDIA_BRANCH:-580}"
echo "NVIDIA driver branch: ${NVIDIA_BRANCH}"

PACKAGES=(
  "linux-modules-nvidia-${NVIDIA_BRANCH}-server-aws"
  "nvidia-driver-${NVIDIA_BRANCH}-server"
  "nvidia-utils-${NVIDIA_BRANCH}-server"
)

# The base image ships with empty apt lists
sudo apt-get update

echo "Installing: ${PACKAGES[*]}"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${PACKAGES[@]}"

echo "Holding the driver set against apt upgrade..."
sudo apt-mark hold "${PACKAGES[@]}"

echo "Installed NVIDIA packages:"
dpkg -l | grep -E "nvidia-(driver|utils)-${NVIDIA_BRANCH}-server|linux-modules-nvidia-${NVIDIA_BRANCH}-server-aws"

# The module metapackage tracks the newest installed linux-aws kernel. Confirm
# an nvidia module exists for the kernel that boots next (the newest installed
# one, which may differ from the running kernel if the base upgraded it
# without rebooting).
# dpkg-query exits 1 when nothing matches; keep the pipeline alive so the
# empty result reaches the explicit check below instead of tripping pipefail.
NEXT_KERNEL=$({ dpkg-query -W -f='${Package} ${db:Status-Status}\n' 'linux-image-[0-9]*-aws' 2>/dev/null || true; } \
  | awk '$2 == "installed" {print $1}' | sed 's/^linux-image-//' | sort -V | tail -n 1)
if [ -z "${NEXT_KERNEL}" ]; then
  echo "ERROR: no installed linux-image-*-aws kernel found"
  exit 1
fi
echo "Running kernel: $(uname -r); next-boot kernel: ${NEXT_KERNEL}"
if ! MODULE_VERSION=$(modinfo -k "${NEXT_KERNEL}" -F version nvidia); then
  echo "ERROR: no nvidia module available for kernel ${NEXT_KERNEL}"
  exit 1
fi
echo "nvidia module ${MODULE_VERSION} available for kernel ${NEXT_KERNEL}"

echo "system_add_nvidia_driver.sh execution completed."
