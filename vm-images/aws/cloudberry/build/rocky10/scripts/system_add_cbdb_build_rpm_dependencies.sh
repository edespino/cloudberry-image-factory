#!/bin/bash

# Enable strict mode for better error handling
set -euo pipefail

# Header indicating the script execution
echo "Executing system_add_cbdb_build_rpm_dependencies.sh..."

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
sudo dnf install -y -d0 git vim tmux wget

# Install additional tools from EPEL repository
sudo dnf install -y -d0 --enablerepo=epel htop bat unzip ripgrep

sudo dnf install -y -d0 \
     apr-util-devel \
     bison \
     bzip2-devel \
     cmake \
     curl-devel \
     flex \
     gcc \
     gcc-c++ \
     krb5-devel \
     libevent-devel \
     libuuid-devel \
     libuv-devel \
     libxml2-devel \
     libzstd-devel \
     lz4-devel \
     openssl-devel \
     pam-devel \
     perl-Env \
     perl-ExtUtils-Embed \
     perl-FindBin \
     perl-Opcode \
     pip \
     python3-devel \
     python3-psutil \
     python3-pyyaml \
     readline-devel

sudo dnf install -y -d0 --enablerepo=devel \
     libyaml-devel \
     perl-IPC-Run \
     perl-Test-Simple \
     protobuf-devel

#Cleanup
sudo dnf clean all

# Footer indicating the script execution is complete
echo "system_add_cbdb_build_rpm_dependencies.sh execution completed."
