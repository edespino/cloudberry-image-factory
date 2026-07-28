# Family Restructure + Agentic Image Family Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure `vm-images/` into a multi-cloud, family-aware layout (cloudberry, synxdb-cloud, agentic) with a cloud-neutral build harness, goss tests run inside the Packer build, dynamic CI matrices, and a first agentic target (ubuntu26).

**Architecture:** Cloud-agnostic content (provision scripts, goss fragments, orchestrator) lives at `vm-images/{scripts,common}`; cloud-specific content lives under `vm-images/<cloud>/<family>/build/<os>` plus per-cloud harness libraries `vm-images/scripts/lib/<cloud>.sh`. The harness infers cloud/family/os purely from the directory it is run in. Goss runs as Packer provisioners, so a published image implies passing tests (no `-PASSED` suffix, no post-build test instance).

**Tech Stack:** Bash, Packer (amazon-ebs), goss, GitHub Actions, AWS CLI.

**Spec:** `docs/superpowers/specs/2026-07-28-family-restructure-design.md` (committed, `472dd3a`).

## Global Constraints

- Image naming: `<family>-packer-<os>-<timestamp>` exactly (no `build` segment, no `-PASSED`/`-FAILED` suffix).
- Directory contract: `vm-images/<cloud>/<family>/build/<os>/` containing `main.pkr.hcl`, optional `scripts/`, `tests/goss.yaml`.
- Provision scripts stay FLAT in `vm-images/common/scripts/` (no subdirectories).
- On-instance goss layout is `~/<os>/tests/goss.yaml` + `~/common/tests/*.yaml` so existing `gossfile: ../../common/tests/*.yaml` includes keep resolving. Do not edit include lines.
- The 9 AI-tooling scripts: `system_add_claude.sh`, `system_configure_claude.sh`, `system_add_opencode.sh`, `system_add_omnigent.sh`, `system_add_pi.sh`, `system_add_gastown.sh`, `system_add_beads.sh`, `system_add_herdr.sh`, `system_add_ai_toolchain.sh`. After Task 7, only agentic HCLs may reference them.
- Do not invent AWS values (AMI filters, owner IDs). Where a value must be discovered, the step says how to discover it.
- Every bash file must pass `bash -n` and `shellcheck` with no errors (warnings: do not add new ones).
- Commit after every task. Work on branch `restructure/family-layout` off `main`.
- Repo root: `/Users/eespino/workspace/cloudberry-image-factory`. All paths below are repo-relative.

---

### Task 0: Branch

- [ ] **Step 0.1:** `git checkout -b restructure/family-layout main`

---

### Task 1: Repo hygiene

**Files:**
- Delete: all `vm-images/aws/cloudberry/build/*/packer-manifest.json`, all `vm-images/aws/cloudberry/build/*/goss-test-results-*.xml`
- Delete: `vm-images/aws/cloudberry/build/al2023-synxdb-elastic/` (archived to git history)
- Delete: `vm-images/aws/cloudberry/build/al2023-synxdb-cloud/scripts/system_add_cbdb_build_rpm_dependencies.sh` (dead — not referenced by that target's HCL)
- Delete: `vm-images/aws/cloudberry/scripts/run-goss-tests.sh` (hardcoded to rocky9, incompatible with gossfile includes, referenced nowhere)
- Modify: `.gitignore`

**Interfaces:**
- Produces: a tree with no committed build artifacts; later tasks assume `al2023-synxdb-elastic` does not exist.

- [ ] **Step 1.1: Verify the dead-file claims before deleting**

```bash
cd /Users/eespino/workspace/cloudberry-image-factory
# Must print nothing (script not referenced by its own target HCL):
grep -n "system_add_cbdb_build_rpm_dependencies" vm-images/aws/cloudberry/build/al2023-synxdb-cloud/main.pkr.hcl || echo "CONFIRMED DEAD"
# Must print nothing (run-goss-tests.sh referenced nowhere outside itself):
grep -rn "run-goss-tests" --include="*.yml" --include="*.md" --include="*.hcl" . | grep -v "^\./vm-images/aws/cloudberry/scripts/run-goss-tests.sh" || echo "CONFIRMED UNREFERENCED"
```
Expected: both `CONFIRMED` lines. If either grep matches, STOP and report instead of deleting.

- [ ] **Step 1.2: Delete artifacts and dead files**

```bash
git rm -r vm-images/aws/cloudberry/build/al2023-synxdb-elastic
git rm vm-images/aws/cloudberry/build/*/packer-manifest.json
git rm 'vm-images/aws/cloudberry/build/*/goss-test-results-*.xml' --ignore-unmatch
# glob may need shell expansion instead:
find vm-images -name 'goss-test-results-*.xml' -exec git rm {} +
git rm vm-images/aws/cloudberry/build/al2023-synxdb-cloud/scripts/system_add_cbdb_build_rpm_dependencies.sh
git rm vm-images/aws/cloudberry/scripts/run-goss-tests.sh
```

- [ ] **Step 1.3: Append to `.gitignore`**

```gitignore
# Packer build outputs (never commit)
packer-manifest.json
goss-test-results*.xml
*.pem
```

- [ ] **Step 1.4: Verify**

```bash
find vm-images -name 'packer-manifest.json' -o -name 'goss-test-results-*.xml' -o -name '*.pem' | wc -l   # expect 0
git status --short   # only deletions + .gitignore
```

- [ ] **Step 1.5: Commit**

```bash
git add .gitignore
git commit -m "chore: remove committed build artifacts, dead scripts, archived elastic target"
```

---

### Task 2: Tree restructure + HCL path rewrite

**Files:**
- Move: `vm-images/aws/cloudberry/build/common/` → `vm-images/common/`
- Move: `vm-images/aws/cloudberry/scripts/packer-build-and-test.sh` → `vm-images/scripts/packer-build-and-test.sh` (content rewritten later, in Task 5)
- Move: `vm-images/aws/cloudberry/build/{rocky8,rocky9,rocky10}/` → `vm-images/aws/cloudberry/build/` (unchanged location, see below)
- Move: `vm-images/aws/cloudberry/build/al2023-synxdb-cloud/` → `vm-images/aws/synxdb-cloud/build/al2023/`
- Move: `vm-images/aws/cloudberry/build/rocky9-synxdb-cloud/` → `vm-images/aws/synxdb-cloud/build/rocky9/`
- Move: `vm-images/aws/cloudberry/build/rocky10-synxdb-cloud/` → `vm-images/aws/synxdb-cloud/build/rocky10/`
- Move: `vm-images/aws/cloudberry/build/ubuntu24-synxdb-cloud/` → `vm-images/aws/synxdb-cloud/build/ubuntu24/`
- Modify: every `vm-images/aws/*/build/*/main.pkr.hcl` (relative script paths)

**Interfaces:**
- Produces: the directory contract `vm-images/<cloud>/<family>/build/<os>/` for all 7 targets; common refs are `../../../../common/scripts/<name>.sh` from every target dir.

- [ ] **Step 2.1: Moves**

```bash
mkdir -p vm-images/scripts vm-images/aws/synxdb-cloud/build
git mv vm-images/aws/cloudberry/build/common vm-images/common
git mv vm-images/aws/cloudberry/scripts/packer-build-and-test.sh vm-images/scripts/packer-build-and-test.sh
rmdir vm-images/aws/cloudberry/scripts
git mv vm-images/aws/cloudberry/build/al2023-synxdb-cloud  vm-images/aws/synxdb-cloud/build/al2023
git mv vm-images/aws/cloudberry/build/rocky9-synxdb-cloud  vm-images/aws/synxdb-cloud/build/rocky9
git mv vm-images/aws/cloudberry/build/rocky10-synxdb-cloud vm-images/aws/synxdb-cloud/build/rocky10
git mv vm-images/aws/cloudberry/build/ubuntu24-synxdb-cloud vm-images/aws/synxdb-cloud/build/ubuntu24
```
(cloudberry rocky8/9/10 stay at `vm-images/aws/cloudberry/build/<os>` — already correct shape.)

- [ ] **Step 2.2: Rewrite common-script paths in every HCL**

From `vm-images/<cloud>/<family>/build/<os>/`, common is now four levels up:

```bash
for f in vm-images/aws/*/build/*/main.pkr.hcl; do
  sed -i.bak 's|"\.\./common/scripts/|"../../../../common/scripts/|g' "$f"
  rm -f "$f.bak"
done
grep -rn '"\.\./common/' vm-images/aws/*/build/*/main.pkr.hcl && echo "LEFTOVER OLD PATHS" || echo "OK"
```
Expected: `OK`.

- [ ] **Step 2.3: Verify goss include lines were NOT touched**

```bash
grep -rn 'common/tests' vm-images/aws/*/build/*/tests/goss.yaml | grep -v '\.\./\.\./common/tests' && echo "UNEXPECTED" || echo "OK"
```
Expected: `OK` (includes still read `../../common/tests/...` — resolved on-instance, not in-repo).

- [ ] **Step 2.4: Validate all 7 targets**

```bash
for d in vm-images/aws/*/build/*/; do
  ( cd "$d" && packer init main.pkr.hcl >/dev/null && \
    PKR_VAR_cloudsmith_user=x PKR_VAR_cloudsmith_token=x \
    packer validate -var "vm_type=x" -var "os_name=$(basename "$d")" main.pkr.hcl ) \
    && echo "PASS $d" || { echo "FAIL $d"; exit 1; }
done
```
Expected: 7× `PASS`. (`vm_type` still exists until Task 3.)

- [ ] **Step 2.5: Commit**

```bash
git add -A
git commit -m "refactor: family-aware layout — hoist common/ and harness, split synxdb-cloud family"
```

---

### Task 3: HCL naming — `family` variable and new `ami_name`

**Files:**
- Modify: all 7 `vm-images/aws/*/build/*/main.pkr.hcl`

**Interfaces:**
- Consumes: tree from Task 2.
- Produces: every HCL declares `variable "family" { type = string }` and `variable "os_name" { type = string }` (no `vm_type`), and sets
  `ami_name = format("%s-packer-%s-%s", var.family, var.os_name, formatdate("YYYYMMDD-HHmmss", timestamp()))`.
  Task 5's harness passes `-var family=<family> -var os_name=<os>`; Task 8's CI validate does the same.

- [ ] **Step 3.1: In each HCL, replace the `vm_type` variable block**

Old (identical in all 7 files):
```hcl
variable "vm_type" {
  type    = string
}
```
New:
```hcl
variable "family" {
  type = string
}
```

- [ ] **Step 3.2: Replace the `ami_name` line in each HCL**

Old pattern (prefix varies: `cloudberry-packer` or `synxdb-cloud-packer`):
```hcl
ami_name = format("cloudberry-packer-%s-%s-%s", var.vm_type, var.os_name, formatdate("YYYYMMDD-HHmmss", timestamp()))
```
New (identical in all 7 files):
```hcl
ami_name = format("%s-packer-%s-%s", var.family, var.os_name, formatdate("YYYYMMDD-HHmmss", timestamp()))
```

- [ ] **Step 3.3: Verify no `vm_type` remains anywhere**

```bash
grep -rn "vm_type" vm-images/ && echo "LEFTOVER" || echo "OK"
```

- [ ] **Step 3.4: Validate all 7 targets**

```bash
for d in vm-images/aws/*/build/*/; do
  fam=$(basename "$(dirname "$(dirname "$d")")")
  ( cd "$d" && PKR_VAR_cloudsmith_user=x PKR_VAR_cloudsmith_token=x \
    packer validate -var "family=$fam" -var "os_name=$(basename "$d")" main.pkr.hcl ) \
    && echo "PASS $d" || { echo "FAIL $d"; exit 1; }
done
```
Expected: 7× `PASS`.

- [ ] **Step 3.5: Commit** — `git commit -am "refactor: family-based AMI naming; drop vm_type"`

---

### Task 4: Goss-as-provisioner in every HCL

**Files:**
- Modify: all 7 `vm-images/aws/*/build/*/main.pkr.hcl`

**Interfaces:**
- Consumes: `variable "os_name"` from Task 3; `system_add_goss.sh` already present as a provisioner in every HCL (verify per file; it installs `/usr/local/bin/goss`).
- Produces: each build runs goss during provisioning and downloads `goss-test-results.xml` into the target dir; a goss failure fails `packer build` (no AMI produced).

- [ ] **Step 4.1: Determine each target's SSH home**

For each HCL, read its `ssh_username` line (`rocky`, `ec2-user`, or `ubuntu`). `HOME` below is `/home/<ssh_username>`.

- [ ] **Step 4.2: Append the goss test block to each HCL**

Insert immediately BEFORE the `post-processors` block, after the last existing provisioner. `HOME` is the literal home dir from Step 4.1; goss.yaml's `../../common/tests/` includes resolve against this exact layout:

```hcl
  # ---- Goss validation (runs inside the build; failure aborts the AMI) ----
  provisioner "shell" {
    inline = [
      "mkdir -p ${HOME}/${var.os_name}/tests ${HOME}/common/tests"
    ]
  }

  provisioner "file" {
    source      = "../../../../common/tests/"
    destination = "${HOME}/common/tests"
  }

  provisioner "file" {
    source      = "tests/goss.yaml"
    destination = "${HOME}/${var.os_name}/tests/goss.yaml"
  }

  provisioner "shell" {
    inline = [
      "sudo /usr/local/bin/goss --gossfile ${HOME}/${var.os_name}/tests/goss.yaml validate --format junit > /tmp/goss-results.xml",
      "sudo /usr/local/bin/goss --gossfile ${HOME}/${var.os_name}/tests/goss.yaml validate --format rspecish"
    ]
  }

  provisioner "file" {
    direction   = "download"
    source      = "/tmp/goss-results.xml"
    destination = "goss-test-results.xml"
  }

  provisioner "shell" {
    inline = [
      "rm -rf ${HOME}/${var.os_name} ${HOME}/common /tmp/goss-results.xml"
    ]
  }
```

Substitute `${HOME}` literally (e.g. `/home/rocky/${var.os_name}/tests`); leave `${var.os_name}` as HCL interpolation. The first inline goss run exits non-zero on assertion failure (junit output is still written), which fails the build before the rspecish echo runs; keep the order so the junit file download only matters on success, while CI logs from a failed run still show which assertion died in the junit-formatted stdout redirect.

**Known risk (document, don't pre-fix):** a few assertions may behave differently in-build vs. post-boot (services not yet started, cloud-init not finalized). Task 10's real builds surface these; fix by adjusting the specific assertion, not by weakening the whole suite.

- [ ] **Step 4.3: Validate all 7 targets** — same loop as Step 3.4. Expected: 7× `PASS`.

- [ ] **Step 4.4: Commit** — `git commit -am "feat: run goss inside the Packer build; download junit results"`

---

### Task 5: Cloud-neutral harness + lib/aws.sh

**Files:**
- Rewrite: `vm-images/scripts/packer-build-and-test.sh`
- Create: `vm-images/scripts/lib/aws.sh`
- Test: `vm-images/scripts/tests/test-derivation.sh` (new; pure-bash unit test, no AWS)

**Interfaces:**
- Consumes: HCL vars `family`/`os_name` (Task 3); goss-in-build (Task 4) — the harness no longer launches a test instance, creates keypairs, or creates security groups (Packer's amazon-ebs manages its own temporary keypair/SG).
- Produces: `packer-build-and-test.sh` runnable from any `vm-images/<cloud>/<family>/build/<os>` dir; `lib/aws.sh` defines `cloud_check_prereqs`, `cloud_image_id_from_manifest`, `cloud_describe_image_name`, `cloud_publish_image`. Future clouds implement the same four functions in `lib/<cloud>.sh`.

- [ ] **Step 5.1: Write the derivation unit test (failing first)**

`vm-images/scripts/tests/test-derivation.sh`:
```bash
#!/usr/bin/env bash
# Unit-tests derive_build_context() from packer-build-and-test.sh without AWS.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS="${SCRIPT_DIR}/../packer-build-and-test.sh"

# shellcheck source=/dev/null
source "$HARNESS" --lib-only   # must define derive_build_context and return

fail() { echo "FAIL: $1"; exit 1; }

tmp=$(mktemp -d)
mkdir -p "$tmp/vm-images/aws/cloudberry/build/rocky9"
touch "$tmp/vm-images/aws/cloudberry/build/rocky9/main.pkr.hcl"

# happy path
( cd "$tmp/vm-images/aws/cloudberry/build/rocky9" && derive_build_context )
out=$(cd "$tmp/vm-images/aws/cloudberry/build/rocky9" && derive_build_context && echo "$CLOUD/$FAMILY/$OS_NAME")
[ "$out" = "aws/cloudberry/rocky9" ] || fail "derivation: got '$out'"

# wrong shape (no build/ segment)
mkdir -p "$tmp/vm-images/aws/cloudberry/rocky9"
touch "$tmp/vm-images/aws/cloudberry/rocky9/main.pkr.hcl"
if (cd "$tmp/vm-images/aws/cloudberry/rocky9" && derive_build_context 2>/dev/null); then
  fail "accepted dir without build/ segment"
fi

# missing main.pkr.hcl
mkdir -p "$tmp/vm-images/aws/cloudberry/build/rocky8"
if (cd "$tmp/vm-images/aws/cloudberry/build/rocky8" && derive_build_context 2>/dev/null); then
  fail "accepted dir without main.pkr.hcl"
fi

# unknown cloud library
mkdir -p "$tmp/vm-images/gcp/cloudberry/build/rocky9"
touch "$tmp/vm-images/gcp/cloudberry/build/rocky9/main.pkr.hcl"
if (cd "$tmp/vm-images/gcp/cloudberry/build/rocky9" && derive_build_context && load_cloud_lib 2>/dev/null); then
  fail "loaded a nonexistent cloud lib"
fi

rm -rf "$tmp"
echo "ALL PASS"
```

- [ ] **Step 5.2: Run it to verify it fails**

```bash
bash vm-images/scripts/tests/test-derivation.sh
```
Expected: FAIL (old harness has no `--lib-only` mode / `derive_build_context`).

- [ ] **Step 5.3: Rewrite `vm-images/scripts/packer-build-and-test.sh`**

Full replacement content:

```bash
#!/usr/bin/env bash
#
# packer-build-and-test.sh — cloud-neutral image build orchestrator.
#
# Run from inside a build target directory:
#   vm-images/<cloud>/<family>/build/<os>/
# Cloud, family, and OS are inferred from that path. Cloud-specific steps
# (credentials, image lookup, publishing) live in lib/<cloud>.sh next to
# this script; only the goss-tested Packer build itself is generic.
#
# Goss runs INSIDE the Packer build (see each target's main.pkr.hcl); a
# test failure aborts the build, so every published image passed its tests.
#
# Usage: packer-build-and-test.sh [-p|--private] [-h|--help]
#   -p, --private   Keep the image private (default: public unless
#                   PKR_VAR_AMI_PUBLIC=false)
#
# Sourcing with --lib-only defines the functions and returns (for tests).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Populates CLOUD, FAMILY, OS_NAME, TARGET_DIR from the current directory.
# Errors out unless CWD matches vm-images/<cloud>/<family>/build/<os> and
# contains main.pkr.hcl.
derive_build_context() {
  TARGET_DIR="$(pwd)"
  OS_NAME="$(basename "$TARGET_DIR")"
  local build_seg family_dir cloud_dir
  build_seg="$(basename "$(dirname "$TARGET_DIR")")"
  family_dir="$(dirname "$(dirname "$TARGET_DIR")")"
  FAMILY="$(basename "$family_dir")"
  cloud_dir="$(dirname "$family_dir")"
  CLOUD="$(basename "$cloud_dir")"

  if [ "$build_seg" != "build" ] || [ "$(basename "$(dirname "$cloud_dir")")" != "vm-images" ]; then
    echo "Error: run from vm-images/<cloud>/<family>/build/<os>/ (got: $TARGET_DIR)" >&2
    return 1
  fi
  if [ ! -f "$TARGET_DIR/main.pkr.hcl" ]; then
    echo "Error: main.pkr.hcl not found in $TARGET_DIR" >&2
    return 1
  fi
}

# Sources lib/<cloud>.sh for the derived CLOUD; hard error if missing.
load_cloud_lib() {
  local lib="${SCRIPT_DIR}/lib/${CLOUD}.sh"
  if [ ! -f "$lib" ]; then
    echo "Error: no harness library for cloud '${CLOUD}' (expected $lib)" >&2
    return 1
  fi
  # shellcheck source=/dev/null
  source "$lib"
}

if [ "${1:-}" = "--lib-only" ]; then
  return 0 2>/dev/null || exit 0
fi

IMAGE_PUBLIC="${PKR_VAR_AMI_PUBLIC:-true}"
while [ $# -gt 0 ]; do
  case "$1" in
    -p|--private) IMAGE_PUBLIC="false"; shift ;;
    -h|--help)
      grep '^#' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

for cmd in packer jq; do
  command -v "$cmd" >/dev/null || { echo "Error: '$cmd' is required" >&2; exit 1; }
done

derive_build_context
load_cloud_lib
cloud_check_prereqs

echo "Cloud:  ${CLOUD}"
echo "Family: ${FAMILY}"
echo "OS:     ${OS_NAME}"

echo "Initializing Packer plugins..."
packer init main.pkr.hcl

echo "Validating Packer template..."
packer validate -var "family=${FAMILY}" -var "os_name=${OS_NAME}" main.pkr.hcl

echo "Building image (goss runs inside the build)..."
packer build -var "family=${FAMILY}" -var "os_name=${OS_NAME}" main.pkr.hcl

IMAGE_ID="$(cloud_image_id_from_manifest)"
IMAGE_NAME="$(cloud_describe_image_name "$IMAGE_ID")"

if [ "$IMAGE_PUBLIC" = "true" ]; then
  echo "Publishing image ${IMAGE_ID}..."
  cloud_publish_image "$IMAGE_ID"
else
  echo "Keeping image private (IMAGE_PUBLIC=${IMAGE_PUBLIC})"
fi

echo "-----------------------------------"
echo "Image Build and Test Completed"
echo "-----------------------------------"
echo "Image ID:   ${IMAGE_ID}"
echo "Image Name: ${IMAGE_NAME}"
echo "Tests:      goss passed (enforced in-build)"
echo "Visibility: $([ "$IMAGE_PUBLIC" = "true" ] && echo public || echo private)"
echo "-----------------------------------"
```

- [ ] **Step 5.4: Create `vm-images/scripts/lib/aws.sh`**

```bash
#!/usr/bin/env bash
# AWS-specific harness steps. Sourced by packer-build-and-test.sh.
# Contract (every lib/<cloud>.sh must define these four functions):
#   cloud_check_prereqs            — verify CLI + credentials; hard error if absent
#   cloud_image_id_from_manifest   — print the built image id (reads packer-manifest.json in CWD)
#   cloud_describe_image_name <id> — print the image's name
#   cloud_publish_image <id>       — make the image publicly launchable

AWS_HARNESS_REGION="${AWS_REGION:-us-west-2}"

cloud_check_prereqs() {
  command -v aws >/dev/null || { echo "Error: aws CLI is required" >&2; return 1; }
  aws sts get-caller-identity >/dev/null 2>&1 || {
    echo "Error: AWS credentials not configured or expired" >&2; return 1; }
}

cloud_image_id_from_manifest() {
  jq -r '.builds[-1].artifact_id' packer-manifest.json | cut -d':' -f2
}

cloud_describe_image_name() {
  aws ec2 describe-images --image-ids "$1" \
    --query "Images[*].Name" --output text --region "$AWS_HARNESS_REGION"
}

cloud_publish_image() {
  local image_id=$1 block_state was_blocked=false
  block_state="$(aws ec2 get-image-block-public-access-state \
    --region "$AWS_HARNESS_REGION" \
    --query 'ImageBlockPublicAccessState' --output text)"
  if [ "$block_state" = "block-new-sharing" ]; then
    was_blocked=true
    echo "Temporarily disabling image block-public-access..."
    aws ec2 disable-image-block-public-access --region "$AWS_HARNESS_REGION"
  fi
  aws ec2 modify-image-attribute --image-id "$image_id" \
    --launch-permission "Add=[{Group=all}]" --region "$AWS_HARNESS_REGION"
  aws ec2 describe-image-attribute --image-id "$image_id" \
    --attribute launchPermission --region "$AWS_HARNESS_REGION"
  if [ "$was_blocked" = "true" ]; then
    echo "Re-enabling image block-public-access..."
    aws ec2 enable-image-block-public-access --region "$AWS_HARNESS_REGION" \
      --image-block-public-access-state block-new-sharing
  fi
}
```

- [ ] **Step 5.5: Run the unit test — expect PASS**

```bash
bash vm-images/scripts/tests/test-derivation.sh
```
Expected: `ALL PASS`.

- [ ] **Step 5.6: Lint**

```bash
bash -n vm-images/scripts/packer-build-and-test.sh vm-images/scripts/lib/aws.sh vm-images/scripts/tests/test-derivation.sh
shellcheck vm-images/scripts/packer-build-and-test.sh vm-images/scripts/lib/aws.sh vm-images/scripts/tests/test-derivation.sh
```
Expected: `bash -n` silent; shellcheck no errors (fix anything it flags — this is new code, hold it to zero findings).

- [ ] **Step 5.7: Smoke the error paths for real**

```bash
( cd /tmp && bash /Users/eespino/workspace/cloudberry-image-factory/vm-images/scripts/packer-build-and-test.sh ) ; echo "exit=$?"
```
Expected: the "run from vm-images/<cloud>/<family>/build/<os>/" error, nonzero exit.

- [ ] **Step 5.8: Commit** — `git add vm-images/scripts && git commit -m "feat: cloud-neutral build harness with per-cloud libraries"`

---

### Task 6: Agentic ubuntu26 target

**Files:**
- Create: `vm-images/aws/agentic/build/ubuntu26/main.pkr.hcl` (ported from `vm-images/aws/synxdb-cloud/build/ubuntu24/main.pkr.hcl`)
- Create: `vm-images/aws/agentic/build/ubuntu26/tests/goss.yaml` (ported from ubuntu24's)
- Create: `vm-images/aws/agentic/build/ubuntu26/scripts/` only if the ported HCL references ubuntu24's target-local scripts (copy + rename those it needs)

**Interfaces:**
- Consumes: Task 3 vars, Task 4 goss block pattern, harness contract from Task 5.
- Produces: a buildable `agentic/ubuntu26` target; AMI name `agentic-packer-ubuntu26-<timestamp>` (falls out of `-var family=agentic`).

**Design note:** this target is the approved standalone exception — it builds from the stock Ubuntu 26.04 AMI (no ubuntu26 base target exists to chain from). Content = ubuntu24-synxdb-cloud ported to 26.04, keeping the AI-tooling provisioners. Future chained agentic targets will instead set `source_ami_filter` to the latest base-family AMI with `base_family`/`base_os` HCL vars.

- [ ] **Step 6.1: Discover the real Ubuntu 26.04 source AMI filter — do NOT guess**

```bash
aws ec2 describe-images --owners 099720109477 --region us-west-2 \
  --filters "Name=name,Values=*26.04*amd64*server*" "Name=virtualization-type,Values=hvm" \
  --query 'sort_by(Images,&CreationDate)[-1].{Name:Name,Owner:OwnerId}' --output table
```
Record the exact `Name` pattern and generalize only the datestamp suffix to `*` (mirror how ubuntu24's HCL generalizes its filter). If this returns nothing, STOP and report — do not substitute a fabricated filter.

- [ ] **Step 6.2: Port the HCL**

```bash
mkdir -p vm-images/aws/agentic/build/ubuntu26/tests
cp vm-images/aws/synxdb-cloud/build/ubuntu24/main.pkr.hcl vm-images/aws/agentic/build/ubuntu26/main.pkr.hcl
cp vm-images/aws/synxdb-cloud/build/ubuntu24/tests/goss.yaml vm-images/aws/agentic/build/ubuntu26/tests/goss.yaml
```
Then edit `vm-images/aws/agentic/build/ubuntu26/main.pkr.hcl`:
1. Replace the `source_ami_filter` name pattern with the Step 6.1 value (owner stays `099720109477` as verified by Step 6.1's output).
2. Update `ami_description` to describe an agentic ubuntu26 image (keep it factual: "Agentic tooling image - Ubuntu 26.04, built via Packer").
3. If it references `scripts/system_add_synxdb_cloud_dependencies.sh` (target-local), copy that script from ubuntu24 into `ubuntu26/scripts/` and review it for 24.04-specific package names; adjust only what `apt` actually renamed (verify against Ubuntu 26.04 package lists during the Task 10 build — leave a `# TODO(verify on 26.04)` free approach: run the build and fix failures, do not guess).
4. Keep all AI-tooling provisioners (this IS the agentic image).
5. The Task 4 goss block: update its `HOME` literal to `/home/ubuntu` and confirm `${var.os_name}` interpolation is intact (it produces `ubuntu26` paths at build time).

- [ ] **Step 6.3: Validate**

```bash
( cd vm-images/aws/agentic/build/ubuntu26 && packer init main.pkr.hcl && \
  PKR_VAR_cloudsmith_user=x PKR_VAR_cloudsmith_token=x \
  packer validate -var "family=agentic" -var "os_name=ubuntu26" main.pkr.hcl )
```
Expected: valid.

- [ ] **Step 6.4: Commit** — `git add vm-images/aws/agentic && git commit -m "feat: agentic ubuntu26 target (standalone from stock Ubuntu 26.04)"`

---

### Task 7: Strip AI tooling from base families

**Files:**
- Modify: `vm-images/aws/synxdb-cloud/build/rocky10/main.pkr.hcl`, `vm-images/aws/synxdb-cloud/build/ubuntu24/main.pkr.hcl` (heaviest users)
- Modify: `vm-images/aws/cloudberry/build/{rocky8,rocky9,rocky10}/main.pkr.hcl` and `vm-images/aws/synxdb-cloud/build/{al2023,rocky9}/main.pkr.hcl` IF they reference any AI script (check each)
- Modify: the matching `tests/goss.yaml` of every HCL edited (remove AI-tool assertions)

**Interfaces:**
- Consumes: agentic target from Task 6 (which now carries the AI provisioners and their goss assertions).
- Produces: `grep -l 'system_add_\(claude\|opencode\|omnigent\|pi\|gastown\|beads\|herdr\|ai_toolchain\)\|system_configure_claude' vm-images/aws/*/build/*/main.pkr.hcl` matches ONLY `vm-images/aws/agentic/build/ubuntu26/main.pkr.hcl`.

- [ ] **Step 7.1: Enumerate current references**

```bash
grep -ln 'system_add_claude\|system_configure_claude\|system_add_opencode\|system_add_omnigent\|system_add_pi\|system_add_gastown\|system_add_beads\|system_add_herdr\|system_add_ai_toolchain' \
  vm-images/aws/*/build/*/main.pkr.hcl
```
(Note: cloudberry rocky9 installs `system_add_claude.sh` for gpadmin and cbadmin — expect matches beyond synxdb-cloud.)

- [ ] **Step 7.2: For each matching HCL except agentic/ubuntu26, delete the whole `provisioner "shell" { ... }` block(s) referencing those scripts** (including their comment lines and `environment_vars` blocks).

- [ ] **Step 7.3: Remove the corresponding goss assertions**

In each edited target's `tests/goss.yaml`, delete assertions that verify AI tooling (file/command checks for `claude`, `opencode`, `omnigent`, `pi`, `gastown`, `beads`, `herdr`, and anything the removed provisioners installed). Before deleting each assertion, confirm the same assertion (or an equivalent) exists in `vm-images/aws/agentic/build/ubuntu26/tests/goss.yaml`; if it does not, ADD it there rather than losing coverage.

- [ ] **Step 7.4: Verify the boundary**

```bash
grep -l 'system_add_claude\|system_configure_claude\|system_add_opencode\|system_add_omnigent\|system_add_pi\|system_add_gastown\|system_add_beads\|system_add_herdr\|system_add_ai_toolchain' \
  vm-images/aws/*/build/*/main.pkr.hcl
```
Expected output: exactly `vm-images/aws/agentic/build/ubuntu26/main.pkr.hcl`.

- [ ] **Step 7.5: Validate all 8 targets** (loop from Step 3.4, now including agentic). Expected: 8× `PASS`.

- [ ] **Step 7.6: Commit** — `git commit -am "refactor: AI tooling ships only in agentic images"`

---

### Task 8: CI workflows

**Files:**
- Rewrite: `.github/workflows/ami-build-on-change.yml`
- Rewrite: `.github/workflows/ami-build-manual.yml`
- Modify: `.github/workflows/ami-cleanup-old.yml`
- Create: `.github/scripts/compute-build-matrix.sh` (so the matrix logic is testable locally)

**Interfaces:**
- Consumes: directory contract; harness invocation `../../../../scripts/packer-build-and-test.sh` from a target dir (vm-images/<cloud>/<family>/build/<os> → up 4 = vm-images → scripts/).
- Produces: matrix entries `{"family":"<family>","name":"<os>","path":"vm-images/aws/<family>/build/<os>"}`.

- [ ] **Step 8.1: Write `.github/scripts/compute-build-matrix.sh`**

```bash
#!/usr/bin/env bash
# Computes the AMI build matrix from a newline-separated changed-file list on
# stdin. Prints JSON {"build":[{family,name,path},...]} on stdout.
# Rules (spec §4):
#   <cloud>/<family>/build/<target>/**            -> that target
#   vm-images/common/scripts/X.sh                 -> targets whose HCL references X.sh
#   vm-images/scripts/lib/<cloud>.sh              -> all targets of that cloud
#   vm-images/scripts/** (orchestrator etc.)      -> all targets
#   vm-images/common/tests/**                     -> all targets
set -euo pipefail

all_targets() {  # prints "family name path" lines for every aws target
  for d in vm-images/aws/*/build/*/; do
    [ -f "${d}main.pkr.hcl" ] || continue
    local fam os
    fam=$(basename "$(dirname "$(dirname "$d")")")
    os=$(basename "$d")
    echo "$fam $os ${d%/}"
  done
}

declare -A picked=()
add_target() { picked["$1|$2|$3"]=1; }
add_all() { while read -r f n p; do add_target "$f" "$n" "$p"; done < <(all_targets); }

while IFS= read -r file; do
  [ -z "$file" ] && continue
  [ -f "$file" ] || continue   # deletions can't affect a build
  case "$file" in
    vm-images/aws/*/build/*/*)
      fam=$(echo "$file" | cut -d/ -f3); os=$(echo "$file" | cut -d/ -f5)
      dir="vm-images/aws/$fam/build/$os"
      [ -f "$dir/main.pkr.hcl" ] && add_target "$fam" "$os" "$dir"
      ;;
    vm-images/common/scripts/*.sh)
      script=$(basename "$file")
      while read -r f n p; do
        grep -q "$script" "$p/main.pkr.hcl" && add_target "$f" "$n" "$p"
      done < <(all_targets)
      ;;
    vm-images/scripts/lib/*.sh)
      cloud=$(basename "$file" .sh)
      [ "$cloud" = "aws" ] && add_all
      ;;
    vm-images/scripts/*|vm-images/common/tests/*)
      add_all
      ;;
  esac
done

entries=()
for key in "${!picked[@]}"; do
  IFS='|' read -r fam os path <<< "$key"
  entries+=("{\"family\":\"$fam\",\"name\":\"$os\",\"path\":\"$path\"}")
done
printf '{"build":[%s]}\n' "$(IFS=,; echo "${entries[*]-}")"
```

- [ ] **Step 8.2: Test the matrix script locally (before wiring the workflow)**

```bash
cd /Users/eespino/workspace/cloudberry-image-factory
chmod +x .github/scripts/compute-build-matrix.sh
# doc-only change -> empty matrix
echo "README.md" | .github/scripts/compute-build-matrix.sh
# single target
echo "vm-images/aws/cloudberry/build/rocky9/main.pkr.hcl" | .github/scripts/compute-build-matrix.sh
# common script referenced by many targets
echo "vm-images/common/scripts/system_add_goss.sh" | .github/scripts/compute-build-matrix.sh
# orchestrator -> all targets
echo "vm-images/scripts/packer-build-and-test.sh" | .github/scripts/compute-build-matrix.sh
```
Expected, in order: `{"build":[]}`; exactly rocky9/cloudberry; every target whose HCL greps `system_add_goss.sh` (spot-check one listed HCL by hand); all 8 targets. Then `shellcheck .github/scripts/compute-build-matrix.sh` — no errors.

- [ ] **Step 8.3: Rewrite `ami-build-on-change.yml`**

Keep the existing job skeleton (checkout, setup-packer, configure-aws-credentials@v6, artifact upload, PR comment, summary) and change:
- `paths` filters (both push and pull_request) to:
  ```yaml
  paths:
    - 'vm-images/**'
    - '!**/*.md'
  ```
- Replace the entire inline matrix bash (old lines 37–186) with:
  ```yaml
      - name: Compute build matrix
        id: set-matrix
        shell: bash
        run: |
          if [ "${{ github.event_name }}" == "pull_request" ]; then
            changed=$(git diff --name-only origin/${{ github.base_ref }}...HEAD)
          else
            changed=$(git diff --name-only HEAD~1 HEAD)
          fi
          echo "$changed"
          matrix=$(echo "$changed" | .github/scripts/compute-build-matrix.sh)
          echo "matrix=$matrix" >> "$GITHUB_OUTPUT"
          if [ "$(echo "$matrix" | jq '.build | length')" -gt 0 ]; then
            echo "should-run=true" >> "$GITHUB_OUTPUT"
          else
            echo "should-run=false" >> "$GITHUB_OUTPUT"
          fi
          {
            echo "changed-files<<EOF"
            echo "$changed"
            echo "EOF"
          } >> "$GITHUB_OUTPUT"
  ```
- validate job step becomes (dummy cloudsmith env kept):
  ```yaml
          packer init main.pkr.hcl
          packer validate -var "family=${{ matrix.build.family }}" -var "os_name=${{ matrix.build.name }}" main.pkr.hcl
  ```
- build step becomes:
  ```yaml
          chmod +x ../../../../scripts/packer-build-and-test.sh
          ../../../../scripts/packer-build-and-test.sh
  ```
- artifact names/paths: `build-artifacts-${{ matrix.build.family }}-${{ matrix.build.name }}`, path `${{ matrix.build.path }}/packer-manifest.json` and `${{ matrix.build.path }}/goss-test-results.xml` (singular filename now — Task 4 downloads a fixed name).
- DELETE the `cleanup` job entirely — the harness no longer creates key pairs or security groups (Packer manages its own ephemeral ones).

- [ ] **Step 8.4: Rewrite `ami-build-manual.yml`**

- Replace the `build_targets` choice input with:
  ```yaml
        build_targets:
          description: 'Targets: "all" or comma-separated family/os (e.g. cloudberry/rocky9,agentic/ubuntu26)'
          required: true
          default: 'all'
          type: string
  ```
- setup-matrix job body:
  ```bash
  if [ "${{ github.event.inputs.build_targets }}" = "all" ]; then
    selector='vm-images/aws/*/build/*/'
    entries=$(for d in $selector; do
      [ -f "${d}main.pkr.hcl" ] || continue
      fam=$(basename "$(dirname "$(dirname "$d")")"); os=$(basename "$d")
      echo "{\"family\":\"$fam\",\"name\":\"$os\",\"path\":\"${d%/}\"}"
    done | paste -sd, -)
  else
    entries=$(echo "${{ github.event.inputs.build_targets }}" | tr ',' '\n' | while IFS=/ read -r fam os; do
      d="vm-images/aws/$fam/build/$os"
      if [ ! -f "$d/main.pkr.hcl" ]; then echo "Unknown target: $fam/$os" >&2; exit 1; fi
      echo "{\"family\":\"$fam\",\"name\":\"$os\",\"path\":\"$d\"}"
    done | paste -sd, -)
  fi
  echo "matrix={\"build\":[$entries]}" >> "$GITHUB_OUTPUT"
  ```
- validate/build steps: same two replacements as Step 8.3 (family var; `../../../../scripts/` path). Keep `max-parallel: 2` and 90-day artifact retention.

- [ ] **Step 8.5: Update `ami-cleanup-old.yml`**

Replace the single hardcoded name filter (`cloudberry-packer-build-*`, and the snapshot description variant) with a per-family loop; the workflow must check out the repo first to enumerate families:
```bash
for famdir in vm-images/aws/*/; do
  family=$(basename "$famdir")
  pattern="${family}-packer-*"
  # existing retention logic runs once per $pattern
done
```
Keep `dry_run` defaulting to true on schedule, `retention_count` default 3.

- [ ] **Step 8.6: Syntax-check the workflows**

```bash
for f in .github/workflows/*.yml; do python3 -c "import yaml,sys; yaml.safe_load(open('$f'))" && echo "OK $f"; done
command -v actionlint >/dev/null && actionlint || echo "actionlint not installed — YAML check only"
```
Expected: `OK` for all files; actionlint clean if present.

- [ ] **Step 8.7: Commit** — `git add .github && git commit -m "ci: dynamic family-aware build matrices; per-family cleanup; drop obsolete resource cleanup job"`

---

### Task 9: Documentation

**Files:**
- Modify: `CLAUDE.md`, `README.md`, `ROADMAP.md`, `.github/workflows/README.md`, `vm-images/common/tests/README.md`
- Modify: `vm-images/aws/synxdb-cloud/build/{rocky9,rocky10,ubuntu24}/CLAUDE.md`
- Create: `vm-images/aws/agentic/build/ubuntu26/CLAUDE.md`

**Interfaces:** consumes the final tree, harness behavior, and naming from Tasks 2–8.

- [ ] **Step 9.1: `CLAUDE.md`** — update: the directory-structure checklist (new `vm-images/<cloud>/<family>/build/<os>` contract); the "Key files" section (harness path `vm-images/scripts/packer-build-and-test.sh`; correct the stale "21 scripts" to the actual count from `ls vm-images/common/scripts/*.sh | wc -l`); the platform table (7 base targets + agentic/ubuntu26; remove al2023-synxdb-elastic, note it as archived); goss now runs in-build (no test instance); AI tooling only in agentic family; keep the numbered provisioner-order checklist and the RPM/DEB notes; add a "new family" checklist (create `vm-images/aws/<family>/build/`, first target, workflows need no edits — matrix is dynamic).
- [ ] **Step 9.2: `README.md`** — regenerate the tree diagram; replace every `../../scripts/packer-build-and-test.sh` example with `../../../../scripts/packer-build-and-test.sh`; state new AMI naming `<family>-packer-<os>-<timestamp>` and that published AMIs are always test-passing (no `-PASSED` suffix); remove references to the post-build test instance.
- [ ] **Step 9.3: `ROADMAP.md`** — update the two path references (`smoke-test.sh` → `vm-images/scripts/smoke-test.sh`; the "In packer-build-and-test.sh after Goss tests" snippet note to reflect goss-in-build); add a short "2026-07: family restructure" note under completed work.
- [ ] **Step 9.4: `.github/workflows/README.md`** — describe the dynamic matrix (`.github/scripts/compute-build-matrix.sh` rules) and the `family/os` manual-dispatch format.
- [ ] **Step 9.5: `vm-images/common/tests/README.md`** — the on-instance layout description stays valid; update only the "created by packer-build-and-test.sh" wording to "created by the goss provisioner block in each main.pkr.hcl".
- [ ] **Step 9.6: Per-target CLAUDE.md files** — fix paths, remove AI-tooling rows from the "How This Differs" tables (now agentic-only), replace "Reference Platforms" mentions of al2023-synxdb-elastic with a note that it is archived (git history). Create `agentic/build/ubuntu26/CLAUDE.md` modeled on ubuntu24's, describing: standalone-from-stock-Ubuntu exception, AI tooling list, future chained pattern.
- [ ] **Step 9.7: Docs accuracy check** — `grep -rn "vm-images/aws/cloudberry/scripts\|cloudberry-packer-build\|-PASSED" README.md CLAUDE.md ROADMAP.md .github/workflows/README.md` → expect no hits (all references updated).
- [ ] **Step 9.8: Commit** — `git commit -am "docs: family layout, in-build goss, dynamic CI matrix"`

---

### Task 10: Live verification builds (operator gate — requires AWS credentials and real spend)

**STOP: get explicit user go-ahead before this task. It launches real Packer builds (~t3.2xlarge, 30-60 min each).**

- [ ] **Step 10.1:** `cd vm-images/aws/cloudberry/build/rocky9 && ../../../../scripts/packer-build-and-test.sh -p`
  Verify: build completes; AMI named `cloudberry-packer-rocky9-<ts>`; `goss-test-results.xml` downloaded; AMI private.
- [ ] **Step 10.2:** same for `vm-images/aws/synxdb-cloud/build/rocky10` (`synxdb-cloud-packer-rocky10-<ts>`); confirm the image does NOT contain AI tooling (`ssh` in or check goss output has no claude/opencode assertions).
- [ ] **Step 10.3:** same for `vm-images/aws/agentic/build/ubuntu26` (`agentic-packer-ubuntu26-<ts>`); fix any in-build goss assertion mismatches (services-not-started class) by adjusting the specific assertion; fix any Ubuntu-26.04 package renames surfaced by the dependency script.
- [ ] **Step 10.4: Negative test:** add a deliberately failing assertion to rocky9's goss.yaml, run the harness, confirm the build ABORTS with no AMI produced, then revert the assertion.
- [ ] **Step 10.5:** deregister the verification AMIs + snapshots (they were `-p` private test builds), commit any assertion fixes: `git commit -am "fix: goss assertion adjustments from live verification builds"`.

---

## Self-review notes (run after drafting — resolved inline)

- Spec coverage: layout (T2), flat scripts (T2 — no subdir created), harness+libs (T5), naming (T3), goss-in-build (T4), agentic ubuntu26 standalone (T6), AI-tooling boundary (T7), dynamic CI + per-family cleanup + every-family-buildable (T8), hygiene+elastic archive (T1), docs (T9), testing incl. negative goss test (T10). Chained-agentic pattern: documented in T6 design note + agentic CLAUDE.md (T9.6) — no chained target is built in this pass, matching the spec.
- Type consistency: matrix entry shape `{family,name,path}` used in 8.1/8.3/8.4; harness vars `family`/`os_name` consistent across T3/T5/T8; lib contract's four function names identical in T5.3 header comment, T5.4, and interfaces block.
- The old harness's `-PASSED` rename, keypair/SG/test-instance logic: intentionally absent everywhere (T5 interfaces note, T8.3 cleanup-job deletion).
