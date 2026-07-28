#!/bin/bash

# Enable strict mode for better error handling
set -euo pipefail

# Header indicating the script execution
echo "Executing system_add_synxdb_cloud_dependencies.sh..."

# Update the package cache
sudo dnf makecache

# Install EPEL repository and import GPG keys for EPEL and Rocky Linux
sudo dnf install -y -d0 epel-release
sudo rpm --import http://download.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-10
sudo rpm --import https://dl.rockylinux.org/pub/sig/8/cloud/x86_64/cloud-kernel/RPM-GPG-KEY-Rocky-SIG-Cloud

# Update the package cache again to include the new repository
sudo dnf makecache

# Disable EPEL repositories to avoid conflicts
sudo dnf config-manager --disable epel

# Install basic utilities
sudo dnf install -y -d0 bc git make vim wget time tree gnupg2 jq

# Install tmux build dependencies and build tmux 3.4 from source
# (Rocky 10 ships a pre-release snapshot packaged as 3.3a)
sudo dnf install -y -d0 automake autoconf libevent-devel ncurses-devel bison gcc
cd /tmp && git clone --branch 3.4 --depth 1 https://github.com/tmux/tmux.git
cd /tmp/tmux && sh autogen.sh && ./configure && make -j$(nproc) && sudo make install
rm -rf /tmp/tmux
hash -r

# Install additional tools from EPEL repository
sudo dnf install -y -d0 --enablerepo=epel htop bat ripgrep bats btop

# Docker on Rocky 10 needs xt_addrtype/br_netfilter from kernel-modules-extra,
# but the base AMI kernel can be ahead of the modules-extra available in the repos.
# Upgrade the kernel to the repo's current version and install the matching
# modules-extra against the new kernel package (NOT uname -r, which reports the
# old kernel until the reboot that follows this provisioner in main.pkr.hcl).
# Query kernel-core, not kernel: the Rocky 10 cloud AMI only installs kernel-core
sudo dnf update -y -d0 kernel-core
NEW_KERNEL=$(rpm -q --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core | sort -V | tail -1)
echo "Installing kernel-modules-extra for kernel ${NEW_KERNEL}"
sudo dnf install -y -d0 "kernel-modules-extra-${NEW_KERNEL}"

# Install network and system tools
# bubblewrap (bwrap): required by omnigent to launch the Claude CLI in a sandbox
sudo dnf install -y -d0 \
     bind-utils \
     bubblewrap \
     iproute \
     less \
     lsof \
     nc \
     net-tools \
     passwd \
     rsync \
     sshpass \
     sudo \
     tar \
     unzip \
     util-linux \
     wget \
     which

#Cleanup
sudo dnf clean all

# Footer indicating the script execution is complete
echo "system_add_synxdb_cloud_dependencies.sh execution completed."
