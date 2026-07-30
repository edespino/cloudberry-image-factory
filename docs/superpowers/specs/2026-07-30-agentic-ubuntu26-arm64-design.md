# Design: agentic/ubuntu26-arm64 Target (Graviton)

Date: 2026-07-30
Repo: cloudberry-image-factory
Status: Approved design, pending implementation plan

## Problem

The `agentic` family builds a single x86_64 target (`ubuntu26`,
`t3.2xlarge`, Canonical `amd64-minimal` source AMI). An arm64 (Graviton)
variant of the same image is wanted. The repository is partially
arch-aware: 18 shared provisioner scripts already detect the CPU
architecture via `uname -m` case blocks, and `gh`/`azure-cli` use
`dpkg --print-architecture`, but 10 shared scripts hardcode x86 download
URLs, the build/test harness hardcodes the goss test instance type
(`t3.medium`), and one tool (dysk) ships no prebuilt arm64 binary.

## Ground truth this design builds on (main 84eec51, 2026-07-30)

- 7 targets across 3 families; `agentic/ubuntu26` is the only agentic
  target and builds standalone from the stock Canonical
  `*ubuntu-resolute-26.04-amd64-minimal-*` AMI (owner `099720109477`).
- CI matrix is directory-derived (`.github/scripts/compute-build-matrix.sh`);
  a new `vm-images/aws/<family>/build/<os>/` directory with a
  `main.pkr.hcl` auto-registers. Editing a shared script selects every
  target whose template references it (grep-matched).
- Arch-hardcoded shared scripts (10): `system_add_yq.sh`,
  `system_add_awscli.sh`, `system_add_gcloud_cli.sh`,
  `system_add_golang.sh` (amd64-only pinned SHA256),
  `system_add_goss.sh`, `system_add_helm_kubectl.sh`,
  `system_add_docker.sh` (`deb [arch=amd64]`),
  `system_add_1password_cli.sh` (`deb [arch=amd64]` + amd64 repo path),
  `system_config_starship_prompt.sh` (`ARCH="x86_64"`),
  `dbadmin_configure_environment.sh` (`just` x86_64 musl tarball).
- `system_add_dysk.sh` installs a prebuilt binary available for x86_64
  only and already SKIPs cleanly on other architectures;
  `agentic/build/ubuntu26/tests/goss.yaml:323` asserts
  `/usr/local/bin/dysk`.
- Harness `vm-images/scripts/packer-build-and-test.sh:569` hardcodes
  `--instance-type "t3.medium"` for the goss test instance; an arm64 AMI
  cannot launch on t3.
- `tests/test_packer_build_security.py:702` asserts the harness passes
  `t3.medium` to `run-instances` (fake-AWS-shim behavioral test).
- `tests/test_repository_policy.py` policy tests glob all
  `vm-images/aws/*/build/*/main.pkr.hcl`, so a new target auto-joins
  most policy checks. `test_agentic_ubuntu26_goss_covers_ai_toolchain_executables`
  hardcodes the `ubuntu26` goss path only.
- The AI toolchain (`system_add_ai_toolchain.sh`) installs 10 tools via
  vendor install scripts that self-detect arch, then hard-fails unless
  every expected binary exists. arm64 support is confirmed for claude
  and the npm-based tools; unverified for hermes, antigravity,
  cursor-agent, kimi.

## Decisions (confirmed with user)

- **Target shape:** new sibling directory
  `vm-images/aws/agentic/build/ubuntu26-arm64/` alongside the untouched
  x86 `ubuntu26` target. Both keep building.
- **dysk:** omitted from the arm64 target — no provisioner, no goss
  assertion. No source build.
- **AI toolchain gaps:** keep strict hard-fail verification. The first
  arm64 build surfaces any vendor installer without arm64 support; each
  gap then becomes an explicit per-tool decision.
- **Arch handling location:** shared scripts become arch-aware
  (Approach A). No per-target script forks. The resulting one-time
  fleet rebuild in CI is accepted as x86 regression proof.

## Design

### 1. New target directory

`vm-images/aws/agentic/build/ubuntu26-arm64/`:

- `main.pkr.hcl` — copy of `ubuntu26/main.pkr.hcl` with three deltas:
  - `source_ami_filter` name `*ubuntu-resolute-26.04-arm64-minimal-*`
    (same owner `099720109477`);
  - `instance_type = "t4g.2xlarge"`;
  - `system_add_dysk.sh` provisioner removed.
- `scripts/system_add_synxdb_cloud_dependencies.sh` — copied from
  `ubuntu26` (apt package list, arch-neutral).
- `tests/goss.yaml` — copied from `ubuntu26` minus the dysk assertion;
  audit for any arch-specific stdout matches during implementation.
- `CLAUDE.md` — target context documenting the arm-specific deltas and
  pointing at the x86 sibling as the provisioner-order reference.

Identity derives from the path: `FAMILY=agentic`,
`OS_NAME=ubuntu26-arm64`; AMIs named
`agentic-packer-ubuntu26-arm64-<timestamp>`. CI needs no workflow edits.

### 2. Arch-aware shared scripts (10 edits)

Each gains the repository-standard case block

```sh
case "$(uname -m)" in
  x86_64)        ARCH=... ;;
  aarch64|arm64) ARCH=... ;;
  *)             echo "ERROR: Unsupported architecture: $(uname -m)"; exit 1 ;;
esac
```

with per-vendor naming:

| Script | x86_64 asset | arm64 asset |
|--------|--------------|-------------|
| `system_add_yq.sh` | `yq_linux_amd64` | `yq_linux_arm64` (checksum grep key follows) |
| `system_add_awscli.sh` | `awscli-exe-linux-x86_64.zip` | `awscli-exe-linux-aarch64.zip` |
| `system_add_gcloud_cli.sh` | `google-cloud-cli-linux-x86_64.tar.gz` | `google-cloud-cli-linux-arm.tar.gz` |
| `system_add_golang.sh` | `go<ver>.linux-amd64.tar.gz` + pinned SHA | `go<ver>.linux-arm64.tar.gz` + second pinned SHA |
| `system_add_goss.sh` | `goss_<ver>_linux_x86_64.tar.gz` | arm64 tarball from the same release (exact asset name verified against the pinned release during implementation) |
| `system_add_helm_kubectl.sh` | `linux-amd64` (both tools) | `linux-arm64` (both tools) |
| `system_config_starship_prompt.sh` | `starship-x86_64-unknown-linux-gnu` | `starship-aarch64-unknown-linux-musl` (no gnu build for aarch64) |
| `dbadmin_configure_environment.sh` | `just-<ver>-x86_64-unknown-linux-musl.tar.gz` | `just-<ver>-aarch64-unknown-linux-musl.tar.gz` |

APT repo lines switch from a hardcoded arch to the host's:

- `system_add_docker.sh` — `deb [arch=$(dpkg --print-architecture) ...]`
  (both the ubuntu and debian branches).
- `system_add_1password_cli.sh` — same substitution; the repo URL path
  component (`.../linux/debian/amd64`) also becomes the detected arch.

Constraint: on x86_64 every script must resolve to byte-identical URLs
and behavior as today. Existing checksum/signature verification rigor is
preserved per-arch (no verification downgraded to make arm64 work).

### 3. Harness: arch-aware test instance type

`vm-images/scripts/packer-build-and-test.sh` queries the built AMI once
before launching the test instance:

```
aws ec2 describe-images --image-ids "${AMI_ID}" \
  --query 'Images[0].Architecture' --output text
```

Mapping: `arm64` → `t4g.medium`; anything else → `t3.medium` (current
behavior preserved, including for `--existing-ami` recovery runs).

### 4. Test suite updates

- `tests/test_packer_build_security.py` — the `t3.medium` assertion
  becomes two behavioral cases against the fake AWS shim: x86_64 AMI →
  `t3.medium`, arm64 AMI → `t4g.medium` (shim's `describe-images`
  response gains an `Architecture` field).
- `tests/test_repository_policy.py` —
  `test_agentic_ubuntu26_goss_covers_ai_toolchain_executables`
  generalized to iterate every `agentic` target's `goss.yaml` so
  `ubuntu26-arm64` gets the same AI-toolchain coverage guarantee.
- Glob-based policy tests (AI-tooling boundary, naming, private-only,
  ami_description comment) pick the new template up automatically —
  verified by running the suite, not assumed.

### 5. Documentation

- Root `CLAUDE.md`: Current Platforms table gains
  `agentic | ubuntu26-arm64` (8 targets).
- `README.md`: Repository Structure and Supported Builds sections.
- Target `CLAUDE.md` as described in section 1.

## Error handling

- Unsupported-arch inputs fail loudly (`exit 1`) in every touched
  script, matching the existing 18 arch-aware scripts.
- The AI toolchain's hard-fail verification loop is unchanged; a vendor
  installer without arm64 support fails the build at that provisioner
  with the tool name in the log.
- Harness: if `describe-images` returns no architecture, the mapping
  falls through to `t3.medium`; an arm64 AMI then fails at
  `run-instances` with an explicit incompatibility error (no silent
  wrong-arch test pass is possible — the instance simply cannot launch).

## Testing

1. `python3 -m unittest discover -s tests` — harness + policy suites.
2. `packer validate` in the new target directory.
3. Local full build:
   `cd vm-images/aws/agentic/build/ubuntu26-arm64 && ../../../../scripts/packer-build-and-test.sh`
   — goss must pass on a `t4g.medium` instance and the AMI must be
   renamed `-PASSED`.
4. An x86 rebuild of `agentic/ubuntu26` after the shared-script edits
   (locally or via the CI fleet rebuild on push) as the no-regression
   check.

## Out of scope

- arm64 targets for `cloudberry` / `synxdb-cloud` families.
- Building dysk from source.
- Any behavioral change to the x86 `ubuntu26` target.
- Multi-arch AMI aliasing/SSM parameter publishing.

## Risks

- Vendor installers (hermes, antigravity, cursor-agent, kimi) may lack
  arm64 builds — surfaced by the first build (decision: hard-fail).
- Per-arch pinned checksums (golang, goss, just) must be sourced from
  the vendors' published checksum files for the exact pinned versions.
- The fleet rebuild triggered by the 10 shared-script edits rebuilds
  most of the 7 existing targets on push; expected and intentional.
