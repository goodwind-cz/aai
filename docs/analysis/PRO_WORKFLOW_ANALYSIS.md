# Pro-Workflow Analysis & AAI Integration Proposal

**Date:** 2026-03-08
**Source:** [rohitg00/pro-workflow](https://github.com/rohitg00/pro-workflow)
**Goal:** Make AI development steps user-friendly, clear, and non-annoying with just the right amount of information

---

## Executive Summary

Pro-workflow emphasizes **checkpoints over chatter** and **learning from corrections** rather than verbose status updates. Key insight: users want *control gates* at decision points, not constant progress reports.

**Recommended AAI improvements:**
1. **Staged checkpoints** in `/aai-loop` (approval gates between phases)
2. **Learning rules** from corrections (persistent memory)
3. **Minimal progress updates** (action-focused, not prose)
4. **Session wrap-up ritual** (capture learnings)
5. **Hook system** for quality gates (pre-commit checks)
6. **Pre-compact context save** (preserve critical state before context compression)
7. **Environment doctor** (`/aai-doctor` diagnostics)
8. **Contextual learning replay** (surface relevant past learnings)

---

## Current AAI Communication Patterns

### What AAI Does Well ✅

1. **Evidence-based validation** - screenshots, test logs, metrics
2. **Structured artifacts** - PRDs, specs, decisions in predictable locations
3. **Clear phase boundaries** - RED→GREEN→REFACTOR, Planning→Implementation→Validation
4. **State transparency** - `STATE.yaml` shows current focus and status

### What Could Be Better ⚠️

1. **Too autonomous** - `/aai-loop` runs 20 ticks without checkpoints
2. **No learning from corrections** - repeated mistakes don't become rules
3. **Verbose in chat** - too much "I will now...", "Let me check..."
4. **No wrap-up ritual** - sessions end without capturing learnings
5. **No pre-action quality gates** - commits happen without final review prompts

---

## Pro-Workflow Patterns to Adopt

### 1. Staged Checkpoints (HIGH PRIORITY)

**Problem:** `/aai-loop` runs autonomously for up to 20 ticks with no human approval between Planning→Implementation→Validation.

**Pro-workflow approach:** "Research > Plan > Implement > Review & Commit with validation gates"

**Proposed AAI Enhancement:**

```yaml
# Add to .aai/SKILL_LOOP.prompt.md

CHECKPOINT_MODE (optional parameter):
  - none: current behavior (autonomous 20 ticks)
  - staged: pause for approval between major phases
  - paranoid: pause after every tick

When checkpoint_mode == "staged":
  1. Run orchestration tick
  2. If dispatched role changes category (Planning→Implementation, Implementation→Validation):
     → PAUSE and output checkpoint approval request
     → User must explicitly approve to continue
  3. Continue with next tick after approval
```

**User-friendly format:**

```
─────────────────────────────────────
CHECKPOINT: Planning → Implementation
─────────────────────────────────────

Planning completed:
• Spec: docs/specs/SPEC-007-user-profile.md
• Test Plan: 8 tests defined (TEST-001..TEST-008)
• Estimate: ~2 TDD cycles

Ready to implement?
[y] Yes, proceed  [n] No, revise plan  [p] Pause loop
─────────────────────────────────────
```

**Benefits:**
- User controls when to proceed between major phases
- Reduces risk of long autonomous runs going off track
- Aligns with pro-workflow's "batch reviews at checkpoints"

---

### 2. Learning Rules (HIGH PRIORITY)

**Problem:** If user corrects a mistake (e.g., "don't use console.log in production code"), AAI doesn't remember for future sessions.

**Pro-workflow approach:** "When corrected, propose rule → add to LEARNED after approval"

**Proposed AAI Enhancement:**

Create `docs/knowledge/LEARNED.md` (project-specific learnings):

```markdown
# Project-Specific Learned Rules

## Code Style
- [2026-03-08] Always use `logger.debug()` instead of `console.log()` (source: user correction)
- [2026-03-07] Prefer named exports over default exports (source: code review)

## Testing
- [2026-03-06] E2E tests must use `playwright-mcp` server, not local Playwright (source: user preference)

## Workflow
- [2026-03-05] Always run `/aai-bootstrap` after adding new npm packages (source: debugging session)
```

**Trigger mechanism:**

When user message contains correction keywords ("don't do X", "use Y instead", "wrong approach"):
1. Detect correction pattern
2. Propose rule in chat: "Should I remember: 'Always use logger.debug() instead of console.log()'?"
3. If approved, append to `docs/knowledge/LEARNED.md` with timestamp and source
4. Future sessions load LEARNED.md in context

**Benefits:**
- Compounding corrections (feedback becomes more valuable over time)
- No repeated mistakes
- Project-specific knowledge persists across sessions

---

### 3. Minimal Progress Updates (MEDIUM PRIORITY)

**Problem:** AAI chat messages are too verbose with "Let me check...", "I will now...", "Processing..."

**Pro-workflow approach:** "Minimal, action-focused notifications" rather than prose updates

**Current AAI (verbose):**

```
Let me check the current state of the repository.
I will now read the STATE.yaml file to see what phase we're in.
I can see that Planning is complete. I will now proceed to run the Implementation phase.
Let me create the test file first...
```

**Proposed AAI (minimal):**

```
✓ State checked → Implementation phase
⚙ Running TDD cycle (TEST-001: password validation)
```

**Guidelines:**

1. **Use symbols** instead of prose:
   - ✓ (completed action)
   - ⚙ (in progress)
   - ⚠ (warning)
   - ✗ (error)
   - ⏸ (paused/waiting)

2. **One-line status** per major action:
   ```
   ⚙ RED phase: writing failing test
   ✓ Test fails as expected → docs/ai/tdd/red-20260308.log
   ⚙ GREEN phase: minimal implementation
   ✓ Test passes → docs/ai/tdd/green-20260308.log
   ⚙ REFACTOR phase: extracting validation logic
   ✓ All tests pass → docs/ai/tdd/refactor-20260308.log
   ```

3. **No "I will..." preambles** - just state what's happening or done

4. **Exception: checkpoints** - these should be verbose and clear

**Benefits:**
- Less noise in chat
- Faster to scan
- Focus on outcomes, not processes

---

### 4. Session Wrap-Up Ritual (MEDIUM PRIORITY)

**Problem:** Sessions end abruptly without capturing what was learned or what's next.

**Pro-workflow approach:** "Structured end-of-session checklist captures learnings"

**Proposed AAI Enhancement:**

Add `/aai-wrap-up` skill:

```markdown
# Wrap-Up Skill

## Goal
Capture learnings and prepare for next session.

## Instructions

1. **Review Current Session**
   - Check `docs/ai/STATE.yaml` for completed work
   - Check `docs/ai/METRICS.jsonl` for latest entries
   - Identify what was accomplished

2. **Capture Learnings**
   ```
   LEARNINGS FROM THIS SESSION
   ───────────────────────────

   Completed:
   • [Feature] User profile page with avatar upload
   • [TDD] 8 tests (TEST-001..TEST-008) → all green
   • [Evidence] Validation report with screenshots

   Challenges:
   • Playwright MCP server connection issues → resolved by restarting
   • Test coverage dropped to 78% → added 2 more edge case tests

   Decisions:
   • Used Cloudflare R2 for avatar storage (see DEC-009)
   • Chose optimistic UI updates for better UX (see DEC-010)

   Next Session:
   • Implement profile editing (REQ-008)
   • Add profile privacy settings
   ```

3. **Suggest New Rules**
   - Review session for patterns
   - Propose additions to `docs/knowledge/LEARNED.md`

4. **Check Uncommitted Work**
   ```bash
   git status
   # If uncommitted work exists, suggest commit or stash
   ```

5. **Update STATE.yaml**
   ```yaml
   last_session:
     ended_utc: 2026-03-08T10:30:00Z
     summary: "User profile feature completed, 8 tests green"
     next_focus: "Profile editing (REQ-008)"
   ```

6. **Output Summary**
   - Show accomplishments
   - Show next steps
   - Prompt user to commit/push if needed
```

**Auto-trigger on session end:**
- Detect session end (user says "bye", "done", "that's all")
- Automatically run wrap-up ritual
- Save session log to `docs/ai/sessions/SESSION-<timestamp>.md`

**Benefits:**
- Clear session boundaries
- Learnings captured systematically
- Easy to resume next session

---

### 5. Quality Gate Hooks (MEDIUM PRIORITY)

**Problem:** No reminders before risky actions (commits, pushes, destructive operations).

**Pro-workflow approach:** "PreToolUse hooks for quality gate reminders before edits/commits"

**Proposed AAI Enhancement:**

Add quality gate checks to commit operations:

```markdown
# Pre-Commit Quality Gates

Before running `git commit`, check:

1. **TDD Evidence Complete?**
   - If STATE.yaml shows incomplete TDD cycle (missing red/green/refactor evidence)
   - Warn: "⚠ TDD cycle incomplete - missing REFACTOR evidence. Continue commit? [y/n]"

2. **Tests Passing?**
   - Run test suite
   - If any tests fail, BLOCK commit
   - Error: "✗ Cannot commit - 3 tests failing. Fix tests first."

3. **Validation Done?**
   - Check if validation report exists for current work item
   - Warn: "⚠ No validation report found. Run `/aai-validate-report` first? [y/n]"

4. **Secrets Check?**
   - Scan staged files for common secret patterns (API keys, tokens, passwords)
   - If found, BLOCK commit
   - Error: "✗ Potential secrets detected in src/config.ts:12 - review before commit"

5. **Debug Statements?**
   - Scan for `console.log`, `debugger`, `TODO`, `FIXME` in staged files
   - Warn: "⚠ Found 2 console.log statements. Remove before commit? [y/n]"
```

**Hook integration:**

- Run these checks automatically before any commit in `/aai-tdd`, `/aai-loop`, `/aai-validate-report`
- User can override warnings (not errors)
- Errors block commit until resolved

**Benefits:**
- Prevents common mistakes
- Enforces quality standards
- Catches issues before they're committed

---

### 6. Pre-Compact Context Save (HIGH PRIORITY)

**Problem:** When Claude Code compresses prior messages to stay within context limits, critical state information (current decisions, in-progress reasoning, uncommitted insights) can be lost. Long sessions suffer most.

**Pro-workflow approach:** A `pre-compact` hook script that saves session state to a file before compression occurs, ensuring continuity.

**Proposed AAI Enhancement:**

Create a pre-compact hook that automatically saves critical context:

```bash
# .aai/scripts/pre-compact-save.sh
# Triggered before context compression

# Save snapshot of current state
cp docs/ai/STATE.yaml docs/ai/.pre-compact-state-backup.yaml

# Capture session context summary
cat > docs/ai/.session-context.md << 'CONTEXT'
# Pre-Compact Context Snapshot
# Auto-generated - read this after context compression

## Current State
$(cat docs/ai/STATE.yaml)

## Recent Decisions
$(tail -5 docs/ai/decisions.jsonl)

## Recent Metrics
$(tail -3 docs/ai/METRICS.jsonl)
CONTEXT
```

**Integration:** Configure as Claude Code hook in `.claude/settings.local.json`:
```json
{
  "hooks": {
    "PreCompact": [
      { "command": "bash .aai/scripts/pre-compact-save.sh" }
    ]
  }
}
```

**Benefits:**
- No lost context during long sessions
- Automatic — no user action needed
- State continuity across context compressions
- Critical decisions preserved even when messages are compressed

---

### 7. Environment Doctor (MEDIUM PRIORITY)

**Problem:** AAI has many moving parts (STATE.yaml, prompt files, skills, scripts, MCP servers, knowledge files). When something is misconfigured or missing, failures are cryptic.

**Pro-workflow approach:** `/doctor` command that diagnoses configuration and environment health.

**Proposed AAI Enhancement:**

Create `/aai-doctor` skill that performs comprehensive health checks:

```
AAI ENVIRONMENT HEALTH CHECK
─────────────────────────────

Core Files:
  ✓ .aai/AGENTS.md exists
  ✓ .aai/PLAYBOOK.md exists
  ✓ docs/ai/STATE.yaml exists and valid YAML
  ✗ docs/TECHNOLOGY.md missing — run /aai-intake first

Skills:
  ✓ 18/18 universal skills have SKILL.md
  ✓ 18/18 skill prompts (.aai/SKILL_*.prompt.md) exist
  ⚠ 0 dynamic skills — run /aai-bootstrap to generate

Knowledge:
  ✓ docs/knowledge/FACTS.md exists
  ⚠ docs/knowledge/PATTERNS.md empty (0 patterns)
  ✓ docs/knowledge/UI_MAP.md exists

State:
  ✓ STATE.yaml passes INV-01..INV-10
  ✓ No stale locks
  ⚠ No active work items

Git:
  ✓ Clean working tree
  ✓ On branch: main
  ⚠ 2 untracked files in docs/analysis/

Overall: HEALTHY (2 warnings)
```

**Difference from `/aai-check-state`:**
- `/aai-check-state` validates only STATE.yaml invariants
- `/aai-doctor` checks the entire environment: files, skills, git, knowledge, dependencies

**Benefits:**
- Fast diagnosis when something breaks
- Onboarding — new users can verify setup
- Proactive detection of missing or broken components

---

### 8. Contextual Learning Replay (MEDIUM PRIORITY)

**Problem:** Even with LEARNED.md, all learnings are loaded into context regardless of relevance. As the file grows, this wastes context window and dilutes signal.

**Pro-workflow approach:** `/replay` command that searches the learning database and surfaces only learnings relevant to the current task context.

**Proposed AAI Enhancement:**

Create `/aai-replay` skill that:

1. Reads current context (STATE.yaml focus, active work items, recent files)
2. Searches knowledge files (FACTS.md, PATTERNS.md, LEARNED.md, decisions.jsonl)
3. Surfaces only relevant entries

```
RELEVANT LEARNINGS FOR: REQ-010 (password reset)
─────────────────────────────────────────────────

From LEARNED.md:
  • [2026-03-06] Always test token expiry edge cases for auth features
  • [2026-03-05] Use bcrypt for password hashing, never SHA-256

From PATTERNS.md:
  • Auth endpoints: always rate-limit to 5 req/min per IP
  • Email sending: use queue, never synchronous in request handler

From Decisions:
  • DEC-005: Chose JWT for session tokens (2026-03-04)

No matches in FACTS.md.
─────────────────────────────────────────────────
3 learnings, 2 patterns, 1 decision surfaced
```

**Search strategy:**
- Extract keywords from current work item (requirement title, spec, test names)
- Full-text search across knowledge files
- Rank by relevance and recency
- Show top N most relevant (default: 10)

**Auto-trigger option:**
- Run automatically at start of Implementation phase in `/aai-loop`
- Ensures relevant past learnings inform current work

**Benefits:**
- Context-aware — only relevant learnings shown
- Scales with growing knowledge base
- Prevents repeating past mistakes on similar tasks
- Works with existing knowledge files (no new database needed)

---

## Implementation Plan

### Phase 1: Quick Wins ✅ IMPLEMENTED

1. **Minimal Progress Updates** ✅
   - Updated `.aai/AGENTS.md` with communication guidelines and symbol guide
   - Added rules: no preambles, one-line status, symbols over prose

2. **Pre-Commit Quality Gates** ✅
   - Created `.aai/scripts/pre-commit-checks.sh` and `.ps1`
   - Checks: secrets, debug statements, TODO/FIXME, TDD evidence, validation reports
   - Supports `--strict` mode; integrated into AGENTS.md skill guidance

### Phase 2: Learning System ✅ IMPLEMENTED

3. **Learning Rules** ✅
   - Created `docs/knowledge/LEARNED.md` template with categorized sections
   - Added to CLAUDE.md canonical sources and AGENTS.md canonical sources
   - Added correction detection guidance to AGENTS.md

4. **Session Wrap-Up** ✅
   - Created `/aai-wrap-up` skill (SKILL.md + SKILL_WRAP_UP.prompt.md)
   - Captures learnings, proposes rules, checks uncommitted work, prepares next session
   - Auto-trigger patterns documented for session end detection

### Phase 3: Resilience & Diagnostics (3-5 days)

5. **Pre-Compact Context Save** ✅ IMPLEMENTED
   - Created `.aai/scripts/pre-compact-save.sh` and `.ps1`
   - Saves STATE.yaml snapshot + recent decisions/metrics before compression
   - Hook configuration ready for `.claude/settings.local.json`

6. **Environment Doctor** ✅ IMPLEMENTED
   - Created `/aai-doctor` skill
   - Checks: core files, skills, knowledge, STATE.yaml, git status
   - Reports HEALTHY / DEGRADED / BROKEN with actionable warnings

7. **Contextual Learning Replay** ✅ IMPLEMENTED
   - Created `/aai-replay` skill
   - Searches LEARNED.md, PATTERNS.md, FACTS.md, decisions.jsonl
   - Surfaces only relevant learnings for current work context

### Phase 4: Checkpoints ✅ IMPLEMENTED

8. **Staged Checkpoints** ✅
   - Updated `.aai/SKILL_LOOP.prompt.md` with checkpoint_mode parameter (none/staged/paranoid)
   - Added checkpoint output format with [y/n/p] approval gates
   - Role category tracking for phase transitions

---

## Migration Guide

### For Existing AAI Users

**No breaking changes** - all improvements are additive or opt-in:

1. **Staged checkpoints**: opt-in via parameter
   ```bash
   /aai-loop --checkpoints staged
   ```

2. **Learning rules**: automatic, but requires user approval per rule

3. **Minimal updates**: automatic in new skills, gradually rolled out

4. **Wrap-up ritual**: manual via `/aai-wrap-up` or auto-triggered

5. **Quality gates**: automatic, but can be overridden

**Recommended adoption:**
- Start with quality gates (Phase 1)
- Add wrap-up ritual to end of sessions
- Try staged checkpoints on next feature
- Build up LEARNED.md over 2-3 sessions

---

## Metrics & Success Criteria

### User Satisfaction

- **Reduced chat noise**: Measure lines of chat per work item (target: -40%)
- **Fewer repeated mistakes**: Track correction frequency (target: -70% after 5 sessions)
- **Clearer progress**: Survey users on clarity (target: >8/10)

### Efficiency

- **Checkpoint value**: % of checkpoints where user changes plan (target: >20% = useful)
- **Quality gate catches**: # of issues caught before commit (track baseline)
- **Session continuity**: % of sessions resumed from previous learnings (target: >80%)

---

## Example: Before & After

### Before (Current AAI)

```
User: Add password reset feature
AI: Let me check the current repository state.
AI: I can see from STATE.yaml that we're ready to start new work.
AI: I will now run the intake process to create a requirement document.
AI: Creating requirement document...
AI: ✓ Created REQ-010-password-reset.md
AI: Now I'll run the autonomous loop.
AI: Reading STATE.yaml...
AI: Dispatching Planning role...
AI: Planning completed. Created spec with 12 tests.
AI: Dispatching Implementation role...
AI: Running TDD cycle for TEST-001...
AI: Writing failing test for email validation...
AI: Test created and verified to fail.
AI: Now implementing minimal solution...
AI: Implementation complete, test passes.
AI: Now refactoring for code quality...
AI: Refactoring complete, all tests pass.
AI: Running TDD cycle for TEST-002...
[... 10 more similar iterations ...]
AI: All tests complete. Running validation...
AI: Validation passed! Generated report.
AI: Loop complete.

** User sees 40+ lines of chat for single feature **
```

### After (Pro-Workflow Enhanced AAI)

```
User: Add password reset feature

AI: ⚙ Intake → REQ-010 created
AI: ⚙ Loop starting (staged checkpoints enabled)

─────────────────────────────────────
CHECKPOINT: Intake → Planning
─────────────────────────────────────
Requirement: REQ-010-password-reset.md
Acceptance criteria: 5 items

Proceed to planning? [y/n]: y

AI: ⚙ Planning
AI: ✓ Spec created → docs/specs/SPEC-010.md
AI: ✓ Test plan: 12 tests (TEST-001..TEST-012)

─────────────────────────────────────
CHECKPOINT: Planning → Implementation
─────────────────────────────────────
Spec: SPEC-010-password-reset.md
Tests: 12 (email validation, token expiry, security checks)
Estimated: 3 TDD cycles

Proceed to implement? [y/n]: y

AI: ⚙ TDD cycles (TEST-001..TEST-012)
AI: ✓ Cycle 1: RED→GREEN→REFACTOR (4 tests)
AI: ✓ Cycle 2: RED→GREEN→REFACTOR (4 tests)
AI: ✓ Cycle 3: RED→GREEN→REFACTOR (4 tests)

─────────────────────────────────────
PRE-COMMIT QUALITY GATE
─────────────────────────────────────
✓ TDD evidence complete
✓ All 12 tests passing
⚠ Found 1 console.log in src/auth/reset.ts:45
  Remove before commit? [y/n]: y
✓ Debug statements removed
✓ No secrets detected

AI: ✓ Committed: feat: password reset with email token

─────────────────────────────────────
CHECKPOINT: Implementation → Validation
─────────────────────────────────────
Implementation: 12 tests green
Ready for validation? [y/n]: y

AI: ⚙ Validation
AI: ✓ Screenshots captured (3)
AI: ✓ Report generated
AI: ✓ All acceptance criteria met

─────────────────────────────────────
LOOP COMPLETE
─────────────────────────────────────
Feature: Password reset
Status: ✓ PASS
Evidence: docs/ai/reports/VALIDATION_REPORT_20260308T103000Z.md

** User sees 15 lines with 4 decision points **

** Wrap-up ritual **

AI: Session wrap-up?

LEARNINGS FROM THIS SESSION
───────────────────────────
Completed:
• Password reset feature (REQ-010, SPEC-010)
• 12 tests → all green
• Validation report with 3 screenshots

Challenges:
• Token expiry edge case needed extra test (TEST-009)

Decisions:
• Used 1-hour token expiry (see DEC-011)
• Email templates stored in database for flexibility

Should I remember:
"Always test token expiry edge cases for auth features"?
[y/n]: y

AI: ✓ Added to docs/knowledge/LEARNED.md

Next session:
• Implement profile editing (REQ-008 pending)

Uncommitted work: none
Ready to push? [y/n]
```

**Comparison:**
- **Chat lines**: 40+ → 15 (62% reduction)
- **Decision points**: 0 → 4 (staged control)
- **Learning captured**: no → yes (persistent rule)
- **Session closure**: abrupt → structured
- **Quality gates**: none → 5 checks

---

## Conclusion

**Pro-workflow teaches us:**
1. Users want *control* at decision points, not constant updates
2. Corrections should become *learnings*, not repeated mistakes
3. Progress updates should be *minimal* and action-focused
4. Sessions should *close deliberately*, capturing insights

**Recommended AAI adoption priority:**
1. **HIGH**: Staged checkpoints, Learning rules, Pre-compact context save
2. **MEDIUM**: Minimal progress updates, Session wrap-up, Quality gates, Environment doctor, Contextual learning replay
3. **LOW**: Hook system customization

**Implementation effort:** 2-3 weeks (phased rollout)

**Expected impact:**
- 40-60% reduction in chat noise
- 70%+ reduction in repeated mistakes
- Clearer user control over autonomous processes
- Better session-to-session continuity

---

**Next Step:** Implement Phase 1 (Quick Wins) in new feature branch `feature/pro-workflow-ux`
