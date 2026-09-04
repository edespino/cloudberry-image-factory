# agentic/ubuntu26-gpu - Claude AI Context

NVIDIA L4 inference sibling of `agentic/ubuntu26`
(`vm-images/aws/agentic/build/ubuntu26-gpu/`). x86_64 only. Consumed by the
`cloudberry-dev-env-launcher` `gpu-node` module (g6.xlarge / g6.2xlarge
sidecar next to the Hermes/Herdr host). See `../ubuntu26/CLAUDE.md` for the
AI-tooling boundary and the Ubuntu 26.04 gotchas, all of which apply here.

## Chained from agentic/ubuntu26

This is the first target that exercises the "Chained Pattern for Future
Agentic Targets" described in `../ubuntu26/CLAUDE.md`:

- `base_family` / `base_os` HCL variables (defaults `agentic` / `ubuntu26`)
  select the source AMI: the newest image owned by this account whose
  **`Name` tag** matches `agentic-packer-ubuntu26-2*-PASSED`, x86_64, hvm.
- `packer-build-and-test.sh` records PASSED/FAILED by re-tagging `Name`; the
  AMI name attribute is never renamed. Filtering on `name` instead of
  `tag:Name` would never find a `-PASSED` image.
- The `-2*` segment (timestamps start with `2`) excludes
  `agentic-packer-ubuntu26-arm64-*` and `agentic-packer-ubuntu26-gpu-*` from
  the candidate set; `architecture = "x86_64"` is a second guard.
- Every base provisioner already ran in the source image. This template
  layers **only** the GPU stack; do not re-run `system_add_docker.sh` or any
  other base provisioner here.
- The source only exists after an `agentic/ubuntu26` build has passed. A base
  rebuild does not rebuild this image; rebuild it deliberately afterwards.

## Provisioner Order (main.pkr.hcl)

1. `scripts/system_add_nvidia_driver.sh` (`NVIDIA_BRANCH=580`) - installs
   and `apt-mark hold`s `linux-modules-nvidia-580-server-aws`,
   `nvidia-driver-580-server`, `nvidia-utils-580-server`; verifies an
   nvidia module exists for the next-boot kernel
2. Reboot (`inline = ["sudo reboot"]`, `expect_disconnect = true`) - unloads
   nouveau, loads nvidia (same pattern as `synxdb-cloud/rocky10`)
3. `scripts/system_add_nvtop.sh` (`pause_before = "30s"`)
4. `scripts/system_add_ollama.sh` - latest GitHub release (or
   `OLLAMA_VERSION`), `ollama-linux-amd64.tar.zst` verified against the
   release `sha256sum.txt` and unpacked with `zstd` into `/usr/local`, user
   `ollama`, systemd unit
5. `scripts/system_verify_gpu_stack.sh` - build-time GPU smoke test
6. `system_add_goss.sh` - already present from the base (no-op), kept so the
   template ends with the test framework like every target

Scripts live in this target, not `common/scripts/`, because they are
GPU-specific and DEB-specific. Promote them if a second GPU target appears.

## Driver Branch and Hold Policy

- `NVIDIA_BRANCH` is set in `main.pkr.hcl` (`environment_vars`) and defaults
  to `580` inside the script. `595` is the verified alternative. Changing the
  branch is a one-line change in the HCL **plus** the matching package names
  in `tests/goss.yaml`.
- `linux-modules-nvidia-<b>-server-aws` is the prebuilt, signed module
  metapackage tracking the `linux-aws` kernel. No DKMS; never install
  `nvidia-dkms-*`.
- All three packages are held so `apt upgrade` cannot move the branch or
  unmatch kernel and modules.

## Where GPU Verification Lives

The harness launches the goss test instance as `t3.medium` (from the AMI
architecture). It has no GPU: the nvidia module does not load there and
`nvidia-smi` fails.

- **Packer build** (`scripts/system_verify_gpu_stack.sh`, on the `g6.xlarge`
  builder): `lsmod` shows nvidia and not nouveau, `nvidia-smi -L` reports an
  `NVIDIA L4`, `ollama` is active with a `library=cuda` accelerator line in
  its journal, and `ss -ltn` shows `127.0.0.1:11434` and no non-loopback
  11434 listener. Any miss fails the build.
- **goss** (`tests/goss.yaml`): hardware-independent facts only. It is a
  complete copy of the base goss file (the harness ships only this target's
  file; the policy test `test_agentic_goss_covers_ai_toolchain_executables`
  applies to it too) plus the "GPU layer" assertions: driver/utils/module
  packages installed and held, `modinfo nvidia`, `nvtop`, `/usr/bin/nvidia-smi`
  exists, Ollama binary/unit/user, `ollama` service enabled+running (CPU
  mode), port 11434 listening on `127.0.0.1` only.
- Never add `nvidia-smi -L` or an `lsmod nvidia` assertion to goss.
- Never assert `ollama --version` in goss. Ollama's `Serve()` opens the
  listener, then runs the scheduler and GPU discovery, and only then serves
  HTTP (`server/routes.go`); discovery bootstrap is bounded at 30s plus a
  30s second pass (`discover/runner.go`), and the CLI's `/api/version` call
  uses `http.DefaultClient` with no timeout. On the GPU-less test instance
  this made `ollama --version` exceed a 10s goss timeout while
  `port tcp:11434` and `service ollama` passed. goss asserts the binary with
  `test -x` and the API with `curl --max-time 85` under a 90s goss timeout.

## Ollama Rules

- Loopback only. `OLLAMA_HOST` is never set (default `127.0.0.1:11434`); the
  unit file, the smoke test, and goss all assert this. Opening 11434 beyond
  loopback is out of scope for this image.
- No model weights are baked. Pull models on the running node (consider the
  launcher's models data volume so weights survive rebuilds).
- Not baked: CUDA toolkit (Ollama bundles its runtime), Docker GPU runtime
  (`nvidia-container-toolkit`), Open WebUI or any HTTP front end.

## CI: Manual Dispatch Only

The `MANUAL_DISPATCH_ONLY` marker file in this directory excludes the target
from the change-driven matrix (`.github/scripts/compute-build-matrix.sh`),
including the "all targets" rules for harness/common-test changes. Build it
with `ami-build-manual.yml` (`build_targets=agentic/ubuntu26-gpu`, or `all`)
or locally:

```bash
cd vm-images/aws/agentic/build/ubuntu26-gpu
../../../../scripts/packer-build-and-test.sh
```

Policy tests: `test_manual_dispatch_only_marker_excludes_target_from_change_matrix`
and `test_agentic_gpu_target_is_manual_dispatch_only` in
`tests/test_repository_policy.py`.

## Do Not

- Do not "fix" the missing base provisioners by re-adding them; they came
  from the chained source image.
- Do not modify `agentic/ubuntu26` or `agentic/ubuntu26-arm64` to accommodate
  this target.
- Do not add an arm64 GPU variant (no arm64 L4 instance exists).
