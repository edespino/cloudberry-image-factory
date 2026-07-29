#!/bin/bash

# Enable strict mode for better error handling
set -euo pipefail

# Header indicating the script execution
echo "Executing system_add_synxdb_cloud_dependencies.sh..."

# Update the package cache
sudo dnf makecache

# Install EPEL repository and import GPG keys for EPEL and Rocky Linux
sudo dnf install -y -d0 epel-release
sudo rpm --import https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-9
sudo rpm --import https://dl.rockylinux.org/pub/sig/9/cloud/x86_64/cloud-kernel/RPM-GPG-KEY-Rocky-SIG-Cloud

# Update the package cache again to include the new repository
sudo dnf makecache

# Disable EPEL repositories to avoid conflicts
sudo dnf config-manager --disable epel

# Install basic utilities
sudo dnf install -y -d0 git vim tmux wget time tree gnupg2 jq

# Install pip via ensurepip (avoids python3 version conflicts on Rocky 9 base AMI)
sudo python3 -m ensurepip --upgrade

# Install additional tools from EPEL repository
sudo dnf install -y -d0 --enablerepo=epel the_silver_searcher htop bat

# Install development tools and dependencies
sudo dnf install -y -d0 \
     bind-utils \
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
     util-linux-ng \
     wget \
     which

#Cleanup
sudo dnf clean all

# Footer indicating the script execution is complete
echo "system_add_synxdb_cloud_dependencies.sh execution completed."
