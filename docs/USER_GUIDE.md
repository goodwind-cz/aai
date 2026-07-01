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

1. **Install AAI into your project:**
   From the target project directory:

   PowerShell:
   ```powershell
   irm https://raw.githubusercontent.com/goodwind-cz/aai/main/install.ps1 | iex
   ```

   Bash:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/goodwind-cz/aai/main/install.sh | bash
   ```

   Review-first variant:

   PowerShell:
   ```powershell
   irm https://raw.githubusercontent.com/goodwind-cz/aai/main/install.ps1 -OutFile install-aai.ps1
   Get-Content .\install-aai.ps1
   powershell -ExecutionPolicy Bypass -File .\install-aai.ps1
   ```

   Bash:
   ```bash
   curl -fsSLo install-aai.sh https://raw.githubusercontent.com/goodwind-cz/aai/main/install.sh
   less install-aai.sh
   bash install-aai.sh
   ```

   Manual sync alternative:
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
- `docs/requirements/`, `docs/specs/`, `docs/decisions/`, `docs/knowledge/`, `docs/project-sessions/`, `docs/archive/analysis/` = project-owned documents

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
| `/aai-session-journal` | Resume named thread | Durable human-language project discussion trail |
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
| `/aai-docs-audit` | Docs hygiene | Drift detection: claimed vs implemented |
| `/aai-docs-canon` | Docs consolidation | Layered intake/specs/RFCs → canonical per-domain layer + archive |
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

#### Parallel multi-agent orchestration

**What:** Each loop tick can run a single agent (default) or fan out to several
agents working independent scopes at once. The loop decides automatically and
**fail-closed** — it only parallelizes work it can prove is non-conflicting.

**How the loop chooses (auto):** before dispatching, `SKILL_LOOP`'s "RUN
ORCHESTRATION" step calls the deterministic selector
`.aai/scripts/orchestration-mode.mjs`. It returns `mode` (single | parallel),
`k` (the fan-out), and the scope `groups`. When `mode=parallel`, the loop routes
the tick to `.aai/ORCHESTRATION_PARALLEL.prompt.md`; when `mode=single` it uses
the normal single-agent `.aai/ORCHESTRATION.prompt.md`.

**The independence rule (when auto goes parallel):** two scopes may run together
only when ALL hold —
- their declared review-scope paths do **not** overlap (a path overlaps another
  if it equals it or is a directory-boundary prefix, e.g. `apps/api/` overlaps
  `apps/api/export/`),
- neither scope is the other's parent/child in the doc links, and
- each scope's path is actually declared and parseable — a **missing, empty, or
  bare-glob** path (`*`, `**`, `*.md`) is treated as *uncertain* and is **never**
  co-scheduled (fail-closed: it can only reduce parallelism, never cause a clash).

Read-only roles (validation, code review) parallelize freely across disjoint
scopes. Write roles (implementation/TDD/remediation) parallelize only when they
are provably disjoint inline, or run in a git worktree (`isolation: worktree`).

**Controls and defaults:**
- `k_max` default is **2** (conservative — parallel fan-out multiplies token/
  compute spend). Raise it to allow wider fan-out; a per-run token/cost budget
  (`max_k_budget`) caps it further.
- **Locks are required:** parallel ticks coordinate writes through the atomic
  scope locks (`.aai/scripts/docs-lock.mjs`). If `docs-lock.mjs` is absent (older
  layer), the selector **degrades to single** (`K=1`) and reports why — it never
  runs parallel without enforceable locks.

**Override:** set `orchestration.mode` in `docs/ai/STATE.yaml` (or pass it as a
loop arg) to one of:
- `auto` (default) — let the selector decide per tick,
- `single` — always one agent per tick (forces single, overrides everything),
- `parallel` — opt in to fan-out, but still **safety-gated**: overlapping or
  undeclared scopes stay sequential (it never bypasses the independence test).

An absent `orchestration` block means `auto` — existing single-scope projects
behave exactly as before.

**Inspecting the locks:** when a parallel tick is running you can see what each
agent holds, and recover after a crash, with the scope-lock CLI:
```bash
node .aai/scripts/docs-lock.mjs list      # show held scope locks (owner, ttl, expired?)
node .aai/scripts/docs-lock.mjs reap      # clear expired locks (a crashed owner self-heals after its TTL)
```
Lock files live under `docs/ai/locks/` (gitignored, per-agent-local). You should
never need to edit them by hand; `reap` recovers a wedged scope if an
orchestrator died mid-tick.

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

#### `/aai-docs-audit`
**What:** Docs hygiene and drift detection (RFC-0002). Classifies every
prefixed doc under `docs/` and compares what each doc claims (frontmatter
`status`, AC Status table) against reality (commits via
`git log --grep="<DOC-ID>"`, `ac_evidence` events in EVENTS.jsonl).
Reports only — never edits a doc unless you approve each change in
remediation mode.

**When to use:**
- Periodic docs hygiene review (weekly, or before a release closeout)
- After inheriting or merging a large docs backlog ("what is actually
  implemented and what is not?")
- First run after `/aai-update` in a project that never audited its docs
- When a backlog row says Done but you do not trust it

**Example:**
```bash
/aai-docs-audit                    # full audit, digest in chat
/aai-docs-audit remediate          # interactive cleanup, per-item approval
/aai-docs-audit verify CHANGE-048  # semantic check of one doc's ACs
                                   # against the actual code (expensive;
                                   # one doc per invocation)

# Direct engine calls:
node .aai/scripts/docs-audit.mjs --list      # per-doc classification table
node .aai/scripts/docs-audit.mjs --check     # CI gate (exit 1 on hard fails)
node .aai/scripts/docs-audit.mjs --quick     # cheap counts, no git probes
node .aai/scripts/docs-audit.mjs --path docs/specs   # scope to a subtree
```

**Reading the verdicts:**
- `tracked-done` — doc says done and evidence agrees (implemented)
- `tracked-open` — legitimately in progress (draft/implementing/frozen)
- `probable-false-done` — doc claims done, evidence disagrees
- `probable-stale-open` — open doc untouched past `stale_after_days`;
  possibly shipped elsewhere and never closed
- `probable-partial` — spec marked done without the mandated AC table
- `orphan` — doc without canonical frontmatter (new ones fail `--check`)

**Configuration** (`docs/ai/docs-audit.yaml`, committed; without it the
audit runs report-only and nothing hard-fails):
```yaml
legacy_until_date: 2026-06-12   # docs first committed before this soft-warn;
                                # newer/untracked docs hard-fail --check
stale_after_days: 90            # open doc with no activity for this long
                                # becomes a stale candidate
plan_scan_mode: lenient         # docs/plans/** without frontmatter are
                                # operator plan files, not orphans
                                # (strict: flag them as orphans)
scan_exclude: []                # extra path globs to skip
backlog_globs: []               # operator plan files to cross-check Done
                                # claims against (read-only)
review_by_methods: []           # extra Review-By method labels beyond
                                # TDD/Loop/code-review/manual/deferred/
                                # PlaywrightSuites/Validation/...
category_prefixes:              # filename segments treated as scopes,
  - PHASE                       # not IDs (DECISION-PHASE-0-scope ->
  - MILESTONE                   # unique slug ID + scope PHASE-0)
  - EPIC
```

**Three modes, three questions:**
- audit (default) — "do recorded claims still match the traces?" (script:
  frontmatter/AC table vs commits and EVENTS; cheap, repo-wide)
- remediate — "fix the metadata I approve" (frontmatter, statuses, AC rows)
- verify — "is this claim actually true in the code?" (agent reads each AC,
  probes the codebase, runs existing tests; expensive, one doc at a time;
  `implemented` requires positive evidence — path:line or a passing test)

**Typical retro-cleanup workflow:**
1. Create the config with `legacy_until_date` set to today.
2. `/aai-docs-audit` — read Orphans + Drift report (each row carries
   evidence and a suggested next step).
3. `/aai-docs-audit remediate` — approve fixes item by item; every applied
   change is logged to EVENTS.jsonl.
4. For docs where you do not trust the claims at all (probable-false-done
   with N acceptance criteria), `/aai-docs-audit verify <DOC-ID>` — the
   agent reconciles each AC against the code and you approve the result.
5. Re-run until CLEAN; wire `--check` into CI to keep it that way
   (template: `.aai/templates/DOCS_AUDIT_TEST_TEMPLATE.md`).

**Where it runs automatically:**
- Intake saves are gated (`--check --strict --path <artifact>`)
- Every `/aai-loop` tick surfaces counts (`--quick`, never blocks)
- `/aai-doctor` CAT-11 reports docs hygiene state

---

#### `/aai-docs-canon`

Consolidates **layered** documentation — where an original intake spawned a
chain of specs, sub-specs, addendums, and corrections — into a single
**canonical "current state" layer**, categorized by functional domain. Use it
when there is no single final view of what a feature does today and readers must
trace breadcrumbs across folders and superseded files (RFC-0003 / SPEC-0002).

`/aai-docs-audit` keeps the *existing* doc set honest; `/aai-docs-canon`
*restructures* it into a working reference. They compose: audit first, then
canonicalize.

**Two phases (human gate between them):**
```bash
# Phase 1 — analyze + propose (writes nothing under docs/canonical|_archive)
node .aai/scripts/docs-canon.mjs --phase1 [--targets docs/specs,docs/rfc]
#   builds a supersession/dependency graph, proposes an AI domain map, and
#   HALTS. Review docs/ai/docs-canon.proposal.json, then persist an approved
#   map to docs/ai/docs-canon.map.json with "approved": true.

# Phase 2 — synthesize + canonicalize (only on an approved map)
node .aai/scripts/docs-canon.mjs --phase2
#   writes one canonical doc per domain to docs/canonical/<domain>.md with the
#   five fixed layer sections (Overview/Intent · UI · Processes · Data model ·
#   Superseded decisions), moves originals to docs/_archive/ with status:
#   archived + a canonical: back-pointer, and records hashes for drift.

# Re-run drift check / resolution
node .aai/scripts/docs-canon.mjs --drift            # report drifted domains (exit 1 if any)
node .aai/scripts/docs-canon.mjs --phase2 --resync  # re-synthesize drifted domains from current sources
```

**What it guarantees:**
- The risky judgment call (domain boundaries) is **human-approved**; the
  mechanical merge is automated.
- Originals are never destroyed — moved to `docs/_archive/` and linked
  bidirectionally (`sources:` ↔ `canonical:`).
- Superseded docs are **harvested** into a "Superseded decisions" audit trail,
  not silently dropped.
- An unsafe approved map (one source in two domains, destination collision)
  **aborts before any file is moved** — no partial mutation.
- Re-runnable: unchanged domains are skipped; changed sources are reported as
  drift and never silently overwritten.

**Integration:** canonical docs are surfaced in `docs/INDEX.md` under a
"Canonical layer" section; `docs/_archive/` is excluded from the active
docs-audit scan, so archived docs are not mis-flagged as orphans.

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
  - `docs/project-sessions/*.md`
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

#### `/aai-session-journal`
**What:** Creates or updates a named project discussion thread in `docs/project-sessions/`.

**When to use:**
- You want a named session you can return to later
- Multiple agents will work from subsets of information
- You want a human-readable decision trail in your working language
- You do not want continuity to depend on vendor chat history alone

**Example:**
```bash
/aai-session-journal "Authentication redesign"

# Output:
SESSION JOURNAL UPDATED
- Session: Authentication redesign
- File: docs/project-sessions/SESSION-authentication-redesign.md
- Index: docs/project-sessions/INDEX.md
- Next resume point: Decide whether to split auth UX from token lifecycle work
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

#### Docs index (`docs/INDEX.md`)
**What:** An auto-generated catalog of all `docs/{issues,rfc,specs,requirements,releases}/**`
documents — status, progress, overdue reviews, broken refs, orphans. The file is
marked `auto-generated, DO NOT EDIT`; never hand-edit it.

**How it stays fresh — three independent mechanisms:**
- **Intake** regenerates it automatically after saving a new artifact (so a fresh
  `CHANGE`/`RFC`/`SPEC`/… immediately appears in the index).
- **Manual** — run it any time after editing docs by hand:
  ```bash
  node .aai/scripts/generate-docs-index.mjs
  ```
- **Pre-commit hook (opt-in)** — see below. Catches `docs/` edits made *outside*
  intake (manual status changes, validation lifecycle updates, etc.).

#### Docs-index pre-commit hook (opt-in)
**What:** A `.git/hooks/pre-commit` hook that regenerates and stages `docs/INDEX.md`
on every commit that touches `docs/`. Catches `docs/` edits made outside intake
(manual status changes, validation lifecycle updates, etc.).

**Installed automatically by `/aai-update`** on a successful sync — no prompt. This
is safe: the installer is idempotent and will **not** overwrite a pre-existing
non-AAI `pre-commit` hook (it leaves a foreign hook untouched and reports it).
`/aai-doctor` reports its state (category CAT-12). You only need the commands below
to install it manually (e.g. before your first update) or to remove it.

**Install / uninstall:**
```bash
bash .aai/scripts/install-pre-commit-hook.sh            # install (idempotent)
bash .aai/scripts/install-pre-commit-hook.sh --force    # overwrite an existing hook
bash .aai/scripts/install-pre-commit-hook.sh --uninstall # remove the AAI hook
# Windows: .aai/scripts/install-pre-commit-hook.ps1
```
It refuses to overwrite a non-AAI `pre-commit` hook unless you pass `--force`.

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

# 1. Resume or create project discussion thread
/aai-session-journal "User profile and avatar flow"

# 2. Intake
/aai-intake "Add user profile page with avatar upload"
# Creates: docs/requirements/REQ-006-user-profile.md

# 3. Create worktree (optional, for parallel work)
/aai-worktree setup user-profile

# 4. TDD cycle
/aai-tdd
# RED → GREEN → REFACTOR with evidence

# 5. Code review
/aai-code-review
# Checks security, performance, style

# 6. Validate
/aai-validate-report
# Generates report with screenshots

# 7. Share
/aai-share docs/ai/reports/LATEST.md
# Returns: https://aai-reports-xyz.pages.dev

# 8. Cleanup worktree
/aai-worktree cleanup user-profile

# 9. View metrics
/aai-dashboard --publish

# 10. Update project discussion thread and wrap up session
/aai-session-journal "User profile and avatar flow"
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
   - Durable collaboration: decision documents, specs, research findings, project session journals

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

## Leak-safe test execution

A long `/aai-loop` can orphan hung test process trees: `vitest run` does not exit
when a suite leaves open handles, the launching agent's shell call returns with
output captured, but nothing kills the spawned process *group* — so the hung tree
is orphaned and grows unbounded (observed: ~40 trees / ~5.6 GB after a 17-tick
run). AAI closes this with a four-part contract (SPEC-0009). Every
externally-spawned test process must be in a **killable group**, **resource
bounded**, **reaped on the step boundary**, and **accounted for**.

1. **Killable group + timeout — the wrapper.** Run test/build commands through
   `.aai/scripts/aai-run-tests.sh <cmd> [args...]`. It starts a new **process
   group**, runs the command as the group leader, arms an inline timeout
   (`AAI_TEST_TIMEOUT`, default 300s — macOS has no GNU `timeout`), and on every
   exit path TERMs then KILLs the whole group. It returns the command's **real
   exit code**, or **124** on timeout (so a *hung* run is distinguishable from a
   *failed* one). A leaky child that backgrounds work and exits 0 still leaves no
   survivor.

2. **Bounded forks.** When Vitest is detected, `/aai-bootstrap` emits leak-safe
   config guidance — `pool: 'forks'`, `poolOptions.forks.maxForks: 2`,
   `minForks: 1`, `teardownTimeout: 10_000` — bounding a run to ~300–400 MB
   instead of ~1.5 GB. Bootstrap never overwrites an existing Vitest config; you
   apply the guidance yourself.

3. **Scoped reaper — workspace + etime, never global.**
   `.aai/scripts/aai-reap-tests.sh` is a defence-in-depth sweep the loop runs
   after a test-running tick. It kills **only** `vitest`/`esbuild` processes whose
   command line matches the current workspace path (`$PWD`, overridable via
   `AAI_REAP_WORKSPACE`) **and** that are older than the step-start age threshold
   (`AAI_REAP_MIN_AGE_SECS`), so a sibling subagent's in-flight run is never
   killed. It is **never** a bare `pkill -f vitest`.

4. **Tick-log accounting.** The loop records `lingering_procs` (post-reap
   workspace vitest/esbuild count) and `free_memory` in each tick log line, so a
   process or memory leak is visible in `docs/ai/LOOP_TICKS.jsonl` rather than
   growing silently across ticks.

Generated `aai-test-unit` / `aai-test-e2e` skills are already wrapped, and both
`/aai-loop` and validation route discovered test commands through
`.aai/scripts/aai-run-tests.sh` and reap with `.aai/scripts/aai-reap-tests.sh` on
the step boundary.

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
   - human discussion trail -> `docs/project-sessions/`
   - broader write-up -> `docs/archive/analysis/`

---

**Last Updated:** 2026-03-29
**Version:** 1.2
**Status:** Current
