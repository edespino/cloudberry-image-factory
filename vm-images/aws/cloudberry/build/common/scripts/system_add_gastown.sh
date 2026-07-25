#!/bin/bash

# Install gastown (gt) multi-agent workspace manager
# Source: https://github.com/steveyegge/gastown
# Requires Go to be installed (uses make build)

set -euo pipefail

echo "Executing system_add_gastown.sh..."

# Ensure Go is available
export PATH=$PATH:/opt/go/bin

if ! command -v go &>/dev/null; then
  echo "ERROR: Go is not installed. Install Go first (system_add_golang.sh)."
  exit 1
fi

echo "Using Go: $(go version)"

# gastown's build pulls in Dolt's go-icu-regex, a cgo binding that needs the
# ICU development headers (unicode/uregex.h) and a C++ compiler (g++).
if command -v dnf &>/dev/null; then
  sudo dnf install -y -d0 libicu-devel gcc-c++
else
  export DEBIAN_FRONTEND=noninteractive
  sudo apt-get update
  sudo apt-get install -y libicu-dev g++
fi

# Clone, build, and install gastown
git clone https://github.com/steveyegge/gastown /tmp/gastown
cd /tmp/gastown
make build
sudo cp gt /usr/local/bin/
cd /
rm -rf /tmp/gastown

# Drop the Go build and module caches (several GB from dolt's dependency
# tree) so they don't persist into the baked image
go clean -cache -modcache

# Verify
/usr/local/bin/gt --version

echo "system_add_gastown.sh execution completed."
