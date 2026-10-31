# Design: openvpn + glab on the Agentic Images (HashData VPN / GitLab path)

Date: 2026-08-03
Repo: cloudberry-image-factory
Status: Approved design, pending implementation plan

## Problem

The HashData workflow on agentic VMs needs a VPN tunnel daemon and the
GitLab CLI: `openvpn` (used by the runtime `hashdata-vpn` helper) and
`glab` (GitLab MRs, used by `hashdata-glab`). Neither package is on the
agentic images today.

## Ground truth this design builds on (main 982b208, 2026-08-03)

- Both packages ship in the Ubuntu 26.04 (resolute) archive — the
  versions observed on a running arm64 VM carry Ubuntu suffixes
  (`openvpn 2.7.0-1ubuntu1.2`, `glab 1.53.0-1build1`), so plain
  `apt-get install` covers both architectures.
- Each agentic target carries its own copy of the apt dependencies
  script: `vm-images/aws/agentic/build/<os>/scripts/system_add_synxdb_cloud_dependencies.sh`
  (unpinned `apt-get install -y` blocks, cleanup at the end).
- Goss package assertions use the `package:` map form
  (`git: {installed: true}` — 32 existing entries on ubuntu26).
- CI: changes under `vm-images/aws/agentic/build/<os>/**` select that
  target in the computed matrix — both targets rebuild, no workflow
  edits.

## Decisions (confirmed with user)

- **Targets:** both `agentic/ubuntu26` and `agentic/ubuntu26-arm64` —
  the siblings stay identical in tooling.
- **Scope: packages only.** The `hashdata-vpn` / `hashdata-glab`
  helper commands, VPN profiles, and GitLab auth are runtime concerns —
  nothing is baked (repo policy: no credentials or site config in
  images).
- **Unpinned**, matching every other apt install in the dependencies
  scripts; the observed versions above are descriptive, not pins.

## Design

### 1. Dependencies scripts (both targets)

Append to `scripts/system_add_synxdb_cloud_dependencies.sh` in both
target directories, before the cleanup step:

```bash
# HashData VPN / GitLab path: openvpn (tunnel daemon), glab (GitLab CLI for
# MRs). VPN profiles and GitLab auth are runtime concerns — nothing is baked.
sudo apt-get install -y openvpn glab
```

### 2. Goss tests (both targets)

Add to the existing `package:` map in `tests/goss.yaml`, byte-identical
in both files:

```yaml
  # HashData VPN / GitLab path
  openvpn: {installed: true}
  glab: {installed: true}
```

Plus one command check following the existing full-path idiom:

```yaml
  # GitLab CLI functionality check
  "/usr/bin/glab version":
    exit-status: 0
    timeout: 10000
```

No openvpn command or service assertion: without a baked profile the
daemon is intentionally inert, and asserting an unconfigured service
tests nothing.

## Error handling

- `apt-get install -y` failure fails the provisioner (script runs under
  the packer shell provisioner; non-zero exit aborts the build).
- A missing package at test time fails goss and the AMI is renamed
  `-FAILED`.

## Testing

1. `python3 -m unittest tests.test_repository_policy -v` — policy suite
   (no new requirements expected; regression check).
2. Local build of one target:
   `cd vm-images/aws/agentic/build/ubuntu26 && ../../../../scripts/packer-build-and-test.sh`
   — goss must pass (two new package assertions + glab command check)
   and the AMI must be renamed `-PASSED`. CI covers the arm64 sibling
   on push.

## Out of scope

- `hashdata-vpn` / `hashdata-glab` wrapper scripts.
- VPN profiles, certificates, GitLab tokens, or any site configuration.
- Version pinning.
- Non-agentic families.

## Risks

- None notable: both packages are archive-native on both architectures,
  and the change follows the existing dependencies-script pattern
  exactly.
