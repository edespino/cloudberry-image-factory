#!/bin/bash

# Enable strict mode for better error handling
set -euo pipefail

# Header indicating the script execution
echo "Executing system_add_cbdb_build_rpm_dependencies.sh..."

# Update the package cache
sudo dnf makecache

# Install basic utilities
sudo dnf install -y -d0 git vim tmux wget

# Install development tools and dependencies

sudo dnf install -y -d0 \
     apr-devel \
     bison \
     bzip2-devel \
     cmake \
     flex \
     gcc \
     gcc-c++ \
     krb5-devel \
     libcurl-devel \
     libevent-devel \
     libuuid-devel \
     libuv-devel \
     libxml2-devel \
     libyaml-devel \
     libzstd-devel \
     openldap-devel \
     openssl-devel \
     pam-devel \
     perl-core \
     perl-ExtUtils-Embed \
     perl-Opcode \
     readline-devel \
     rpm-build \
     rpm-sign \
     rpmdevtools \
     rsync \
     zlib-devel

# Cleanup
sudo dnf clean all

# Footer indicating the script execution is complete
echo "system_add_cbdb_build_rpm_dependencies.sh execution completed."
