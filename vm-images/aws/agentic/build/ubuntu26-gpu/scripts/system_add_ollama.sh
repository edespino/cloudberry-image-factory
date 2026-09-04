#!/bin/bash

# Install Ollama - local LLM inference server
# Source: https://github.com/ollama/ollama
#
# Mirrors the official Linux install: the zstd-compressed release archive
# (ollama-linux-<arch>.tar.zst, verified against the release's sha256sum.txt)
# extracted into /usr/local (/usr/local/bin/ollama + /usr/local/lib/ollama
# with the bundled CUDA runtime), system user `ollama`, systemd unit. Uses
# the latest GitHub release unless OLLAMA_VERSION pins one.
#
# Loopback only: OLLAMA_HOST is deliberately never set, so the server binds
# to its default 127.0.0.1:11434. No model weights are pulled.

set -euo pipefail

echo "Executing system_add_ollama.sh..."

# Detect architecture
case "$(uname -m)" in
  x86_64)        ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)             echo "ERROR: Unsupported architecture: $(uname -m)"; exit 1 ;;
esac

echo "Detected architecture: ${ARCH}"

# Resolve release tag: pinned via OLLAMA_VERSION, else latest
if [ -n "${OLLAMA_VERSION:-}" ]; then
  TAG="v${OLLAMA_VERSION#v}"
  echo "Pinned Ollama release: ${TAG}"
else
  TAG=$(curl -fsSL "https://api.github.com/repos/ollama/ollama/releases/latest" | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4)
  if [ -z "${TAG}" ]; then
    echo "ERROR: Failed to fetch latest release tag (possible GitHub API rate limit)"
    exit 1
  fi
  echo "Latest Ollama release: ${TAG}"
fi

# Releases ship zstd-compressed archives; the official installer requires
# the zstd tool to unpack them.
if ! command -v zstd &>/dev/null; then
  echo "Installing zstd..."
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y zstd
fi

# Download, verify checksum, extract into /usr/local (official layout)
ARCHIVE="ollama-linux-${ARCH}.tar.zst"
BASE_URL="https://github.com/ollama/ollama/releases/download/${TAG}"
WORK_DIR=$(mktemp -d /tmp/ollama-install.XXXXXX)

echo "Downloading from: ${BASE_URL}/${ARCHIVE}"
curl -fsSL -o "${WORK_DIR}/${ARCHIVE}" "${BASE_URL}/${ARCHIVE}"
curl -fsSL -o "${WORK_DIR}/sha256sum.txt" "${BASE_URL}/sha256sum.txt"

echo "Verifying checksum..."
# sha256sum.txt entries are prefixed "./<asset>"; check only our archive
(cd "${WORK_DIR}" && grep " ./${ARCHIVE}\$" sha256sum.txt | sha256sum -c -)

echo "Extracting into /usr/local..."
sudo rm -rf /usr/local/lib/ollama
zstd -d -c "${WORK_DIR}/${ARCHIVE}" | sudo tar -xf - -C /usr/local
sudo chmod 0755 /usr/local/bin/ollama
rm -rf "${WORK_DIR}"

# Service account (as the official installer creates it; the home directory
# holds ~/.ollama with the server key and any models pulled later)
if ! id ollama &>/dev/null; then
  echo "Creating ollama system user..."
  sudo useradd --system --user-group --shell /bin/false \
    --create-home --home-dir /usr/share/ollama ollama
fi
sudo usermod -a -G ollama ubuntu

# systemd unit equivalent to the official one. No OLLAMA_HOST: loopback only.
echo "Installing ollama.service..."
sudo tee /etc/systemd/system/ollama.service > /dev/null <<UNIT
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
ExecStart=/usr/local/bin/ollama serve
User=ollama
Group=ollama
Restart=always
RestartSec=3
Environment="PATH=${PATH}"

[Install]
WantedBy=default.target
UNIT
sudo chmod 0644 /etc/systemd/system/ollama.service

sudo systemctl daemon-reload
sudo systemctl enable --now ollama

# Wait for the API on loopback. The server opens its listener first and
# serves HTTP only after GPU discovery (bootstrap up to 30s, second pass up
# to 30s), so allow well beyond that before failing the build.
echo "Waiting for the Ollama API on 127.0.0.1:11434..."
for _ in $(seq 1 90); do
  if curl -fsS http://127.0.0.1:11434/api/version > /dev/null 2>&1; then
    break
  fi
  sleep 1
done
curl -fsS http://127.0.0.1:11434/api/version
echo

# Verify
sudo systemctl is-active ollama
/usr/local/bin/ollama --version

echo "system_add_ollama.sh execution completed."
