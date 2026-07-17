# AAI User Guide

Complete guide for using AAI (Autonomous AI) skills in your projects.

## Table of Contents

- [Getting Started](#getting-started)
- [Quick Reference](#quick-reference)
- [Skills Catalog](#skills-catalog)
- [Workflows](#workflows)
- [Best Practices](#best-practices)
- [Leak-safe test execution](#leak-safe-test-execution)
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
| `/aai-test-canon` | Test consolidation | Fragmented tests → canonical per-domain suites + RED stubs for gaps |
| `/aai-pr` | Open a PR | Scope-only staging, staged-vs-scope audit, PR body; never merges |
| `/aai-profile` | Optimize | Performance analysis |
| `/aai-auto-trigger` | Deprecated | No runtime consumer — use wrapper-description trigger phrases |

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

#### `/aai-pr`
**What:** PR ceremony (SPEC-0013). Turns a validated, review-passed scope into
a pushed branch and an opened pull request — with scope-only staging and a
hard merge boundary. It **never merges**; merging is an operator-only action.

**When to use:**
- After validation PASS and code review pass/waived, when the scope is ready
  to leave the working tree
- As the closing step of a loop-driven feature (the loop ends with an open PR)

**Example:**
```bash
/aai-pr

# 1. Derives the in-scope file list from STATE.yaml + the frozen spec
#    (code_review.scope, worktree.inline_review_scope, spec Links)
# 2. Stages ONLY in-scope paths — git add <path> per file
# 3. Staged-vs-scope audit: git diff --cached --name-only must equal the
#    scope list (plus expected companions: docs/INDEX.md, review reports,
#    CHANGELOG.md) or it ABORTS and resets the offenders
# 4. Adds a CHANGELOG.md entry for feat/fix scopes
# 5. Conventional commit referencing the ref id, push, gh pr create
#    with the PR body template (Summary / Scope / Spec-AC table /
#    Review status / Test evidence / Links)
# 6. Reports the PR URL and STOPS
```

**What it refuses to do:**
- `git add -A`, `git add .`, `git commit -a` — forbidden (that is exactly how
  unrelated in-flight files end up in a feature commit)
- Commit before validation PASS + review pass/waived + your explicit
  confirmation
- `gh pr merge`, PR approval, or auto-merge — merging is yours, after your
  own review
- Force-push or history rewrites of a pushed branch

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
/aai-code-review                   # Review local changes (clean diff scope)
/aai-code-review --pr 42           # Review a GitHub PR's diff
```

**One pass, two verdicts (SPEC single-dual-verdict-review):**
- spec_compliance: pass|fail — diff vs the frozen AC table, per-AC citations
- code_quality: pass|fail — real defects with file:line + failure scenario
- cannot_verify: mandatory list of claims the diff alone cannot substantiate

**Finding severity:**
- BLOCKING: must fix before merge (fails the verdict)
- NON-BLOCKING: needs a disposition (remediate or promote — warnings policy)

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
node .aai/scripts/docs-audit.mjs --gate SPEC-0011    # close-time gate (below)
node .aai/scripts/docs-audit.mjs --lint-body         # body-lint digest (below)
```

**Close-time gate (`--gate <DOC-ID>`, SPEC-0011):** an offline structural
predicate over one doc's AC Status table, run **before** a `status: done`
flip. It fails (exit 1) on: missing AC Status table, a non-terminal row, a
done row with empty Evidence, or an invalid Review-By method. Exit 0 = pass,
exit 2 = the id resolves to no scanned doc. The loop runs it automatically
(VALIDATION done-flip, METRICS_FLUSH, wrap-up advisory, and the implementer's
pre-handoff self-check); run it yourself before hand-closing a doc:
```bash
node .aai/scripts/docs-audit.mjs --gate CHANGE-0007
# GATE PASS: AC Status table complete ...        (exit 0)
# GATE FAIL — the AC Status table is not reconciled:   (exit 1, reasons listed)
```
`--gate-file <file>` gates an explicit file path instead of resolving by id —
this is what the pre-commit hook uses on the materialized STAGED blob, so a
clean worktree copy cannot mask a dirty staged one.

**Body lint (`--lint-body`, SPEC-0013):** three rules over governed docs —
stray tool markup (`</content>`, `<result>` and friends), unbalanced code
fences (a fence still open at EOF), and leftover template placeholders.
Fenced blocks and inline code spans are masked first, so documentation that
*quotes* such markup (like this guide) is never flagged. Report-only by
default; `--strict` promotes findings to exit 1. `--lint-body-file <file>` is
the pure single-file predicate (exit 1 findings / 0 clean / 2 unreadable),
again used by the pre-commit hook against staged content.

**What the audit now reports** (report-only verdicts, never hard-fail):
- `missing-close-telemetry` — a done doc with no `work_item_closed` close
  event in EVENTS.jsonl (close events — `work_item_closed`,
  `code_review_completed` — are appended via `append-event.mjs` at closeout)
- `review-claim-unbacked` — a `Review-By: code-review` claim with no
  corroborating event or report artifact
- near-miss AC table WARNING — an almost-canonical table (e.g.
  `Evidence (TEST)` columns, non-canonical headings) is called out explicitly
  instead of being silently misread

**Reading the verdicts:**
- `tracked-done` — doc says done and evidence agrees (implemented)
- `tracked-open` — legitimately in progress (draft/implementing/frozen)
- `probable-false-done` — doc claims done, evidence disagrees
- `probable-stale-open` — open doc untouched past `stale_after_days`;
  possibly shipped elsewhere and never closed
- `probable-false-open` — open doc (draft/implementing/accepted) whose
  delivery is already evidenced (a later feat/fix/chore commit mentioning it,
  an `ac_evidence` event, or a fully terminal evidenced AC table); confirm
  delivery, then run the close ceremony
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
close_gate: report-only         # report-only | enforce — pre-commit hook
                                # behavior when a STAGED status:done flip
                                # fails --gate-file: warn vs abort commit
body_lint: report-only          # report-only | enforce — same for staged
                                # governed docs failing --lint-body-file
```

The two gate keys are consulted by the **callers** (the AAI pre-commit hook
and the closeout skills), not by the script — `--gate`/`--lint-body-file`
always return the raw predicate exit code. Under `report-only` (the default,
also when the key or file is absent) the hook prints a warning and lets the
commit through; under `enforce` it aborts the commit. Either way the hook
checks the **staged blob**, not your worktree.

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

#### `/aai-test-canon`

The test-side twin of `/aai-docs-canon` (RFC-0006 / SPEC-0008). Consolidates
tests fragmented per-change/issue (scattered across `tests/skills/`,
`tests/self-hosting/`, ...) into a single canonical "current state" suite per
functional domain in `tests/canonical/`, anchored on the approved docs-canon
domain map. Use it when no single suite answers "what does this feature's
test coverage look like today".

**Two phases (human gate between them):**
```bash
# Phase 1 — analyze + propose (writes nothing under tests/canonical|_archive)
node .aai/scripts/test-canon.mjs --phase1
#   builds a traceability matrix (test -> domain), emits a coverage-gap report
#   (acceptance criteria with no covering test), proposes a per-domain test
#   map, and HALTS. Review docs/ai/test-canon.proposal.json, then persist an
#   approved map to docs/ai/test-canon.map.json with "approved": true.

# Phase 2 — consolidate + canonicalize (only on an approved map)
node .aai/scripts/test-canon.mjs --phase2
#   consolidates each domain's tests into tests/canonical/<domain>.sh, MOVES
#   originals (tracked git move) to tests/_archive/ with a back-link, and
#   scaffolds a failing/pending RED stub for each uncovered acceptance
#   criterion — hand-off to /aai-tdd for GREEN. Verifies the canonical suite
#   still runs via existing runners BEFORE archiving; aborts otherwise.

# Re-run drift check / resolution
node .aai/scripts/test-canon.mjs --drift            # report drifted domains
node .aai/scripts/test-canon.mjs --phase2 --resync  # re-synthesize drifted domains
```

**What it guarantees:**
- Domain boundaries are human-approved (HITL gate); the mechanical
  consolidation is automated.
- Originals are never destroyed — moved to `tests/_archive/` with a
  `# Canonical:` forward pointer.
- Phase 2 never implements GREEN — uncovered criteria become RED stubs and go
  to `/aai-tdd`.
- Tests it cannot confidently map land in an `unclear` bucket and stay in
  place until you assign a domain.
- Re-runs are idempotent: unchanged domains are skipped; changed sources are
  reported as DRIFT and never silently overwritten (`--resync` resolves
  deliberately).

If `docs/canonical/` is absent (docs-canon has not run), Phase 1 degrades
gracefully and maps against raw `docs/` instead of blocking.

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

#### `/aai-auto-trigger` (deprecated)
**What:** DEPRECATED — the `.claude/triggers.json` mechanism this skill
configured has no runtime consumer, so triggers wired there never fire
(grep-proven in SPEC-0013 D8). Invoking it now explains the deprecation.

**Instead:** put trigger phrases directly into the target skill wrapper's
`description:` frontmatter (`.claude/skills/<name>/SKILL.md` plus the
`.codex`/`.gemini` mirrors) — that is the channel native skill-matching
actually reads. Example: the `aai-wrap-up` wrapper carries "wrap up",
"end session", "done for today", "hotovo", "konec", "bye" in its description.

Full notice: `.aai/SKILL_AUTO_TRIGGER.prompt.md`.

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

#### Runtime state CLI (`state.mjs`)
**What:** `.aai/scripts/state.mjs` is the transactional writer for
`docs/ai/STATE.yaml` (SPEC-0012). All loop roles (Planning, Implementation,
Validation, Remediation, TDD, Orchestration, Metrics Flush) now mutate state
through its closed-set subcommands instead of free-text YAML edits: atomic
tmp+rename writes, integrity refusal on a corrupt STATE (exit 1), enum
validation, and comment/key-order-preserving edits.

**When you would touch it:** normally never — the loop drives it. Operator
cases: a manual HITL fix (answering a blocked question by hand), unblocking a
wedged verdict during a hand-driven remediation, or scripted inspection/setup.
Examples:
```bash
# Clear a human-input block by hand (what /aai-hitl does under the hood)
node .aai/scripts/state.mjs set-human-input --required false

# Reset a FAILED verdict block for re-validation
node .aai/scripts/state.mjs reset-block last_validation
# A pass/waived verdict is guarded — the command REFUSES to clobber it:
node .aai/scripts/state.mjs reset-block code_review
# state: reset-block: REFUSED — code_review.status is "pass" (not fail) ...
node .aai/scripts/state.mjs reset-block code_review --force   # explicit human decision only

# Record a strategy decision made outside the loop
node .aai/scripts/state.mjs set-strategy --selected tdd --rationale "operator call"
```
(`log-tick` also exists but is loop-internal — it appends to
`docs/ai/LOOP_TICKS.jsonl` and never touches STATE.)

**Strict flags:** every subcommand rejects flags outside its declared set — a
misspelled `--evidnce` fails loud with exit 2 and prints the valid set,
instead of silently dropping your data. Exit contract: 0 success (including
idempotent no-ops), 1 integrity refusal (file preserved byte-identical),
2 usage/validation error before any write.

**Rule:** never hand-edit `STATE.yaml`. If you absolutely must, run
`node .aai/scripts/check-state.mjs` afterwards (or `/aai-check-state`, with
`REPAIR:` prefix to auto-fix) before the next loop tick.

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

#### Self-hosting contract and smoke tests
**What:** AAI develops itself with AAI. The ownership model separates three
layers so sync never clobbers project content:

- **Canonical authoring layer** (vendored, sync-managed): `.aai/*.prompt.md`, `.aai/templates/*`, `.aai/system/*`, `.aai/scripts/*`.
- **Project-generated layer** (project-owned, never overwritten): `docs/TECHNOLOGY.md`, `docs/requirements/*`, `docs/specs/*`, `docs/decisions/*`, `docs/knowledge/*`, `docs/project-sessions/*`.
- **Runtime layer** (machine-written): `docs/ai/STATE.yaml`, `docs/ai/*.jsonl`, `docs/ai/reports/**`.

See `.aai/system/SELF_HOSTING.md` for the full contract and
`tests/fixtures/target-project/` for the disposable sync fixture.

**Verify packaging (canonical repo only):**
```bash
bash tests/self-hosting/test-self-hosting-smoke.sh
# or:
powershell -ExecutionPolicy Bypass -File tests/self-hosting/test-self-hosting-smoke.ps1
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

# 7. Open the pull request
/aai-pr
# Scope-only staging + staged-vs-scope audit + gh pr create
# Reports the PR URL and stops — YOU merge it after your own review

# 8. Share
/aai-share docs/ai/reports/LATEST.md
# Returns: https://aai-reports-xyz.pages.dev

# 9. Cleanup worktree (after the PR is merged)
/aai-worktree cleanup user-profile

# 10. View metrics
/aai-dashboard --publish

# 11. Update project discussion thread and wrap up session
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
# 1. Start autonomous loop
/aai-loop

# 2. Monitor progress
/aai-check-state

# 3. Resolve human decisions if needed
/aai-hitl

# 4. Loop completes automatically
# A finished scope ends with an OPEN pull request (/aai-pr ceremony) —
# the loop never merges; merging is your action after your own review.
```

### Shell loop runners (autonomous-loop.sh / .ps1)

`/aai-loop` is the preferred way to run the loop inside a capable agent
session. When you instead want to drive an agent CLI externally (repeated
one-shot invocations from a shell), use the helper scripts
`.aai/scripts/autonomous-loop.sh` / `.aai/scripts/autonomous-loop.ps1`. They
run repeated autonomous ticks until a stop condition:

- `project_status=paused`
- `human_input.required=true`
- `last_validation.status=pass`

Default behavior is **skill-first**: each tick runs
`.aai/SKILL_CHECK_STATE.prompt.md`, then `.aai/SKILL_INTAKE.prompt.md`, then
`.aai/SKILL_LOOP.prompt.md`. Legacy orchestration-only behavior is available
via `legacy` mode with a custom one-tick command.

Bash:

```bash
./.aai/scripts/autonomous-loop.sh \
  --mode skill \
  --agent-command "codex" \
  --max-iterations 20 \
  --sleep-seconds 1 \
  --auto-init-state
```

PowerShell (`-AgentCommand` accepts `codex`, `claude`, or `gemini`):

```powershell
.\.aai\scripts\autonomous-loop.ps1 `
  -Mode skill `
  -AgentCommand 'codex' `
  -MaxIterations 20 `
  -SleepSeconds 1 `
  -AutoInitState

# Legacy mode (custom one-tick command)
.\.aai\scripts\autonomous-loop.ps1 `
  -Mode legacy `
  -TickCommand 'codex --prompt-file .aai/ORCHESTRATION.prompt.md' `
  -MaxIterations 20 `
  -SleepSeconds 1 `
  -AutoInitState
```

Notes:

- PyYAML is auto-installed if missing (PowerShell); use `-NoAutoInstallPyYaml` to disable.
- In `skill` mode the script checks `.claude/skills/AAI_DYNAMIC_SKILLS.md` as a bootstrap marker; use `-SkipBootstrapCheck` / `--skip-bootstrap-check` only when you intentionally skip dynamic-skills bootstrap.
- Use `-DryRun` (PowerShell) or `--dry-run` (Bash) to verify loop behavior without executing the agent command.
- Validate skill readiness and evidence with `.aai/scripts/validate-skills.sh` / `.aai/scripts/validate-skills.ps1`.

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
- `/aai-auto-trigger` - Deprecated (use wrapper-description trigger phrases)

### Token Optimization

1. **Use `/aai-bootstrap` first**
   - Generates optimized project-specific skills
   - 90% token reduction for common tasks

2. **Prefer wrapper-description trigger phrases**
   - Enrich a skill wrapper's `description:` with the phrases users actually say
   - Example: the `aai-wrap-up` wrapper auto-invokes on "wrap up" / "end session"

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

3. **Standardize with shared wrapper trigger phrases**
   - Team-wide phrases in the skill wrapper descriptions
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

4. **Warnings have teeth**
   - A code-review PASS with WARNINGs is not a free pass: every WARNING must
     be either remediated or recorded as an explicit decision
     (decisions.jsonl / a follow-up ref). `/aai-wrap-up` surfaces any
     unrecorded ones, so they cannot silently evaporate at session end.
   - Implementers reconcile the spec's AC-Status table and run
     `docs-audit.mjs --gate <DOC-ID>` as a self-check **before** handing off
     to validation — this is why validations now tend to pass first-try
     instead of bouncing on unreconciled tables (SPEC-0011/SPEC-0012).

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

### FAQ

**Q: Can I add another workflow doc?**
A: No. Only `.aai/workflow/WORKFLOW.md` is canonical; no other document may
redefine or summarize the workflow.

**Q: Where do I list technologies? Can I assume them?**
A: `docs/TECHNOLOGY.md` is the authoritative technology contract (created and
updated by the tech prompts). Never assume technologies — consult it first.

**Q: Where should older analyses go?**
A: Move them to `docs/archive/analysis/` and treat them as immutable; do not
extend archived analyses.

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
3. **Add trigger phrases to the skill wrappers your team uses most**
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

**Last Updated:** 2026-07-06
**Version:** 1.4
**Status:** Current
