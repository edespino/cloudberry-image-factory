# agentic/ubuntu26-arm64 (Graviton) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an arm64 (Graviton) build target `agentic/ubuntu26-arm64` alongside the existing x86 `agentic/ubuntu26`, by making 10 shared provisioner scripts arch-aware and teaching the harness to pick the goss test instance type from the AMI architecture.

**Architecture:** New sibling directory `vm-images/aws/agentic/build/ubuntu26-arm64/` (CI auto-registers it from the path). Arch handling lives in the shared scripts via the repository-standard `uname -m` case block — no per-target script forks. The harness queries the built AMI's `Architecture` and maps `arm64` → `t4g.medium`, else `t3.medium`.

**Tech Stack:** Bash provisioner scripts, Packer HCL (amazon-ebs), Goss, Python unittest (fake-AWS-shim behavioral tests), GitHub Actions (no workflow edits needed).

**Spec:** `docs/superpowers/specs/2026-07-30-agentic-ubuntu26-arm64-design.md`

## Global Constraints

- On x86_64, every touched script must resolve to byte-identical download URLs and behavior as today.
- Arch case blocks follow the repository-standard pattern: `x86_64)`, `aarch64|arm64)`, `*)` → `echo "ERROR: Unsupported architecture: $(uname -m)"; exit 1`.
- No checksum/signature verification may be weakened to make arm64 work.
- dysk is x86-only: the arm64 target ships no `system_add_dysk.sh` provisioner and no dysk goss assertion. The x86 `ubuntu26` target is not modified.
- AI-toolchain verification stays strict (hard-fail) — no skip-on-arm64 logic anywhere.
- Test suite command (run from repo root): `python3 -m unittest discover -s tests -v`
- Commits are attributed to the user; never modify git config; no Claude co-author trailers.
- Verified vendor facts baked into this plan (do not re-derive): go1.26.1 linux-arm64 SHA256 `a290581cfe4fe28ddd737dde3095f3dbeb7f2e4065cab4eae44dfc53b760c2f7` (from go.dev/dl JSON); goss arm64 asset is `goss_<ver>_linux_arm64.tar.gz`; AWS CLI arm64 asset is `awscli-exe-linux-aarch64.zip` (+`.sig`); gcloud arm64 tarball is `google-cloud-cli-linux-arm.tar.gz`; starship ships `aarch64-unknown-linux-musl` only (no gnu build for aarch64); 1Password hosts `https://downloads.1password.com/linux/debian/arm64`; `just` ships `aarch64-unknown-linux-musl`; helm/kubectl ship `linux-arm64`.

---

### Task 1: Harness — arch-aware goss test instance type

**Files:**
- Modify: `tests/test_packer_build_security.py` (fake `aws` shim in `_write_fakes`, ~line 68; new tests after `test_existing_ami_skips_packer_and_runs_private_test_flow`, ~line 720)
- Modify: `vm-images/scripts/packer-build-and-test.sh` (insert Step 6b after the Step 6 `fi`, ~line 516; `--instance-type` at line 569)

**Interfaces:**
- Consumes: existing test helpers `self._run(*args, extra_env=...)`, `self._aws_calls()` (parse `aws.log` into arg lists).
- Produces: harness shell variable `TEST_INSTANCE_TYPE` (`"t4g.medium"` | `"t3.medium"`), shim env knob `FAKE_AMI_ARCHITECTURE` (default `"x86_64"`). Task 8 relies on the `arm64` → `t4g.medium` mapping.

- [ ] **Step 1: Extend the fake `aws` shim to answer the architecture query**

In `tests/test_packer_build_security.py`, inside the `_write_fakes` `aws` fake (a triple-quoted Python string), replace:

```python
elif operation == "describe-images":
    print(os.environ.get("FAKE_AMI_METADATA", "fake-ami-name"))
```

with:

```python
elif operation == "describe-images":
    if "Images[0].Architecture" in args:
        print(os.environ.get("FAKE_AMI_ARCHITECTURE", "x86_64"))
    else:
        print(os.environ.get("FAKE_AMI_METADATA", "fake-ami-name"))
```

(`args` is the shim's `sys.argv[1:]`; the harness passes `--query Images[0].Architecture` as a distinct argv element, so exact list membership works.)

- [ ] **Step 2: Write the failing tests**

Add to `tests/test_packer_build_security.py`, immediately after `test_existing_ami_skips_packer_and_runs_private_test_flow` (same class, same indentation as its siblings):

```python
    def test_arm64_ami_launches_graviton_test_instance(self) -> None:
        result = self._run(extra_env={"FAKE_AMI_ARCHITECTURE": "arm64"})

        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        run_instance = next(
            call for call in self._aws_calls()
            if call[:2] == ["ec2", "run-instances"]
        )
        self.assertEqual(
            run_instance[run_instance.index("--instance-type") + 1],
            "t4g.medium",
        )

    def test_x86_64_ami_keeps_t3_test_instance(self) -> None:
        result = self._run()

        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        run_instance = next(
            call for call in self._aws_calls()
            if call[:2] == ["ec2", "run-instances"]
        )
        self.assertEqual(
            run_instance[run_instance.index("--instance-type") + 1],
            "t3.medium",
        )
```

- [ ] **Step 3: Run the new tests to verify the arm64 one fails**

Run: `python3 -m unittest tests.test_packer_build_security -k arm64 -v && python3 -m unittest tests.test_packer_build_security -k t3_test_instance -v`

Expected: `test_arm64_ami_launches_graviton_test_instance` FAILS with `'t3.medium' != 't4g.medium'` (harness doesn't query architecture yet). `test_x86_64_ami_keeps_t3_test_instance` PASSES (documents preserved behavior).

- [ ] **Step 4: Implement the harness change**

In `vm-images/scripts/packer-build-and-test.sh`, replace (the `fi` here closes the Step 2–6 `if [ -z "${EXISTING_AMI}" ]` block — this exact three-line sequence is unique because of the `# Step 7` line):

```bash
  AMI_VALIDATED_FOR_TAGGING=true
fi

# Step 7: Retrieve local IP address to restrict SSH access to the current machine
```

with:

```bash
  AMI_VALIDATED_FOR_TAGGING=true
fi

# Step 6b: Pick the goss test instance type from the AMI architecture
# (arm64 AMIs cannot launch on t3; Graviton t4g is the arm64 equivalent).
AMI_ARCHITECTURE="$(
  aws ec2 describe-images \
    --image-ids "${AMI_ID}" \
    --query "Images[0].Architecture" \
    --output "text" \
    --region "${REGION}"
)"
if [ "${AMI_ARCHITECTURE}" = "arm64" ]; then
  TEST_INSTANCE_TYPE="t4g.medium"
else
  TEST_INSTANCE_TYPE="t3.medium"
fi
echo "AMI architecture: ${AMI_ARCHITECTURE}; test instance type: ${TEST_INSTANCE_TYPE}"

# Step 7: Retrieve local IP address to restrict SSH access to the current machine
```

Then in `run_test_instance()` (~line 569) replace:

```bash
    --instance-type "t3.medium" \
```

with:

```bash
    --instance-type "${TEST_INSTANCE_TYPE}" \
```

- [ ] **Step 5: Run the full build-security suite**

Run: `python3 -m unittest tests.test_packer_build_security -v`

Expected: ALL PASS, including the pre-existing `test_existing_ami_skips_packer_and_runs_private_test_flow` (its `describe-images`-before-`create-security-group` ordering and first-describe-region assertions are unaffected: the metadata query still comes first, and the new query also uses `us-west-2`).

- [ ] **Step 6: Commit**

```bash
git add tests/test_packer_build_security.py vm-images/scripts/packer-build-and-test.sh
git commit -m "harness: pick goss test instance type from AMI architecture"
```

---

### Task 2: Generalize the agentic goss-coverage policy test

**Files:**
- Modify: `tests/test_repository_policy.py:211-234` (`test_agentic_ubuntu26_goss_covers_ai_toolchain_executables`)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: policy test `test_agentic_goss_covers_ai_toolchain_executables` that iterates every `vm-images/aws/agentic/build/*/tests/goss.yaml` — Task 6's new goss.yaml is automatically held to the AI-toolchain coverage guarantee.

- [ ] **Step 1: Replace the ubuntu26-only test with an all-agentic-targets version**

In `tests/test_repository_policy.py`, replace the entire method:

```python
    def test_agentic_ubuntu26_goss_covers_ai_toolchain_executables(self) -> None:
        toolchain = (
            REPOSITORY
            / "vm-images/common/scripts"
            / "system_add_ai_toolchain.sh"
        ).read_text()
        # The installer hard-fails unless every binary in this loop exists;
        # goss must verify each of them (and its version command) too.
        verification_loop = toolchain.split("for BIN in", 1)[1].split("do", 1)[0]
        suffixes = sorted(
            set(re.findall(r'"\$\{USER_HOME\}/([^"]+)"', verification_loop))
        )
        self.assertTrue(suffixes)
        goss = (
            REPOSITORY
            / "vm-images/aws/agentic/build/ubuntu26/tests"
            / "goss.yaml"
        ).read_text()
        for suffix in suffixes:
            path = f"/home/ubuntu/{suffix}"
            with self.subTest(executable=path):
                self.assertIn(path, goss)
        # herdr installs system-wide via its own provisioner
        self.assertIn("/usr/local/bin/herdr", goss)
```

with:

```python
    def test_agentic_goss_covers_ai_toolchain_executables(self) -> None:
        toolchain = (
            REPOSITORY
            / "vm-images/common/scripts"
            / "system_add_ai_toolchain.sh"
        ).read_text()
        # The installer hard-fails unless every binary in this loop exists;
        # goss must verify each of them (and its version command) too.
        verification_loop = toolchain.split("for BIN in", 1)[1].split("do", 1)[0]
        suffixes = sorted(
            set(re.findall(r'"\$\{USER_HOME\}/([^"]+)"', verification_loop))
        )
        self.assertTrue(suffixes)
        goss_files = sorted(
            REPOSITORY.glob("vm-images/aws/agentic/build/*/tests/goss.yaml")
        )
        self.assertTrue(goss_files)
        for goss_file in goss_files:
            goss = goss_file.read_text()
            target = goss_file.parents[1].name
            for suffix in suffixes:
                path = f"/home/ubuntu/{suffix}"
                with self.subTest(target=target, executable=path):
                    self.assertIn(path, goss)
            # herdr installs system-wide via its own provisioner
            with self.subTest(target=target, executable="herdr"):
                self.assertIn("/usr/local/bin/herdr", goss)
```

- [ ] **Step 2: Run the policy suite**

Run: `python3 -m unittest tests.test_repository_policy -v`

Expected: ALL PASS (only `ubuntu26` matches the glob today; behavior is identical until Task 6 adds the second target).

- [ ] **Step 3: Commit**

```bash
git add tests/test_repository_policy.py
git commit -m "tests: hold every agentic target's goss to AI-toolchain coverage"
```

---

### Task 3: Arch-aware download scripts with dynamic checksums (yq, awscli, gcloud, helm/kubectl, starship)

**Files:**
- Modify: `vm-images/common/scripts/system_add_yq.sh`
- Modify: `vm-images/common/scripts/system_add_awscli.sh`
- Modify: `vm-images/common/scripts/system_add_gcloud_cli.sh`
- Modify: `vm-images/common/scripts/system_add_helm_kubectl.sh`
- Modify: `vm-images/common/scripts/system_config_starship_prompt.sh`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: five scripts that install correctly on both x86_64 and aarch64 hosts. Task 6's build depends on them.

These scripts already fetch checksums per-asset from the vendor at run time, so only the asset names become arch-dependent.

- [ ] **Step 1: system_add_yq.sh**

Insert an arch case after the version echo — replace:

```bash
echo "Latest version: ${YQ_VERSION}"

# Download checksums file
```

with:

```bash
echo "Latest version: ${YQ_VERSION}"

# Detect architecture (yq uses amd64/arm64)
case "$(uname -m)" in
  x86_64)        ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)             echo "ERROR: Unsupported architecture: $(uname -m)"; exit 1 ;;
esac

# Download checksums file
```

Then apply these four exact replacements:

| Old | New |
|-----|-----|
| `# Extract checksum for Linux AMD64 binary (SHA256 is field 19)` | `# Extract checksum for the Linux binary (SHA256 is field 19)` |
| `YQ_SHA256=$(grep "^yq_linux_amd64\s" checksums \| awk '{print $19}')` | `YQ_SHA256=$(grep "^yq_linux_${ARCH}\s" checksums \| awk '{print $19}')` |
| `curl -sL https://github.com/mikefarah/yq/releases/download/v"${YQ_VERSION}"/yq_linux_amd64 -o yq_linux_amd64` | `curl -sL https://github.com/mikefarah/yq/releases/download/v"${YQ_VERSION}"/yq_linux_"${ARCH}" -o "yq_linux_${ARCH}"` |
| `echo "${YQ_SHA256}  yq_linux_amd64" \| sha256sum -c -` | `echo "${YQ_SHA256}  yq_linux_${ARCH}" \| sha256sum -c -` |
| `sudo mv yq_linux_amd64 /usr/local/bin/yq` | `sudo mv "yq_linux_${ARCH}" /usr/local/bin/yq` |

- [ ] **Step 2: system_add_awscli.sh**

Replace:

```bash
# Download AWS CLI installer
echo "Downloading AWS CLI v2 installer..."
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
```

with:

```bash
# Detect architecture (AWS CLI installers use x86_64/aarch64)
case "$(uname -m)" in
  x86_64)        AWS_ARCH="x86_64" ;;
  aarch64|arm64) AWS_ARCH="aarch64" ;;
  *)             echo "ERROR: Unsupported architecture: $(uname -m)"; exit 1 ;;
esac

# Download AWS CLI installer
echo "Downloading AWS CLI v2 installer..."
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" -o "awscliv2.zip"
```

Then replace both remaining occurrences (lines ~21 and ~26) of
`awscli-exe-linux-x86_64.zip.sig` with `awscli-exe-linux-${AWS_ARCH}.zip.sig`.

- [ ] **Step 3: system_add_gcloud_cli.sh**

Replace (8-space indent — inside the OS case branch):

```bash
        INSTALL_ROOT="/usr/local"
        SDK_DIR="${INSTALL_ROOT}/google-cloud-sdk"
        TARBALL="google-cloud-cli-linux-x86_64.tar.gz"
```

with:

```bash
        INSTALL_ROOT="/usr/local"
        SDK_DIR="${INSTALL_ROOT}/google-cloud-sdk"

        # Detect architecture (Google ships x86_64 and arm tarballs)
        case "$(uname -m)" in
          x86_64)        GCLOUD_ARCH="x86_64" ;;
          aarch64|arm64) GCLOUD_ARCH="arm" ;;
          *)             echo "ERROR: Unsupported architecture: $(uname -m)"; exit 1 ;;
        esac
        TARBALL="google-cloud-cli-linux-${GCLOUD_ARCH}.tar.gz"
```

- [ ] **Step 4: system_add_helm_kubectl.sh**

Insert a shared arch case — replace:

```bash
log "Working in temporary directory: $TEMP_DIR"
```

with:

```bash
log "Working in temporary directory: $TEMP_DIR"

# Detect architecture (Helm and kubectl use amd64/arm64)
case "$(uname -m)" in
  x86_64)        KUBE_ARCH="amd64" ;;
  aarch64|arm64) KUBE_ARCH="arm64" ;;
  *)             log "ERROR: Unsupported architecture: $(uname -m)"; exit 1 ;;
esac
```

Then:

| Old | New |
|-----|-----|
| `    HELM_ARCH="linux-amd64"` | `    HELM_ARCH="linux-${KUBE_ARCH}"` |
| `    KUBECTL_URL="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"` | `    KUBECTL_URL="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${KUBE_ARCH}/kubectl"` |

(The later `sudo mv ${HELM_ARCH}/helm` and `rm -rf ${HELM_ARCH}` already use the variable — no change.)

- [ ] **Step 5: system_config_starship_prompt.sh**

Replace (2-space indent):

```bash
  # Download the binary directly instead of using installer script
  echo "Downloading Starship binary..."
  ARCH="x86_64"
  PLATFORM="unknown-linux-gnu"
```

with:

```bash
  # Download the binary directly instead of using installer script
  echo "Downloading Starship binary..."
  # Detect architecture (starship ships musl-only for aarch64, gnu for x86_64)
  case "$(uname -m)" in
    x86_64)        ARCH="x86_64";  PLATFORM="unknown-linux-gnu" ;;
    aarch64|arm64) ARCH="aarch64"; PLATFORM="unknown-linux-musl" ;;
    *)             echo "ERROR: Unsupported architecture: $(uname -m)"; exit 1 ;;
  esac
```

- [ ] **Step 6: Verify syntax and x86 URL identity**

Run:

```bash
cd vm-images/common/scripts
for f in system_add_yq.sh system_add_awscli.sh system_add_gcloud_cli.sh \
         system_add_helm_kubectl.sh system_config_starship_prompt.sh; do
  bash -n "$f" && echo "OK $f"
done
grep -c 'amd64\|x86_64' system_add_yq.sh system_add_awscli.sh \
  system_add_gcloud_cli.sh system_add_helm_kubectl.sh \
  system_config_starship_prompt.sh
```

Expected: `OK` for all five; remaining `amd64`/`x86_64` mentions only inside case blocks/comments (each file's count comes from its case block lines — no bare hardcoded asset name remains; spot-check with `grep -n 'linux-amd64\|linux-x86_64\|yq_linux_amd64\|exe-linux-x86_64' *.sh` returning nothing for these five files).

- [ ] **Step 7: Run the test suite (regression gate)**

Run: `python3 -m unittest discover -s tests`

Expected: ALL PASS.

- [ ] **Step 8: Commit**

```bash
git add vm-images/common/scripts/system_add_yq.sh \
        vm-images/common/scripts/system_add_awscli.sh \
        vm-images/common/scripts/system_add_gcloud_cli.sh \
        vm-images/common/scripts/system_add_helm_kubectl.sh \
        vm-images/common/scripts/system_config_starship_prompt.sh
git commit -m "scripts: arch-aware downloads for yq, awscli, gcloud, helm/kubectl, starship"
```

---

### Task 4: Arch-aware pinned-version scripts (golang, goss, just)

**Files:**
- Modify: `vm-images/common/scripts/system_add_golang.sh`
- Modify: `vm-images/common/scripts/system_add_goss.sh`
- Modify: `vm-images/common/scripts/dbadmin_configure_environment.sh` (the `just` install lives inside an **escaped heredoc** — every `$` in inserted code must be written `\$`)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: three more arm64-capable scripts. Task 6's build depends on them.

- [ ] **Step 1: system_add_golang.sh — per-arch tarball and pinned SHA**

Replace:

```bash
# Official GO Download page - https://go.dev/dl/
# Hardcoded Go version and SHA256 checksum
GO_VERSION="go1.26.1"
GO_SHA256="031f088e5d955bab8657ede27ad4e3bc5b7c1ba281f05f245bcc304f327c987a"
GO_URL="https://go.dev/dl/${GO_VERSION}.linux-amd64.tar.gz"
```

with (the arm64 SHA256 is real, fetched from go.dev's official checksum JSON on 2026-07-30):

```bash
# Official GO Download page - https://go.dev/dl/
# Hardcoded Go version and per-architecture SHA256 checksums
GO_VERSION="go1.26.1"
case "$(uname -m)" in
  x86_64)
    GO_ARCH="amd64"
    GO_SHA256="031f088e5d955bab8657ede27ad4e3bc5b7c1ba281f05f245bcc304f327c987a"
    ;;
  aarch64|arm64)
    GO_ARCH="arm64"
    GO_SHA256="a290581cfe4fe28ddd737dde3095f3dbeb7f2e4065cab4eae44dfc53b760c2f7"
    ;;
  *)
    echo "ERROR: Unsupported architecture: $(uname -m)"; exit 1
    ;;
esac
GO_TARBALL="${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
GO_URL="https://go.dev/dl/${GO_TARBALL}"
```

Then:

| Old | New |
|-----|-----|
| `echo "${GO_SHA256}  ${GO_VERSION}.linux-amd64.tar.gz" \| sha256sum -c -` | `echo "${GO_SHA256}  ${GO_TARBALL}" \| sha256sum -c -` |
| `tar xf "${GO_VERSION}.linux-amd64.tar.gz"` | `tar xf "${GO_TARBALL}"` |
| `rm -f "${GO_VERSION}.linux-amd64.tar.gz"` | `rm -f "${GO_TARBALL}"` |

- [ ] **Step 2: system_add_goss.sh — arch-mapped tarball name**

Replace (4-space indent — inside the `if ! command -v goss` block; the SHA256SUMS grep is already per-file and needs no change):

```bash
    # As of v0.4.10 releases ship tarballs (goss_<ver>_linux_x86_64.tar.gz)
    # plus a combined goss_<ver>_SHA256SUMS file; the raw goss-linux-amd64
    # binary and per-file .sha256 assets no longer exist.
    TARBALL="goss_${GOSS_VERSION}_linux_x86_64.tar.gz"
```

with:

```bash
    # Detect architecture (goss release tarballs use x86_64/arm64)
    case "$(uname -m)" in
      x86_64)        GOSS_ARCH="x86_64" ;;
      aarch64|arm64) GOSS_ARCH="arm64" ;;
      *)             echo "ERROR: Unsupported architecture: $(uname -m)"; exit 1 ;;
    esac

    # As of v0.4.10 releases ship tarballs (goss_<ver>_linux_<arch>.tar.gz)
    # plus a combined goss_<ver>_SHA256SUMS file; the raw goss-linux-amd64
    # binary and per-file .sha256 assets no longer exist.
    TARBALL="goss_${GOSS_VERSION}_linux_${GOSS_ARCH}.tar.gz"
```

- [ ] **Step 3: dbadmin_configure_environment.sh — `just` tarball**

This section sits inside a heredoc whose `$` are escaped as `\$` in the file. Replace exactly (keep every backslash):

```bash
# Extract the SHA256 hash for the specific binary
JUST_FILENAME="just-\${JUST_VERSION}-x86_64-unknown-linux-musl.tar.gz"
```

with:

```bash
# Detect architecture (just ships x86_64/aarch64 musl builds)
case "\$(uname -m)" in
  x86_64)        JUST_ARCH="x86_64" ;;
  aarch64|arm64) JUST_ARCH="aarch64" ;;
  *)             echo "ERROR: Unsupported architecture: \$(uname -m)"; exit 1 ;;
esac

# Extract the SHA256 hash for the specific binary
JUST_FILENAME="just-\${JUST_VERSION}-\${JUST_ARCH}-unknown-linux-musl.tar.gz"
```

- [ ] **Step 4: Verify syntax and remaining hardcodes**

Run:

```bash
cd vm-images/common/scripts
bash -n system_add_golang.sh && bash -n system_add_goss.sh \
  && bash -n dbadmin_configure_environment.sh && echo SYNTAX-OK
grep -n 'linux-amd64\|linux_x86_64\|x86_64-unknown-linux-musl' \
  system_add_golang.sh system_add_goss.sh dbadmin_configure_environment.sh
```

Expected: `SYNTAX-OK`; the grep matches only comment lines and case-block arms (no remaining hardcoded asset assignments).

- [ ] **Step 5: Run the test suite (regression gate)**

Run: `python3 -m unittest discover -s tests`

Expected: ALL PASS.

- [ ] **Step 6: Commit**

```bash
git add vm-images/common/scripts/system_add_golang.sh \
        vm-images/common/scripts/system_add_goss.sh \
        vm-images/common/scripts/dbadmin_configure_environment.sh
git commit -m "scripts: arch-aware golang, goss, and just installs"
```

---

### Task 5: APT repositories — stop pinning arch=amd64 (docker, 1password)

**Files:**
- Modify: `vm-images/common/scripts/system_add_docker.sh` (ubuntu branch ~line 98, debian branch ~line 124)
- Modify: `vm-images/common/scripts/system_add_1password_cli.sh` (~line 45)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: APT repo definitions that follow the host architecture. Task 6's build depends on them.

- [ ] **Step 1: Docker ubuntu branch**

Replace:

```bash
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

with:

```bash
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

- [ ] **Step 2: Docker debian branch**

Replace:

```bash
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

with:

```bash
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

- [ ] **Step 3: 1Password APT repo (arch pin and URL path)**

Replace:

```bash
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/amd64 stable main" | \
```

with (this is 1Password's documented pattern; `downloads.1password.com/linux/debian/arm64` is a live suite):

```bash
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" | \
```

- [ ] **Step 4: Verify**

Run:

```bash
cd vm-images/common/scripts
bash -n system_add_docker.sh && bash -n system_add_1password_cli.sh && echo SYNTAX-OK
grep -n 'arch=amd64' system_add_docker.sh system_add_1password_cli.sh || echo NO-HARDCODED-ARCH
```

Expected: `SYNTAX-OK` then `NO-HARDCODED-ARCH`.

- [ ] **Step 5: Run the test suite, then commit**

Run: `python3 -m unittest discover -s tests` — expected ALL PASS. Then:

```bash
git add vm-images/common/scripts/system_add_docker.sh \
        vm-images/common/scripts/system_add_1password_cli.sh
git commit -m "scripts: follow host architecture in docker and 1password APT repos"
```

---

### Task 6: Create the ubuntu26-arm64 target

**Files:**
- Create: `vm-images/aws/agentic/build/ubuntu26-arm64/main.pkr.hcl` (copy of ubuntu26 + 3 deltas)
- Create: `vm-images/aws/agentic/build/ubuntu26-arm64/scripts/system_add_synxdb_cloud_dependencies.sh` (verbatim copy)
- Create: `vm-images/aws/agentic/build/ubuntu26-arm64/scripts/system_set_default_locale.sh` (verbatim copy)
- Create: `vm-images/aws/agentic/build/ubuntu26-arm64/tests/goss.yaml` (copy minus dysk block)
- Create: `vm-images/aws/agentic/build/ubuntu26-arm64/CLAUDE.md`

**Interfaces:**
- Consumes: arch-aware scripts from Tasks 3–5 (referenced by relative path from the template, unchanged names).
- Produces: the buildable target directory; identity derives from the path (`FAMILY=agentic`, `OS_NAME=ubuntu26-arm64`). Task 8 builds it.

- [ ] **Step 1: Copy the target directory**

```bash
cd vm-images/aws/agentic/build
cp -R ubuntu26 ubuntu26-arm64
rm -f ubuntu26-arm64/packer-manifest.json ubuntu26-arm64/goss-test-results*.xml
rm ubuntu26-arm64/CLAUDE.md
```

(The copied `CLAUDE.md` is removed because it documents the x86 target; Step 5 writes a fresh arm64 one.)

- [ ] **Step 2: Edit main.pkr.hcl — the three arm64 deltas**

In `vm-images/aws/agentic/build/ubuntu26-arm64/main.pkr.hcl`:

Delta 1 — replace:

```hcl
  instance_type = "t3.2xlarge"
```

with:

```hcl
  instance_type = "t4g.2xlarge"
```

Delta 2 — replace:

```hcl
      name                = "*ubuntu-resolute-26.04-amd64-minimal-*"
```

with:

```hcl
      name                = "*ubuntu-resolute-26.04-arm64-minimal-*"
```

Delta 3 — delete this block entirely (including the comment line):

```hcl
  # Install dysk (better df alternative)
  provisioner "shell" {
    script = "../../../../common/scripts/system_add_dysk.sh"
  }
```

- [ ] **Step 3: Edit tests/goss.yaml — drop dysk, fix the header**

In `vm-images/aws/agentic/build/ubuntu26-arm64/tests/goss.yaml`:

Delete this block (lines ~322–326 of the copy):

```yaml
  # dysk
  /usr/local/bin/dysk:
    exists: true
    mode: "0755"
    filetype: file

```

Replace the stale header comment:

```yaml
# SynxDB Cloud AMI (Ubuntu 24.04) - Goss Validation Tests
```

with:

```yaml
# Agentic AMI (Ubuntu 26.04 arm64) - Goss Validation Tests
```

- [ ] **Step 4: Confirm no other dysk references remain in the new target**

Run: `grep -rn dysk vm-images/aws/agentic/build/ubuntu26-arm64/`

Expected: no output.

- [ ] **Step 5: Write the target CLAUDE.md**

Create `vm-images/aws/agentic/build/ubuntu26-arm64/CLAUDE.md` with exactly:

```markdown
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
```

- [ ] **Step 6: Run the test suites (new template auto-joins glob-based policy/security tests)**

Run: `python3 -m unittest discover -s tests -v 2>&1 | tail -20`

Expected: ALL PASS — including `test_agentic_goss_covers_ai_toolchain_executables` (now iterating both targets), the template naming/security tests, and the compute-build-matrix test.

- [ ] **Step 7: Packer validation**

Run:

```bash
cd vm-images/aws/agentic/build/ubuntu26-arm64
packer init main.pkr.hcl
packer validate -var family=agentic -var os_name=ubuntu26-arm64 -var region=us-west-2 main.pkr.hcl
```

Expected: `The configuration is valid.`

- [ ] **Step 8: Verify CI matrix picks up the target**

Run: `printf 'vm-images/aws/agentic/build/ubuntu26-arm64/main.pkr.hcl\n' | .github/scripts/compute-build-matrix.sh`

Expected: JSON containing `{"family":"agentic","name":"ubuntu26-arm64","path":"vm-images/aws/agentic/build/ubuntu26-arm64"}`.

- [ ] **Step 9: Commit**

```bash
git add vm-images/aws/agentic/build/ubuntu26-arm64
git commit -m "agentic: add ubuntu26-arm64 (Graviton) target"
```

---

### Task 7: Documentation

**Files:**
- Modify: `README.md` (structure tree ~line 103, Supported Builds table ~line 123, agentic family bullets ~line 190)
- Modify: `CLAUDE.md` (Current Platforms heading + table, repository-layout snippet)

**Interfaces:**
- Consumes: target name `ubuntu26-arm64` from Task 6.
- Produces: docs that match the 8-target reality.

- [ ] **Step 1: README structure tree**

Replace:

```
│       └── agentic/build/
│           └── ubuntu26/         # Standalone AI-tooling image on Ubuntu 26.04
```

with:

```
│       └── agentic/build/
│           ├── ubuntu26/         # Standalone AI-tooling image on Ubuntu 26.04
│           └── ubuntu26-arm64/   # Same image on arm64 (Graviton)
```

- [ ] **Step 2: README Supported Builds table**

Replace:

```
| **agentic** | ubuntu26 | APT | Standalone AI-tooling image (Ubuntu 26.04) |
```

with:

```
| **agentic** | ubuntu26 | APT | Standalone AI-tooling image (Ubuntu 26.04) |
| **agentic** | ubuntu26-arm64 | APT | Same image on arm64/Graviton (no dysk — x86-only binary) |
```

- [ ] **Step 3: README agentic family bullets**

Replace:

```
**agentic** (ubuntu26):
```

with:

```
**agentic** (ubuntu26, ubuntu26-arm64):
```

- [ ] **Step 4: Root CLAUDE.md — platforms table and layout snippet**

Replace:

```
## Current Platforms (7 targets)
```

with:

```
## Current Platforms (8 targets)
```

Add to the platforms table after the existing agentic row:

```
| agentic | ubuntu26-arm64 | APT | arm64/Graviton sibling of ubuntu26; no dysk |
```

In the Repository Layout snippet, replace:

```
    └── agentic/build/{ubuntu26}/
```

with:

```
    └── agentic/build/{ubuntu26,ubuntu26-arm64}/
```

- [ ] **Step 5: Run the policy suite (docs are policy-checked for private-only wording)**

Run: `python3 -m unittest tests.test_repository_policy`

Expected: ALL PASS.

- [ ] **Step 6: Commit**

```bash
git add README.md CLAUDE.md
git commit -m "docs: add agentic/ubuntu26-arm64 target"
```

---

### Task 8: Full build verification (requires AWS credentials — confirm with user before running)

**Files:** none (verification only)

**Interfaces:**
- Consumes: everything above; harness mapping `arm64` → `t4g.medium` from Task 1.
- Produces: a `-PASSED` arm64 AMI, or a concrete list of vendor installers lacking arm64 support (each becomes an explicit follow-up decision per the spec's hard-fail policy).

- [ ] **Step 1: Confirm with the user before any AWS spend** (builds launch real EC2 instances)

- [ ] **Step 2: Build and test the arm64 target**

Run:

```bash
cd vm-images/aws/agentic/build/ubuntu26-arm64
../../../../scripts/packer-build-and-test.sh
```

Expected: build completes; harness reports `AMI architecture: arm64; test instance type: t4g.medium`; goss suite passes; AMI renamed `agentic-packer-ubuntu26-arm64-<timestamp>-PASSED`.

Known risk (spec: hard-fail policy): `system_add_ai_toolchain.sh` may fail on hermes, antigravity, cursor-agent, or kimi if a vendor lacks arm64 builds. If it fails: record which tool, stop, and surface the list to the user — each gap is a per-tool decision (drop on arm64 + goss/policy adjustments, or wait for vendor support). Do NOT add skip logic unilaterally.

- [ ] **Step 3: x86 regression build**

Either run the x86 target locally (`cd vm-images/aws/agentic/build/ubuntu26 && ../../../../scripts/packer-build-and-test.sh`) or rely on the CI fleet rebuild triggered by the shared-script changes on push. Expected: x86 targets still build and pass — the arch-aware scripts resolve to today's exact URLs on x86_64.

- [ ] **Step 4: Push** (confirm with user first)

```bash
git push origin main
```

CI rebuilds every target referencing the touched shared scripts (expected, intentional — this is the fleet-wide regression proof).
