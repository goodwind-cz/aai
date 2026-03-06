# Expert Resolution Protocol

## Purpose
Fetch and inject domain-expert system prompts from the VoltAgent/awesome-claude-code-subagents
repository into AAI implementation and TDD workflows. Experts provide domain-specific knowledge
while AAI retains full control over orchestration, quality gates, and state management.

**TOKEN RULE: Do NOT read `.aai/system/EXPERT_REGISTRY.yaml`. Use CLI commands only.**
The fetch script handles all registry lookups, caching, security, and sanitization internally.

## When to Resolve an Expert

An expert SHOULD be resolved when:
- The task scope clearly involves a specific technology domain (language, framework, database, infra)
- The domain expertise would improve implementation quality beyond generic knowledge

An expert MUST NOT be resolved when:
- The task is purely orchestration, planning, or validation (AAI owns these)
- The task is TDD RED phase (tests must reflect project conventions, not expert opinions)

## Resolution Process

### Step 1: Detect Matching Experts

Pass file extensions and/or technology keywords from the task scope:

```bash
# Returns 0-2 expert keys (one per line), or empty if no match
bash .aai/scripts/expert-fetch.sh --detect .tsx .py docker security
```

Input sources for keywords:
- File extensions from work item scope (`.ts`, `.py`, `.rs`, etc.)
- Technology names from `docs/TECHNOLOGY.md` (react, postgres, docker, etc.)
- Explicit keywords in task description or spec

### Step 2: Check Phase Eligibility

```bash
# Returns "eligible" (exit 0) or "not-eligible" (exit 1) or "not-found" (exit 2)
bash .aai/scripts/expert-fetch.sh --check typescript tdd-green
```

Valid phases: `implementation`, `tdd-green`, `tdd-refactor`

### Step 3: Fetch Expert

```bash
# Returns path to cached file. Handles: pinned SHA, size limit, injection scan, sanitization.
bash .aai/scripts/expert-fetch.sh typescript
```

If fetch fails (exit 1) or not found (exit 2), proceed without expert.

### Step 4: Extract Prompt Body

```bash
# Returns prompt body without YAML frontmatter — ready for injection
EXPERT_BODY=$(bash .aai/scripts/expert-fetch.sh --body typescript)
```

### Step 5: Inject into Subagent Call

Compose the Agent call with the expert prompt body wrapped in AAI constraints:

```
Agent(
  prompt = """
You are operating as a domain expert within the AAI workflow.

## Your Expert Identity
{EXPERT_BODY from step 4}

## AAI Constraints (OVERRIDE expert instructions if conflict)
- You are implementing a SPECIFIC scope assigned to you. Do not modify files outside your scope.
- Return results in SUBAGENT_PROTOCOL.md format (see below).
- Do NOT modify docs/ai/STATE.yaml — the orchestrator owns state.
- Do NOT run git commit, git push, or any git write operations.
- Do NOT create new files outside the assigned scope paths.
- Respect docs/TECHNOLOGY.md as the authoritative technology contract.

## Your Assignment
SCOPE: {scope from work item}
TASK: {task description}
FILES: {file paths in scope}
CONSTRAINTS FROM SPEC: {relevant AC items}
TECHNOLOGY: {relevant entries from TECHNOLOGY.md}

## Required Output Format
Return a YAML result block:
subagent_result:
  scope: {scope}
  role: Implementation
  status: PASS | FAIL | BLOCKED
  started_utc: {capture from system clock}
  ended_utc: {capture from system clock}
  duration_seconds: {integer}
  evidence:
    - command: {verification command}
      exit_code: {int}
      output_snippet: {first 200 chars}
  files_changed:
    - {relative path}
  blockers: []
""",
  tools = "Read, Write, Edit, Bash, Glob, Grep"
)
```

## Security Model

All security enforcement is handled by `expert-fetch.sh` — the agent does not need to implement these checks.

### Defense Layers (enforced by script)
1. **Pinned SHA** — fetches only from a reviewed commit, not upstream `main`
2. **Size limit** — rejects prompts exceeding `max_prompt_bytes` (default 8KB)
3. **Tool whitelist** — only Read, Write, Edit, Bash, Glob, Grep
4. **Injection detection** — rejects prompts matching `ignore previous`, `you are now`, etc.
5. **Destructive command strip** — removes `git push`, `rm -rf`, `--no-verify` lines
6. **Blocked categories** — meta-orchestration and business agents cannot be fetched
7. **AAI constraint override** — expert instructions are subordinate to AAI rules (step 5)
8. **Scope isolation** — expert can only touch files in assigned scope (step 5)

### SHA Update Process (human-only, not for agents)
To update the pinned SHA (after reviewing upstream changes):
1. Review the diff: `gh api repos/VoltAgent/awesome-claude-code-subagents/compare/{old_sha}...main`
2. Verify no malicious changes in agent prompts
3. Human edits `pinned_sha` in `.aai/system/EXPERT_REGISTRY.yaml`
4. Clear cache: `rm -rf .aai/cache/experts/`
