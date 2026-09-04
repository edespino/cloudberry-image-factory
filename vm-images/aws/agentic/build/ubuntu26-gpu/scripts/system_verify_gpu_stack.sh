#!/bin/bash

# Build-time GPU smoke test for agentic/ubuntu26-gpu
#
# Runs on the g6.xlarge builder after the driver reboot and the Ollama
# install. The goss test instance the harness launches later has no GPU, so
# every hardware-dependent assertion lives here and fails the build on a
# miss. goss (tests/goss.yaml) covers only hardware-independent facts.

set -euo pipefail

echo "Executing system_verify_gpu_stack.sh..."

fail() {
  echo "ERROR: $*"
  exit 1
}

echo "Running kernel: $(uname -r)"

echo "Checking kernel modules (nvidia loaded, nouveau absent)..."
lsmod | grep -q '^nvidia ' || fail "nvidia kernel module is not loaded"
if lsmod | grep -q '^nouveau '; then
  fail "nouveau kernel module is loaded"
fi

echo "Checking nvidia-smi sees the L4..."
nvidia-smi -L
nvidia-smi -L | grep -q 'NVIDIA L4' || fail "nvidia-smi did not report an NVIDIA L4"
nvidia-smi --query-gpu=driver_version,memory.total --format=csv,noheader

echo "Checking the ollama service is active..."
sudo systemctl is-active ollama || fail "ollama service is not active"

# Ollama logs one 'msg="inference compute" ... library=<backend>' line per
# detected device shortly after the service starts (discover/types.go, slog
# text handler); the CUDA backend reports library=CUDA, CPU fallback
# library=cpu.
echo "Checking ollama detected a CUDA accelerator..."
found=false
for _ in $(seq 1 30); do
  if sudo journalctl -u ollama --no-pager | grep -q 'library=CUDA'; then
    found=true
    break
  fi
  sleep 1
done
sudo journalctl -u ollama --no-pager | grep 'inference compute' || true
[ "${found}" = true ] || fail "ollama journal has no library=CUDA inference compute line"

echo "Checking ollama listens on loopback only..."
ss -ltn
ss -ltn | grep -q '127.0.0.1:11434' || fail "ollama is not listening on 127.0.0.1:11434"
if ss -ltn | grep -qE '(0\.0\.0\.0|\[::\]):11434'; then
  fail "ollama is listening on a non-loopback address"
fi

echo "system_verify_gpu_stack.sh execution completed."
