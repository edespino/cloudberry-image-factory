# Cloudberry Image Factory - Improvement Roadmap

This document tracks potential improvements and enhancements for the Cloudberry Image Factory project, organized by priority and impact.

**Last Updated:** October 9, 2025

---

## Completed Improvements

### Phase 1: Foundation & Core Workflows ✅

- [x] **Enable AMI cleanup workflow** - Count-based retention policy
  - Count-based retention (keep N newest per OS configuration)
  - Automatic FAILED AMI cleanup
  - Enhanced output showing both KEEP and DELETE decisions
  - Fixed critical DRY_RUN defaulting bug
  - Fixed counter reporting with process substitution
  - Snapshot cleanup integration

- [x] **Documentation maintainability improvements**
  - Removed hardcoded version numbers (Go, CMake, libraries)
  - Added AL2023 to all relevant sections
  - Replaced detailed matrices with conceptual organization
  - Added version management best practices
  - Documented UTC timezone behavior and AMI naming convention

- [x] **Architecture diagrams**
  - System overview diagram
  - Build pipeline flow diagram
  - CI/CD workflow decision tree
  - Monthly AMI cleanup flow diagram

---

## High Priority (Should Do Next)

### 1. Complete Troubleshooting Guide ⭐⭐⭐⭐⭐

**Status:** Partially complete
**Effort:** 1-2 hours
**Impact:** High (reduces support burden, enables self-service debugging)

**Current State:** Basic troubleshooting exists but needs expansion

**Add Sections For:**
- **AMI cleanup issues**
  - Permission errors (missing ec2:DeregisterImage, ec2:DeleteSnapshot)
  - Stuck deletions (in-use AMIs, snapshot dependencies)
  - Orphaned snapshot handling

- **Build timeout handling**
  - What to do when builds exceed 60-90 minutes
  - How to extend timeouts for specific OS targets
  - Identifying slow provisioning scripts

- **Network connectivity failures**
  - Download timeouts for large packages
  - Package manager repository issues
  - GitHub API rate limiting
  - Checksum verification failures

- **Goss test debugging**
  - How to iterate on failing tests locally
  - Common test failure patterns
  - Test expectation mismatches by OS version

- **SSH connection problems**
  - Key pair issues and permissions
  - Security group misconfiguration
  - Network ACL blocking
  - Instance not ready (timing issues)

- **Packer plugin issues**
  - Init failures and version conflicts
  - Plugin download errors
  - HCL syntax validation errors

- **Common error messages with solutions**
  - Real examples from build logs
  - Step-by-step resolution procedures
  - Links to relevant documentation

**Deliverables:**
- Expanded Troubleshooting section in README.md
- Or separate TROUBLESHOOTING.md file
- Quick reference table of error patterns

---

### 2. Add Cost Estimation Documentation ⭐⭐⭐⭐⭐

**Status:** Not started
**Effort:** 30 minutes
**Impact:** High (transparency, budgeting, decision-making)

**Why:** Users need to understand costs before running builds

**Add Section With:**

**Per-Build Costs:**
```
Single OS Build (e.g., Rocky 9):
├─ t3.2xlarge build instance (60 min avg): $0.33/hour = $0.33
├─ t3.medium test instance (10 min avg): $0.04/hour = ~$0.01
├─ EBS volume during build (24GB): Negligible
├─ Data transfer (minimal): Negligible
└─ Total per build: ~$0.34

AMI Storage Costs (per month):
├─ EBS snapshot (24GB): $0.05/GB-month = $1.20/month
└─ Per AMI per month: $1.20
```

**Monthly Costs with Retention Policy:**
```
Configuration: retention_count=3, 6 OS targets

Maximum AMIs: 3 × 6 = 18 AMIs
Monthly storage: 18 × $1.20 = $21.60/month

Weekly builds (4 builds/month/OS):
├─ Build costs: 6 OS × 4 builds × $0.34 = $8.16/month
├─ Storage costs: $21.60/month (capped by retention)
└─ Total monthly: ~$30/month

Without cleanup (unlimited accumulation):
└─ After 6 months: 6 OS × 24 builds × $1.20 = $172.80/month (!)
```

**Cost Optimization Tips:**
- Schedule builds during off-peak hours (same cost, but better for rate limits)
- Use retention_count=2 for development (saves 33% storage)
- Delete old FAILED AMIs immediately (automatic now)
- Parallel build limits prevent runaway costs (max 3 concurrent)
- Smart rebuilds save ~70% of unnecessary builds

**AWS Cost Allocation Tags:**
```
Project: cloudberry-image-factory
Environment: development
CostCenter: engineering
ManagedBy: packer
AutoCleanup: true
```

**Cost Monitoring Commands:**
```bash
# View AMI storage costs
aws ec2 describe-snapshots --owner-ids self \
  --filters "Name=description,Values=*cloudberry-packer-build-*" \
  --query 'Snapshots[*].[SnapshotId,VolumeSize,StartTime]' \
  --output table

# Count current AMIs per configuration
aws ec2 describe-images --owners self \
  --filters "Name=name,Values=cloudberry-packer-build-*" \
  --query 'Images[*].Name' --output text | \
  sed 's/.*-build-\([^-]*\)-.*/\1/' | sort | uniq -c
```

**Deliverables:**
- New "Cost Management" section in README.md
- Cost calculator examples
- Monitoring commands

---

### 3. Version Pinning for Critical Tools ⭐⭐⭐⭐

**Status:** Not started (Priority 1, Item 4)
**Effort:** 1 hour
**Impact:** Medium-High (prevents unexpected breaks)

**Why:** "Latest" versions can break builds unexpectedly

**Pin These Versions:**

**Go Language** (currently dynamic in `system_add_golang.sh`):
```bash
# Current: Fetches latest from golang.org
# Change to:
GO_VERSION="1.23.1"  # Pin to tested version
GO_SHA256="..."      # Pin checksum
```

**Goss Testing Framework** (currently latest in `system_add_goss.sh`):
```bash
# Current: Fetches latest from GitHub releases
# Change to:
GOSS_VERSION="0.4.8"
GOSS_SHA256="..."
```

**Just Command Runner** (currently latest in `cbadmin_configure_environment.sh`):
```bash
# Current: Fetches latest from GitHub releases
# Change to:
JUST_VERSION="1.34.0"
JUST_SHA256="..."
```

**CMake** (currently package manager default):
```bash
# Consider pinning major version:
# Rocky: cmake-3.26.x
# Ubuntu: cmake-3.25.x
# Or use binary download with pinned version
```

**Implementation Steps:**
1. Test current "latest" versions
2. Document working versions
3. Update scripts with pinned versions
4. Add version variables at top of each script
5. Update Goss tests to verify specific versions
6. Document version upgrade process

**Add Version Upgrade Process:**
```markdown
## Upgrading Pinned Versions

1. Test new version locally:
   - Update version variable in script
   - Run build manually
   - Verify Goss tests pass

2. Update checksum:
   - Download new binary
   - Calculate SHA256: sha256sum binary-name
   - Update checksum in script

3. Update Goss tests:
   - Adjust version expectations if needed
   - Test validation passes

4. Commit and test in CI:
   - Create PR with version bump
   - Review automated build results
   - Merge if successful

5. Document in CHANGELOG.md
```

**Trade-offs:**
- **Pro:** Reproducible builds, no surprise breakage
- **Con:** Manual version updates required
- **Con:** May miss security updates in dependencies

**Deliverables:**
- Updated scripts with pinned versions
- Version upgrade documentation
- CHANGELOG entry for version changes

---

### 4. Health Check / Smoke Test Script ⭐⭐⭐⭐

**Status:** Not started
**Effort:** 2-3 hours
**Impact:** Medium-High (quick validation, confidence in AMIs)

**Why:** Quick validation that AMIs work correctly after launch

**Create:** `vm-images/aws/cloudberry/scripts/smoke-test.sh`

**Functionality:**
```bash
#!/bin/bash
# Quick smoke test for Cloudberry AMIs
# Usage: ./smoke-test.sh <ami-id> [region]

# 1. Launch instance from AMI
#    - Use t3.medium (cost-effective)
#    - Temporary security group (SSH only)
#    - Auto-assigned public IP

# 2. Wait for instance ready (max 5 minutes)

# 3. Run basic checks via SSH:
#    - SSH connectivity (cbadmin user)
#    - Docker running and accessible
#    - Go version available
#    - Disk space adequate (>5GB free)
#    - User permissions correct (sudo works)
#    - Development tools present (gcc, make, git)
#    - cbdb build dependencies installed

# 4. Optional: Run minimal Cloudberry build test
#    - Clone cloudberry repo
#    - Run configure
#    - Compile single module
#    - Verify build environment works

# 5. Report results:
#    - ✅ PASS: All checks successful
#    - ❌ FAIL: List failed checks
#    - 🟡 WARN: List warnings (non-critical)

# 6. Cleanup:
#    - Terminate instance
#    - Delete security group
#    - Delete key pair

# Exit codes:
#   0 = All checks passed
#   1 = One or more checks failed
#   2 = Unable to launch/connect
```

**Use Cases:**
- Post-build manual validation
- Pre-deployment checks before production use
- Regression testing after infrastructure changes
- Quick AMI verification without full Goss suite

**Integration Points:**
- Could be called from GitHub Actions workflow (optional)
- Could replace or supplement Goss testing
- Useful for manual AMI verification

**Deliverables:**
- New smoke-test.sh script
- Documentation in README
- Example usage in workflows

---

## Medium Priority (Nice to Have)

### 5. Multi-Region AMI Copying ⭐⭐⭐

**Status:** Not started
**Effort:** 3-4 hours
**Impact:** Medium (disaster recovery, global availability)

**Why:** Disaster recovery, reduce cross-region launch latency

**Implementation:**

**New Workflow:** `.github/workflows/ami-copy-regions.yml`
```yaml
# Triggered after successful AMI build
# Or manual/scheduled

# For each successful AMI:
#   1. Copy to secondary regions:
#      - us-east-1 (primary backup)
#      - us-west-1 (secondary backup)
#      - Optional: eu-west-1, ap-southeast-1
#
#   2. Maintain tags and naming
#      - Add tag: SourceRegion=us-west-2
#      - Add tag: CopiedDate={timestamp}
#
#   3. Apply same retention policy
#      - Keep N newest in each region
#      - Or: Keep fewer in backup regions (cost savings)
#
#   4. Cleanup old copied AMIs
#      - Same count-based retention
#      - Or: Different retention (e.g., keep 1 in backup)
```

**Configuration:**
```yaml
backup_regions:
  - us-east-1
  - us-west-1
retention_in_backup: 1  # Keep only 1 newest in backup regions
```

**Benefits:**
- Disaster recovery if us-west-2 fails
- Faster instance launches in other regions
- Geographic distribution options

**Costs:**
- Snapshot storage in multiple regions
- Data transfer costs for copying (~$0.02/GB)
- With retention=1: Minimal ongoing cost

**Deliverables:**
- New ami-copy-regions.yml workflow
- Documentation on multi-region strategy
- Cost implications documented

---

### 6. Build Performance Metrics ⭐⭐⭐

**Status:** Not started
**Effort:** 2-3 hours
**Impact:** Medium (identify bottlenecks, track trends)

**Why:** Track build times, identify slow builds, optimization opportunities

**Implementation:**

**Add to Workflows:**
```yaml
# Capture timing information:
- Start time: $(date +%s)
- Packer build duration
- Goss test duration
- Total pipeline duration
- End time: $(date +%s)

# Store metrics:
- GitHub Actions artifacts (JSON)
- Or: Push to metrics service (CloudWatch, Datadog)
- Or: Append to metrics file in repo

# Generate reports:
- Weekly summary of build times
- Trend analysis (getting faster/slower?)
- Identify outliers (unusually slow builds)
```

**Metrics to Track:**
```json
{
  "build_id": "rocky9-20251002-120000",
  "os": "rocky9",
  "date": "2025-10-02T12:00:00Z",
  "duration_seconds": 3600,
  "phases": {
    "packer_validate": 5,
    "packer_build": 2700,
    "instance_launch": 120,
    "goss_tests": 180,
    "cleanup": 30
  },
  "instance_type": "t3.2xlarge",
  "result": "success"
}
```

**Visualization:**
```
Rocky9 Build Times (Last 30 Days)
60 min |     *
55 min |   *   *
50 min | *       *  *
45 min |*             *
       +------------------
        Oct 1  Oct 15  Oct 30

Average: 48 minutes
Trend: Stable
Outlier: Oct 15 (62 min) ← Investigate
```

**Benefits:**
- Identify performance regressions
- Justify infrastructure investments
- Optimize slow provisioning scripts
- Set realistic timeout expectations

**Deliverables:**
- Metrics collection in workflows
- Storage strategy (artifacts vs. service)
- Optional: Visualization dashboard

---

### 7. AMI Tagging Strategy ⭐⭐⭐

**Status:** Partially implemented
**Effort:** 1-2 hours
**Impact:** Medium (organization, cost tracking, lifecycle)

**Why:** Better organization, cost tracking, automated lifecycle management

**Current State:** Basic tags exist (Name, managed by Packer)

**Enhanced Tagging:**
```yaml
# Add to Packer templates (main.pkr.hcl):
tags = {
  Name                = "cloudberry-packer-build-{os}-{timestamp}"
  Project             = "cloudberry-database"
  Environment         = "development"
  ManagedBy           = "packer"
  OS                  = var.os_name
  BuildDate           = timestamp()
  GitCommit           = env("GITHUB_SHA")      # From CI
  GitBranch           = env("GITHUB_REF_NAME") # From CI
  CostCenter          = "engineering"
  Team                = "cloudberry-team"
  AutoCleanup         = "true"
  RetentionDays       = "managed-by-workflow"
  BuildWorkflow       = env("GITHUB_WORKFLOW") # Which workflow built it
  TestStatus          = "pending"              # Updated after tests
}
```

**Update Tags After Testing:**
```bash
# In packer-build-and-test.sh after Goss tests:
aws ec2 create-tags --resources $AMI_ID --tags \
  Key=TestStatus,Value=passed \
  Key=TestDate,Value=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
  Key=GossVersion,Value=$(goss --version)
```

**Benefits:**
- **AWS Cost Explorer:** Filter by Project, CostCenter, Environment
- **Resource Groups:** Organize AMIs by tag combinations
- **Lifecycle Policies:** Auto-delete based on tags (alternative to our workflow)
- **Audit Trail:** Track which commit/branch created each AMI
- **Compliance:** Meet organizational tagging requirements

**Cost Allocation Example:**
```
AWS Cost Explorer > Group By: Tag: Project
└─ cloudberry-database: $30.45/month
   ├─ AMI Storage: $21.60
   ├─ Build Instances: $8.16
   └─ Test Instances: $0.69
```

**Deliverables:**
- Updated Packer templates with comprehensive tags
- Tag updates in build scripts
- Documentation on tagging strategy

---

### 8. Notification System ⭐⭐⭐

**Status:** Not started
**Effort:** 2-3 hours
**Impact:** Medium (awareness, faster response to issues)

**Why:** Alert on build failures, cleanup actions, important events

**Implementation Options:**

**Option A: Slack/Discord Integration**
```yaml
# Add to GitHub Actions workflows
- name: Notify on failure
  if: failure()
  uses: slackapi/slack-github-action@v1
  with:
    webhook-url: ${{ secrets.SLACK_WEBHOOK }}
    payload: |
      {
        "text": "❌ AMI Build Failed: rocky9",
        "blocks": [
          {
            "type": "section",
            "text": {
              "type": "mrkdwn",
              "text": "*Build Failed*\n• OS: rocky9\n• Workflow: ${{ github.workflow }}\n• Run: ${{ github.run_id }}"
            }
          }
        ]
      }
```

**Option B: Email Notifications**
```yaml
# Use GitHub Actions email action
- name: Send failure email
  if: failure()
  uses: dawidd6/action-send-mail@v3
  with:
    server_address: smtp.gmail.com
    subject: "[CI] AMI Build Failed: ${{ matrix.os }}"
    body: |
      Build failed for ${{ matrix.os }}

      Workflow: ${{ github.workflow }}
      Run: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
```

**Option C: AWS SNS**
```bash
# Publish to SNS topic
aws sns publish \
  --topic-arn arn:aws:sns:us-west-2:xxx:cloudberry-builds \
  --subject "AMI Build Status" \
  --message "Build completed for rocky9: SUCCESS"
```

**Notification Events:**
- ❌ Build failures (always notify)
- ❌ Test failures (always notify)
- ✅ All builds successful (optional, can be noisy)
- 🔄 Monthly cleanup dry-run results (digest format)
- ⚠️  Accumulating FAILED AMIs (> 5 failed AMIs)
- 📊 Weekly build summary (optional)

**Digest Format (Monthly Cleanup):**
```
📧 Monthly AMI Cleanup Report - October 2025

Dry-Run Results (No AMIs deleted):
• Total AMIs Found: 24
• FAILED AMIs: 3 (will be deleted)
• Old AMIs: 6 (will be deleted)
• Retained AMIs: 15 (3 per OS)

Action Required:
To execute cleanup, run: gh workflow run ami-cleanup-old.yml -f dry_run=false

Full report: [GitHub Actions Link]
```

**Benefits:**
- Faster response to build failures
- Awareness of system health
- Monthly cleanup visibility
- Reduced need to check GitHub Actions manually

**Deliverables:**
- Notification integration in workflows
- Configuration for notification channels
- Documentation on notification settings

---

## Lower Priority (Future Enhancements)

### 9. Build Caching / Incremental Builds ⭐⭐

**Status:** Not started
**Effort:** 5-8 hours (complex)
**Impact:** Medium (faster builds, but complexity tradeoff)

**Why:** Speed up builds by caching common layers

**Challenge:** Packer doesn't natively support incremental builds well

**Potential Approaches:**

**Option A: Base AMI Strategy**
```
Phase 1: Build base AMI (monthly)
├─ OS + common tools
├─ Docker, Go, system configs
└─ Rarely changes → Cache for 30 days

Phase 2: Build app AMI (daily/weekly)
├─ Start from base AMI
├─ Add app-specific tools
└─ Much faster (20 min vs. 60 min)
```

**Option B: Docker Layer Caching**
```
# Use Docker for provisioning (instead of shell scripts)
# Docker layers are cached automatically
# Packer + Docker provisioner

Challenge: Requires rearchitecting provisioning approach
```

**Option C: Artifact Caching**
```
# Cache downloaded packages between builds
# Store in S3, restore before build
# Reduces download time

Savings: Limited (downloads are not the bottleneck)
```

**Benefits:**
- Faster iteration during development
- Reduced build costs (less instance time)
- Faster CI/CD pipeline

**Drawbacks:**
- Increased complexity
- Cache invalidation challenges
- Potential for stale caches
- More moving parts to maintain

**Recommendation:** Defer until build times become a significant bottleneck

**Deliverables:**
- Proof of concept with base AMI strategy
- Documentation on caching approach
- Comparison: cached vs. uncached build times

---

### 10. Golden AMI Pipeline ⭐⭐

**Status:** Not started
**Effort:** 4-6 hours
**Impact:** Low-Medium (cleaner separation, but added complexity)

**Why:** Separate base AMIs from application AMIs

**Structure:**
```
Tier 1: Base OS AMIs (monthly)
├─ Rocky Linux base
├─ Ubuntu base
└─ Amazon Linux base
    └─ Minimal OS hardening
    └─ Common security configs

Tier 2: Development AMIs (weekly)
├─ Built from Tier 1
├─ Add development tools
├─ Docker, Go, compilers
└─ Cloudberry build dependencies

Tier 3: Application AMIs (on-demand)
├─ Built from Tier 2
└─ Application-specific configs
```

**Benefits:**
- Faster rebuilds (start from Tier 2 instead of base OS)
- Clearer separation of concerns
- Base OS updates propagate through tiers
- Reduced duplication

**Drawbacks:**
- More complexity (3-tier pipeline)
- Dependency management between tiers
- More AMIs to track and cleanup
- Current flat structure works well

**Recommendation:** Only implement if:
- Build times become problematic (>90 min regularly)
- Clear need for base OS standardization
- Multiple teams sharing base AMIs

**Deliverables:**
- Multi-tier build pipeline design
- Updated workflows for tiered builds
- Cleanup logic for multiple tiers

---

### 11. Integration Testing ⭐⭐

**Status:** Not started
**Effort:** 6-10 hours
**Impact:** Low-Medium (high confidence, but expensive and time-consuming)

**Why:** Test actual Cloudberry Database operations on AMIs

**Scope:**
```
1. Launch Cloudberry cluster from AMI
   ├─ 1 coordinator node
   └─ 2 segment nodes

2. Initialize database
   ├─ Run gpinitsystem
   └─ Verify cluster state

3. Run basic operations
   ├─ Create database
   ├─ Create tables
   ├─ Insert data
   ├─ Run queries (SELECT, JOIN, aggregate)
   └─ Verify results

4. Test cluster operations
   ├─ Stop/start segments
   ├─ Verify fault tolerance
   └─ Check replication

5. Performance smoke test
   ├─ Load sample dataset
   ├─ Run benchmark queries
   └─ Verify acceptable performance

6. Cleanup
   ├─ Terminate all instances
   └─ Remove test resources
```

**Challenges:**
- Time-consuming (20-30 minutes per test)
- Expensive (multiple instances running)
- Complex test logic (cluster management)
- Harder to debug failures

**Benefits:**
- High confidence in AMI functionality
- Catches issues Goss tests miss
- Validates actual Cloudberry DB operations
- Regression testing for DB features

**Recommendation:**
- Start with manual integration tests
- Automate only if builds frequently pass Goss but fail in production
- Consider as optional workflow (not blocking builds)

**Deliverables:**
- Integration test scripts
- Cluster configuration templates
- Optional workflow integration
- Documentation on running integration tests

---

### 12. Documentation Website ⭐

**Status:** Not started
**Effort:** 4-8 hours
**Impact:** Low (nice to have, README works well currently)

**Why:** Better organization, search, navigation, professional appearance

**Tools:**
- **GitHub Pages** (free hosting)
- **MkDocs** (simple, Python-based)
- **Docusaurus** (feature-rich, React-based)
- **Jekyll** (GitHub's default)

**Structure:**
```
docs/
├─ index.md                    # Landing page
├─ getting-started/
│  ├─ prerequisites.md
│  ├─ first-build.md
│  └─ understanding-output.md
├─ architecture/
│  ├─ overview.md
│  ├─ build-pipeline.md
│  └─ workflows.md
├─ guides/
│  ├─ adding-os-target.md
│  ├─ customizing-builds.md
│  └─ cost-optimization.md
├─ reference/
│  ├─ configuration.md
│  ├─ scripts.md
│  └─ workflows.md
└─ troubleshooting/
   ├─ common-issues.md
   └─ debugging-builds.md
```

**Benefits:**
- Professional appearance
- Better navigation (sidebar, search)
- Versioned documentation
- Easier for newcomers
- Can include interactive examples

**Drawbacks:**
- Additional maintenance burden
- Need to keep README and website in sync
- Or: Migrate entirely to website (README becomes pointer)

**Recommendation:** Defer until:
- Documentation exceeds ~5,000 lines
- Multiple contributors need better organization
- External users request better docs

**Deliverables:**
- Documentation website setup
- Migrate content from README
- GitHub Pages deployment
- README becomes quick-start + link to full docs

---

## Implementation Priorities

### Recommended Order

**Phase 2: Stability & Operations** (Next 2-4 weeks)
1. Complete troubleshooting guide (High Priority #1)
2. Add cost estimation (High Priority #2)
3. Pin critical versions (High Priority #3)
4. Create health check script (High Priority #4)

**Phase 3: Enhanced Operations** (Month 2)
5. Multi-region AMI copying (Medium Priority #5)
6. Build performance metrics (Medium Priority #6)
7. Enhanced AMI tagging (Medium Priority #7)
8. Notification system (Medium Priority #8)

**Phase 4: Advanced Features** (Future / As Needed)
9. Build caching (Lower Priority #9)
10. Golden AMI pipeline (Lower Priority #10)
11. Integration testing (Lower Priority #11)
12. Documentation website (Lower Priority #12)

---

## Decision Framework

When deciding which improvement to tackle next, consider:

**Impact vs. Effort Matrix:**
```
High Impact, Low Effort:
→ Do first (Cost docs, Troubleshooting)

High Impact, High Effort:
→ Do when you have time (Integration testing)

Low Impact, Low Effort:
→ Do if easy wins needed (Tagging)

Low Impact, High Effort:
→ Avoid or defer (Documentation website)
```

**Current Pain Points:**
- Builds failing? → Troubleshooting guide
- Costs unclear? → Cost estimation
- Builds breaking unexpectedly? → Pin versions
- Need faster validation? → Health check script
- Multi-region needed? → AMI copying
- Want better visibility? → Notifications

---

## Contributing to This Roadmap

To propose new improvements:

1. **Add to appropriate priority section**
2. **Include:**
   - Clear problem statement (Why?)
   - Proposed solution (What?)
   - Estimated effort (How long?)
   - Expected impact (What's the benefit?)
   - Trade-offs or risks
3. **Submit PR** for discussion
4. **Update status** as work progresses

---

## Measuring Success

For each improvement, define success criteria:

**Troubleshooting Guide:**
- ✅ Reduced time to resolution for common issues
- ✅ Fewer support requests on same issues
- ✅ New contributors can self-serve debugging

**Cost Estimation:**
- ✅ Users can predict costs before building
- ✅ Better budget planning and approval
- ✅ Increased adoption due to transparency

**Version Pinning:**
- ✅ Zero unexpected build breaks from upstream changes
- ✅ Reproducible builds across time
- ✅ Documented upgrade path for versions

**Health Check Script:**
- ✅ Quick validation (< 5 minutes)
- ✅ Catches issues Goss tests miss
- ✅ Usable by CI and manual testing

---

## Notes

- Priorities may shift based on team needs and feedback
- Effort estimates are approximate and may vary
- Impact ratings are subjective but based on expected value
- Some improvements may be combined or split as needed
- Mark items as ✅ when completed and move to "Completed" section

---

**Generated:** October 9, 2025
**Status:** Living document - update as priorities change
