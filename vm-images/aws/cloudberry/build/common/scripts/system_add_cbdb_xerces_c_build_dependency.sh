#!/bin/bash

# Enable strict mode for better error handling
set -euo pipefail

# Header indicating the script execution
echo "Executing system_add_cbdb_xerces_c_build_dependency.sh..."

# Change to home directory
cd

# Variables
XERCES_LATEST_RELEASE=3.3.0
INSTALL_PREFIX="/opt/xerces-c"

sudo chmod a+w /opt

wget -nv "https://archive.apache.org/dist/xerces/c/3/sources/xerces-c-${XERCES_LATEST_RELEASE}.tar.gz"

echo "$(curl -sL https://archive.apache.org/dist/xerces/c/3/sources/xerces-c-${XERCES_LATEST_RELEASE}.tar.gz.sha256)" | sha256sum -c -

tar xf "xerces-c-${XERCES_LATEST_RELEASE}.tar.gz"
rm "xerces-c-${XERCES_LATEST_RELEASE}.tar.gz"

cd xerces-c-${XERCES_LATEST_RELEASE}

./configure --prefix=${INSTALL_PREFIX}

make -j$(nproc)
make install

rm -rf ~/xerces-c*

# Footer indicating the script execution is complete
echo "system_add_cbdb_xerces_c_build_dependency.sh execution completed."
