# Family Restructure + Agentic Image Family — Implementation Plan (v2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure `vm-images/` into a multi-cloud-ready, family-aware layout (cloudberry, synxdb-cloud, agentic), adapt the hardened build harness to path-derived identity and unified `<family>-packer-<os>` naming, add the first agentic target (ubuntu26), strip AI tooling from base families, and replace the hand-maintained CI dependency map with a dynamic matrix — migrating the Python test suites in lockstep.

**Architecture:** Cloud-agnostic content at `vm-images/{scripts,common}`; targets at `vm-images/<cloud>/<family>/build/<os>`. The hardened post-build test-instance flow, private-only policy, and PASSED/FAILED tagging are PRESERVED (spec v2 decision — goss-as-provisioner was reverted). The harness is adapted (identity + paths), never rewritten.

**Tech Stack:** Bash, Packer (amazon-ebs), goss, GitHub Actions, AWS CLI, Python unittest.

**Spec:** `docs/superpowers/specs/2026-07-28-family-restructure-design.md` (v2). Base: origin/main `8741ff0` (includes PR #5).

## Global Constraints

- Image naming: HCL `ami_name` = `<family>-packer-<os>-<timestamp>`; harness `AMI_NAME_PREFIX` = `<family>-packer-<os>-`. PASSED/FAILED Name-tag suffixing stays on top (unchanged code).
- Directory contract: `vm-images/<cloud>/<family>/build/<os>/`; cloud is `aws` only for now (hard error otherwise).
- Private-only builds everywhere — never introduce publish/make-public code or wording ("make public" is policy-forbidden in docs by `test_docs_describe_private_only_builds`).
- The hardened harness behavior (runtime-key handling, run-nonce tagging, bounded cleanup, `--existing-ami`, region fixed us-west-2, owner 703671893074) is preserved verbatim except the exact edits Task 2 names.
- The three harness files (`packer-build-and-test.sh`, `private-runtime-key.py`, `validate-ami-metadata.py`) always move/live together.
- Provision scripts stay FLAT in `vm-images/common/scripts/`.
- The 9 AI-tooling scripts: `system_add_claude.sh`, `system_configure_claude.sh`, `system_add_opencode.sh`, `system_add_omnigent.sh`, `system_add_pi.sh`, `system_add_gastown.sh`, `system_add_beads.sh`, `system_add_herdr.sh`, `system_add_ai_toolchain.sh`. After Task 4, only agentic HCLs reference them.
- On-instance goss layout (`~/<os>/tests` + `~/common/tests`) unchanged; never edit `gossfile:` include lines in `tests/goss.yaml` files.
- **`python3 -m unittest discover -s tests` must pass at the end of every task** (run from the worktree root).
- Never invent AWS values; discovery commands are given where needed.
- Work on branch `restructure/family-layout` off `main` (8741ff0+docs). Commit after every task. Do not push.
- Repo root: `/Users/eespino/workspace/cloudberry-image-factory`; work in the worktree the controller names. Paths below are worktree-relative.

---

### Task 1: Hygiene — delete run-goss-tests.sh

**Files:**
- Delete: `vm-images/aws/cloudberry/scripts/run-goss-tests.sh`

- [ ] **Step 1.1: Verify it is functionally unreferenced**

```bash
grep -rn "run-goss-tests" --include="*.yml" --include="*.yaml" --include="*.hcl" --include="*.sh" --include="*.py" . | grep -v "vm-images/aws/cloudberry/scripts/run-goss-tests.sh:" || echo "CONFIRMED UNREFERENCED"
```
Expected: `CONFIRMED UNREFERENCED`. Doc mentions (README/plan/spec) do not block. If a functional file matches, STOP and report BLOCKED.

- [ ] **Step 1.2:** `git rm vm-images/aws/cloudberry/scripts/run-goss-tests.sh`
- [ ] **Step 1.3:** `python3 -m unittest discover -s tests` → all pass (suite never referenced it).
- [ ] **Step 1.4:** `git commit -m "chore: remove stale rocky9-only run-goss-tests.sh"`

---

### Task 2: Layout + identity migration (tree, HCL paths, naming, harness, test suites)

This is one atomic migration: directory renames change what the harness's
naming case-statement and the template tests key on, so moves, naming, and
test updates land together, ending green.

**Files:**
- Move: `vm-images/aws/cloudberry/build/common/` → `vm-images/common/`
- Move: `vm-images/aws/cloudberry/scripts/{packer-build-and-test.sh,private-runtime-key.py,validate-ami-metadata.py}` → `vm-images/scripts/`
- Move: `vm-images/aws/cloudberry/build/al2023-synxdb-cloud` → `vm-images/aws/synxdb-cloud/build/al2023`; same pattern for `rocky9-synxdb-cloud`→`rocky9`, `rocky10-synxdb-cloud`→`rocky10`, `ubuntu24-synxdb-cloud`→`ubuntu24`
- Modify: all 6 `vm-images/aws/*/build/*/main.pkr.hcl`
- Modify: `vm-images/scripts/packer-build-and-test.sh` (surgical edits only)
- Modify: `tests/test_packer_build_security.py`, `tests/test_packer_template_security.py`, `tests/test_repository_policy.py`
- Modify (paths only): `.github/workflows/ami-build-on-change.yml`, `.github/workflows/ami-build-manual.yml`

**Interfaces:**
- Produces: directory contract `vm-images/aws/<family>/build/<os>` (families: cloudberry{rocky9,rocky10}, synxdb-cloud{al2023,rocky9,rocky10,ubuntu24}); HCL vars `family` + `os_name` (no `vm_type`); harness derives CLOUD/FAMILY/OS_NAME from CWD; AMI base name `<family>-packer-<os>-<timestamp>`. Tasks 3-5 rely on all of these.

- [ ] **Step 2.1: Moves**

```bash
mkdir -p vm-images/scripts vm-images/aws/synxdb-cloud/build
git mv vm-images/aws/cloudberry/build/common vm-images/common
git mv vm-images/aws/cloudberry/scripts/packer-build-and-test.sh vm-images/scripts/
git mv vm-images/aws/cloudberry/scripts/private-runtime-key.py vm-images/scripts/
git mv vm-images/aws/cloudberry/scripts/validate-ami-metadata.py vm-images/scripts/
rmdir vm-images/aws/cloudberry/scripts
git mv vm-images/aws/cloudberry/build/al2023-synxdb-cloud  vm-images/aws/synxdb-cloud/build/al2023
git mv vm-images/aws/cloudberry/build/rocky9-synxdb-cloud  vm-images/aws/synxdb-cloud/build/rocky9
git mv vm-images/aws/cloudberry/build/rocky10-synxdb-cloud vm-images/aws/synxdb-cloud/build/rocky10
git mv vm-images/aws/cloudberry/build/ubuntu24-synxdb-cloud vm-images/aws/synxdb-cloud/build/ubuntu24
```

- [ ] **Step 2.2: HCL common-script path rewrite (all 6 main.pkr.hcl)**

```bash
for f in vm-images/aws/*/build/*/main.pkr.hcl; do
  sed -i.bak 's|"\.\./common/scripts/|"../../../../common/scripts/|g' "$f"; rm -f "$f.bak"
done
grep -rn '"\.\./common/' vm-images/aws/*/build/*/main.pkr.hcl && echo "LEFTOVER" || echo "OK"
```

- [ ] **Step 2.3: HCL naming (all 6 main.pkr.hcl)**

In each file: replace the variable block
```hcl
variable "vm_type" {
  type    = string
}
```
with
```hcl
variable "family" {
  type = string
}
```
and replace the `ami_name` line (current prefixes vary: `cloudberry-packer`, `synxdb-cloud-packer`, `synx-cloud-packer`) with the identical line:
```hcl
ami_name = format("%s-packer-%s-%s", var.family, var.os_name, formatdate("YYYYMMDD-HHmmss", timestamp()))
```
Then `grep -rn "vm_type" vm-images/ && echo LEFTOVER || echo OK` → `OK`.

- [ ] **Step 2.4: Harness identity edits (`vm-images/scripts/packer-build-and-test.sh`) — exactly these, nothing else**

(a) Replace the derivation block (currently):
```bash
# Derive OS_NAME and VM_TYPE from the HCL file's location
VM_TYPE=$(basename "$(dirname "$CURRENT_DIR")")  # VM_TYPE is the parent directory name
OS_NAME=$(basename "$CURRENT_DIR")  # OS_NAME is the current directory name
```
with:
```bash
# Derive CLOUD, FAMILY, and OS_NAME from the directory structure:
#   vm-images/<cloud>/<family>/build/<os>
OS_NAME=$(basename "$CURRENT_DIR")
FAMILY=$(basename "$(dirname "$(dirname "$CURRENT_DIR")")")
CLOUD=$(basename "$(dirname "$(dirname "$(dirname "$CURRENT_DIR")")")")
if [ "$(basename "$(dirname "$CURRENT_DIR")")" != "build" ] || \
   [ "$(basename "$(dirname "$(dirname "$(dirname "$(dirname "$CURRENT_DIR")")")")")" != "vm-images" ]; then
  echo "Error: run from vm-images/<cloud>/<family>/build/<os>/ (got: ${CURRENT_DIR})" >&2
  exit 1
fi
if [ "${CLOUD}" != "aws" ]; then
  echo "Error: no harness exists for cloud '${CLOUD}' (only aws is supported)." >&2
  exit 1
fi
```

(b) Replace the whole `AMI_NAME_PREFIX` case statement (the
`al2023-synxdb-cloud` / `*-synxdb-cloud` / `*` arms, currently around lines
161-171) with:
```bash
AMI_NAME_PREFIX="${FAMILY}-packer-${OS_NAME}-"
```

(c) Replace every remaining `${VM_TYPE}` with `${FAMILY}` (they appear in
`PKR_VAR_KEY_NAME`, `SECURITY_GROUP_NAME`, and the two packer var lists).
The packer invocations become `-var "family=${FAMILY}"` instead of
`-var "vm_type=${VM_TYPE}"` (both `packer validate` at ~line 484 and
`packer build` at ~line 495; keep the existing `-var "os_name=..."` and
`-var "region=..."` lines).
Then `grep -n "VM_TYPE\|vm_type" vm-images/scripts/packer-build-and-test.sh` → no output.

(d) Replace both occurrences of `${CURRENT_DIR}/../common/tests` (the
`[ -d ... ]` check at ~line 639 and the `scp` source at ~line 645) with
`${SCRIPT_DIR}/../common/tests`.

- [ ] **Step 2.5: `tests/test_packer_build_security.py` updates**

1. `SCRIPT = REPOSITORY / "vm-images/aws/cloudberry/scripts/packer-build-and-test.sh"` → `REPOSITORY / "vm-images/scripts/packer-build-and-test.sh"`.
2. In `setUp`'s synthetic tree: the target dir `build/rocky9-synxdb-cloud` (two-level) becomes `vm-images/aws/synxdb-cloud/build/rocky9`, and the common tests dir `build/common/tests` becomes `vm-images/common/tests`. IMPORTANT: the harness now finds common tests relative to the REAL script's location (`${SCRIPT_DIR}/../common/tests`), not the CWD — so the fixture must invoke a COPY of the whole `vm-images/scripts/` dir placed inside the tempdir at `vm-images/scripts/` (the existing `test_helpers_must_be_executable` already copies `SCRIPT.parent`; generalize that copy into `setUp` and invoke the copied script) so the sibling `../common/tests` resolves inside the fixture tree.
3. `_metadata` fixture and every literal AMI name: `synxdb-cloud-packer-build-rocky9-synxdb-cloud-20260727-120000` → `synxdb-cloud-packer-rocky9-20260727-120000` (and `-PASSED`/`-FAILED` variants likewise).
4. Any assertion on key/SG names embedding the old `build`/`rocky9-synxdb-cloud` tokens updates to `synxdb-cloud`/`rocky9` (harness names are now `key-synxdb-cloud-rocky9-<runid>` and `synxdb-cloud-rocky9-<runid>-sg`).
5. Run ONLY this file first: `python3 -m unittest tests.test_packer_build_security -v` → all pass.

- [ ] **Step 2.6: `tests/test_packer_template_security.py` updates**

1. `BUILD_ROOT = REPOSITORY / "vm-images/aws/cloudberry/build"` and its `BUILD_ROOT.glob("*/main.pkr.hcl")` → `REPOSITORY.glob("vm-images/aws/*/build/*/main.pkr.hcl")` (both tests).
2. `test_template_ami_name_prefix_matches_target_policy`: replace the three-arm prefix table with the single rule — for each template, family = `template.parents[2].name`; assert exactly one `ami_name =` per source block and that it contains the literal `format("%s-packer-%s-%s", var.family, var.os_name` (the naming is now variable-driven, identical across templates; the family binding is enforced at build time by the harness passing `-var family=<dir>` — assert the format shape, not a literal prefix).
3. `python3 -m unittest tests.test_packer_template_security -v` → all pass.

- [ ] **Step 2.7: `tests/test_repository_policy.py` path migration**

Update path constants and surface lists (mechanism rewrites happen in Tasks 4-5):
1. Common scripts root: `vm-images/aws/cloudberry/build/common/scripts` → `vm-images/common/scripts` everywhere.
2. `test_metadata_helper_documents_not_publicly_shared_policy`: helper path → `vm-images/scripts/validate-ami-metadata.py`.
3. `test_retired_elastic_platform_is_not_an_active_target` / `test_retired_rocky8_platform_is_not_an_active_target` surface lists: `vm-images/aws/cloudberry/scripts/packer-build-and-test.sh` → `vm-images/scripts/packer-build-and-test.sh`; `vm-images/aws/cloudberry/build/common/tests/README.md` → `vm-images/common/tests/README.md`; the absent-dir checks gain the new roots (`vm-images/aws/cloudberry/build/rocky8` still correct; keep as-is).
4. `test_synxdb_cloud_templates_require_no_cloudsmith_variables`: glob → `(REPOSITORY / "vm-images/aws/synxdb-cloud/build").glob("*/main.pkr.hcl")`.
5. `test_template_comments_explain_description_omission_without_version_pin`: glob → `REPOSITORY.glob("vm-images/aws/*/build/*/main.pkr.hcl")`.
6. `test_ubuntu24_synxdb_cloud_rebuilds_when_shared_scripts_change` (PR #5): HCL path → `vm-images/aws/synxdb-cloud/build/ubuntu24/main.pkr.hcl`; the common-script regex → `r"\.\./\.\./\.\./\.\./common/scripts/([a-z0-9_]+\.sh)"`; the COMMON_SCRIPT_DEPS membership assertion now expects `ubuntu24` (matching Step 2.8's workflow rename). This test is deleted in Task 5; here it just has to keep passing against the interim workflows.
7. `test_ubuntu24_goss_covers_ai_toolchain_executables` (PR #5): paths → `vm-images/common/scripts/system_add_ai_toolchain.sh` and `vm-images/aws/synxdb-cloud/build/ubuntu24/tests/goss.yaml`.
8. `test_rocky10_claude_launcher_is_symlink` and `test_rocky10_has_no_nodejs`: rocky10 paths are unchanged (`vm-images/aws/cloudberry/build/rocky10/...`) — no edit here (Task 4 handles the claude test).
9. `test_ci_runs_offline_unittest_before_build_script`: asserted invocation literal `../../scripts/packer-build-and-test.sh` → `../../../../scripts/packer-build-and-test.sh`.

- [ ] **Step 2.8: Minimal workflow path fixes (keep CI coherent until Task 5's rewrite)**

In `.github/workflows/ami-build-on-change.yml` and `ami-build-manual.yml` — do NOT restructure the matrix logic yet; only make paths/names track the moved tree:
1. Path filters: replace `vm-images/aws/cloudberry/build/**` and `vm-images/aws/cloudberry/scripts/**` with `vm-images/**` (keep `!**/*.md`).
2. Target rename: every `ubuntu24-synxdb-cloud` token in COMMON_SCRIPT_DEPS values, case arms, `all_builds`, and the manual `build_targets` options becomes `ubuntu24`.
3. Matrix `path` construction: cloudberry targets keep `vm-images/aws/cloudberry/build/<name>`; add family awareness — build each entry as `{"family":F,"name":N,"path":"vm-images/aws/F/build/N"}` where F is `cloudberry` for rocky9/rocky10 and `synxdb-cloud` for ubuntu24 (a small lookup case in the matrix-emission loop).
4. Common-script case arm: `"vm-images/aws/cloudberry/build/common/scripts/"*.sh)` → `"vm-images/common/scripts/"*.sh)`; common tests arm → `"vm-images/common/tests/"*.yaml)`.
5. Harness arm: `"vm-images/aws/cloudberry/scripts/packer-build-and-test.sh")` → `"vm-images/scripts/"*)`.
6. Per-target script/HCL/goss case arms: replace the `vm-images/aws/cloudberry/build/...` patterns with `vm-images/aws/*/build/*/...` extracting `os=$(echo "$file" | cut -d'/' -f5)` and appending `"$os"` (the name tokens rocky9/rocky10/ubuntu24 remain what DEPS/all_builds use; note cloudberry/rocky9 and synxdb-cloud/rocky9 collide on the bare name — acceptable interim behavior matching upstream's own name-keyed maps; Task 5 fixes it properly with family-qualified entries).
7. Build invocations (both workflows): `chmod +x ../../scripts/packer-build-and-test.sh` and `../../scripts/packer-build-and-test.sh` → `../../../../scripts/packer-build-and-test.sh`.
8. Validate step: `-var "vm_type=cloudberry"` → `-var "family=${{ matrix.build.family }}"`.

- [ ] **Step 2.9: Validate everything**

```bash
for d in vm-images/aws/*/build/*/; do
  fam=$(basename "$(dirname "$(dirname "$d")")")
  ( cd "$d" && packer init main.pkr.hcl >/dev/null && \
    packer validate -var "family=$fam" -var "os_name=$(basename "$d")" -var "region=us-west-2" main.pkr.hcl ) \
    && echo "PASS $d" || { echo "FAIL $d"; exit 1; }
done
bash -n vm-images/scripts/packer-build-and-test.sh
python3 -m unittest discover -s tests
for f in .github/workflows/*.yml; do python3 -c "import yaml; yaml.safe_load(open('$f'))" && echo "OK $f"; done
```
Expected: 6× PASS, bash -n silent, full unittest suite green, YAML OK ×3.

- [ ] **Step 2.10: Commit** — `git add -A && git commit -m "refactor: family-aware layout; path-derived harness identity; <family>-packer-<os> naming; test suites migrated"`

---

### Task 3: Agentic ubuntu26 target

**Files:**
- Create: `vm-images/aws/agentic/build/ubuntu26/main.pkr.hcl` (ported from `vm-images/aws/synxdb-cloud/build/ubuntu24/main.pkr.hcl`, which includes PR #5's refreshed AI toolchain)
- Create: `vm-images/aws/agentic/build/ubuntu26/tests/goss.yaml` (ported from ubuntu24's, incl. PR #5's `--version` checks)
- Create: `vm-images/aws/agentic/build/ubuntu26/scripts/` — copy the target-local scripts the ported HCL references (ubuntu24 has `system_add_synxdb_cloud_dependencies.sh`, `system_set_default_locale.sh`)

**Interfaces:**
- Consumes: Task 2's contract (HCL vars family/os_name; `../../../../common/scripts/` refs).
- Produces: buildable agentic target; AMI `agentic-packer-ubuntu26-<timestamp>`. Design note: this is the approved standalone exception (no ubuntu26 base exists); future chained agentic targets set `source_ami_filter` to the base target's `*-PASSED` AMIs with `base_family`/`base_os` vars.

- [ ] **Step 3.1: Discover the real Ubuntu 26.04 source AMI — never guess**

```bash
aws ec2 describe-images --owners 099720109477 --region us-west-2 \
  --filters "Name=name,Values=*26.04*amd64*server*" "Name=virtualization-type,Values=hvm" \
  --query 'sort_by(Images,&CreationDate)[-1].{Name:Name,Owner:OwnerId}' --output json
```
Record the `Name`; generalize only its trailing datestamp to `*` (mirror how ubuntu24's HCL generalizes its filter). If the result is empty: STOP, report BLOCKED (do not fabricate a filter).

- [ ] **Step 3.2: Port**

```bash
mkdir -p vm-images/aws/agentic/build/ubuntu26/tests vm-images/aws/agentic/build/ubuntu26/scripts
cp vm-images/aws/synxdb-cloud/build/ubuntu24/main.pkr.hcl vm-images/aws/agentic/build/ubuntu26/main.pkr.hcl
cp vm-images/aws/synxdb-cloud/build/ubuntu24/tests/goss.yaml vm-images/aws/agentic/build/ubuntu26/tests/goss.yaml
cp vm-images/aws/synxdb-cloud/build/ubuntu24/scripts/*.sh vm-images/aws/agentic/build/ubuntu26/scripts/
```
Edits to the new HCL:
1. `source_ami_filter` name → Step 3.1's pattern (owner stays `099720109477`).
2. Keep ALL provisioners including the AI-tooling set (this IS the agentic image).
3. Keep the `Omit ami_description: it would call denied ModifyImageAttribute.` comment (policy test requires it in every template).
4. Verify `temporary_security_group_source_public_ip = true` survived the copy (template security test).
Edits to the new goss.yaml: none expected (paths are `/home/ubuntu/...`; includes resolve on-instance identically). Check `grep -n "ubuntu24" vm-images/aws/agentic/build/ubuntu26/tests/goss.yaml` and fix any hit to `ubuntu26`.

- [ ] **Step 3.3: Validate + suite**

```bash
( cd vm-images/aws/agentic/build/ubuntu26 && packer init main.pkr.hcl >/dev/null && \
  packer validate -var "family=agentic" -var "os_name=ubuntu26" -var "region=us-west-2" main.pkr.hcl )
python3 -m unittest discover -s tests
```
The template-security and description-comment tests glob `vm-images/aws/*/build/*/main.pkr.hcl` after Task 2, so the new target is automatically covered — both must pass.

- [ ] **Step 3.4: Commit** — `git add vm-images/aws/agentic && git commit -m "feat: agentic ubuntu26 target (standalone from stock Ubuntu 26.04)"`

---

### Task 4: Strip AI tooling from base families (+ policy tests)

**Files:**
- Modify: every `vm-images/aws/{cloudberry,synxdb-cloud}/build/*/main.pkr.hcl` that references an AI-tooling script, and its `tests/goss.yaml`
- Modify: `tests/test_repository_policy.py`

**Interfaces:**
- Consumes: agentic target (Task 3) carrying the AI provisioners + assertions.
- Produces: AI-tooling references exist ONLY in `vm-images/aws/agentic/**`; a policy test enforces this permanently.

- [ ] **Step 4.1: Enumerate**

```bash
grep -ln 'system_add_claude\|system_configure_claude\|system_add_opencode\|system_add_omnigent\|system_add_pi\.sh\|system_add_gastown\|system_add_beads\|system_add_herdr\|system_add_ai_toolchain' \
  vm-images/aws/cloudberry/build/*/main.pkr.hcl vm-images/aws/synxdb-cloud/build/*/main.pkr.hcl
```
(cloudberry rocky9/rocky10 install `system_add_claude.sh` for gpadmin+cbadmin; synxdb-cloud rocky10 and ubuntu24 carry larger sets.)

- [ ] **Step 4.2:** In each matching base-family HCL, delete the entire `provisioner "shell" { ... }` blocks referencing those scripts (including their comment lines and `environment_vars` blocks).

- [ ] **Step 4.3:** In each edited target's `tests/goss.yaml`, delete the assertions verifying AI tooling (file/command checks for claude, opencode, omnigent, pi, gastown, beads, herdr, codex, copilot, gemini, cursor-agent, kimi, hermes, agy — including PR #5's `--version` command checks). Before deleting each, confirm an equivalent exists in `vm-images/aws/agentic/build/ubuntu26/tests/goss.yaml`; if missing there, ADD it there (with `/home/ubuntu/` paths) rather than losing coverage. Do not remove non-AI assertions.

- [ ] **Step 4.4: Policy test updates in `tests/test_repository_policy.py`**

1. DELETE `test_rocky10_claude_launcher_is_symlink` (rocky10 no longer ships claude — this task removes the premise).
2. Keep `test_rocky10_has_no_nodejs` (should still pass).
3. Repoint PR #5's `test_ubuntu24_goss_covers_ai_toolchain_executables` at the agentic target: rename to `test_agentic_ubuntu26_goss_covers_ai_toolchain_executables`; goss path → `vm-images/aws/agentic/build/ubuntu26/tests/goss.yaml` (script path unchanged from Task 2).
4. ADD the boundary test:
```python
    def test_ai_tooling_ships_only_in_agentic_family(self) -> None:
        ai_scripts = [
            "system_add_claude.sh", "system_configure_claude.sh",
            "system_add_opencode.sh", "system_add_omnigent.sh",
            "system_add_pi.sh", "system_add_gastown.sh",
            "system_add_beads.sh", "system_add_herdr.sh",
            "system_add_ai_toolchain.sh",
        ]
        templates = sorted(REPOSITORY.glob("vm-images/aws/*/build/*/main.pkr.hcl"))
        self.assertTrue(templates)
        for template in templates:
            family = template.parents[2].name
            if family == "agentic":
                continue
            content = template.read_text()
            for script in ai_scripts:
                with self.subTest(template=str(template), script=script):
                    self.assertNotIn(script, content)
```

- [ ] **Step 4.5: Verify + suite**

```bash
grep -rln 'system_add_claude\|system_configure_claude\|system_add_opencode\|system_add_omnigent\|system_add_pi\.sh\|system_add_gastown\|system_add_beads\|system_add_herdr\|system_add_ai_toolchain' vm-images/aws/*/build/*/main.pkr.hcl
# expected output: ONLY vm-images/aws/agentic/build/ubuntu26/main.pkr.hcl
for d in vm-images/aws/*/build/*/; do fam=$(basename "$(dirname "$(dirname "$d")")"); ( cd "$d" && packer validate -var "family=$fam" -var "os_name=$(basename "$d")" -var "region=us-west-2" main.pkr.hcl ) || exit 1; done
python3 -m unittest discover -s tests
```

- [ ] **Step 4.6: Commit** — `git commit -am "refactor: AI tooling ships only in agentic images; boundary policy test"`

---

### Task 5: CI workflows — dynamic matrix

**Files:**
- Create: `.github/scripts/compute-build-matrix.sh`
- Rewrite matrix logic in: `.github/workflows/ami-build-on-change.yml`
- Rewrite target selection in: `.github/workflows/ami-build-manual.yml`
- Modify: `.github/workflows/ami-cleanup-old.yml`
- Modify: `tests/test_repository_policy.py`

**Interfaces:**
- Consumes: directory contract; harness invocation `../../../../scripts/packer-build-and-test.sh` (Task 2).
- Produces: matrix entries `{"family":"<family>","name":"<os>","path":"vm-images/aws/<family>/build/<os>"}`; every target CI-buildable.
- Preserve verbatim (policy-tested): PR validation-only gating (`github.event_name != 'pull_request'` on build+cleanup jobs AND their credential steps), PR diff via `github.event.pull_request.{base,head}.sha` with `fetch-depth: 0`, offline unittest step before builds (incl. its `install -d -m 0700` / `XDG_RUNTIME_DIR` / `GITHUB_ENV` lines), `AWS_REGION: us-west-2` env in every workflow, no `make_public`/`aws_region` inputs.

- [ ] **Step 5.1: Write `.github/scripts/compute-build-matrix.sh`**

```bash
#!/usr/bin/env bash
# Computes the AMI build matrix from a newline-separated changed-file list on
# stdin. Prints JSON {"build":[{family,name,path},...]} on stdout.
# Rules:
#   vm-images/aws/<family>/build/<os>/**                -> that target
#   vm-images/common/scripts/X.sh                       -> targets whose HCL references X.sh
#   vm-images/scripts/** or vm-images/common/tests/**   -> all targets
set -euo pipefail

all_targets() {
  local d fam os
  for d in vm-images/aws/*/build/*/; do
    [ -f "${d}main.pkr.hcl" ] || continue
    fam=$(basename "$(dirname "$(dirname "$d")")")
    os=$(basename "$d")
    echo "$fam $os ${d%/}"
  done
}

declare -A picked=()
add_target() { picked["$1|$2|$3"]=1; }
add_all() { local f n p; while read -r f n p; do add_target "$f" "$n" "$p"; done < <(all_targets); }

while IFS= read -r file; do
  [ -z "$file" ] && continue
  [ -f "$file" ] || continue   # deletions cannot affect a build
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
`chmod +x` it; `shellcheck` it — zero findings (new code).

- [ ] **Step 5.2: Test the matrix script locally**

```bash
echo "README.md" | .github/scripts/compute-build-matrix.sh                                              # {"build":[]}
echo "vm-images/aws/cloudberry/build/rocky9/main.pkr.hcl" | .github/scripts/compute-build-matrix.sh    # exactly cloudberry/rocky9
echo "vm-images/common/scripts/system_add_goss.sh" | .github/scripts/compute-build-matrix.sh           # every target whose HCL references it (spot-check one)
echo "vm-images/scripts/packer-build-and-test.sh" | .github/scripts/compute-build-matrix.sh            # all 7 targets
echo "vm-images/common/scripts/system_add_ai_toolchain.sh" | .github/scripts/compute-build-matrix.sh   # ONLY agentic/ubuntu26 (post Task 4)
```

- [ ] **Step 5.3: `ami-build-on-change.yml`** — replace the `COMMON_SCRIPT_DEPS` map and case-statement logic in `detect-changes` with:

```yaml
      - name: Compute build matrix
        id: set-matrix
        shell: bash
        run: |
          if [ "${{ github.event_name }}" == "pull_request" ]; then
            changed=$(git diff --name-only "${{ github.event.pull_request.base.sha }}...${{ github.event.pull_request.head.sha }}")
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
Keep everything the Interfaces block lists as preserved. Add `tests/**` and `.github/**` to the `paths:` filters (keep `!**/*.md`). Fix the cleanup job's leftover-resource filters to match harness names (post-Task-2): SG filter `${{ matrix.build.family }}-${{ matrix.build.name }}-*-sg`, key filter `key-${{ matrix.build.family }}-${{ matrix.build.name }}-*`.

- [ ] **Step 5.4: `ami-build-manual.yml`** — replace the choice input + `all_builds` array:

```yaml
        build_targets:
          description: 'Targets: "all" or comma-separated family/os (e.g. cloudberry/rocky9,agentic/ubuntu26)'
          required: true
          default: 'all'
          type: string
```
setup-matrix body:
```bash
if [ "${{ github.event.inputs.build_targets }}" = "all" ]; then
  entries=$(for d in vm-images/aws/*/build/*/; do
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
Keep `max-parallel: 2`, the unittest step, validate/build steps as in 5.3.

- [ ] **Step 5.5: `ami-cleanup-old.yml`** — replace the single `cloudberry-packer-build-*` AMI filter, its snapshot-description filter, and the `sed 's/cloudberry-packer-build-.../'` config derivation with a per-family loop (requires a checkout step to enumerate families):

```bash
for famdir in vm-images/aws/*/; do
  family=$(basename "$famdir")
  pattern="${family}-packer-*"
  # existing retention logic runs once per $pattern; config key derivation:
  #   sed "s/^${family}-packer-\(.*\)-[0-9]\{8\}-[0-9]\{6\}.*/\1/"
done
```
Keep `dry_run` (forced true on schedule), `retention_count` default 3, `AWS_REGION: us-west-2`.

- [ ] **Step 5.6: Policy test rewrites in `tests/test_repository_policy.py`**

1. DELETE `test_ubuntu24_synxdb_cloud_rebuilds_when_shared_scripts_change` — the drift it guarded (hand-map vs HCL) is structurally impossible under the grep-based matrix. Replace with:
```python
    def test_dynamic_matrix_selects_targets_from_hcl_references(self) -> None:
        import json
        import subprocess
        script = REPOSITORY / ".github/scripts/compute-build-matrix.sh"
        self.assertTrue(script.exists())
        out = subprocess.run(
            ["bash", str(script)],
            input="vm-images/common/scripts/system_add_goss.sh\n",
            capture_output=True, text=True, cwd=REPOSITORY, check=True,
        ).stdout
        names = {(b["family"], b["name"]) for b in json.loads(out)["build"]}
        expected = set()
        for template in REPOSITORY.glob("vm-images/aws/*/build/*/main.pkr.hcl"):
            if "system_add_goss.sh" in template.read_text():
                expected.add((template.parents[2].name, template.parent.name))
        self.assertTrue(expected)
        self.assertEqual(names, expected)
```
2. `test_ci_runs_offline_unittest_before_build_script`, `test_pull_requests_validate_without_building_or_cleaning_aws`, `test_change_detection_fetches_and_diffs_pull_request_shas`, `test_all_workflows_are_fixed_to_us_west_2`: keep UNCHANGED — the rewritten workflows must satisfy them (that is the point of preserving the invariants).

- [ ] **Step 5.7: Verify**

```bash
shellcheck .github/scripts/compute-build-matrix.sh
for f in .github/workflows/*.yml; do python3 -c "import yaml; yaml.safe_load(open('$f'))" && echo "OK $f"; done
python3 -m unittest discover -s tests
```

- [ ] **Step 5.8: Commit** — `git add .github tests && git commit -m "ci: dynamic family-aware build matrix; per-family cleanup; policy tests updated"`

---

### Task 6: Documentation

**Files:**
- Modify: `CLAUDE.md`, `README.md`, `ROADMAP.md`, `.github/workflows/README.md`, `vm-images/common/tests/README.md`
- Modify: `vm-images/aws/synxdb-cloud/build/{rocky9,rocky10,ubuntu24}/CLAUDE.md`
- Create: `vm-images/aws/agentic/build/ubuntu26/CLAUDE.md`

Constraints from policy tests (verify each doc against them): no "make public"/"make ami public" substrings (case-insensitive) in README.md or the workflows README; `rocky8` and elastic mentioned only on lines containing retired/archived/recoverable/history/historical.

- [ ] **Step 6.1: `CLAUDE.md`** — new layout tree; platform table = 7 targets (cloudberry rocky9/rocky10; synxdb-cloud al2023/rocky9/rocky10/ubuntu24; agentic ubuntu26); harness path `vm-images/scripts/packer-build-and-test.sh`; script count from `ls vm-images/common/scripts/*.sh | wc -l`; keep provisioner-order checklist + RPM/DEB notes; add "new family" checklist (create `vm-images/aws/<family>/build/<os>/` — no workflow edits needed, matrix is dynamic) and "new target" checklist; state AI tooling is agentic-only.
- [ ] **Step 6.2: `README.md`** — tree diagram; invocation examples → `../../../../scripts/packer-build-and-test.sh`; AMI naming → `<family>-packer-<os>-<timestamp>` (+ unchanged `-PASSED`/`-FAILED` tagging); remove the `run-goss-tests.sh` line from the directory listing (flagged in Task 1); build-target table incl. agentic/ubuntu26; keep all private-only wording.
- [ ] **Step 6.3: `ROADMAP.md`** — `smoke-test.sh` path → `vm-images/scripts/smoke-test.sh`; fix the "In packer-build-and-test.sh after Goss tests" snippet's path mention; add completed note "2026-07: family-aware restructure (cloudberry / synxdb-cloud / agentic)".
- [ ] **Step 6.4: `.github/workflows/README.md`** — dynamic matrix rules (from compute-build-matrix.sh), `family/os` dispatch format, per-family cleanup patterns; keep private-only IAM wording.
- [ ] **Step 6.5: `vm-images/common/tests/README.md`** — path updates; fix the stale archived-platform list (al2023, ubuntu22, centos10, debian12, ubuntu20 — label archived/git-history).
- [ ] **Step 6.6: Per-target CLAUDE.md** — update paths in the 3 synxdb-cloud files; remove AI-tooling rows (agentic-only now); replace elastic "Reference Platforms" mentions with archived-note wording. Create `vm-images/aws/agentic/build/ubuntu26/CLAUDE.md` modeled on ubuntu24's: standalone-from-stock-Ubuntu exception, AI tooling list, chained pattern for future targets.
- [ ] **Step 6.7: Verify**

```bash
grep -rn "vm-images/aws/cloudberry/scripts\|cloudberry-packer-build\|run-goss-tests" README.md CLAUDE.md ROADMAP.md .github/workflows/README.md && echo STALE || echo OK
python3 -m unittest discover -s tests
```
Expected: `OK`; suite green (doc policy tests included).

- [ ] **Step 6.8: Commit** — `git commit -am "docs: family layout, unified AMI naming, dynamic CI matrix, agentic family"`

---

### Task 7: Live verification builds (operator gate — REQUIRES explicit user go-ahead; real AWS spend, ~30-60 min per build)

- [ ] **Step 7.1:** `cd vm-images/aws/cloudberry/build/rocky9 && ../../../../scripts/packer-build-and-test.sh` — verify: AMI `cloudberry-packer-rocky9-<ts>` tagged `-PASSED`, private, goss results retrieved, all temp resources cleaned.
- [ ] **Step 7.2:** same for `vm-images/aws/synxdb-cloud/build/rocky10` — additionally verify the image has NO AI tooling (goss output contains no claude/opencode assertions; optionally ssh in and check `~gpadmin/.local/bin`).
- [ ] **Step 7.3:** same for `vm-images/aws/agentic/build/ubuntu26` — fix Ubuntu 26.04 package renames or assertion mismatches surfaced by the build (adjust the specific item; never weaken the suite wholesale).
- [ ] **Step 7.4:** negative test — add a deliberately false assertion to rocky9's goss.yaml, run, confirm the AMI is tagged `-FAILED` and the run fails; revert the assertion.
- [ ] **Step 7.5:** deregister the verification AMIs + snapshots; commit any fixes: `git commit -am "fix: adjustments from live verification builds"`.

---

## Self-review notes (resolved inline)

- Spec v2 coverage: layout+hoist (T2), harness adapt-not-rewrite + naming (T2), test-suite migration §4a (T2/T4/T5), agentic ubuntu26 standalone (T3), AI boundary + new policy test (T4), dynamic CI + preserved invariants + per-family cleanup + SG/key filter fix (T5), hygiene (T1), docs incl. wording constraints (T6), live verification incl. negative test (T7). Private-only: no publish code or wording introduced anywhere. Chained-agentic pattern documented (T3 interface note + T6.6).
- Ordering hazards addressed: dir renames ↔ naming ↔ tests land atomically (T2); minimal workflow path fix (T2.8) keeps CI coherent between T2 and T5; PR #5's two policy tests are migrated in T2.7 and repointed/replaced in T4.4/T5.6.
- Type consistency: matrix entry `{family,name,path}` in 5.1/5.3/5.4; HCL vars `family`/`os_name` in T2.3/T2.4/T2.8/T3/T5; AI-script list identical in Global Constraints, T4.1, T4.4; family extraction `template.parents[2].name` / os `template.parent.name` consistent in T2.6/T4.4/T5.6.
