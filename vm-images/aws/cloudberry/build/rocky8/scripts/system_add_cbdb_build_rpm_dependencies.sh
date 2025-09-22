#!/bin/bash

# Enable strict mode for better error handling
set -euo pipefail

# Header indicating the script execution
echo "Executing system_add_cbdb_build_rpm_dependencies.sh..."

# Update the package cache
sudo dnf makecache

# Install EPEL repository and import GPG keys for EPEL and Rocky Linux
sudo dnf install -y -d0 epel-release
sudo rpm --import http://download.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-8
sudo rpm --import https://dl.rockylinux.org/pub/sig/8/cloud/x86_64/cloud-kernel/RPM-GPG-KEY-Rocky-SIG-Cloud

# Update the package cache again to include the new repository
sudo dnf makecache

# Disable EPEL repositories to avoid conflicts
sudo dnf config-manager --disable epel

# Install basic utilities
sudo dnf install -y -d0 git vim tmux wget

# Install additional tools from EPEL repository
sudo dnf install -y -d0 --enablerepo=epel the_silver_searcher htop

# Install development tools and dependencies
sudo dnf install -y -d0 \
     apr-devel \
     autoconf \
     bison \
     bzip2-devel \
     cmake \
     createrepo_c \
     ed \
     flex \
     gcc \
     gcc-c++ \
     glibc-langpack-en \
     glibc-locale-source \
     initscripts \
     iproute \
     java-1.8.0-openjdk \
     java-1.8.0-openjdk-devel \
     java-11-openjdk \
     java-11-openjdk-devel \
     krb5-devel \
     less \
     libcurl-devel \
     libevent-devel \
     libuuid-devel \
     libxml2-devel \
     libzstd-devel \
     lz4 \
     lz4-devel \
     make \
     maven \
     m4 \
     nmap-ncat \
     net-tools \
     openldap-devel \
     openssh-clients \
     openssh-server \
     openssl-devel \
     pam-devel \
     passwd \
     perl \
     perl-Env \
     perl-ExtUtils-Embed \
     perl-Test-Simple \
     pinentry \
     procps-ng \
     python36 \
     python36-devel \
     python3-psutil \
     python3-pyyaml \
     readline-devel \
     rpm-build \
     rpm-sign \
     rpmdevtools \
     rsync \
     sshpass \
     sudo \
     tar \
     unzip \
     util-linux \
     wget \
     which \
     zlib-devel

# Install development tools and dependencies from Devel repository
sudo dnf install -y -d0 --enablerepo=devel \
     libuv-devel \
     libyaml-devel \
     perl-IPC-Run \
     protobuf-devel

#Cleanup
sudo dnf clean all

# Footer indicating the script execution is complete
echo "system_add_cbdb_build_rpm_dependencies.sh execution completed."
