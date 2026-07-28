---
id: core-prompt-diet
number: null
type: change
status: draft
user_visible: false
links:
  pr: []
  commits: []
---

# Change — core-prompt diet: pointer-ize script-restatement + cross-file dedup into ROLE_COMMON

## Summary
- CORE-skill sweep (two read-only audits, operator direction 2026-07-28)
  over the hot-path role/flow prompts loaded every tick/ride. No staleness
  found anywhere (decapod, old product-doc model, az-repos-pr-thread all
  absent or already corrected). Most files KEEP (already tight post-#159 /
  post-CODE_REVIEW-RFC). The real wins, all behaviour-preserving:
  reductions + de-duplication of prose that either restates a script's own
  header contract (replace with a pointer, like this session's doctor/
  dashboard determinizations) or duplicates another prompt (fold into
  ROLE_COMMON, the #159 pattern). ~7 KB off the hot-path corpus.

## Work list (audit-sourced, exact)
LOW-RISK (do all):
- SKILL_TDD.prompt.md: delete 3 prose-only sections with no gate/behaviour —
  "## Token Optimization", "## Example Complete Cycle", "## Troubleshooting"
  (the last duplicates SKILL_DEBUG's purpose; replace with a 1-line pointer).
- ROLE_COMMON.md: absorb 4 surviving cross-prompt duplications as canonical
  blocks (mirroring the METRICS block), each caller reduced to a pointer +
  its role-specific verb:
  - FRICTION HOOK (4 sites: IMPLEMENTATION, VALIDATION x2, REMEDIATION)
  - PYTHON MONTY SCRATCHPAD (2 sites: IMPLEMENTATION, SKILL_TDD)
  - PRE-HANDOFF AC-TABLE RECONCILIATION tail (2 sites: IMPLEMENTATION, SKILL_TDD)
  - WORKTREE GATE check (3 sites: ORCHESTRATION_PARALLEL, IMPLEMENTATION, SKILL_TDD)
- SKILL_LOOP.prompt.md: VALIDATOR INDEPENDENCE -> pointer to
  SUBAGENT_PROTOCOL.md "Spawning a validator in a separate agent" (exact
  duplicate); run-budget rationale intra-file dedup (keep step 2f, trim the
  LOOP PARAMETERS bullet).
- SKILL_CHECK_STATE.prompt.md: INV-14 DETECT/REPAIR prose -> pointer to
  check-state.mjs header; KEEP the WRITER RULE line.
- SKILL_PR.prompt.md: RECONCILE WORKTREE TELEMETRY rationale -> pointer to
  reconcile-telemetry.mjs header PURPOSE; KEEP the exit-code branching.
MEDIUM-RISK (keep the operative recipe, cut only rationale; validation must
confirm the recipe survives verbatim):
- VALIDATION.prompt.md LEAK-SAFE EXECUTION: keep the invocation recipe
  (capture AAI_REAP_STEP_START_EPOCH, wrap via aai-run-tests.sh, reap via
  aai-reap-tests.sh same epoch); point the "why" to the script headers.
- ORCHESTRATION_PARALLEL.prompt.md SCOPE LOCKING: keep the acquire/release
  CALL PATTERN + exit-code branching; point exit-code/TTL detail to
  docs-lock.mjs header.
- SKILL_LOOP.prompt.md POST-TICK REAP: keep the env-var/when-to-run
  instructions; point the safety rationale to aai-reap-tests.sh header.

## Acceptance Criteria
- AC-001: every listed reduction/dedup applied; NO behavioural/contract/
  fail-closed/anti-gaming prose lost — only rationale, duplication, and the
  3 dead SKILL_TDD sections removed; each ROLE_COMMON block has exactly one
  canonical copy with each former site now a pointer (grep: the moved text
  appears once).
- AC-002: prompt-corpus governance holds — one NEGATIVE RECLAIMED ledger
  entry reconciles the net reduction so headroom stays in [0, CAP=2048];
  TEST-012 pin updated RED-first; verify-gate consistent.
- AC-003: no regression — every touched role prompt still parses/loads and
  its role's suite is green where one exists; docs-audit --check --strict
  CLEAN; the operative recipes (leak-safe exec, scope-lock call pattern,
  reap env-var) survive verbatim (grep-pinned).

## Verification
- grep pins for the moved-once blocks + surviving recipes; prompt-diet;
  verify-gate; a spot suite per touched role (validation, tdd, close-work-item);
  docs-audit --check --strict.

## Constraints / Risks
- Ceremony L2 (prompt corpus; no L3 path). Blast radius = every role prompt;
  adversarial validation on "no load-bearing prose lost" is the gate. Medium-
  risk trims keep the operative recipe; conservative by default (skip the
  low-value/medium-risk items the audit itself did not recommend, e.g. the
  STAGNATION Huntley clause).
