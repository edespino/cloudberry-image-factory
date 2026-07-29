#!/bin/bash

# Enable strict mode for better error handling
set -euo pipefail

# Header indicating the script execution
echo "Executing system_add_synxdb_cloud_dependencies.sh..."

export DEBIAN_FRONTEND=noninteractive

# Update the package cache
sudo apt-get update

# Install basic utilities
# (gnupg replaces the RPM platforms' gnupg2; required for AWS CLI GPG verification)
sudo apt-get install -y \
     bc \
     ca-certificates \
     curl \
     git \
     gnupg \
     jq \
     make \
     time \
     tree \
     vim \
     wget

# tmux 3.4 ships in the Ubuntu 24.04 (noble) archive, so no source build is
# needed (Rocky 10 builds tmux 3.4 from source because it only packages a
# 3.3a pre-release snapshot).
sudo apt-get install -y tmux

# Additional tools (EPEL equivalents live in the Ubuntu universe repository,
# which is enabled by default on Ubuntu 24.04 cloud images)
sudo apt-get install -y htop bat ripgrep bats btop

# Debian/Ubuntu install bat's binary as /usr/bin/batcat to avoid a historical
# name clash; symlink the conventional name onto the PATH.
sudo ln -sf /usr/bin/batcat /usr/local/bin/bat

# NOTE: The Rocky 10 kernel-modules-extra upgrade is intentionally omitted:
# Ubuntu AWS kernels ship xt_addrtype/br_netfilter (needed by Docker) in the
# default linux-modules-*-aws package, so no kernel upgrade or reboot is needed.

# Python tooling: Debian/Ubuntu disable ensurepip and mark the system Python
# as PEP 668 externally managed, so pip and venv support come from apt.
sudo apt-get install -y python3 python3-pip python3-venv

# Install network and system tools
# bubblewrap (bwrap): general sandboxing utility
# lsb-release: required by common provisioners that add APT repos via `lsb_release -cs`
# `which` is provided by debianutils (preinstalled essential package) — no package to install
sudo apt-get install -y \
     bind9-dnsutils \
     bubblewrap \
     iproute2 \
     less \
     lsb-release \
     lsof \
     netcat-openbsd \
     net-tools \
     passwd \
     rsync \
     sshpass \
     sudo \
     tar \
     unzip \
     util-linux \
     wget

#Cleanup
sudo apt-get clean

# Footer indicating the script execution is complete
echo "system_add_synxdb_cloud_dependencies.sh execution completed."
