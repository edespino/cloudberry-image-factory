# Grok CLI in the Agentic AI Toolchain — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install the xAI Grok CLI (as tool 11 of the consolidated AI toolchain) on both agentic AMI targets, with goss coverage.

**Architecture:** One shared provisioner script gains an eleventh `curl | bash` per-user installer step plus a hard-fail binary verification; both agentic targets' goss suites assert the installed binary and its version command. An existing repository policy test (`test_agentic_goss_covers_ai_toolchain_executables`) derives required goss coverage from the script's verification loop, so it is the failing-test driver for this change.

**Tech Stack:** Bash provisioner scripts, Packer HCL, Goss YAML, Python `unittest` policy suite.

**Spec:** `docs/superpowers/specs/2026-07-31-agentic-grok-cli-design.md`

## Global Constraints

- Install command is exactly `curl -fsSL https://x.ai/cli/install.sh | bash` — unpinned, latest stable (matches the toolchain versioning policy).
- Grok installs to `/home/ubuntu/.grok/bin/grok`; that native path (not `~/.local/bin`) is what gets verified and goss-tested.
- Scope is user `ubuntu` only. No standalone `system_add_grok.sh`; no gpadmin/cbadmin install; no auth/config baked.
- All repo test commands run from the repository root: `/Users/eespino/workspace/cloudberry-image-factory`.
- The user must confirm before any build/AWS command (`packer`, `packer-build-and-test.sh`).

---

### Task 1: Add grok to the toolchain script and goss suites

**Files:**
- Modify: `vm-images/common/scripts/system_add_ai_toolchain.sh` (header list lines 7–16, installer sections lines 89–121, verification loop lines 129–139, version report lines 174–183)
- Modify: `vm-images/aws/agentic/build/ubuntu26/tests/goss.yaml` (file block ~line 240, command block ~line 573)
- Modify: `vm-images/aws/agentic/build/ubuntu26-arm64/tests/goss.yaml` (file block ~line 241, command block ~line 567)
- Test: `tests/test_repository_policy.py` (existing test, no edits — it derives expectations from the script)

**Interfaces:**
- Consumes: existing `run_as_user` helper and `report_version` helper inside `system_add_ai_toolchain.sh`.
- Produces: verified executable `/home/ubuntu/.grok/bin/grok` on both agentic AMIs; goss assertions later tasks' docs refer to.

- [ ] **Step 1: Edit the script header tool list**

In `vm-images/common/scripts/system_add_ai_toolchain.sh`, after the line

```
#   agy           Google Antigravity CLI       ~/.local/bin/agy
```

add:

```
#   grok          xAI Grok CLI                 ~/.grok/bin/grok
```

- [ ] **Step 2: Renumber installer section headers and add the grok step**

Change every `[n/10]` header to `[n/11]` (10 occurrences, lines 89–121):

```
=== [1/10] claude   → === [1/11] claude
=== [2/10] pi       → === [2/11] pi
=== [3/10] codex    → === [3/11] codex
=== [4/10] copilot  → === [4/11] copilot
=== [5/10] gemini   → === [5/11] gemini
=== [6/10] cursor-agent → === [6/11] cursor-agent
=== [7/10] kimi     → === [7/11] kimi
=== [8/10] opencode → === [8/11] opencode
=== [9/10] hermes   → === [9/11] hermes
=== [10/10] agy     → === [10/11] agy
```

Then, after the agy install line

```bash
echo "=== [10/11] agy (Google Antigravity CLI) ==="
run_as_user bash -c 'curl -fsSL https://antigravity.google/cli/install.sh | bash'
```

add:

```bash
echo "=== [11/11] grok (xAI Grok CLI) ==="
# Installs to ~/.grok/bin (native path; the installer's ~/.local/bin symlink
# is skipped because that dir is not on PATH in the provisioner session).
# The installer adds ~/.grok/bin to .bashrc itself.
run_as_user bash -c 'curl -fsSL https://x.ai/cli/install.sh | bash'
```

- [ ] **Step 3: Extend the verification loop**

In the same script, change

```bash
  "${USER_HOME}/.local/bin/agy"
do
```

to

```bash
  "${USER_HOME}/.local/bin/agy" \
  "${USER_HOME}/.grok/bin/grok"
do
```

- [ ] **Step 4: Extend the version report**

After

```bash
report_version agy          "${USER_HOME}/.local/bin/agy" --version
```

add:

```bash
report_version grok         "${USER_HOME}/.grok/bin/grok" --version
```

- [ ] **Step 5: Run the policy test to verify it fails**

Run:
```bash
python3 -m unittest tests.test_repository_policy.RepositoryPolicyTests.test_agentic_goss_covers_ai_toolchain_executables -v
```
Expected: FAIL — both agentic goss files lack `/home/ubuntu/.grok/bin/grok` (subTest failures for `ubuntu26` and `ubuntu26-arm64`). This confirms the policy test now demands grok coverage.

- [ ] **Step 6: Add goss file assertions (both targets)**

In `vm-images/aws/agentic/build/ubuntu26/tests/goss.yaml` (~line 240) and `vm-images/aws/agentic/build/ubuntu26-arm64/tests/goss.yaml` (~line 241), after the block

```yaml
  # Google Antigravity CLI
  /home/ubuntu/.local/bin/agy:
    exists: true
```

add:

```yaml
  # xAI Grok CLI (per-user install, native path ~/.grok/bin)
  /home/ubuntu/.grok/bin/grok:
    exists: true
```

- [ ] **Step 7: Add goss version-command checks (both targets)**

In `vm-images/aws/agentic/build/ubuntu26/tests/goss.yaml` (~line 578) and `vm-images/aws/agentic/build/ubuntu26-arm64/tests/goss.yaml` (~line 572), after the block

```yaml
  # Google Antigravity CLI — executable-only. `agy --version` needs a TTY
  # (bubbletea: "error opening TTY: could not open TTY: open /dev/tty: no
  # such device or address"), so no version command can run under goss.
  "test -x /home/ubuntu/.local/bin/agy":
    exit-status: 0
    timeout: 5000
```

add:

```yaml
  # xAI Grok CLI version check
  "sudo -n -u ubuntu env HOME=/home/ubuntu PATH=/home/ubuntu/.local/bin:/usr/local/bin:/usr/bin:/bin /home/ubuntu/.grok/bin/grok --version < /dev/null":
    exit-status: 0
    timeout: 30000
```

Contingency (build-time, not now): if the first real build shows `grok --version` needs a TTY (as agy does), replace this entry with `"test -x /home/ubuntu/.grok/bin/grok": {exit-status: 0, timeout: 5000}` plus a comment explaining the TTY limitation, mirroring the agy pattern.

- [ ] **Step 8: Run the policy test to verify it passes**

Run:
```bash
python3 -m unittest tests.test_repository_policy.RepositoryPolicyTests.test_agentic_goss_covers_ai_toolchain_executables -v
```
Expected: PASS.

- [ ] **Step 9: Run the full repo test suite**

Run:
```bash
python3 -m unittest discover -s tests -v 2>&1 | tail -20
```
Expected: all tests pass (`OK`).

- [ ] **Step 10: Shellcheck the edited script**

Run:
```bash
shellcheck vm-images/common/scripts/system_add_ai_toolchain.sh
```
Expected: no new warnings (compare against `git stash`-free baseline only if warnings appear; the script is currently clean).

- [ ] **Step 11: Commit** *(requires user confirmation)*

```bash
git add vm-images/common/scripts/system_add_ai_toolchain.sh \
        vm-images/aws/agentic/build/ubuntu26/tests/goss.yaml \
        vm-images/aws/agentic/build/ubuntu26-arm64/tests/goss.yaml
git commit -m "agentic: add grok CLI to ai toolchain"
```

---

### Task 2: Update template comments and target docs

**Files:**
- Modify: `vm-images/aws/agentic/build/ubuntu26/main.pkr.hcl:244-246` (provisioner comment)
- Modify: `vm-images/aws/agentic/build/ubuntu26-arm64/main.pkr.hcl:244-246` (provisioner comment)
- Modify: `vm-images/aws/agentic/build/ubuntu26/CLAUDE.md:33-35` (AI tooling list)

**Interfaces:**
- Consumes: the tool set installed by Task 1 (claude, pi, codex, copilot, gemini, cursor-agent, kimi, opencode, hermes, agy, grok).
- Produces: documentation only; no code contracts.

- [ ] **Step 1: Update both main.pkr.hcl comments**

In `vm-images/aws/agentic/build/ubuntu26/main.pkr.hcl` and `vm-images/aws/agentic/build/ubuntu26-arm64/main.pkr.hcl`, change

```
  # Install the AI agent toolchain for ubuntu (single consolidated process:
  # claude, pi, codex, copilot, gemini, cursor-agent, kimi, opencode, hermes
  # — all per-user so each tool can self-update)
```

to

```
  # Install the AI agent toolchain for ubuntu (single consolidated process:
  # claude, pi, codex, copilot, gemini, cursor-agent, kimi, opencode, hermes,
  # agy, grok — all per-user so each tool can self-update)
```

(The comment was already stale — it omitted agy; this edit also fixes that.)

- [ ] **Step 2: Update the ubuntu26 CLAUDE.md tool list**

In `vm-images/aws/agentic/build/ubuntu26/CLAUDE.md`, change

```
- `system_add_ai_toolchain.sh` (DB_USERNAME=ubuntu) - single consolidated
  per-user install: claude, pi, codex, copilot, gemini, cursor-agent, kimi,
  opencode, hermes (each self-updating)
```

to

```
- `system_add_ai_toolchain.sh` (DB_USERNAME=ubuntu) - single consolidated
  per-user install: claude, pi, codex, copilot, gemini, cursor-agent, kimi,
  opencode, hermes, agy, grok (each self-updating)
```

(The arm64 target's `CLAUDE.md` does not enumerate the tools — no change.)

- [ ] **Step 3: Validate both templates** *(requires user confirmation — packer)*

Run:
```bash
cd vm-images/aws/agentic/build/ubuntu26 && packer validate . ; cd -
cd vm-images/aws/agentic/build/ubuntu26-arm64 && packer validate . ; cd -
```
Expected: `The configuration is valid.` for both. (Comments only changed, but this guards against stray HCL breakage.)

- [ ] **Step 4: Commit** *(requires user confirmation)*

```bash
git add vm-images/aws/agentic/build/ubuntu26/main.pkr.hcl \
        vm-images/aws/agentic/build/ubuntu26-arm64/main.pkr.hcl \
        vm-images/aws/agentic/build/ubuntu26/CLAUDE.md
git commit -m "agentic: document grok in toolchain comments"
```

---

### Task 3: Local build verification (gate before push)

**Files:**
- None modified (build artifacts only), unless the goss contingency from Task 1 Step 7 triggers.

**Interfaces:**
- Consumes: everything committed in Tasks 1–2.
- Produces: an `agentic-packer-ubuntu26-<timestamp>-PASSED` AMI proving the change end-to-end; the build log's `VERSION grok:` line records the resolved version.

- [ ] **Step 1: Full build + goss test of the x86 target** *(requires user confirmation — AWS build, ~long-running)*

Run:
```bash
cd vm-images/aws/agentic/build/ubuntu26 && ../../../../scripts/packer-build-and-test.sh
```
Expected:
- Build log shows `=== [11/11] grok (xAI Grok CLI) ===`, `OK: /home/ubuntu/.grok/bin/grok`, and a `VERSION grok:` line.
- Goss passes; AMI renamed with `-PASSED` suffix.

If goss fails only on the grok version-command check with a TTY error: apply the Task 1 Step 7 contingency (executable-only check) to **both** goss files, re-run the policy test and full suite from Task 1 Steps 8–9, commit as `agentic: grok goss check executable-only (TTY)` *(requires user confirmation)*, and re-run this build.

- [ ] **Step 2: Report results**

State the resolved grok version from the build log and the final AMI name/status. The arm64 target is exercised by CI on push (the shared-script edit selects both agentic targets); a local arm64 build is optional and only warranted if x86 results suggest arch-specific risk.

- [ ] **Step 3: Push** *(requires user confirmation)*

```bash
git push origin main
```
Expected: CI rebuilds both agentic targets (shared-script change selects them in the computed matrix).
