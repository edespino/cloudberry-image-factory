# ubuntu24-synxdb-cloud - Claude AI Context

SynxDB Cloud-optimized AMI on Ubuntu 24.04 (Noble). Minimal operations image (no build toolchain) with Kubernetes tooling (helm, kubectl), omnistrate-ctl, and Cloudsmith credentials managed via 1Password. DEB/apt port of `rocky10-synxdb-cloud`.

## How This Differs from Standard ubuntu22

| Aspect | ubuntu22 | ubuntu24-synxdb-cloud |
|--------|----------|----------------------|
| Purpose | Development build AMI | Cloud operations |
| Build tools | gcc, cmake, etc. | None |
| Kubernetes | No | helm + kubectl |
| omnistrate-ctl | No | Yes (latest from GitHub) |
| DBaaS package | No | Disabled (provisioner commented out) |
| Claude CLI | gpadmin, cbadmin | Yes (gpadmin, cbadmin, ubuntu) |
| Ulimits | Yes | No |
| Kernel configs | Yes | No |

## Reference Platforms

This platform is the DEB/apt port of `rocky10-synxdb-cloud` — mirror its provisioner set and ordering. Use `ubuntu22` for DEB-platform idioms (apt dependency script style, locale configuration, Ubuntu AMI source filters).

## Provisioner Order (main.pkr.hcl)

1. `system_add_synxdb_cloud_dependencies.sh` - OS packages (apt)
2. `system_set_default_locale.sh` - en_US.UTF-8 system locale (DEB-only)
3. `python3 -m venv` + `pip install` (inline) - Python venv at `/home/ubuntu/.venv` with deps for omnistrate-cli-tools + synxdb-cli
4. `system_adduser_dbadmin.sh` x2 - gpadmin, cbadmin
5. `system_add_yq.sh`
6. `system_add_awscli.sh`
7. `system_add_azure_cli.sh` / `system_add_gcloud_cli.sh`
8. `system_set_timezone.sh`
9. `system_config_starship_prompt.sh`
10. `system_add_swap.sh`
11. `dbadmin_configure_environment.sh` x3 - gpadmin, cbadmin, ubuntu
12. `system_add_gh.sh` - GitHub CLI
13. `system_add_helm_kubectl.sh` - Helm + kubectl (SHA256 verified, bash completion)
14. `system_add_omnistrate_ctl.sh` - Omnistrate CLI (latest release, platform-detected)
15. Tooling: k9s, kind, terraform, tofu, packer, age, sops, ansible, uv, nodejs, pi, hermes, omnigent, 1password-cli, direnv
16. ~~`system_add_synxdb_dbaas.sh`~~ - DBaaS offline package (disabled, commented out)
17. `system_add_motd_manager.sh` - MOTD with `synx` template
18. `system_add_claude.sh` x3 - gpadmin, cbadmin, ubuntu
19. Tooling: gitleaks, opencode, cloudsmith-cli, autoenv, git-profiles, zellij, herdr, hwatch, dysk, zoxide, golang, dolt, beads, bun, gastown, emacs, ssh-agent-tmux, configure-claude x3
20. `system_add_goss.sh` - Must be near end
21. `system_add_docker.sh`

## Differences from rocky10-synxdb-cloud (RPM → DEB)

- **No `system_configure_dnf.sh`** - RPM-only
- **No kernel upgrade + reboot** - Rocky 10 needed `kernel-modules-extra` for Docker's xt_addrtype/br_netfilter; Ubuntu AWS kernels ship those modules in the default `linux-modules-*-aws` package
- **No ensurepip/system pip upgrade** - Debian/Ubuntu disable ensurepip and the system Python is PEP 668 externally managed; `python3-pip`/`python3-venv` come from apt
- **tmux from apt** - noble packages tmux 3.4 (Rocky 10 builds it from source); binary is `/usr/bin/tmux`, not `/usr/local/bin/tmux`
- **`system_set_default_locale.sh` added** - DEB platforms configure en_US.UTF-8 explicitly
- **Package renames** - `gnupg2`→`gnupg`, `bind-utils`→`bind9-dnsutils`, `iproute`→`iproute2`, `nc`→`netcat-openbsd`; EPEL tools (htop, bat, ripgrep, bats, btop) come from universe; `which` is provided by the preinstalled `debianutils`
- **bat is batcat** - Debian/Ubuntu install bat as `/usr/bin/batcat`; the dependencies script symlinks `/usr/local/bin/bat`

## Shell Aliases (via /etc/profile.d/)

- `da` — `direnv allow` (approve `.envrc` in current directory)
- `dr` — `direnv reload` (force re-evaluate current `.envrc`)

**Note:** `cd`-based reload aliases don't work with direnv. direnv hooks into `PROMPT_COMMAND`, which only fires between commands. Any alias that `cd`s away and back in a single prompt cycle results in no net `$PWD` change, so direnv sees nothing. Use `direnv reload` directly.

## Ubuntu 24.04 Base AMI Gotchas

- **SSH uses systemd socket activation** - `ssh.socket` listens on a dual-stack IPv6 socket and triggers `ssh.service` on demand; goss `service: sshd` and `port: tcp:22` assertions from the RPM platforms do not hold. Test the sshd process and an `ss` listener check instead
- **PEP 668 externally managed Python** - `sudo pip install` and `python3 -m ensurepip` fail; use apt's `python3-pip`/`python3-venv` and per-user venvs. `pip install --user` needs `--break-system-packages`
- **Python deps use a venv** at `/home/ubuntu/.venv` — use `/home/ubuntu/.venv/bin/pip` for package operations
- **bat installs as batcat** - test `/usr/local/bin/bat` (symlink created by the dependencies script)
- **`lsb_release` is required** by common provisioners that add APT repos (`docker`, `packer`, `azure-cli`); the dependencies script installs `lsb-release`
- **Helm writes version to stderr** - goss cannot match stdout patterns for `helm version`; test via file existence only
- **Goss interprets `{{` as templates** - cannot use `helm version --template` in goss tests
- **Use full paths in goss command tests** - goss runs with minimal PATH; `/usr/local/bin/` binaries need absolute paths
- **Do NOT include `common-security.yaml`** - tests ulimits and kernel params that this platform intentionally omits
