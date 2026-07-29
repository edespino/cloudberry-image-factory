#!/bin/bash

# Install Cloudsmith CLI for the Packer SSH user via `uv tool install`.
# Source: https://help.cloudsmith.io/docs/cli
#
# Why not `pip install --user`:
#   That drops packages in ~/.local/lib/python*/site-packages (user site).
#   access-env / `access run` sets PYTHONNOUSERSITE=1 and a private HOME, so a
#   --user install fails with: ModuleNotFoundError: cloudsmith_cli
#
# `uv tool install` puts the app in an isolated tool venv and a shim at
# ~/.local/bin/cloudsmith. The shim's venv site-packages still load under
# PYTHONNOUSERSITE=1 (same pattern as system_add_omnigent.sh).
#
# Requires: system_add_uv.sh first (uv at /usr/local/bin/uv).
# Installs to: ${HOME}/.local/bin/cloudsmith

set -euo pipefail

echo "Executing system_add_cloudsmith_cli.sh..."

if ! command -v /usr/local/bin/uv >/dev/null 2>&1; then
  echo "ERROR: uv is not installed. Install uv first (system_add_uv.sh)."
  exit 1
fi

# Prefer the login user's HOME (Packer SSH user: ubuntu/rocky/...).
TARGET_HOME="${HOME}"
TARGET_USER="$(id -un)"

# Remove a prior pip --user install so the shim is not a stale console_script
# pointing at user-site packages.
if /usr/bin/python3 -m pip show cloudsmith-cli >/dev/null 2>&1; then
  echo "Removing previous pip install of cloudsmith-cli (if present)..."
  PIP_UNINSTALL=(/usr/bin/python3 -m pip uninstall -y)
  if /usr/bin/python3 -m pip uninstall --help 2>/dev/null | grep -q 'break-system-packages'; then
    PIP_UNINSTALL+=(--break-system-packages)
  fi
  # Best-effort: ignore if nothing to remove or PEP 668 blocks residual cleanup.
  "${PIP_UNINSTALL[@]}" cloudsmith-cli cloudsmith-api 2>/dev/null || true
fi

# Isolated tool venv + ~/.local/bin/cloudsmith shim
env HOME="${TARGET_HOME}" PATH="/usr/local/bin:${TARGET_HOME}/.local/bin:/usr/bin:/bin" \
  /usr/local/bin/uv tool install --force -q --python 3.12 cloudsmith-cli || {
  echo "ERROR: uv tool install cloudsmith-cli failed for user '${TARGET_USER}'"
  exit 1
}

BIN="${TARGET_HOME}/.local/bin/cloudsmith"
if [[ ! -x "${BIN}" ]]; then
  echo "ERROR: Cloudsmith CLI binary not found at ${BIN}"
  exit 1
fi

# Functional check: must import under PYTHONNOUSERSITE=1 (access-env contract)
if ! env PYTHONNOUSERSITE=1 PATH="${TARGET_HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin" \
  "${BIN}" --version >/dev/null 2>&1; then
  echo "ERROR: cloudsmith failed under PYTHONNOUSERSITE=1 (access-env incompatible install)"
  env PYTHONNOUSERSITE=1 PATH="${TARGET_HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    "${BIN}" --version 2>&1 || true
  exit 1
fi

echo "Cloudsmith CLI installed successfully at ${BIN}"
env PYTHONNOUSERSITE=1 PATH="${TARGET_HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin" \
  "${BIN}" --version || true

echo "system_add_cloudsmith_cli.sh execution completed."
