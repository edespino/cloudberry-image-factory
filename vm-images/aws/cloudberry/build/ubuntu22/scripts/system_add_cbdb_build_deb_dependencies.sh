#!/bin/bash

# Enable strict mode for better error handling
set -euo pipefail

# Header indicating the script execution
echo "Executing system_add_cbdb_build_dependencies.sh..."

export DEBIAN_FRONTEND=noninteractive

# Update package lists and upgrade existing packages
sudo apt-get update
## sudo apt-get install -y apt-utils
sudo apt-get upgrade -y

# Add universe repository
sudo sed -i 's/^# deb .*universe/deb &/' /etc/apt/sources.list

# Update package lists again after adding new repository
sudo apt-get update

# Install initial packages
sudo apt-get install -y git less

# Install additional utilities
sudo apt-get install -y bat htop silversearcher-ag sudo tmux

# Install build essentials and development tools
sudo apt-get install -y \
     bison \
     cmake \
     curl \
     flex \
     g++-11 \
     gcc-11 \
     iproute2 \
     iputils-ping \
     lsof \
     make \
     maven \
     openssh-server \
     rsync \
     tzdata \
     vim \
     wget

# Install runtime and library dependencies
sudo apt-get install -y \
     libapr1-dev \
     libbz2-dev \
     libcurl4-gnutls-dev \
     libevent-dev \
     libipc-run-perl \
     libkrb5-dev \
     libldap-dev \
     liblz4-dev \
     libpam0g-dev \
     libperl-dev \
     libprotobuf-dev \
     libreadline-dev \
     libssl-dev \
     libuv1-dev \
     libxerces-c-dev \
     libxml2-dev \
     libyaml-dev \
     libzstd-dev \
     pkg-config \
     protobuf-compiler \
     python3-distutils \
     python3-setuptools \
     python3.10 \
     python3.10-dev \
     python3-psutil \
     zlib1g-dev

sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-11 100 && \
sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-11 100 && \
sudo update-alternatives --install /usr/bin/x86_64-linux-gnu-gcc x86_64-linux-gnu-gcc /usr/bin/gcc-11 100 && \
sudo update-alternatives --set gcc /usr/bin/gcc-11 && \
sudo update-alternatives --set g++ /usr/bin/g++-11

# Footer indicating the script execution is complete
echo "system_add_cbdb_build_dependencies.sh execution completed."
