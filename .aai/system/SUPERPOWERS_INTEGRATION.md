# Superpowers Integration

## Overview

AAI has integrated proven patterns from the [Superpowers framework](https://github.com/obra/superpowers), a systematic approach to agent-driven development that emphasizes test-driven development, task decomposition, and evidence-based completion.

## What We Adopted from Superpowers

### 1. Mandatory TDD Cycles (`/aai-tdd`)

**Superpowers Concept:**
- Enforced RED-GREEN-REFACTOR workflow
- Code deletion before test writing
- Evidence at each phase

**AAI Implementation:**
- `/aai-tdd` skill enforces 3-phase cycle
- Evidence stored in `docs/ai/tdd/`
- STATE.yaml tracks current TDD phase
- Hard blocks prevent skipping phases

**Benefits:**
- Ensures tests actually test new behavior (RED verification)
- Prevents over-engineering (minimal GREEN)
- Maintains code quality (REFACTOR with tests)

### 2. Git Worktrees for Parallel Development (`/aai-worktree`)

**Superpowers Concept:**
- Isolated development contexts
- No branch switching overhead
- Parallel subagent execution

**AAI Implementation:**
- `/aai-worktree` skill manages worktree lifecycle
- Each worktree has isolated STATE.yaml
- Parallel development without conflicts
- Automatic cleanup after merge

**Benefits:**
- Multiple features in parallel
- Clean context per task
- Faster switching (cd vs git checkout)

### 3. Task Decomposition (2-5 minute chunks)

**Superpowers Concept:**
- Break work into 2-5 minute tasks
- Prevents context explosion
- Enables better progress tracking

**AAI Implementation:**
- Enhanced `PLANNING.prompt.md` with chunking rules
- Tasks must have clear completion criteria
- If task > 5 minutes, auto-decompose further

**Benefits:**
- Reduced cognitive load
- Clear progress indicators
- Better parallelization

### 4. Two-Stage Code Review

**Superpowers Concept:**
- Stage 1: Spec compliance (blocking)
- Stage 2: Code quality (non-blocking warnings)

**AAI Implementation:**
- Enhanced `/aai-validate-report` with two stages
- Spec violations block completion
- Quality issues logged as techdebt

**Benefits:**
- Ensures requirements met
- Allows pragmatic quality trade-offs
- Tracks technical debt

## Comparison: Superpowers vs AAI

| Aspect | Superpowers | AAI | Integration |
|--------|-------------|-------|-------------|
| **Workflow** | 7-phase (Brainstorm→Plan→Execute→Test→Review→Finalize) | 4-phase (Intake→Planning→Implementation→Validation) | Unified 5-phase |
| **TDD** | Mandatory RED-GREEN-REFACTOR | Optional VALIDATION phase | Now mandatory via `/aai-tdd` |
| **Parallelism** | Git worktrees | Subagent orchestration | Combined: worktrees + subagents |
| **Evidence** | Git artifacts, test results | JSONL logs, STATE.yaml | Both: TDD logs + metrics |
| **Task Size** | 2-5 minute chunks | Role-based phases | Chunking added to PLANNING |
| **Triggers** | Auto-activation by conditions | Explicit skill invocation | Future: auto-triggers |

## Unified Workflow

### Option 1: TDD-First Feature Development

```
User: "Add password reset feature"

1. /aai-intake
   → Creates: docs/requirements/REQ-005-password-reset.md

2. /aai-planning
   → Breaks into 2-5 min tasks:
     - Task 1: Create password reset model (3 min)
     - Task 2: Add reset token generation (2 min)
     - Task 3: Implement reset endpoint (4 min)
     - Task 4: Add email notification (5 min)

3. /aai-worktree setup password-reset
   → Creates isolated worktree: ../app-feature-password-reset

4. For each task: /aai-tdd
   → RED: Write failing test
   → GREEN: Minimal implementation
   → REFACTOR: Improve quality

5. /aai-validate-report
   → Stage 1: Verify all acceptance criteria met
   → Stage 2: Code quality check

6. /aai-worktree cleanup password-reset
   → Merge and remove worktree
```

### Option 2: Parallel Development with Worktrees

```
User: "Work on login and profile in parallel"

1. Main agent orchestrates:
   /aai-worktree setup login
   /aai-worktree setup profile

2. Spawn subagent for login:
   cd ../app-feature-login
   /aai-intake "JWT-based login"
   /aai-tdd (RED-GREEN-REFACTOR)

3. Spawn subagent for profile:
   cd ../app-feature-profile
   /aai-intake "User profile page"
   /aai-tdd (RED-GREEN-REFACTOR)

4. Both subagents work independently
   → No conflicts (isolated worktrees)
   → No context pollution (separate STATE.yaml)

5. Cleanup after completion:
   /aai-worktree cleanup login
   /aai-worktree cleanup profile
```

## New Skills Added

### `/aai-tdd` - Test-Driven Development

**Usage:**
```bash
/aai-tdd
```

**Phases:**
1. RED - Write failing test
2. GREEN - Minimal implementation
3. REFACTOR - Improve code quality

**Evidence:**
- `docs/ai/tdd/red-[timestamp].log`
- `docs/ai/tdd/green-[timestamp].log`
- `docs/ai/tdd/refactor-[timestamp].log`

**STATE.yaml Integration:**
```yaml
tdd_cycle:
  status: GREEN  # RED | GREEN | REFACTOR | IDLE
  test_path: tests/auth/login.spec.ts
  evidence:
    red: docs/ai/tdd/red-20260302.log
    green: docs/ai/tdd/green-20260302.log
    refactor: null
```

### `/aai-worktree` - Git Worktree Management

**Commands:**
```bash
/aai-worktree setup <task-name> [base-branch]
/aai-worktree switch <task-name>
/aai-worktree list
/aai-worktree sync
/aai-worktree cleanup <task-name>
```

**Worktree Structure:**
```
/workspace/my-app/               # Main worktree
├── .git/
├── docs/ai/STATE.yaml           # Main state

/workspace/my-app-feature-login/ # Feature worktree
├── .git -> /workspace/my-app/.git/worktrees/feature-login
├── docs/ai/STATE.yaml           # Isolated state for login feature
```

## What We Didn't Adopt (Yet)

### Auto-Triggering Skills

**Superpowers:** Skills auto-activate based on trigger patterns

**AAI Status:** Currently requires explicit invocation

**Future:** Could add trigger system:
```yaml
# .claude/triggers.json
triggers:
  - pattern: "add|create .* feature"
    skill: aai-intake
    args: { type: "prd" }
```

### Socratic Brainstorming

**Superpowers:** Interactive refinement phase before planning

**AAI Status:** INTAKE asks clarifying questions, but not Socratic

**Future:** Could enhance INTAKE with structured questioning

### Severity-Based Code Review Blocking

**Superpowers:** Different severity levels (error, warning, info)

**AAI Status:** Binary (pass/fail)

**Future:** Could add severity levels to VALIDATION

## Migration Guide

### For Existing AAI Projects

If you're already using AAI, here's how to adopt Superpowers patterns:

1. **Enable TDD Workflow**
   ```bash
   # In your project
   /aai-tdd

   # Follow RED-GREEN-REFACTOR for new features
   ```

2. **Use Worktrees for Parallel Work**
   ```bash
   # Instead of:
   git checkout -b feature/login
   # ... work ...
   git checkout main
   git checkout -b feature/profile
   # ... work ...

   # Use:
   /aai-worktree setup login
   # ... work in ../project-feature-login ...
   /aai-worktree setup profile
   # ... work in ../project-feature-profile ...
   ```

3. **Apply 2-5 Minute Chunking**
   - Review your PLANNING outputs
   - Decompose tasks > 5 minutes
   - Each task should have testable outcome

### For Superpowers Users

If you're coming from Superpowers, here's how AAI complements it:

1. **Structured Documentation**
   - Superpowers: Design docs
   - AAI: Templates for requirements, specs, decisions
   - Benefit: Standardized, searchable artifacts

2. **State Tracking**
   - Superpowers: Task checkpoints
   - AAI: STATE.yaml + METRICS.jsonl
   - Benefit: Queryable state, time-series analytics

3. **Knowledge Accumulation**
   - Superpowers: Implicit learning
   - AAI: FACTS.md, PATTERNS.md
   - Benefit: Explicit knowledge base for future reference

## Best Practices

### When to Use /aai-tdd

✅ **Good for:**
- New features with clear behavior
- Bug fixes with reproducible cases
- Refactoring with existing test coverage

❌ **Skip for:**
- Exploratory research
- Documentation updates
- Configuration changes

### When to Use /aai-worktree

✅ **Good for:**
- Parallel feature development
- Long-running branches (> 1 day)
- Subagent isolation
- Experimental work alongside stable features

❌ **Skip for:**
- Quick fixes (< 1 hour)
- Hot patches
- Documentation-only changes

### Combining TDD + Worktrees

**Optimal Pattern:**
```
/aai-worktree setup feature-name
cd ../project-feature-name
/aai-intake "..."
/aai-planning
/aai-tdd  # Repeat for each task
/aai-validate-report
/aai-worktree cleanup feature-name
```

## Metrics & Evidence

### TDD Metrics

Tracked in `docs/ai/METRICS.jsonl`:
```jsonl
{"timestamp":"2026-03-02T10:00:00Z","type":"tdd_cycle","task":"password-reset","duration_seconds":420,"phases":{"red":60,"green":240,"refactor":120},"tests_added":4,"coverage_delta":"+3%"}
```

### Worktree Metrics

```jsonl
{"timestamp":"2026-03-02T09:00:00Z","type":"worktree_create","task":"feature/login","path":"../app-feature-login"}
{"timestamp":"2026-03-02T14:00:00Z","type":"worktree_cleanup","task":"feature/login","duration_hours":5,"commits":12,"merged":true}
```

## Future Enhancements

### Planned Integrations

1. **Auto-Trigger System**
   - Detect user intent from natural language
   - Auto-invoke appropriate skill
   - Reduce explicit invocation friction

2. **Enhanced Decomposition**
   - ML-based task estimation
   - Automatic 2-5 minute chunking
   - Suggest parallelization opportunities

3. **Continuous TDD**
   - Auto-run RED phase when requirements change
   - Suggest test cases from spec
   - Detect untested code paths

4. **Worktree Analytics**
   - Context switch frequency
   - Parallel efficiency metrics
   - Worktree lifecycle optimization

## References

- [Superpowers GitHub](https://github.com/obra/superpowers)
- [Superpowers Documentation](https://github.com/obra/superpowers/tree/main/docs)
- [AAI Workflow](../workflow/WORKFLOW.md)
- [TDD Skill](../../.aai/SKILL_TDD.prompt.md)
- [Worktree Skill](../../.aai/SKILL_WORKTREE.prompt.md)

## Contributing

If you have ideas for better Superpowers integration:
1. Open an issue describing the pattern
2. Reference Superpowers implementation
3. Propose AAI adaptation
4. Submit PR with skill implementation

## Credits

Superpowers framework by [@obra](https://github.com/obra) and contributors.

AAI integration designed to complement, not replace, Superpowers patterns.
