# AAI User Guide

Complete guide for using AAI (Autonomous AI) skills in your projects.

## Table of Contents

- [Getting Started](#getting-started)
- [Quick Reference](#quick-reference)
- [Skills Catalog](#skills-catalog)
- [Workflows](#workflows)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

---

## Getting Started

### Installation

1. **Sync AAI into your project:**
   ```bash
   cd /path/to/aai-os
   ./scripts/ai-os-sync.sh /path/to/your-project
   ```

2. **Bootstrap your project (one-time):**
   ```bash
   cd /path/to/your-project
   /aai-bootstrap
   ```
   This detects your architecture and generates optimized skills.

3. **Verify installation:**
   ```bash
   /aai-test-skills
   ```

### Your First Workflow

```bash
# 1. Start a new feature
/aai-intake "Add user authentication with JWT"

# 2. AAI will create a requirement document
# docs/requirements/REQ-001-user-auth.md

# 3. Run TDD cycle
/aai-tdd

# 4. Validate your work
/aai-validate-report

# 5. Share the report
/aai-share docs/ai/reports/VALIDATION_REPORT_*.md
```

---

## Quick Reference

### Essential Skills (Use Daily)

| Skill | Usage | What it does |
|-------|-------|--------------|
| `/aai-intake` | Start any work | Detects type, creates artifact |
| `/aai-tdd` | Development | RED-GREEN-REFACTOR cycle |
| `/aai-validate-report` | End of work | Validation with screenshots |
| `/aai-share` | Share results | Publish to Cloudflare Pages |
| `/aai-loop` | Autonomous work | Multi-tick autonomous loop |

### Discovery & Exploration

| Skill | Usage | What it does |
|-------|-------|--------------|
| `/aai-docs-hub` | Learn skills | Interactive skill catalog |
| `/aai-test-skills` | Verify setup | Test all skills work |
| `/aai-check-state` | See status | View STATE.yaml |

### Advanced Skills

| Skill | Usage | What it does |
|-------|-------|--------------|
| `/aai-dashboard` | View metrics | Interactive charts |
| `/aai-code-review` | Review code | AI-powered review |
| `/aai-profile` | Optimize | Performance analysis |
| `/aai-auto-trigger` | Automate | Pattern-based triggering |

---

## Skills Catalog

### 1. Project Initialization

#### `/aai-bootstrap`
**What:** Detects your project architecture and generates optimized skills.

**When to use:**
- First time using AAI in a project
- After adding new tools (Playwright, Jest, etc.)
- After installing MCP servers

**Example:**
```bash
/aai-bootstrap

# Output:
✅ Detected: TypeScript + Playwright + playwright-mcp
✅ Generated: /aai-test-e2e (with MCP support)
✅ Generated: /aai-test-unit
✅ Generated: /aai-build
```

**Benefits:**
- 90% token reduction for testing/building
- MCP server integration
- Project-specific shortcuts

---

### 2. Intake & Planning

#### `/aai-intake`
**What:** Universal router for starting any work (feature, bug, change, etc.)

**When to use:**
- Starting any new work
- Converting user request to structured artifact

**Example:**
```bash
/aai-intake "Add password reset via email"

# Auto-detects: This is a feature (PRD)
# Creates: docs/requirements/REQ-005-password-reset.md
```

**Supports:**
- Features → PRD
- Bugs → Issue
- Changes → Change doc
- Research → Research doc
- Hotfixes → Hotfix doc
- Tech debt → Tech debt doc
- RFCs → RFC doc
- Releases → Release doc

---

### 3. Development Workflows

#### `/aai-tdd`
**What:** Enforces RED-GREEN-REFACTOR test-driven development.

**When to use:**
- Implementing any feature
- Writing tests first
- Ensuring code quality

**Example:**
```bash
/aai-tdd

# RED Phase:
- Write failing test
- Evidence: docs/ai/tdd/red-20260308.log

# GREEN Phase:
- Minimal implementation
- Evidence: docs/ai/tdd/green-20260308.log

# REFACTOR Phase:
- Improve code quality
- Evidence: docs/ai/tdd/refactor-20260308.log
```

**Benefits:**
- Guarantees tests exist
- Prevents over-engineering
- Evidence-based completion

#### `/aai-worktree`
**What:** Manages git worktrees for parallel development.

**When to use:**
- Working on multiple features simultaneously
- Long-running branches
- Experimental work

**Commands:**
```bash
/aai-worktree setup login          # Create worktree
/aai-worktree switch login         # Switch to worktree
/aai-worktree list                 # List all worktrees
/aai-worktree cleanup login        # Remove worktree
```

**Benefits:**
- No branch switching overhead
- Parallel development
- Clean isolation per feature

#### `/aai-loop`
**What:** Autonomous multi-tick loop orchestration.

**When to use:**
- Complex multi-step workflows
- Hands-off automation
- Long-running tasks

**Example:**
```bash
/aai-loop

# Reads STATE.yaml
# Dispatches roles (Planning → Implementation → Validation)
# Stops on completion or human input needed
```

---

### 4. Quality & Validation

#### `/aai-validate-report`
**What:** Validates work and generates report with screenshots.

**When to use:**
- End of feature development
- Before sharing results
- Evidence collection

**Example:**
```bash
/aai-validate-report

# Output:
✅ Report: docs/ai/reports/VALIDATION_REPORT_20260308T100000Z.md
📸 Screenshots: 3 files
```

**Includes:**
- Test results
- Screenshots
- Metrics
- Pass/fail status

#### `/aai-code-review`
**What:** AI-powered code review for security, performance, style.

**When to use:**
- Before committing
- Reviewing PRs
- Security audits

**Example:**
```bash
/aai-code-review                   # Review local changes
/aai-code-review --pr 42           # Review GitHub PR
/aai-code-review --pr 42 --post    # Post review to PR
```

**Checks:**
- Security (SQL injection, XSS, credentials)
- Performance (N+1 queries, inefficient loops)
- Style (formatting, naming)
- Best practices (error handling, DRY)

**Severity levels:**
- ERROR: Must fix (blocks)
- WARNING: Should fix
- INFO: Nice to have

---

### 5. Publishing & Sharing

#### `/aai-share`
**What:** Publishes Markdown documents to Cloudflare Pages.

**When to use:**
- Sharing validation reports
- Publishing documentation
- Team collaboration

**Example:**
```bash
/aai-share docs/ai/reports/VALIDATION_REPORT.md

# Output:
✅ Published!
🔗 URL: https://ai-os-reports-abc123.pages.dev
```

**Supports:**
- Markdown with embedded images
- GitHub-style CSS
- Dark mode
- Mobile-friendly

**Requirements (one-time):**
```bash
npm install -g wrangler
wrangler login
```

---

### 6. Metrics & Analytics

#### `/aai-dashboard`
**What:** Interactive HTML dashboard with metrics visualization.

**When to use:**
- Monthly reviews
- Performance analysis
- Team reporting

**Example:**
```bash
/aai-dashboard --publish

# Generates: docs/dashboard.html
# Publishes: https://ai-os-reports-dashboard.pages.dev
```

**Visualizes:**
- Token usage over time (line chart)
- TDD cycle duration (bar chart)
- Worktree efficiency (pie chart)
- Publishing stats (area chart)
- Skill usage frequency (horizontal bar)

#### `/aai-profile`
**What:** Performance profiling and optimization suggestions.

**When to use:**
- Optimizing workflows
- Identifying bottlenecks
- Token usage analysis

**Example:**
```bash
/aai-profile aai-intake           # Profile single skill
/aai-profile --workflow           # Profile full workflow
/aai-profile --history --days 30  # 30-day trends
```

**Tracks:**
- Token usage (input/output/cached)
- Execution time
- Memory (disk usage)
- Cache hit rates

**Outputs:**
- Bottleneck detection
- Optimization suggestions
- Performance trends

---

### 7. Automation & Integration

#### `/aai-auto-trigger`
**What:** Automatic skill triggering based on user input patterns.

**When to use:**
- Reducing manual invocations
- Automating common workflows
- Pattern-based routing

**Example:**
```bash
# Setup triggers
/aai-auto-trigger add

# Pattern: "add.*feature"
# Skill: aai-intake
# Args: { type: "prd" }

# Now this works automatically:
User: "add login feature"
→ Auto-triggers: /aai-intake "add login feature"
```

**Manages:**
- `.claude/triggers.json` config
- Pattern → skill mapping
- Priority resolution
- Enable/disable triggers

#### `/aai-decapod`
**What:** Decapod compliance framework integration.

**When to use:**
- Compliance requirements (SOC2, HIPAA, GDPR)
- Governance needs
- Attestation artifacts

**Example:**
```bash
/aai-decapod

# Runs advisory checks before planning
# Generates attestation after validation
# Stores in docs/ai/compliance/
```

**Supports:**
- SOC2, ISO27001, HIPAA, GDPR, PCI-DSS
- Advisory checks (pre-planning)
- Attestation generation (post-validation)

---

### 8. Maintenance & Testing

#### `/aai-test-skills`
**What:** Tests all AAI skills to ensure they work.

**When to use:**
- After AAI updates
- Troubleshooting issues
- CI/CD validation

**Example:**
```bash
/aai-test-skills

# Output:
Total:   7
Passed:  7 (100%)
Failed:  0 (0%)
Skipped: 0 (0%)
```

**Tests:**
- Dependency checks
- Skill functionality
- Integration tests
- Output validation

#### `/aai-flush`
**What:** Flushes completed metrics to METRICS.jsonl.

**When to use:**
- Manual state cleanup
- After interrupted workflows
- Metrics synchronization

**Example:**
```bash
/aai-flush

# Moves completed work from STATE.yaml to METRICS.jsonl
# Cleans up state
```

#### `/aai-canonicalize`
**What:** Normalizes legacy AAI structure.

**When to use:**
- Migrating from old AAI versions
- Cleaning up scattered artifacts
- Structure validation

**Example:**
```bash
/aai-canonicalize

# Migrates old files to new structure
# Consolidates evidence
# Generates architecture summary
```

#### `/aai-docs-hub`
**What:** Generates interactive skill catalog.

**When to use:**
- Learning available skills
- Team onboarding
- Skill discovery

**Example:**
```bash
/aai-docs-hub

# Generates: docs/SKILL_CATALOG.html
# Interactive, searchable, with examples
```

#### `/aai-check-state`
**What:** Views current STATE.yaml.

**When to use:**
- Checking workflow status
- Debugging
- Understanding current task

**Example:**
```bash
/aai-check-state

# Displays:
- Current task
- Workflow phase
- TDD cycle status
- Metrics
```

#### `/aai-hitl`
**What:** Human-in-the-loop resolver.

**When to use:**
- When autonomous loop pauses
- Answering blocking questions
- Manual decision points

**Example:**
```bash
/aai-hitl

# Reads blocked question from STATE.yaml
# Collects your answer
# Saves decision artifact
# Unblocks loop
```

---

## Workflows

### Complete Feature Development

```bash
# 1. Intake
/aai-intake "Add user profile page with avatar upload"
# Creates: docs/requirements/REQ-006-user-profile.md

# 2. Create worktree (optional, for parallel work)
/aai-worktree setup user-profile

# 3. TDD cycle
/aai-tdd
# RED → GREEN → REFACTOR with evidence

# 4. Code review
/aai-code-review
# Checks security, performance, style

# 5. Validate
/aai-validate-report
# Generates report with screenshots

# 6. Share
/aai-share docs/ai/reports/VALIDATION_REPORT_*.md
# Returns: https://ai-os-reports-xyz.pages.dev

# 7. Cleanup worktree
/aai-worktree cleanup user-profile

# 8. View metrics
/aai-dashboard --publish
```

### Bug Fix Workflow

```bash
# 1. Intake
/aai-intake "Fix login redirect loop on mobile"
# Creates: docs/issues/ISSUE-012-login-redirect.md

# 2. TDD (write failing test first)
/aai-tdd
# RED: Test reproduces bug
# GREEN: Fix bug
# REFACTOR: Improve code

# 3. Validate
/aai-validate-report

# 4. Review
/aai-code-review

# 5. Share
/aai-share docs/ai/reports/VALIDATION_REPORT_*.md
```

### Research & Documentation

```bash
# 1. Intake
/aai-intake "Research best database for high-volume time-series data"
# Creates: docs/research/RESEARCH-003-timeseries-db.md

# 2. Complete research (manual work)

# 3. Share findings
/aai-share docs/research/RESEARCH-003-timeseries-db.md
# Team can review at shared URL
```

### Autonomous Workflow

```bash
# 1. Setup auto-triggers (one-time)
/aai-auto-trigger add
# Pattern: "add.*feature" → /aai-intake

# 2. Start autonomous loop
/aai-loop

# 3. Monitor progress
/aai-check-state

# 4. Resolve human decisions if needed
/aai-hitl

# 5. Loop completes automatically
```

---

## Best Practices

### When to Use Each Skill

**Daily use:**
- `/aai-intake` - Start everything
- `/aai-tdd` - All development
- `/aai-validate-report` - End of work
- `/aai-share` - Team sharing

**Weekly use:**
- `/aai-dashboard` - Review metrics
- `/aai-code-review` - PR reviews
- `/aai-test-skills` - Health check

**Monthly use:**
- `/aai-profile` - Optimization
- `/aai-canonicalize` - Cleanup

**Setup (one-time):**
- `/aai-bootstrap` - Project init
- `/aai-auto-trigger` - Automation setup

### Token Optimization

1. **Use `/aai-bootstrap` first**
   - Generates optimized project-specific skills
   - 90% token reduction for common tasks

2. **Prefer auto-triggers**
   - Set up once, saves tokens forever
   - Example: "add feature" → `/aai-intake`

3. **Use worktrees for parallel work**
   - Isolated contexts
   - No repeated setup

4. **Profile regularly**
   - `/aai-profile` identifies bottlenecks
   - Follow optimization suggestions

### Team Collaboration

1. **Share via `/aai-share`**
   - Validation reports
   - Decision documents
   - Research findings

2. **Use `/aai-dashboard` for reviews**
   - Weekly team metrics
   - Performance trends
   - Success rates

3. **Standardize with auto-triggers**
   - Team-wide patterns
   - Consistent workflows

### Quality Gates

1. **Always use `/aai-tdd`**
   - Guarantees test coverage
   - Evidence-based

2. **Run `/aai-code-review` before commits**
   - Catches security issues
   - Maintains style

3. **Generate `/aai-validate-report`**
   - Proof of completion
   - Shareable evidence

---

## Troubleshooting

### Common Issues

#### "Skill not found"
**Solution:**
```bash
# Re-sync AAI
cd /path/to/aai-os
./scripts/ai-os-sync.sh /path/to/your-project

# Re-bootstrap
cd /path/to/your-project
/aai-bootstrap
```

#### "Dependency missing"
**Solution:**
```bash
# Check what's missing
/aai-test-skills

# Install missing tools:
npm install -g wrangler    # For /aai-share
npm install -g @decapod/cli # For /aai-decapod
```

#### "Wrangler authentication failed"
**Solution:**
```bash
wrangler logout
wrangler login
# Re-authenticate in browser
```

#### "Tests failing"
**Solution:**
```bash
# Verbose test output
/aai-test-skills --verbose

# Test specific skill
/aai-test-skills --skill aai-tdd

# Check STATE.yaml
/aai-check-state
```

#### "Dashboard not generating"
**Solution:**
```bash
# Check METRICS.jsonl exists
ls docs/ai/METRICS.jsonl

# If empty, run some workflows first
/aai-intake "test"
/aai-tdd
/aai-validate-report

# Then generate dashboard
/aai-dashboard
```

### Getting Help

1. **View skill catalog:**
   ```bash
   /aai-docs-hub
   open docs/SKILL_CATALOG.html
   ```

2. **Test skills:**
   ```bash
   /aai-test-skills --verbose
   ```

3. **Check documentation:**
   - This guide: `docs/USER_GUIDE.md`
   - Technical docs: `docs/ai/DECAPOD_INTEGRATION.md`
   - TODO/roadmap: `docs/TODO.md`

---

## Next Steps

1. **Complete the getting started workflow above**
2. **Explore the skills catalog:**
   ```bash
   /aai-docs-hub
   /aai-share docs/SKILL_CATALOG.html
   ```
3. **Set up auto-triggers for your team**
4. **Generate your first dashboard**
5. **Share your first validation report**

---

**Last Updated:** 2026-03-08
**Version:** 1.0
**Branch:** feature/comprehensive-improvements
