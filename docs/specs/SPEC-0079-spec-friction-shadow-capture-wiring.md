---
id: spec-friction-shadow-capture-wiring
type: spec
number: 79
status: done
ceremony_level: 2
links:
  requirement: CHANGE-0046-friction-shadow-capture-wiring
  rfc: RFC-0012
  pr:
    - 144
  commits:
    - c67b8b1d742ce8e929fdbf3add5d626f8d528305
---

# SPEC — RFC-0012 Phase 1: local shadow-mode friction capture wiring

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0046-friction-shadow-capture-wiring.md (RFC-0012 Phase 1)
- RFC: docs/rfc/RFC-0012-aai-self-improvement-feedback-loop.md (section 1 "Local capture shared by every skill")
- Phase 0 foundation: .aai/system/FRICTION_PROTOCOL.md, .aai/scripts/aai-friction.mjs
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec being written
- implementing: spec frozen, work in flight
- done: all Spec-AC terminal; validation PASS recorded
- deferred | rejected | superseded: as usual

## Implementation strategy
- Strategy: tdd
- Rationale: The deliverable's entire value is an ENFORCEMENT SEAM — a skill-suite
  guard that fails when the friction wiring is absent. That guard is exactly a
  RED/GREEN driver: written first it must FAIL against the current tree (no seam
  section, no AGENTS pointer), then pass once the seam lands. Prose-only changes
  with a test that has never been RED prove nothing (tautology risk, PLANNING
  rationalization table); TDD forces the observed-RED before GREEN. The companion
  prompt-diet ledger true-up is itself test-gated (TEST-012 checkpoint) and rides
  the same RED/GREEN. Low mechanical risk, but the guard's teeth must be proven.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: Small, single logical scope (one protocol section + one
  AGENTS.md pointer + one new test file + a ledger true-up), fully reversible,
  already isolated on dedicated branch feat/friction-shadow-capture-wiring off
  main per branch-per-work-item hygiene. No protected_paths_l3 surface.
- User decision: inline
- Base ref: main
- Inline review scope: .aai/system/FRICTION_PROTOCOL.md (new "Skill wiring" section only), .aai/AGENTS.md (new thin friction pointer only), tests/skills/test-aai-friction-wiring.sh (new), tests/skills/lib/prompt-diet-ledger.sh (JUSTIFIED_ADDITIONS entry), tests/skills/test-aai-prompt-diet.sh (TEST-012 checkpoint bump only)

## Acceptance Criteria Mapping
- Spec-AC-01 (maps CHANGE AC-001): `.aai/system/FRICTION_PROTOCOL.md` gains a
  canonical "Skill wiring (shadow capture)" section that (a) names the exact
  offline command `node .aai/scripts/aai-friction.mjs record --input <path|->`,
  and (b) states WHEN to record by reference to the existing taxonomy/exclusions
  (does not restate them). Verification: grep the section heading + the literal
  command substring.
- Spec-AC-02 (AC-002): `.aai/AGENTS.md` gains ONE thin pointer directing every
  agent/skill to the FRICTION_PROTOCOL "Skill wiring" seam, so every universal
  skill inherits it via the shared guide rather than duplicating the protocol
  body per prompt. Verification: grep AGENTS.md for the pointer referencing
  FRICTION_PROTOCOL.md + shadow capture.
- Spec-AC-03 (AC-003): a skill-suite test `tests/skills/test-aai-friction-wiring.sh`
  asserts Spec-AC-01 and Spec-AC-02 AND contains a negative control that FAILS
  when the seam section or the AGENTS pointer is removed (mutation on a temp
  copy). Verification: the suite is green on the delivered tree and its negative
  control demonstrably exits non-zero on the mutated copy.
- Spec-AC-04 (AC-004): the seam explicitly documents SHADOW semantics —
  best-effort, MUST NOT change/mask the calling skill's result, a failed or
  absent capture is swallowed (never escalates), and points at the protocol's
  existing "Capture never masks the caller" invariant. Verification: grep the
  seam for the best-effort/never-mask/swallow contract sentence.
- Spec-AC-05 (AC-005): the change introduces NO triage/upsert/network/config
  surface (no `/aai-feedback-triage`, no `.aai/feedback.yaml`, no `gh`/network
  call, no `review`/`auto` mode token) — Phase 2+ stays out. Verification:
  grep-assertable absence across the changed lines.
- Spec-AC-06 (AC-006): companion obligations satisfied — because AGENTS.md
  (tracked prompt corpus) grows, the prompt-diet ledger gets a new
  JUSTIFIED_ADDITIONS entry and the TEST-012 checkpoint is bumped by exactly the
  measured deficit; `.aai/system/*.md` growth (FRICTION_PROTOCOL.md) is NOT
  corpus and adds no ledger cost; no new `.aai/**` file is added so PROFILES.yaml
  is unaffected. Verification: test-aai-prompt-diet.sh green + test-aai-layer-profiles.sh green.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC    | Description                                                        | Status   | Evidence | Review-By | Notes |
|------------|-------------------------------------------------------------------|----------|----------|-----------|-------|
| Spec-AC-01 | FRICTION_PROTOCOL.md "Skill wiring" seam names record command     | done     | docs/ai/tdd/green-20260725T055657Z-friction-wiring.log | —         | GREEN |
| Spec-AC-02 | AGENTS.md thin inheriting pointer to the seam                     | done     | docs/ai/tdd/green-20260725T055657Z-friction-wiring.log | —         | GREEN |
| Spec-AC-03 | Skill-suite enforcement test + negative control                   | done     | docs/ai/tdd/green-20260725T055657Z-friction-wiring.log | —         | GREEN |
| Spec-AC-04 | Shadow best-effort / never-mask / swallow contract documented     | done     | docs/ai/tdd/green-20260725T055657Z-friction-wiring.log | —         | GREEN |
| Spec-AC-05 | No triage/upsert/network/config surface introduced                | done     | docs/ai/tdd/green-20260725T055657Z-friction-wiring.log | —         | GREEN |
| Spec-AC-06 | Companion prompt-diet ledger true-up; PROFILES unaffected          | done     | docs/ai/tdd/green-20260725T055657Z-friction-wiring.log | —         | GREEN |

## Implementation plan
- Components affected:
  - `.aai/system/FRICTION_PROTOCOL.md` — add "## Skill wiring (shadow capture)"
    section: the record command, when-to-record (by reference to the taxonomy),
    and the shadow best-effort/never-mask/swallow contract. NOT prompt corpus.
  - `.aai/AGENTS.md` — one thin pointer block naming the seam (tracked corpus).
  - `tests/skills/test-aai-friction-wiring.sh` — new enforcement suite (auto
    discovered by the skills runner glob, like Phase 0's test-aai-friction.sh).
  - `tests/skills/lib/prompt-diet-ledger.sh` + `tests/skills/test-aai-prompt-diet.sh`
    — companion true-up (JUSTIFIED_ADDITIONS entry + TEST-012 checkpoint).
- Data flow: no runtime data flow changes. The seam is documentation that
  instructs an agent to invoke the EXISTING Phase-0 CLI; capture writes to the
  existing untracked spool `docs/ai/friction/`.
- Edge cases: capture command missing/errors mid-skill → swallowed, skill result
  unchanged (asserted); AGENTS pointer must not duplicate the protocol body
  (DRY — enforced by keeping the body only in FRICTION_PROTOCOL.md).

## Seam analysis (6a)
- SEAM 1 (prose → CLI): the seam documents a command contract owned by the
  Phase-0 script. A prose-only assertion would pass even if the documented
  invocation no longer works. INTEGRATION TEST-007 runs the exact documented
  command end-to-end and asserts one spool line + exit 0 — crossing prose→CLI.
- SEAM 2 (protocol body ↔ shared guide inheritance): every universal skill
  inherits the seam only if AGENTS.md actually points at it. TEST-003's negative
  control crosses this by mutating each side and proving the guard fails.
- Residual risk: this spec does NOT prove agents actually CALL record at runtime
  on real failures (that is the >=2-week shadow OBSERVATION window, operational,
  tracked against RFC-0012 Phase 1, not automatable here). Recorded explicitly.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                     | Description                                                                 | Status  |
|----------|------------|-------------|------------------------------------------|-----------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-friction-wiring.sh | Protocol has "Skill wiring" section naming the exact record command         | green |
| TEST-002 | Spec-AC-02 | unit        | tests/skills/test-aai-friction-wiring.sh | AGENTS.md has a thin pointer to the FRICTION_PROTOCOL shadow-capture seam    | green |
| TEST-003 | Spec-AC-03 | integration | tests/skills/test-aai-friction-wiring.sh | Negative control: removing the seam section OR the AGENTS pointer fails guard| green |
| TEST-004 | Spec-AC-04 | unit        | tests/skills/test-aai-friction-wiring.sh | Seam states best-effort / never-mask / swallow shadow contract              | green |
| TEST-005 | Spec-AC-05 | unit        | tests/skills/test-aai-friction-wiring.sh | No triage/upsert/network/config token introduced by the seam                | green |
| TEST-006 | Spec-AC-06 | integration | tests/skills/test-aai-prompt-diet.sh     | Prompt-diet ledger trued up: TEST-012 checkpoint == new corpus size, green  | green |
| TEST-007 | Spec-AC-01 | integration | tests/skills/test-aai-friction-wiring.sh | The documented record command runs end-to-end: one spool line, exit 0       | green |

RED-proof obligation: TEST-001..005 and TEST-007 are written first and observed
FAILING against the current tree (no seam section, no AGENTS pointer) before the
seam lands. TEST-006 is RED when the ledger checkpoint still reflects the
pre-seam corpus size.

## Verification
- `bash tests/skills/test-aai-friction-wiring.sh` (new suite green; negative control proven)
- `bash tests/skills/test-aai-friction.sh` (Phase 0 CLI suite still green)
- `bash tests/skills/test-aai-prompt-diet.sh` (ledger trued up, TEST-012 green)
- `bash tests/skills/test-aai-layer-profiles.sh` (classification intact — no new file)
- `node .aai/scripts/docs-audit.mjs` CLEAN
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal (done with evidence)

## Evidence contract
For each implementation, TDD, validation, and code review artifact record:
- ref_id: friction-shadow-capture-wiring
- Spec-AC and TEST-xxx links
- command or review scope
- exit code or review verdict
- evidence path (docs/ai/tdd/*.log, run logs)
- commit SHA or diff range when available

Notes:
This document defines HOW, not WHAT/WHY. It does not define workflow.
