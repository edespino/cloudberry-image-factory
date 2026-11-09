#!/bin/bash

# Enable strict mode for better error handling
set -euo pipefail

# Header indicating the script execution
echo "Executing system_add_cbdb_build_rpm_dependencies.sh..."

# Update the package cache
sudo dnf makecache

# Install EPEL repository and import GPG keys for EPEL and Rocky Linux
sudo dnf install -y -d0 epel-release
sudo rpm --import https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-9
sudo rpm --import https://dl.rockylinux.org/pub/sig/8/cloud/x86_64/cloud-kernel/RPM-GPG-KEY-Rocky-SIG-Cloud

# Update the package cache again to include the new repository
sudo dnf makecache

# Disable EPEL repositories to avoid conflicts
sudo dnf config-manager --disable epel

# Install basic utilities
sudo dnf install -y -d0 git vim tmux wget time tree

# Install additional tools from EPEL repository
sudo dnf install -y -d0 --enablerepo=epel the_silver_searcher htop bat

# Install development tools and dependencies
sudo dnf install -y -d0 \
     apr-devel \
     autoconf \
     automake \
     bison \
     boost-devel \
     bzip2-devel \
     cmake3 \
     createrepo_c \
     ed \
     flex \
     gcc \
     gcc-c++ \
     gdb \
     glibc-langpack-en \
     glibc-locale-source \
     gmp-devel \
     initscripts \
     iproute \
     java-1.8.0-openjdk \
     java-1.8.0-openjdk-devel \
     java-11-openjdk \
     java-11-openjdk-devel \
     krb5-devel \
     less \
     libcurl-devel \
     libffi-devel \
     libevent-devel \
     libtool \
     libuuid-devel \
     libxml2-devel \
     libzstd-devel \
     lsof \
     lz4 \
     lz4-devel \
     m4 \
     make \
     maven \
     mpfr-devel \
     nc \
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
     python3 \
     python3-devel \
     python3-psutil \
     python3-pyyaml \
     readline-devel \
     rpm-build \
     rpm-sign \
     rpmdevtools \
     rsync \
     sqlite-devel \
     sshpass \
     sudo \
     tar \
     unzip \
     util-linux-ng \
     wget \
     which \
     zlib-devel

# Install development tools and dependencies from Devel repository
sudo dnf install -y -d0 --enablerepo=devel \
     libuv-devel \
     libyaml-devel \
     perl-IPC-Run \
     protobuf-devel \
     protobuf-c-devel

# PAX requires liburing on Linux. On Rocky 9 the devel package is in CRB,
# not the devel repo used above. Meson and ninja are in CRB too. Meson
# cannot compile without ninja 1.10 or later: older ninja rejects the
# build.ninja Meson writes. CRB has meson 0.63.3 and ninja-build 1.10.2.
sudo dnf install -y -d0 --enablerepo=crb \
     liburing-devel \
     meson \
     ninja-build

sudo dnf install -y -d0 --enablerepo=epel \
     docbook-style-xsl \
     libxslt

# Distro maven is 3.6.3. Keep the package so the package test stays true,
# and put the current Apache Maven release first on PATH.
MAVEN_VERSION="3.10.0"
MAVEN_SHA512="908b1501bfb420bf7c8affb855534a9c407fd6099367bfb9f2f2dcb8e9799102bffb84518cde74c679bd76870247c6528683abdd620581bffa90f95d92d175aa"
MAVEN_TARBALL="apache-maven-${MAVEN_VERSION}-bin.tar.gz"
wget -nv -O "/tmp/${MAVEN_TARBALL}" "https://downloads.apache.org/maven/maven-3/${MAVEN_VERSION}/binaries/${MAVEN_TARBALL}"
echo "${MAVEN_SHA512}  /tmp/${MAVEN_TARBALL}" | sha512sum -c -
sudo rm -rf "/opt/apache-maven-${MAVEN_VERSION}"
sudo tar -xzf "/tmp/${MAVEN_TARBALL}" -C /opt
sudo ln -sfn "/opt/apache-maven-${MAVEN_VERSION}/bin/mvn" /usr/local/bin/mvn
rm -f "/tmp/${MAVEN_TARBALL}"

#Cleanup
sudo dnf clean all

# Footer indicating the script execution is complete
echo "system_add_cbdb_build_rpm_dependencies.sh execution completed."
