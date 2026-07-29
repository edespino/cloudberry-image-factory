# Design: Family-Aware Restructure + Agentic Image Family

Date: 2026-07-28 (revised same day against origin/main d8908be — see "Revision
history" at the end)
Repo: cloudberry-image-factory
Status: Approved design, pending implementation plan (v2)

## Problem

1. `vm-images/aws/cloudberry/` mixes two product families: plain Cloudberry
   build targets (rocky9/10) and SynxDB Cloud targets (`*-synxdb-cloud`).
2. The build/test harness lives inside the `cloudberry` tree and cannot be
   shared cleanly by a new peer family.
3. A new **agentic** family is being introduced: dedicated images carrying
   the AI/agent tooling that today is baked into the synxdb-cloud images
   via common provision scripts.
4. Accumulated maintainability problems:
   - `vm_type` in the harness resolves to the literal string `build`
     (`basename $(dirname $CWD)`), which is why AMIs are named
     `<prefix>-packer-build-*`; the AMI name prefix policy is a hand-coded
     case statement duplicated across the harness, a template test, and the
     cleanup workflow.
   - CI's `COMMON_SCRIPT_DEPS` dependency map is hand-maintained and must be
     edited for every provisioner/target pairing; synxdb-cloud targets are
     not buildable via the manual workflow.
   - The cleanup workflow's `cloudberry-packer-build-*` filter never matches
     synxdb AMIs, so they are never cleaned up. Its SG/key-pair filters also
     do not match the names the harness actually creates (pre-existing bug).
   - `run-goss-tests.sh` is hardcoded to rocky9, incompatible with the
     current gossfile include layout, and referenced nowhere.

## Ground truth this design builds on (origin/main, 2026-07-28)

- 6 base targets: cloudberry {rocky9, rocky10}; synxdb-cloud
  {al2023, rocky9, rocky10, ubuntu24}. rocky8 and al2023-synxdb-elastic are
  already retired upstream (git history).
- The harness (`packer-build-and-test.sh`, 683 lines) was security-hardened
  by commit 8ccac08: **private-only builds** (all make-public code removed
  and policy-tested), keys confined to a mode-0700 runtime dir, run-nonce
  resource tagging with client tokens, bounded retrying cleanup,
  `--existing-ami` recovery mode, and two required sibling helpers
  (`private-runtime-key.py`, `validate-ami-metadata.py`).
- A Python test suite (`tests/`, run as `python3 -m unittest discover -s
  tests` in the validate job of both build workflows) guards the harness
  (~30 behavioral tests against fake AWS shims), the templates (security +
  naming-policy tests), and repository policy (private-only docs, retired
  platforms, CI structure). Many of these tests hard-code paths, target
  names, and AMI naming patterns.
- PRs are validation-only in CI; pushes to main build.
- No committed build artifacts; .gitignore already covers *.pem,
  packer-manifest.json, goss-test-results*.xml.
- PR #5 (merging first, before implementation) refreshes the AI toolchain in
  ubuntu24-synxdb-cloud, upgrades its goss checks to real `--version`
  executions, and extends `COMMON_SCRIPT_DEPS` + policy tests around it.

## Decisions (confirmed with user; revisions marked)

- Target repo: cloudberry-image-factory only. The dev-env-launcher is a
  follow-up consumer, not part of this work.
- Three peer families: `cloudberry`, `synxdb-cloud`, `agentic`.
- Agentic images are **dedicated AI-tooling images**. The base families stop
  installing AI tooling.
- Agentic builds **chain from family AMIs** (Packer source = latest tested
  family AMI) as the standard pattern. Exception approved for the first
  target: `agentic/build/ubuntu26` builds standalone from the stock Ubuntu
  26.04 AMI because no ubuntu26 base target exists.
- Initial agentic target: **ubuntu26 only**.
- Compatibility: repo layout, workflow inputs, and AMI name patterns can
  change; dev-env-launcher AMI filters get updated afterward.
- Approach: family layout + shared harness, **per-target `main.pkr.hcl`
  kept** (no HCL templating).
- Provision scripts stay **flat** in `vm-images/common/scripts/` — no
  agentic subdirectory. The "AI tooling ships only in agentic images"
  boundary lives in HCL provisioner lists, tests, and documentation.
- Multi-cloud expandability: GCP and Azure may come later. Cloud-agnostic
  content (provision scripts, goss fragments) is hoisted above the cloud
  level now; `vm-images/gcp/` and `vm-images/azure/` are reserved.
- **REVISED — harness:** the hardened post-build test-instance flow and its
  ~30-test suite are KEPT. goss-as-provisioner (previously adopted) is
  **reverted** — it would have deleted the just-hardened, policy-tested
  flow. The harness is ADAPTED to the new layout, not rewritten. Full
  cloud-neutrality of the harness is **deferred**: it remains AWS-specific;
  a future cloud brings its own harness. What changes now: path-derived
  cloud/family/os identity and family-derived AMI naming.
- **REVISED — publishing:** images are private-only, per upstream policy
  (enforced by tests in code and docs). No publish/make-public capability
  anywhere in this design.
- **REVISED — PASSED/FAILED:** AMI Name-tag suffixing (`-PASSED`/`-FAILED`)
  stays (part of the hardened flow). Chained agentic targets therefore
  select `*-PASSED` source AMIs.

## Section 1: Repository layout

```
vm-images/
├── scripts/
│   ├── packer-build-and-test.sh   # hardened AWS harness (moved, adapted)
│   ├── private-runtime-key.py     # required sibling helper (moved with it)
│   └── validate-ami-metadata.py   # required sibling helper (moved with it)
├── common/
│   ├── scripts/                   # all shared provisioners, flat
│   │                              #   (incl. the AI-tooling set)
│   └── tests/                     # shared goss fragments
├── aws/
│   ├── cloudberry/
│   │   └── build/{rocky9,rocky10}/                 # main.pkr.hcl, scripts/, tests/
│   ├── synxdb-cloud/
│   │   └── build/{al2023,rocky9,rocky10,ubuntu24}/ # '-synxdb-cloud' suffix dropped
│   └── agentic/
│       └── build/
│           └── ubuntu26/          # first target; standalone from stock Ubuntu 26.04
├── gcp/                           # future (own harness when it arrives)
└── azure/                         # future
```

Placement rule: a script or goss fragment goes under `vm-images/common/`
if it would run unchanged on another cloud's image; cloud-specific logic
stays in the (currently AWS-only) harness under `vm-images/scripts/` or
under `vm-images/<cloud>/`.

- Per-target HCL provisioner refs change from `../common/scripts/` to
  `../../../../common/scripts/` (target → build → family → aws → vm-images).
- The three harness files move TOGETHER (the script hard-fails if its
  helpers are not siblings).
- On-instance goss layout (`~/<os>/tests` + `~/common/tests`) is unchanged;
  `tests/goss.yaml` include lines are untouched.

## Section 2: Build harness (adapt, do not rewrite)

`packer-build-and-test.sh` + its two Python helpers move to
`vm-images/scripts/`. The hardened behavior (private runtime key handling,
run-nonce tagging, bounded cleanup, `--existing-ami` mode, private-only,
test-instance goss flow, PASSED/FAILED tagging) is preserved. Changes are
limited to identity and paths:

1. Identity derived from the directory structure:
   `cwd = vm-images/<cloud>/<family>/build/<os>` yields CLOUD, FAMILY,
   OS_NAME. Errors out if the CWD does not match that shape, if
   `main.pkr.hcl` is missing, or if CLOUD is not `aws` (clear message that
   only an AWS harness exists today).
2. AMI naming: the hand-coded prefix case statement
   (`synx-cloud-packer-` / `synxdb-cloud-packer-` / `cloudberry-packer-`)
   is replaced by `<family>-packer-<os>-<timestamp>`. This drops the
   accidental `build` segment and the special `synx-cloud-` prefix for
   al2023 (becomes `synxdb-cloud-packer-al2023-*`). PASSED/FAILED Name-tag
   suffixing stays on top of this base name.
3. `common/tests` located via the script's own location
   (`vm-images/scripts/../common/tests`) instead of `${CURRENT_DIR}/../
   common/tests`.
4. Everything else — required commands, region fixed to us-west-2, expected
   AMI owner, key-pair/SG/instance lifecycle, cleanup semantics, flags —
   unchanged.
5. `run-goss-tests.sh` deleted.
6. The Python test suites are updated in lockstep (Section 4a).

## Section 3: Agentic family

1. Standard pattern: an agentic target's `source_ami_filter` selects the
   latest `*-PASSED` AMI of its base target, with `base_family`/`base_os`
   recorded as HCL vars. The build fails clearly if the filter matches
   nothing.
2. First target `ubuntu26` is the approved exception: builds from the stock
   canonical Ubuntu 26.04 AMI (filter discovered from AWS at implementation
   time, never guessed) and composes shared provisioners + the AI tooling
   itself. Content is ported from ubuntu24-synxdb-cloud **after PR #5
   merges**, inheriting its refreshed toolchain and version-check goss
   assertions.
3. The AI-tooling scripts stay flat in `vm-images/common/scripts/`; after
   the split, only agentic HCLs may reference them — enforced by a policy
   test (Section 4a), review, and documentation.
4. Base families stop installing AI tooling: those provisioner lines are
   removed from base-family HCLs; their goss AI-tool assertions move to the
   agentic target's tests.
5. AMI naming: `agentic-packer-ubuntu26-<timestamp>` (falls out of
   Section 2).

## Section 4: CI workflows

`ami-build-on-change.yml`
- `paths` filter: `vm-images/**` plus `tests/**` and
  `.github/**` (doc-only changes stay excluded). DEFERRED (v2.1): the
  filters are present but changes under `tests/`/`.github/` alone still
  yield an empty matrix, so the validate/unittest lane does not run for
  them — an always-run validation lane is a filed follow-up, not part of
  this branch.
- Matrix computed dynamically (replaces `COMMON_SCRIPT_DEPS`):
  - change in `<cloud>/<family>/build/<target>/**` → that target;
  - change in `vm-images/common/scripts/X.sh` → targets whose
    `main.pkr.hcl` references `X.sh` (computed by grep, not a map);
  - change in `vm-images/scripts/**` or `vm-images/common/tests/**` → all
    targets.
- Preserved invariants (policy-tested): PRs remain validation-only
  (build/cleanup jobs and their credential steps gated on
  `github.event_name != 'pull_request'`); PR change detection keeps using
  `github.event.pull_request.{base,head}.sha` with `fetch-depth: 0`;
  offline unittest step runs before any build step; `AWS_REGION: us-west-2`
  fixed in every workflow.
- Every family becomes CI-buildable.

`ami-build-manual.yml`
- `build_targets`: free-form `<family>/<os>` list or `all`; matrix
  discovered from the directory tree. `max-parallel: 2` kept. No region or
  publish inputs (upstream already removed them).

`ami-cleanup-old.yml`
- Cleans per family: `<family>-packer-*` for each family dir found in the
  tree (fixes synxdb AMIs never being cleaned up).
- The leftover SG/key-pair cleanup filters in the build workflows are fixed
  to match the names the harness actually creates (pre-existing mismatch).

Agentic in CI: builds on changes under `agentic/**` and via manual
dispatch. No automatic rebuild-when-base-AMI-updates trigger in this pass.

## Section 4a: Python test suites (first-class migration surface)

`tests/` is updated in lockstep with every structural change:

- `test_packer_build_security.py`: the synthetic-tree fixture and `_metadata`
  fixture encode the old two-level layout, `VM_TYPE=build`, and old AMI
  names — updated to the new `<cloud>/<family>/build/<os>` shape and
  `<family>-packer-<os>` naming. The 30 behavioral tests otherwise keep
  their assertions (the behavior they test is preserved).
- `test_packer_template_security.py`: `BUILD_ROOT` glob widens to
  `vm-images/aws/*/build/*/main.pkr.hcl`; the AMI-prefix policy table
  becomes the single `<family>-packer-` rule derived from the directory
  name.
- `test_repository_policy.py`: every hard-coded path (harness invocation
  depth, surface lists, per-target goss paths) is updated; tests asserting
  the `COMMON_SCRIPT_DEPS` structure are rewritten to assert the dynamic
  matrix mechanism instead; `test_rocky10_claude_launcher_is_symlink` and
  any other base-family AI assertions are removed/moved with Task "strip AI
  tooling"; a NEW policy test enforces the agentic boundary (no base-family
  HCL references an AI-tooling script).
- The suite must pass (`python3 -m unittest discover -s tests`) at the end
  of every implementation task that touches its subjects.

## Section 5: Hygiene and documentation

Repo hygiene
- Delete `run-goss-tests.sh` (verified functionally unreferenced).
- (Artifacts/elastic/rocky8: already handled upstream — nothing to do.)

Documentation (all under the policy tests' wording constraints: no
"make public" phrasing; retired-platform mentions only with
retired/archived/recoverable/history context)
- `CLAUDE.md`: new layout, platform table, harness path, correct script
  count, provisioner-order checklist kept, "new family" / "new target"
  checklists added.
- `README.md`: new tree, invocation examples
  (`../../../../scripts/packer-build-and-test.sh`), new AMI naming.
- `ROADMAP.md`: path updates (`smoke-test.sh` → `vm-images/scripts/`).
- `.github/workflows/README.md`: dynamic matrix description, `family/os`
  dispatch format.
- `vm-images/common/tests/README.md`: path updates; also fix the stale
  archived-platform list already present.
- Per-target CLAUDE.md files updated; new one for `agentic/build/ubuntu26`.

## Out of scope / follow-ups

- dev-env-launcher `config/os-config-*.yaml` AMI filters → new
  `<family>-packer-<os>-*` naming, once first new AMIs exist.
- `smoke-test.sh` (ROADMAP item).
- Automatic agentic rebuild when a base AMI updates.
- HCL templating (rejected).
- Harness cloud-neutrality (deferred; revisit when a second cloud is real).
- goss-as-provisioner (reverted; revisit only with a plan that preserves
  the hardened flow's guarantees).

## Error handling

- Harness: hard error on wrong CWD shape, missing `main.pkr.hcl`, non-aws
  cloud segment, or missing sibling helpers (existing check).
- Chained agentic targets: build fails clearly when the base-AMI filter
  matches nothing.
- CI: `fail-fast: false` retained; goss failure on the test instance tags
  the AMI `-FAILED` and fails the job (unchanged hardened behavior).

## Testing

- `python3 -m unittest discover -s tests` green after every task.
- Live builds (operator-gated): one target per family (cloudberry/rocky9,
  synxdb-cloud/rocky10, agentic/ubuntu26); confirm AMI names, PASSED
  tagging, goss results retrieved; confirm the synxdb-cloud image contains
  no AI tooling.
- Matrix logic tested locally against synthetic changed-file lists before
  wiring into the workflow.

## Revision history

- v1 (2026-07-28): initial approved design (included goss-as-provisioner,
  cloud-neutral harness rewrite, publish toggle).
- v2 (2026-07-28): re-baselined against origin/main d8908be after
  discovering 8 upstream commits (hardened private-only harness + Python
  test suites, rocky8/elastic retirements) and open PR #5. Reverted
  goss-as-provisioner; harness is adapted not rewritten; private-only
  everywhere; PASSED/FAILED tagging retained; test-suite migration added
  as a first-class section; target inventory corrected to 6.
