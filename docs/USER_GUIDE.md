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
   cd /path/to/aai
   ./.aai/scripts/aai-sync.sh /path/to/your-project
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

4. **Optional: register the session-start hook**
   This injects the AAI meta-skill automatically when a new agent session starts.

   Bash / Git-Bash:
   ```json
   {
     "hooks": {
       "SessionStart": [
         {
           "matcher": "startup|resume|clear|compact",
           "hooks": [
             {
               "type": "command",
               "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh\"",
               "async": false
             }
           ]
         }
       ]
     }
   }
   ```

   PowerShell:
   ```json
   {
     "hooks": {
       "SessionStart": [
         {
           "matcher": "startup|resume|clear|compact",
           "hooks": [
             {
               "type": "command",
               "command": "powershell -ExecutionPolicy Bypass -File \"${CLAUDE_PLUGIN_ROOT}/hooks/session-start.ps1\"",
               "async": false
             }
           ]
         }
       ]
     }
   }
   ```

   Synced files:
   - `hooks/session-start.sh`
   - `hooks/session-start.ps1`
   - `hooks/hooks.json`
   - `hooks/hooks.windows.json`

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

# 5. Share the local runtime report
/aai-share docs/ai/reports/LATEST.md

# 6. If the result is important long-term, promote it into project docs
# examples: docs/decisions/, docs/specs/, docs/knowledge/, docs/archive/analysis/
```

---

## Quick Reference

### Runtime Reports vs Project Docs

AAI uses two different classes of documentation:

- `docs/ai/reports/` = local runtime evidence only
  - validation reports
  - screenshots
  - migration advisories
  - sync conflict advisories
- `docs/requirements/`, `docs/specs/`, `docs/decisions/`, `docs/knowledge/`, `docs/archive/analysis/` = project-owned documents

**Important:**
- Files in `docs/ai/reports/` should **not** be committed.
- Share them temporarily with `/aai-share` when you need quick review.
- If a report contains durable conclusions, copy the conclusion into a project-owned document and commit that instead.

### Essential Skills (Use Daily)

| Skill | Usage | What it does |
|-------|-------|--------------|
| `/aai-intake` | Start any work | Detects type, creates artifact |
| `/aai-tdd` | Development | RED-GREEN-REFACTOR cycle |
| `/aai-validate-report` | End of work | Validation with screenshots |
| `/aai-share` | Share results | Publish to Cloudflare Pages |
| `/aai-loop` | Autonomous work | Multi-tick autonomous loop |
| `/aai-update` | Refresh AAI | Re-sync vendored AAI layer from canonical git `main` |

### Session Management

| Skill | Usage | What it does |
|-------|-------|--------------|
| `/aai-wrap-up` | End session | Capture learnings, propose rules |
| `/aai-replay` | Start session | Surface relevant past learnings |
| `/aai-doctor` | Diagnostics | Full environment health check |

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

#### `/aai-update`
**What:** Re-syncs the current project's vendored AAI layer from the `main` branch of its canonical git repository, including private repositories with authenticated access.

**When to use:**
- After upstream AAI changes
- When a project needs the latest prompts/scripts/shims
- Before re-running bootstrap or skill health checks

**Example:**
```bash
/aai-update

# Or preview only:
/aai-update --dry-run
```

**Follow-up:**
- `/aai-bootstrap` if you want refreshed project-local dynamic skills
- `/aai-doctor` to verify the environment
- `/aai-test-skills` to verify skill health

**Note:**
- For private upstream repos, prefer authenticated `gh repo clone` or an authenticated git remote/SSH URL

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
✅ Report: docs/ai/reports/validation-20260308T100000Z.md
✅ Latest alias: docs/ai/reports/LATEST.md
📸 Screenshots: 3 files
```

**Includes:**
- Test results
- Screenshots
- Metrics
- Pass/fail status

**Storage policy:**
- Output goes into `docs/ai/reports/` as local runtime evidence.
- Treat that folder as ephemeral and uncommitted.
- If the validation result changes project knowledge or delivery state, promote the durable summary into:
  - `docs/specs/`
  - `docs/decisions/`
  - `docs/knowledge/`
  - `docs/archive/analysis/`

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
/aai-share docs/ai/reports/LATEST.md

# Output:
✅ Published!
🔗 URL: https://aai-reports-abc123.pages.dev
```

**Supports:**
- Markdown with embedded images
- GitHub-style CSS
- Dark mode
- Mobile-friendly

**Recommended usage:**
- Share `docs/ai/reports/LATEST.md` for temporary validation review.
- Share project-owned docs for durable collaboration:
  - `docs/requirements/*.md`
  - `docs/specs/*.md`
  - `docs/decisions/*.md`
  - `docs/research/*.md`

**Do not treat shared runtime reports as canonical docs:**
- `docs/ai/reports/` is evidence storage, not your long-term documentation source.

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
# Publishes: https://aai-reports-dashboard.pages.dev
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

### 8. Session Management (pro-workflow)

#### `/aai-doctor`
**What:** Comprehensive environment health check — broader than `/aai-check-state`.

**When to use:**
- After AAI sync or setup
- When something seems broken
- Onboarding new team members

**Hook note:**
- `[CAT-09] Pre-Compact Hook` checks whether the pre-compact helper exists and appears configured.
- Session-start hook registration is separate and user-managed; use `hooks/hooks.json` for Bash/Git-Bash or `hooks/hooks.windows.json` for native PowerShell as the template.

**Example:**
```bash
/aai-doctor

# Output:
[CAT-01] Core Files:        ✓ 7/7 present
[CAT-02] Role Prompts:      ✓ 4/4 present
[CAT-03] Universal Skills:  ✓ 21/21 healthy
[CAT-04] Dynamic Skills:    ⚠ none (run /aai-bootstrap)
[CAT-05] Knowledge:         ✓ 3 files
[CAT-06] STATE.yaml:        ✓ HEALTHY
[CAT-07] Telemetry:         ✓ 3 files
[CAT-08] Git:               ✓ clean on main
[CAT-09] Pre-Compact Hook:  ⚠ not set up

Overall: HEALTHY (2 warnings)
```

#### `/aai-replay`
**What:** Surfaces relevant past learnings before starting work.

**When to use:**
- Starting a new feature (especially similar to past work)
- Before implementation phase
- When you want to avoid past mistakes

**Example:**
```bash
/aai-replay authentication

# Output:
RELEVANT LEARNINGS FOR: authentication
From LEARNED.md:
  • [2026-03-06] Always test token expiry edge cases
From PATTERNS.md:
  • Auth endpoints: rate-limit to 5 req/min per IP
From Decisions:
  • DEC-005: Chose JWT for session tokens
```

#### `/aai-wrap-up`
**What:** End-of-session ritual that captures learnings.

**When to use:**
- End of work session
- Before context gets lost
- After completing a feature

**Example:**
```bash
/aai-wrap-up

# Output:
SESSION SUMMARY
───────────────
Completed:
• [Feature] Password reset (REQ-010)
• [TDD] 12 tests → all green

Proposed rule: "Always test token expiry for auth features"
Add to docs/knowledge/LEARNED.md? [y/n]: y
✓ Rule added

NEXT SESSION
────────────
Suggested focus:
• Profile editing (REQ-008)
```

---

### 9. Maintenance & Testing

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
# 0. Replay relevant past learnings
/aai-replay "user profile"

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
/aai-share docs/ai/reports/LATEST.md
# Returns: https://aai-reports-xyz.pages.dev

# 7. Cleanup worktree
/aai-worktree cleanup user-profile

# 8. View metrics
/aai-dashboard --publish

# 9. Wrap up session
/aai-wrap-up
# Captures learnings, proposes rules, prepares next session
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
/aai-share docs/ai/reports/LATEST.md
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
   - Temporary review: `docs/ai/reports/LATEST.md`
   - Durable collaboration: decision documents, specs, research findings

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
   - Shareable temporary evidence
   - Promote durable conclusions into project-owned docs before commit

---

## Troubleshooting

### Common Issues

#### "Skill not found"
**Solution:**
```bash
# Re-sync AAI
cd /path/to/aai
./.aai/scripts/aai-sync.sh /path/to/your-project

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
   ```bash
   /aai-share docs/ai/reports/LATEST.md
   ```

6. **Promote anything durable before commit**
   - decisions -> `docs/decisions/`
   - implementation constraints -> `docs/specs/`
   - reusable facts -> `docs/knowledge/`
   - broader write-up -> `docs/archive/analysis/`

---

**Last Updated:** 2026-03-16
**Version:** 1.1
**Status:** Current
