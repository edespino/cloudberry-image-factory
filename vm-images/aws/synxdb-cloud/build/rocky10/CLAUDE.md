# rocky10-synxdb-cloud - Claude AI Context

SynxDB Cloud-optimized AMI on Rocky Linux 10. Minimal operations image (no build toolchain) with Kubernetes tooling (helm, kubectl), omnistrate-ctl, and the Cloudsmith CLI. Cloudsmith credentials are supplied at runtime through 1Password, not during the AMI build.

## How This Differs from Standard rocky10

| Aspect | rocky10 | rocky10-synxdb-cloud |
|--------|---------|---------------------|
| Purpose | Development build AMI | Cloud operations |
| Build tools | gcc, cmake, etc. | None |
| Kubernetes | No | helm + kubectl |
| omnistrate-ctl | No | Yes (latest from GitHub) |
| DBaaS package | No | Disabled (provisioner commented out) |
| Claude CLI | No | Yes (gpadmin, cbadmin, rocky) |
| Ulimits | Yes | No |
| Kernel configs | Yes | No |

## Reference Platforms

When refactoring, use `al2023-synxdb-cloud` for the cloud-specific provisioner ordering.

## Provisioner Order (main.pkr.hcl)

1. `system_configure_dnf.sh` - DNF resilience (must be first)
2. `system_add_synxdb_cloud_dependencies.sh` - OS packages
3. `python3 -m venv` + `pip install` (inline) - Python venv at `/home/rocky/.venv` with deps for omnistrate-cli-tools + synxdb-cli
4. `system_adduser_dbadmin.sh` x2 - gpadmin, cbadmin
5. `system_add_yq.sh`
6. `system_add_awscli.sh`
7. `system_set_timezone.sh`
8. `system_config_starship_prompt.sh`
9. `system_add_swap.sh`
10. `dbadmin_configure_environment.sh` x2 - gpadmin, cbadmin
11. `system_add_gh.sh` - GitHub CLI
12. `system_add_helm_kubectl.sh` - Helm + kubectl (SHA256 verified, bash completion)
13. `system_add_omnistrate_ctl.sh` - Omnistrate CLI (latest release, platform-detected)
14. ~~`system_add_synxdb_dbaas.sh`~~ - DBaaS offline package (disabled, commented out)
15. `system_add_motd_manager.sh` - MOTD with `synx` template
16. `system_add_claude.sh` x3 - gpadmin, cbadmin, rocky
17. `system_add_goss.sh` - Must be near end
18. `system_add_docker.sh`

## Shell Aliases (via /etc/profile.d/)

- `da` — `direnv allow` (approve `.envrc` in current directory)
- `dr` — `direnv reload` (force re-evaluate current `.envrc`)

**Note:** `cd`-based reload aliases don't work with direnv. direnv hooks into `PROMPT_COMMAND`, which only fires between commands. Any alias that `cd`s away and back in a single prompt cycle results in no net `$PWD` change, so direnv sees nothing. Use `direnv reload` directly.

## Rocky 10 Base AMI Gotchas

- **Do NOT add `python3` to dnf install** - already on the base AMI; adding it causes version conflicts with `python-unversioned-command`
- **Python deps use a venv** at `/home/rocky/.venv` — no system-level pip or ensurepip needed
- **Use `/home/rocky/.venv/bin/pip`** for package operations, not system `pip3`
- **Use `util-linux`** not `util-linux-ng` - the `-ng` suffix was dropped in later RHEL/Rocky releases
- **Helm writes version to stderr** - goss cannot match stdout patterns for `helm version`; test via file existence only
- **Goss interprets `{{` as templates** - cannot use `helm version --template` in goss tests
- **Use full paths in goss command tests** - goss runs with minimal PATH; `/usr/local/bin/` binaries need absolute paths
- **Do NOT include `common-security.yaml`** - tests ulimits and kernel params that this platform intentionally omits
