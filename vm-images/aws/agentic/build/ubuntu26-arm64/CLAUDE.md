# agentic/ubuntu26-arm64 - Claude AI Context

arm64 (Graviton) sibling of `agentic/ubuntu26`
(`vm-images/aws/agentic/build/ubuntu26-arm64/`). Same standalone AI-tooling
image on Ubuntu 26.04 (`ubuntu-resolute`), built for arm64. See
`../ubuntu26/CLAUDE.md` for the provisioner order, the standalone-exception
rationale, the AI-tooling boundary, and the Ubuntu 26.04 base-AMI gotchas —
all of which apply here unchanged.

## Deltas from agentic/ubuntu26 (x86_64)

- Source AMI filter: `*ubuntu-resolute-26.04-arm64-minimal-*` (same
  Canonical owner `099720109477`).
- Build instance: `t4g.2xlarge` (Graviton). The harness launches the goss
  test instance as `t4g.medium` (selected automatically from the AMI's
  `Architecture` field).
- **No dysk**: the vendor ships x86_64-only prebuilt binaries, so the
  `system_add_dysk.sh` provisioner and the dysk goss assertion are omitted
  on this target. Do not "fix" the difference by re-adding either one.
- Every other provisioner is shared with the x86 target; arch selection
  happens inside the shared scripts (`uname -m` /
  `dpkg --print-architecture`), never in this template.

## Keeping the siblings in sync

A provisioner or goss change for one ubuntu26 target almost always belongs
in both. When editing this target or `../ubuntu26`, mirror the change in
the sibling (dysk being the deliberate exception).
