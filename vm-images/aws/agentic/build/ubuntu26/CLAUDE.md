# agentic/ubuntu26 - Claude AI Context

Standalone AI-tooling AMI on Ubuntu 26.04 (`ubuntu-resolute`) (`vm-images/aws/agentic/build/ubuntu26/`). This is the first `agentic`-family target and, unlike future agentic targets, it builds directly from the stock Ubuntu 26.04 minimal AMI rather than chaining from another family's tested image. Ships the full AI agent toolchain (Claude CLI, ai-toolchain, omnigent, herdr, beads) in addition to the same Kubernetes/cloud tooling as the `synxdb-cloud` operations images.

## Standalone Exception

Every other target in this repository either builds from a base OS AMI within
its own family lineage, or (for future agentic targets) is expected to chain
from another family's already-tested `*-PASSED` AMI via `base_family`/`base_os`
HCL variables. `agentic/ubuntu26` is the deliberate exception: it builds
directly from the stock `*ubuntu-resolute-26.04-amd64-minimal-*` AMI (owner
`099720109477`, Canonical) because no other family currently ships an
Ubuntu 26.04 target to chain from. When a `cloudberry` or `synxdb-cloud`
Ubuntu 26.04 target exists, new agentic targets on that OS should chain from
its `-PASSED` AMI instead of repeating this standalone pattern.

## How This Differs from synxdb-cloud/ubuntu24

| Aspect | synxdb-cloud/ubuntu24 | agentic/ubuntu26 |
|--------|------------------------|-------------------|
| Purpose | Cloud operations | AI agent development |
| Base AMI | Ubuntu 24.04 (Noble) | Ubuntu 26.04 (`ubuntu-resolute`), standalone |
| AI tooling | None | Full toolchain (this is the only family that ships it) |
| Kubernetes / cloud CLIs | Yes | Yes (same provisioners) |
| DBaaS package | Disabled (provisioner commented out) | Disabled (provisioner commented out) |

## AI Tooling Shipped (agentic-only)

AI tooling must never appear in `cloudberry` or `synxdb-cloud` templates — a
repository policy test (`test_ai_tooling_ships_only_in_agentic_family`)
enforces this boundary. On this target:

- `system_add_ai_toolchain.sh` (DB_USERNAME=ubuntu) - single consolidated
  per-user install: claude, pi, codex, copilot, gemini, cursor-agent, kimi,
  opencode, hermes (each self-updating)
- `system_add_omnigent.sh` (DB_USERNAME=ubuntu) - Omnigent
- `system_add_claude.sh` x2 (gpadmin, cbadmin) - standalone Claude CLI install
  for the two DB admin users; `ubuntu` gets Claude via the ai-toolchain above
- `system_add_herdr.sh` - agent multiplexer, installs system-wide
  (`/usr/local/bin/herdr`), not per-user
- `system_add_beads.sh` - beads/`bd`
- `system_configure_claude.sh` x3 (gpadmin, cbadmin, ubuntu) - Claude Code
  settings
- Goss coverage: `tests/goss.yaml` must assert every executable the
  ai-toolchain installer verifies at `/home/ubuntu/<suffix>` (see
  `system_add_ai_toolchain.sh`'s verification loop), plus
  `/usr/local/bin/herdr`

## Provisioner Order (main.pkr.hcl)

1. `system_add_synxdb_cloud_dependencies.sh` - OS packages (apt)
2. `system_set_default_locale.sh` - en_US.UTF-8 system locale (DEB-only)
3. `python3 -m venv` + `pip install` (inline) - Python venv for omnistrate-cli-tools + synxdb-cli
4. `system_adduser_dbadmin.sh` x2 - gpadmin, cbadmin
5. `system_add_yq.sh`
6. `system_add_awscli.sh`
7. `system_add_azure_cli.sh` / `system_add_gcloud_cli.sh`
8. `system_set_timezone.sh`
9. `system_config_starship_prompt.sh`
10. `system_add_swap.sh`
11. `dbadmin_configure_environment.sh` x3 - gpadmin, cbadmin, ubuntu
12. `system_add_gh.sh` - GitHub CLI
12b. `system_add_glow.sh` - glow (terminal markdown viewer, Charm repo)
13. `system_add_helm_kubectl.sh` - Helm + kubectl
14. `system_add_omnistrate_ctl.sh` - Omnistrate CLI
15. Tooling: k9s, kind, terraform, tofu, packer, age, sops, ansible, uv, nodejs (required by omnigent's claude/codex/pi harnesses)
16. `system_add_ai_toolchain.sh` (ubuntu) - AI agent toolchain
17. `system_add_omnigent.sh` (ubuntu)
18. `system_add_1password_cli.sh` / `system_add_direnv.sh`
19. `system_add_motd_manager.sh` - MOTD with `synx` template
20. `system_add_claude.sh` x2 - gpadmin, cbadmin
21. `system_add_gitleaks.sh`
22. `system_add_cloudsmith_cli.sh`
23. Tooling: autoenv, git-profiles, zellij, herdr, hwatch, dysk, zoxide, golang, dolt, beads, bun
24. `system_configure_ssh_agent_tmux.sh`
25. `system_configure_claude.sh` x3 - gpadmin, cbadmin, ubuntu
26. `system_add_goss.sh` - Must be near end
27. `system_add_docker.sh`

## Ubuntu 26.04 Base AMI Gotchas

Inherited from the `ubuntu-resolute` minimal source AMI and shared with
DEB-based targets generally:

- **SSH uses systemd socket activation** - `ssh.socket` listens on a
  dual-stack IPv6 socket and triggers `ssh.service` on demand; goss
  `service: sshd` / `port: tcp:22` assertions from RPM platforms do not hold.
  Test the sshd process and an `ss` listener check instead
- **PEP 668 externally managed Python** - `sudo pip install` and
  `python3 -m ensurepip` fail; use apt's `python3-pip`/`python3-venv` and
  per-user venvs
- **bat installs as batcat** - test `/usr/local/bin/bat` (symlink created by
  the dependencies script)
- **`lsb_release` is required** by common provisioners that add APT repos
  (`docker`, `packer`, `azure-cli`); the dependencies script installs
  `lsb-release`
- **Helm writes version to stderr** - goss cannot match stdout patterns for
  `helm version`; test via file existence only
- **Goss interprets `{{` as templates** - cannot use `helm version --template`
  in goss tests
- **Use full paths in goss command tests** - goss runs with minimal PATH;
  `/usr/local/bin/` binaries need absolute paths

## Chained Pattern for Future Agentic Targets

Future agentic targets (e.g. an agentic AMI layered on top of a tested
`cloudberry` or `synxdb-cloud` image) are expected to chain rather than
rebuild from a stock OS AMI:

1. Add `base_family` and `base_os` HCL variables to the new target's
   `main.pkr.hcl`.
2. Use those variables to select the source AMI: the most recent
   `<base_family>-packer-<base_os>-*-PASSED` AMI owned by this account in
   `us-west-2`, instead of a `source_ami_filter` against a public
   marketplace AMI.
3. Layer only the AI-tooling provisioners on top (ai-toolchain, omnigent,
   claude, herdr, beads, configure-claude) — the base family's provisioners
   already cover OS setup, users, and cloud/dev tooling.
4. Keep the AI-tooling boundary: only `agentic` templates may reference the
   AI scripts listed above.
5. `agentic/ubuntu26` remains standalone because it is the first target on
   its OS; do not treat it as the template for the *build strategy* of later
   agentic targets, only for the *provisioner list*.
