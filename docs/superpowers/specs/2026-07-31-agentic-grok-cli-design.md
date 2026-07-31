# Design: Grok CLI in the Agentic AI Toolchain

Date: 2026-07-31
Repo: cloudberry-image-factory
Status: Approved design, pending implementation plan

## Problem

The `agentic` family images (`ubuntu26`, `ubuntu26-arm64`) ship a
consolidated AI agent toolchain (`system_add_ai_toolchain.sh`: claude,
pi, codex, copilot, gemini, cursor-agent, kimi, opencode, hermes, agy).
The xAI Grok CLI is wanted on these images.

## Ground truth this design builds on (main eaaf889, 2026-07-31)

- Install command (user-provided): `curl -fsSL https://x.ai/cli/install.sh | bash`.
- Installer facts (verified by fetching the script 2026-07-31):
  - Installs to `$HOME/.grok/bin/grok` by default
    (`BIN_DIR="${GROK_BIN_DIR:-$HOME/.grok/bin}"`); a sibling `agent`
    binary lands in the same directory.
  - Supports `x86_64` and `aarch64` Linux — both agentic targets covered.
  - Symlinks into `~/.local/bin` only when that directory is already on
    PATH and writable; not true in the packer provisioner session, so
    `~/.grok/bin/grok` is the testable artifact (same native-path
    pattern as kimi at `~/.kimi-code/bin/kimi` and opencode at
    `~/.opencode/bin/opencode`).
  - Appends a PATH block for `~/.grok/bin` to `.bashrc` itself.
  - Unpinned by default; installs latest stable — matches the
    toolchain's documented versioning policy (latest stable at build
    time, resolved versions captured in the build report).
  - Auth (`grok login` / `GROK_DEPLOYMENT_KEY`) is a runtime concern;
    nothing credential-related is baked, consistent with the toolchain
    policy.
- `system_add_ai_toolchain.sh` is the single consolidated per-agent
  installer for user `ubuntu`; its verification loop hard-fails the
  build if any expected binary is missing.
- Policy test `test_agentic_goss_covers_ai_toolchain_executables`
  derives the expected executables from that verification loop and
  requires every agentic target's `goss.yaml` to assert each one —
  adding grok to the loop automatically extends the requirement.
- CI matrix is grep-derived: editing `system_add_ai_toolchain.sh`
  selects both agentic targets. No workflow edits.

## Decisions (confirmed with user)

- **Approach A:** grok joins `system_add_ai_toolchain.sh` as tool 11.
  No standalone `system_add_grok.sh`.
- **Scope:** user `ubuntu` only, matching every other toolchain tool
  (gpadmin/cbadmin receive only claude).

## Design

### 1. `vm-images/common/scripts/system_add_ai_toolchain.sh`

- Header tool list gains `grok  xAI Grok CLI  ~/.grok/bin/grok`.
- Section headers renumber `[n/10]` → `[n/11]`; new step:

  ```sh
  echo "=== [11/11] grok (xAI Grok CLI) ==="
  run_as_user bash -c 'curl -fsSL https://x.ai/cli/install.sh | bash'
  ```

- Verification loop gains `"${USER_HOME}/.grok/bin/grok"`.
- Version report gains
  `report_version grok "${USER_HOME}/.grok/bin/grok" --version`
  (best-effort by design; the executable check is the hard gate).

### 2. Goss tests (both agentic targets)

`tests/goss.yaml` in `agentic/ubuntu26` and `agentic/ubuntu26-arm64`:

- File assertion following the kimi/opencode native-path pattern:

  ```yaml
  # xAI Grok CLI
  /home/ubuntu/.grok/bin/grok:
    exists: true
  ```

- Version command following the kimi pattern:

  ```yaml
  # xAI Grok CLI version check
  "sudo -n -u ubuntu env HOME=/home/ubuntu PATH=/home/ubuntu/.local/bin:/usr/local/bin:/usr/bin:/bin /home/ubuntu/.grok/bin/grok --version < /dev/null":
    exit-status: 0
    timeout: 30000
  ```

- Whether `grok --version` runs without a TTY is unknown until a build
  runs. If it fails the way agy does, fall back to the executable-only
  pattern (`test -x /home/ubuntu/.grok/bin/grok`) with an explanatory
  comment, as done for agy.

### 3. Comment/documentation updates

- Both `main.pkr.hcl` files: the ai-toolchain provisioner comment's
  tool list gains grok.
- `vm-images/aws/agentic/build/ubuntu26/CLAUDE.md`: AI tooling list
  gains grok. The arm64 target's `CLAUDE.md` does not enumerate the
  tools (it defers to the x86 sibling) — no change there.
- No root `CLAUDE.md`/`README.md` change — neither enumerates
  individual toolchain tools.

## Error handling

- The installer runs under `set -euo pipefail` via `run_as_user`; an
  installer failure fails the provisioner.
- The verification loop hard-fails if `~/.grok/bin/grok` is missing.
- Unsupported-arch is not reachable: both targets are architectures the
  installer supports (it exits 1 on anything else).

## Testing

1. `python3 -m unittest discover -s tests` — policy suite, including
   the toolchain-coverage test now expecting grok in both goss files.
2. `packer validate` in both target directories.
3. Local full build of at least one target:
   `cd vm-images/aws/agentic/build/ubuntu26 && ../../../../scripts/packer-build-and-test.sh`
   — goss must pass and the AMI must be renamed `-PASSED`. The build
   log's version report captures the resolved grok version.

## Out of scope

- grok for gpadmin/cbadmin.
- Version pinning (`install.sh` accepts an `X.Y.Z` argument; not used,
  per toolchain versioning policy).
- Baking auth/config (`~/.grok/config.toml`, `GROK_DEPLOYMENT_KEY`).
- The sibling `agent` binary: not verified, not goss-asserted — only
  grok is the product surface here, and asserting an incidental
  binary couples tests to installer internals.

## Risks

- `grok --version` may require a TTY under goss (as agy does); the
  fallback is defined in section 2.
- Latest-stable install means two builds on different days may bake
  different grok versions — accepted, identical to the other ten tools.
