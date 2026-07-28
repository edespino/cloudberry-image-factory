# Design: Family-Aware Restructure + Agentic Image Family

Date: 2026-07-28
Repo: cloudberry-image-factory
Status: Approved design, pending implementation plan

## Problem

1. `vm-images/aws/cloudberry/` mixes two product families: plain Cloudberry
   build targets (rocky8/9/10) and SynxDB Cloud targets (`*-synxdb-cloud`).
2. The build/test harness (`scripts/packer-build-and-test.sh`,
   `run-goss-tests.sh`) lives inside the `cloudberry` tree and cannot be
   shared cleanly by a new peer family.
3. A new **agentic** family is being introduced: dedicated images carrying
   the AI/agent tooling that today is baked into the synxdb-cloud images
   via ~9 common provision scripts.
4. Accumulated maintainability problems:
   - `vm_type` in the harness resolves to the literal string `build`
     (`basename $(dirname $CWD)`), which is why AMIs are named
     `cloudberry-packer-build-*`.
   - CI can only build rocky8/9/10; no synxdb-cloud target is buildable or
     auto-triggered. The on-change workflow's hand-maintained dependency map
     covers 19 of 58 common scripts.
   - The cleanup workflow's `cloudberry-packer-build-*` filter never matches
     synxdb AMIs, so they are never cleaned up.
   - `run-goss-tests.sh` is hardcoded to rocky9, incompatible with the
     current gossfile include layout, and referenced nowhere.
   - Build artifacts are committed: 8x `packer-manifest.json`,
     17x `goss-test-results-*.xml`.
   - Stale docs (CLAUDE.md claims "21 scripts"; actual: 58).

## Decisions (confirmed with user)

- Target repo: cloudberry-image-factory only. The dev-env-launcher is a
  follow-up consumer, not part of this work.
- Three peer families: `cloudberry`, `synxdb-cloud`, `agentic`.
- Agentic images are **dedicated AI-tooling images**. The base families stop
  installing AI tooling.
- Agentic builds **chain from family AMIs** (Packer source = latest PASSED
  family AMI) as the standard pattern. Exception approved for the first
  target: `agentic/build/ubuntu26` builds standalone from the stock Ubuntu
  26.04 AMI because no ubuntu26 base target exists.
- Initial agentic target: **ubuntu26 only**. No rocky agentic target now.
- `al2023-synxdb-elastic` is **archived** (deleted from the tree; git
  history retains it).
- Compatibility: everything can change, including AMI name patterns and
  workflow inputs. dev-env-launcher AMI filters get updated afterward.
- Approach chosen: family layout + shared harness, **per-target
  `main.pkr.hcl` kept** (no HCL templating).
- Multi-cloud expandability: GCP and Azure images may be introduced later.
  Cloud-agnostic content (provision scripts, goss fragments, build
  harness) is hoisted above the cloud level in this pass; cloud-specific
  content (Packer HCL, families' build dirs, cloud API steps) stays under
  `vm-images/<cloud>/` or in per-cloud harness libraries.
- Provision scripts stay **flat** in `vm-images/common/scripts/` — no
  agentic subdirectory. The "AI tooling ships only in agentic images"
  boundary lives in the HCL provisioner lists and documentation, not the
  tree.
- The build harness is **cloud-independent**: it infers cloud, family,
  and OS from the directory structure it is run in.
- **Goss runs as a Packer provisioner** during the build (the
  kubernetes-sigs/image-builder pattern), replacing the separate
  test-instance launch/SSH/SCP flow. A goss failure aborts the build, so
  every published image is a passing image.

## Section 1: Repository layout

```
vm-images/
├── scripts/
│   ├── packer-build-and-test.sh   # cloud-neutral orchestrator (moved from
│   │                              #   aws/cloudberry/scripts/)
│   └── lib/
│       └── aws.sh                 # AWS-specific steps (keypair, SG, EC2,
│                                  #   AMI tagging); gcp.sh/azure.sh later
├── common/
│   ├── scripts/                   # all ~58 shared provisioners, flat
│   │                              #   (incl. the 9 AI-tooling scripts)
│   └── tests/                     # shared goss fragments
├── aws/
│   ├── cloudberry/
│   │   └── build/{rocky8,rocky9,rocky10}/          # main.pkr.hcl, scripts/, tests/
│   ├── synxdb-cloud/
│   │   └── build/{al2023,rocky9,rocky10,ubuntu24}/ # '-synxdb-cloud' suffix dropped
│   └── agentic/
│       └── build/
│           └── ubuntu26/          # first target; standalone from stock Ubuntu 26.04
├── gcp/                           # future: family dirs + scripts/lib/gcp.sh
└── azure/                         # future
```

Placement rule: a script or goss fragment goes under `vm-images/common/`
if it would run unchanged on another cloud's image; anything invoking
cloud APIs or cloud-specific metadata belongs in a harness library
(`vm-images/scripts/lib/<cloud>.sh`) or under `vm-images/<cloud>/`.

- Per-target HCL provisioner refs change from `../common/scripts/` to
  `../../../../common/scripts/` (target → build → family → aws → vm-images).
- Agentic HCLs reference the AI-tooling set the same way as any other
  common script: `../../../../common/scripts/<name>.sh`.
- On-instance goss layout (`~/<os>/tests` + `~/common/tests`) is unchanged,
  so `tests/goss.yaml` include lines are untouched.
- Dead files deleted during the move: the unreferenced
  `system_add_cbdb_build_rpm_dependencies.sh` copies in the two al2023
  synxdb dirs.

## Section 2: Build harness

`packer-build-and-test.sh` moves to `vm-images/scripts/` and becomes
cloud-neutral:

1. Stays CWD-driven; run from inside a build target dir. No new required
   flags.
2. Config inferred from the directory structure:
   `cwd = vm-images/<cloud>/<family>/build/<os>` yields `cloud=<cloud>`,
   `family=<family>`, `os=<os>`. Errors out if the CWD does not match that
   shape or `main.pkr.hcl` is missing.
3. **Goss testing moves inside the Packer build**: the final provisioning
   steps upload the target's `tests/` and `common/tests/` (preserving the
   `~/<os>/tests` + `~/common/tests` layout so `goss.yaml` includes are
   untouched), run goss, and download the junit results to the target dir.
   A goss failure fails `packer build` — no image is produced. This
   removes the harness's test-instance launch, SSH-wait, SCP, and
   PASSED/FAILED renaming logic entirely.
4. Remaining cloud-specific steps (credential checks, image
   tagging/publishing, make-public toggle) live in
   `vm-images/scripts/lib/<cloud>.sh`, sourced by the orchestrator based
   on the inferred cloud. Only `aws.sh` is implemented in this pass; an
   unknown cloud is a hard error naming the missing library.
5. Image naming: `<family>-packer-<os>-<timestamp>` (drops the accidental
   `build` segment); applies uniformly across clouds. No `-PASSED`
   suffix — a published image implies tests passed.
6. `common/tests` located relative to the script's own location
   (`vm-images/scripts/../common/tests`), not guessed from CWD.
7. The SSH-user case block is no longer needed for testing (Packer owns
   the connection); kept only if other steps require it.
8. `run-goss-tests.sh` deleted.
9. ROADMAP's planned `smoke-test.sh` will live in this shared `scripts/`
   dir when built (not part of this work).

## Section 3: Agentic family

1. Standard pattern: an agentic target's `source_ami_filter` selects the
   latest AMI of its base target (all published AMIs are passing, per the
   goss-as-provisioner model), with `base_family`/`base_os` recorded as
   HCL vars in the target's `main.pkr.hcl`. The harness fails with a
   clear error if the source filter matches nothing.
2. First target `ubuntu26` is the approved exception: builds from the stock
   canonical Ubuntu 26.04 AMI and composes shared provisioners + the AI
   tooling itself.
3. The ~9 AI-tooling scripts stay flat in `vm-images/common/scripts/`
   alongside the rest (cloud-agnostic; reusable by a future gcp/azure
   agentic family). After the split, only agentic HCLs may reference them
   — enforced by review and documentation.
4. Base families stop installing AI tooling: those provisioner lines are
   removed from the synxdb-cloud HCLs (rocky10 and ubuntu24 use them
   today); their goss AI-tool assertions move to agentic tests.
5. AMI naming: `agentic-packer-<os>-<timestamp>` (falls out of Section 2).
6. Agentic goss: own `tests/goss.yaml` with AI-tooling assertions plus
   common fragment includes; base-image functionality is not re-asserted.

## Section 4: CI workflows

`ami-build-on-change.yml`
- `paths` filter: `vm-images/**` (common/ changes must trigger AWS builds).
- Matrix computed dynamically:
  - change in `<cloud>/<family>/build/<target>/**` → that target;
  - change in `common/scripts/**/X.sh` → grep all `main.pkr.hcl` files for
    `X.sh` → affected targets (replaces the hand-maintained dep map);
  - change in `scripts/lib/<cloud>.sh` → all of that cloud's targets;
  - change in the orchestrator or `common/tests/` → all targets.
- Every family becomes CI-buildable.

`ami-build-manual.yml`
- `build_targets`: free-form `<family>/<target>` list or `all`; matrix
  discovered from the directory tree.
- Validate step no longer overrides `vm_type`.
- `max-parallel: 2` kept.

`ami-cleanup-old.yml`
- Cleans per family: `<family>-packer-*` for each family dir found in the
  tree.

Agentic in CI: builds on changes under `agentic/**` and via manual
dispatch. No automatic rebuild-when-base-AMI-updates trigger in this pass.

## Section 5: Hygiene and documentation

Repo hygiene
- Delete committed artifacts (8x `packer-manifest.json`,
  17x `goss-test-results-*.xml`); gitignore those patterns and `*.pem`.
- Delete `al2023-synxdb-elastic`, dead script copies, `run-goss-tests.sh`.

Documentation
- `CLAUDE.md`: new layout, fix stale "21 scripts", keep provisioner-order
  checklist, add "new family" and "new target" checklists.
- `README.md`: new tree and invocation examples
  (`../../../scripts/packer-build-and-test.sh`).
- `ROADMAP.md`: path updates (`smoke-test.sh` → shared `scripts/`).
- `.github/workflows/README.md`: updated.
- Per-target CLAUDE.md files (synxdb-cloud rocky9/rocky10/ubuntu24): paths
  updated; AI-tooling references move to agentic docs.

## Out of scope / follow-ups

- GCP and Azure image families: the layout reserves `vm-images/gcp/` and
  `vm-images/azure/`; each future cloud adds a harness library
  (`vm-images/scripts/lib/<cloud>.sh`) and its family dirs. No GCP/Azure
  content is built in this pass.

- dev-env-launcher `config/os-config-*.yaml` AMI filters updated to the new
  `<family>-packer-<os>-*` naming once the first new AMIs are published.
- `smoke-test.sh` (ROADMAP item).
- Automatic agentic rebuild when a base AMI updates.
- HCL templating (Approach B — explicitly rejected for readability).

## Error handling

- Harness: hard error when CWD shape is wrong, `main.pkr.hcl` missing, or
  (chained targets) the base-AMI filter matches nothing.
- CI: `fail-fast: false` retained so one target's failure doesn't cancel
  siblings; a goss failure aborts the Packer build (no image produced) and
  fails the job.

## Testing

- Harness: run a full build (goss inside) for one target per family
  (cloudberry/rocky9, synxdb-cloud/rocky10, agentic/ubuntu26) after the
  restructure; confirm AMI names, downloaded junit results, and that an
  intentionally failing goss assertion aborts the build with no AMI.
- Workflows: exercise `workflow_dispatch` for a single `<family>/<target>`;
  verify the dynamic on-change matrix with a doc-only change (no builds),
  a single-target change (one build), and a common-script change (grep-
  derived set).
- Cleanup: dry-run mode against each family's pattern before enabling.
