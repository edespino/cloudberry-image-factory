# Design: `agentic/ubuntu26-gpu` — NVIDIA L4 inference image chained from `agentic/ubuntu26`

Date: 2026-09-03
Repo: cloudberry-image-factory
Status: Approved design, ready to implement
Consumer: `cloudberry-dev-env-launcher` `modules/aws/gpu-node` (g6.2xlarge / g6.xlarge sidecar next to the Hermes/Herdr host `cdw`)

## Problem

The GPU sidecar node launched today from the plain `agentic-packer-ubuntu26-*` x86 image needed four
manual steps before it was usable: `apt update` (the image ships with empty apt lists, so
`ubuntu-drivers` finds nothing), `ubuntu-drivers install --gpgpu`, a reboot, then
`nvidia-utils-<branch>-server` because `--gpgpu` does not install `nvidia-smi`. Ollama, nvtop, and the
Ollama systemd unit were further manual steps. The node must also carry the full agentic toolchain
(Claude CLI, ai-toolchain, omnigent, herdr, beads, zellij, direnv, docker, cloud CLIs) exactly like cdw.

Goal: a first-boot-ready x86_64 GPU image, `agentic-packer-ubuntu26-gpu-<timestamp>`, that is the
agentic ubuntu26 image plus NVIDIA driver, `nvidia-smi`, `nvtop`, and Ollama bound to loopback.

## Ground truth this design builds on (verified 2026-09-03)

- **Chaining is the prescribed pattern.** `vm-images/aws/agentic/build/ubuntu26/CLAUDE.md`, section
  "Chained Pattern for Future Agentic Targets": new agentic targets chain from a tested `-PASSED` AMI
  via `base_family` / `base_os` HCL variables and layer only their own provisioners. No target does
  this yet; this is the first.
- **How `-PASSED` is expressed.** `vm-images/scripts/packer-build-and-test.sh` `rename_ami()` (line
  ~205) re-tags the AMI's **`Name` tag** to `<ami_name>-PASSED` (or `-FAILED`). The AMI *name*
  attribute is never changed. A chained `source_ami_filter` must therefore filter on `tag:Name`, not
  `name`.
- **Goss test instance has no GPU.** The harness picks the goss test instance type from the AMI
  architecture: `t4g.medium` for arm64, `t3.medium` for x86_64 (lines ~516–530). GPU-dependent goss
  assertions (`nvidia-smi -L`) would fail there. GPU verification must happen inside the Packer
  build on the GPU builder instance; goss covers only hardware-independent facts.
- **Goss shipping.** The harness copies `vm-images/common/tests/*.yaml` to `~/common/tests/` and the
  target's `tests/goss.yaml` to `~/<os_name>/tests/goss.yaml` on the test instance (lines ~653–672).
  Sibling target goss files are not shipped, so the GPU target cannot `gossfile:`-include
  `../ubuntu26/tests/goss.yaml`; it needs its own complete file.
- **Reboot precedent.** `vm-images/aws/synxdb-cloud/build/rocky10/main.pkr.hcl` lines ~94–99:
  `inline = ["sudo reboot"]`, `expect_disconnect = true`, next provisioner `pause_before = "30s"`.
- **Matrix.** `.github/scripts/compute-build-matrix.sh` treats every `vm-images/aws/*/build/*/`
  directory as a target; a change under the new directory builds it in `ami-build-on-change.yml`.
  Manual builds: `ami-build-manual.yml` with `agentic/ubuntu26-gpu`.
- **Policy tests** (`tests/test_repository_policy.py`, `tests/test_packer_template_security.py`)
  that this target must satisfy: `test_template_ami_name_prefix_matches_target_policy`,
  `test_all_amazon_ebs_sources_restrict_temporary_sg_to_public_ip`,
  `test_agentic_goss_covers_ai_toolchain_executables` (the new goss file must assert every
  ai-toolchain executable, same as the base), `test_dynamic_matrix_selects_targets_from_hcl_references`.
  AI tooling stays inside the `agentic` family; this target is in that family.
- **Driver packages exist in the 26.04 archive** (probed on a live node, `restricted` component):
  `nvidia-driver-580-server`, `nvidia-driver-595-server`, `nvidia-utils-<b>-server`, and prebuilt
  signed `linux-modules-nvidia-{580,595}-server-aws` for the `linux-aws` kernel. The 595 metapackage's
  modalias list includes the L4 (`10de:27b8`). Running today on the live node: `595.71.05`, CUDA 13.2,
  kernel `7.0.0-1008-aws`.
- **Base image facts.** `agentic/ubuntu26` builds on `t3.2xlarge` from the stock
  `*ubuntu-resolute-26.04-amd64-minimal-*` AMI, 24 GiB `/dev/sda1` gp2, ends with
  `system_add_goss.sh` then `system_add_docker.sh`, and its dependencies script empties the apt lists.
  `btop` is already in the base (goss asserts it).
- **Consumer side.** The launcher's `gpu-node` module sets `lifecycle { ignore_changes = [ami] }`,
  and its `.envrc` resolves the AMI by **name** filter (`agentic-packer-ubuntu26-2*` today). The new
  image will be selected by a new launcher config entry with filter `agentic-packer-ubuntu26-gpu-*`.
  That name does not glob-match the existing x86 (`…ubuntu26-2*`) or arm64 (`…ubuntu26-arm64-*`) filters.

## Decisions (confirmed with user)

- **Chain, do not rebuild.** Source = newest `agentic-packer-ubuntu26-2*-PASSED` x86_64 AMI owned by
  this account. All agentic tooling arrives from the base; this target adds only the GPU layer.
- **Layer contents:** NVIDIA server driver (pinned branch, held), `nvidia-utils` (nvidia-smi),
  `nvtop`, Ollama (systemd service, loopback only), plus goss and a build-time GPU smoke test.
- **Not baked:** model weights, CUDA toolkit (Ollama bundles its runtime), Docker GPU runtime
  (`nvidia-container-toolkit`), Open WebUI, anything listening on a non-loopback address.
- **Builder:** `g6.xlarge` so the smoke test runs against a real L4. Not `t3.*`.
- **Driver branch:** `NVIDIA_BRANCH=580` (NVIDIA production branch) as the script default, exposed as a
  script environment variable. 595 is the verified-today alternative; either is acceptable, the choice
  is a one-line change. Hold the three driver packages with `apt-mark hold`.
- **Ollama version:** repo convention is "latest release from GitHub API" (see
  `system_add_zoxide.sh`); do the same, with an `OLLAMA_VERSION` override for pinning.
- **Root volume:** 32 GiB launch block device (base uses 24; driver + Ollama need headroom). The
  launcher sets the instance root to 100 GiB at launch anyway.
- **Users:** the GPU node is used as `ubuntu` (same as cdw). No per-user work beyond what the base
  already did.

## Design

### 1. Target directory

```
vm-images/aws/agentic/build/ubuntu26-gpu/
├── main.pkr.hcl
├── CLAUDE.md
├── scripts/
│   ├── system_add_nvidia_driver.sh
│   ├── system_add_nvtop.sh
│   └── system_add_ollama.sh
└── tests/
    └── goss.yaml
```

Scripts live in the target (not `common/`) because they are GPU-specific and DEB-specific. If a second
GPU target ever appears, promote them to `common/scripts/` then.

### 2. `main.pkr.hcl`

Same `packer {}` block, same variables (`family`, `os_name`, `default_username`,
`custom_shell_commands`, `aws_*`, `region`) as `agentic/ubuntu26`, plus:

```hcl
variable "base_family" { type = string  default = "agentic" }
variable "base_os"     { type = string  default = "ubuntu26" }
```

Source block differences from the base:

```hcl
source "amazon-ebs" "gpu-build-image" {
  # ... access_key/secret_key/token/region as in the base ...
  temporary_security_group_source_public_ip = true   # policy test requires this

  instance_type = "g6.xlarge"                        # real L4 for the build-time smoke test

  source_ami_filter {
    filters = {
      "tag:Name"          = "${var.base_family}-packer-${var.base_os}-2*-PASSED"
      architecture        = "x86_64"
      virtualization-type = "hvm"
    }
    owners      = ["self"]                           # no account ID in the template
    most_recent = true
  }

  ssh_username = "ubuntu"

  ami_name = format("%s-packer-%s-%s", var.family, var.os_name, formatdate("YYYYMMDD-HHmmss", timestamp()))

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 32
    volume_type           = "gp3"
    delete_on_termination = true
  }
}
```

The `-2*` in the tag filter is what keeps `ubuntu26-arm64-*` and `ubuntu26-gpu-*` images out of the
candidate set; `architecture = "x86_64"` is a second guard.

Provisioner order:

1. `scripts/system_add_nvidia_driver.sh` — installs and holds the driver set (below).
2. Reboot — copy the rocky10 pattern exactly: `inline = ["sudo reboot"]`, `expect_disconnect = true`.
3. `scripts/system_add_nvtop.sh` with `pause_before = "30s"`.
4. `scripts/system_add_ollama.sh`.
5. **Build-time GPU smoke test** (inline shell, fails the build on any miss):
   ```bash
   nvidia-smi -L | grep -q 'NVIDIA L4'
   nvidia-smi --query-gpu=driver_version,memory.total --format=csv,noheader
   lsmod | grep -q '^nvidia ' && ! lsmod | grep -q '^nouveau'
   sudo systemctl is-active ollama
   sudo journalctl -u ollama --no-pager | grep -qiE 'library=cuda|inference compute.*cuda'
   ss -ltn | grep -q '127.0.0.1:11434' && ! ss -ltn | grep -qE '(0.0.0.0|\[::\]):11434'
   ```
   (Ollama logs its detected accelerators at service start; the exact log line should be confirmed
   against the installed version and the grep adjusted if needed.)
6. `../../../../common/scripts/system_add_goss.sh` — goss is already on the base image, but the base
   template ends with it and the root CLAUDE.md checklist says never omit it. Re-running is harmless.
7. `manifest` post-processor as in the base.

Do **not** re-run `system_add_docker.sh` or any base provisioner; the base already did them.

### 3. `scripts/system_add_nvidia_driver.sh`

Style: same header/`set -euo pipefail`/echo banners as `common/scripts/system_add_zoxide.sh`.

```bash
NVIDIA_BRANCH="${NVIDIA_BRANCH:-580}"
sudo apt-get update                                  # lists are empty on the base image
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  "linux-modules-nvidia-${NVIDIA_BRANCH}-server-aws" \
  "nvidia-driver-${NVIDIA_BRANCH}-server" \
  "nvidia-utils-${NVIDIA_BRANCH}-server"
sudo apt-mark hold \
  "linux-modules-nvidia-${NVIDIA_BRANCH}-server-aws" \
  "nvidia-driver-${NVIDIA_BRANCH}-server" \
  "nvidia-utils-${NVIDIA_BRANCH}-server"
dpkg -l | grep -E "nvidia-(driver|utils)-${NVIDIA_BRANCH}-server|linux-modules-nvidia-${NVIDIA_BRANCH}-server-aws"
```

Notes for the implementer:
- `linux-modules-nvidia-<b>-server-aws` is the prebuilt, signed module metapackage that tracks the
  `linux-aws` kernel meta. It avoids DKMS entirely and keeps kernel and driver matched on later
  `apt upgrade`. Do not install `nvidia-dkms-*`.
- The driver packages blacklist `nouveau` and rebuild the initramfs. The reboot in step 2 is what
  unloads nouveau and loads `nvidia`; do not try `modprobe` in the same boot.
- Verify at the end of the script that the installed module package matches the kernel that will
  boot next (`dpkg -l 'linux-modules-nvidia-*' | grep ^ii` should show the same `<ver>-aws` as
  `linux-image-aws` depends on). If the base dependencies script upgraded the kernel without a
  reboot, the reboot in step 2 also brings the new kernel up; the module metapackage covers it.

### 4. `scripts/system_add_nvtop.sh`

```bash
sudo apt-get install -y nvtop
/usr/bin/nvtop --version
```
(`nvtop` is in `universe`; `btop` is already on the base.) If apt lists were cleaned between steps,
run `sudo apt-get update` first.

### 5. `scripts/system_add_ollama.sh`

Mirror the official Linux install, pinned or latest:

- Resolve `OLLAMA_VERSION` (env override) or latest tag via
  `https://api.github.com/repos/ollama/ollama/releases/latest` (same pattern and error handling as
  `system_add_zoxide.sh`).
- Download `ollama-linux-amd64.tgz` for that tag, extract into `/usr/local` (yields
  `/usr/local/bin/ollama` and `/usr/local/lib/ollama/*` including the bundled CUDA runtime).
- Create system user/group `ollama` (`--system --no-create-home --home-dir /usr/share/ollama --shell
  /bin/false`), add `ubuntu` to group `ollama`.
- Write `/etc/systemd/system/ollama.service` equivalent to the official unit:
  `User=ollama`, `Group=ollama`, `ExecStart=/usr/local/bin/ollama serve`, `Restart=always`,
  `RestartSec=3`, `Environment="PATH=$PATH"`, `[Install] WantedBy=default.target`.
  **Do not set `OLLAMA_HOST`.** The default is `127.0.0.1:11434`, which is the only approved bind.
- `systemctl daemon-reload && systemctl enable --now ollama`, then `/usr/local/bin/ollama --version`.
- Do not pull any model.

### 6. `tests/goss.yaml` — complete file, hardware-independent

Start from a **copy** of `vm-images/aws/agentic/build/ubuntu26/tests/goss.yaml` (the harness ships
only this target's goss file, and the policy test requires the ai-toolchain executable assertions to be
present here too), keep the same `gossfile:` includes, and append a GPU section. Everything below
passes on the `t3.medium` test instance:

```yaml
package:
  nvidia-driver-580-server: {installed: true}          # match NVIDIA_BRANCH
  nvidia-utils-580-server: {installed: true}
  linux-modules-nvidia-580-server-aws: {installed: true}
  nvtop: {installed: true}
file:
  /usr/bin/nvidia-smi: {exists: true}
  /usr/local/bin/ollama: {exists: true, mode: "0755"}
  /etc/systemd/system/ollama.service: {exists: true}
user:
  ollama: {exists: true}
service:
  ollama: {enabled: true, running: true}               # runs in CPU mode without a GPU
port:
  tcp:11434:
    listening: true
    ip: ["127.0.0.1"]                                  # loopback only
command:
  "/usr/local/bin/ollama --version": {exit-status: 0}
  "/usr/sbin/modinfo nvidia":        {exit-status: 0}  # module present for the running kernel
  "/usr/bin/apt-mark showhold":
    exit-status: 0
    stdout: ["nvidia-driver-580-server"]
```

Do **not** put `nvidia-smi -L` or any `lsmod nvidia` assertion in goss; the test instance has no GPU
and the module will not load there. Those checks live in the Packer build (step 5 above). Use full
paths in `command:` tests (goss runs with a minimal PATH, per the base CLAUDE.md gotchas).

### 7. `CLAUDE.md` for the target

Follow the sibling files. State: chained from `agentic/ubuntu26` via `tag:Name … -PASSED`, why the
builder is `g6.xlarge`, why goss is hardware-independent and where the GPU smoke test lives, the
driver branch and hold policy, the loopback-only Ollama rule, and that model weights are never baked.

### 8. Documentation

- `README.md`: Repository Structure and Supported Builds table (new row: `agentic/ubuntu26-gpu`,
  x86_64, chained, g6.xlarge builder).
- `vm-images/aws/agentic/build/ubuntu26/CLAUDE.md`: note that `ubuntu26-gpu` is the first chained
  target, so the "Chained Pattern" section is now exercised.

## CI and cost

- The new directory is a target automatically. Every change under it triggers a `g6.xlarge` build in
  `ami-build-on-change.yml`; a change to a `common/scripts/*.sh` it references also selects it. A GPU
  build is short (the base did the heavy work) but not free. If that is unwanted, the options are a
  matrix exclusion for this target plus manual dispatch only, or accepting the cost. Decide with the
  user before merging; default is to accept.
- The chained source only exists after an `agentic/ubuntu26` build has passed. A base rebuild does
  not automatically rebuild the GPU image; rebuild it manually when the base changes.
- Cleanup (`ami-cleanup-old.yml`) already matches `agentic-packer-*`; no change.

## Verification checklist (implementer)

1. `packer validate` with the harness's `-var` set, from the target directory.
2. `python3 -m unittest discover -s tests` at repo root: all policy tests green, including the
   ai-toolchain goss coverage test against the new goss file.
3. `../../../../scripts/packer-build-and-test.sh` from the target directory. Expect: g6.xlarge builder,
   reboot mid-build, smoke test output showing `NVIDIA L4` and a cuda library line from Ollama, goss
   green on `t3.medium`, AMI Name tag ending in `-PASSED`.
4. Launch the produced AMI as `g6.2xlarge` in `us-west-2c` (the launcher's `gpu-node` sidecar can do
   this with a new `ubuntu26-gpu` config entry) and confirm within one boot: `nvidia-smi` shows the
   L4, `systemctl is-active ollama`, `ss -ltn` shows `127.0.0.1:11434` only, `nvtop` starts,
   `claude --version` and `herdr --version` work for `ubuntu` (agentic layer intact).

## Follow-ups in `cloudberry-dev-env-launcher` (not this repo)

- `config/os-config-agentic.yaml`: add `ubuntu26-gpu` with `ami_filter: "agentic-packer-ubuntu26-gpu-*"`,
  `username: ubuntu`, and a marker so `os-selector` never offers it for database nodes; make it the
  default AMI key in `bin/gpu-node`.
- The running GPU node keeps its current AMI (`ignore_changes = [ami]`). Moving it to this image is a
  deliberate `terraform apply -replace`, which recreates the root volume. Consider the optional
  models data volume in `gpu-node` first so weights survive rebuilds.
- Launcher AMI filters match by name and therefore include `-FAILED` builds; pre-existing behavior,
  out of scope here.

## Out of scope

Model weights in the image; CUDA toolkit; `nvidia-container-toolkit` / Docker GPU; Open WebUI or any
HTTP front end; opening 11434 beyond loopback; an arm64 GPU variant (no arm64 L4 instance exists);
changes to `agentic/ubuntu26` or `ubuntu26-arm64` provisioner lists.
