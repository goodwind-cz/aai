---
id: friction-shadow-capture-wiring
number: 46
type: change
status: done
links:
  rfc: RFC-0012
  spec: null
  pr:
    - 144
  commits:
    - c67b8b1d742ce8e929fdbf3add5d626f8d528305
---

# RFC-0012 Phase 1 — local shadow-mode friction capture wiring

## Summary
- Implements ONLY Phase 1 of RFC-0012 (accepted/implementing): **local shadow
  mode**. Wire the Phase-0 capture CLI (`.aai/scripts/aai-friction.mjs record`)
  into the skill surface so a real AAI-owned failure gets recorded to the local
  untracked spool during normal work — capture-only, no triage, no upstream.
- Deliver ONE canonical friction seam (a thin reference to
  `.aai/system/FRICTION_PROTOCOL.md` + the record invocation), inherited by every
  universal skill rather than duplicated per prompt, plus **skill-test-suite
  enforcement** that the seam exists and that the universal-skill contract points
  at it. This is the smallest slice that turns Phase 0's dormant CLI into a
  live-but-silent (shadow) capture path.

## Type
- change (feature — second implementation slice of RFC-0012)

## Motivation / Business Value
- Phase 0 shipped the protocol + offline CLI but nothing CALLS it: the spool
  stays empty. Phase 1 makes capture actually happen so that, after the RFC's
  mandated ">= two weeks" shadow window, Phase 2 (review mode + threshold
  calibration) has real local observations to calibrate against.
- Shadow mode is deliberately silent: it must never change a skill's outcome or
  surface anything to the user — it only accumulates local evidence.

## Scope
- In scope:
  - A single canonical **friction seam** — a thin, DRY reference block naming
    `.aai/system/FRICTION_PROTOCOL.md`, the recordable failure classes +
    exclusions (by reference, not re-stated), and the exact offline command
    `node .aai/scripts/aai-friction.mjs record --input <sanitized-json|->`.
  - Placement so **every universal skill inherits the seam** without duplication
    (RFC section 1: "thin platform wrappers must reference it rather than
    duplicate it"). Candidate host: the shared always-loaded agent guidance
    (`.aai/AGENTS.md` / `.aai/SUBAGENT_PROTOCOL.md` / `.aai/knowledge/PATTERNS_UNIVERSAL.md`)
    — resolved in Planning (see Open Questions).
  - **Skill-test-suite enforcement** (RFC section 1: "Enforce this seam in the
    skill test suite"): a test asserting the canonical seam is present exactly
    once in its host and that the universal-skill contract references it; a
    negative control proving the test fails if the seam is removed.
  - Shadow semantics: capture is best-effort and MUST NOT replace or mask the
    skill's original result (RFC section 1, final bullet) — a failed/absent
    capture is swallowed, never escalated.
  - Companion obligations (per PLANNING step 3a): if the seam grows prompt
    corpus (`.aai/*.prompt.md` / `AGENTS.md`), true up the prompt-diet ledger
    (`tests/skills/lib/prompt-diet-ledger.sh` JUSTIFIED_ADDITIONS + TEST-012
    checkpoint); if any new `.aai/**` file is added, classify it in
    `PROFILES.yaml`.
- Out of scope (DEFERRED to Phase 2+ per RFC roadmap):
  - `/aai-feedback-triage`, scoring, fingerprint clustering, upstream issue
    search/upsert, the `<!-- aai-friction:v1:<fp> -->` marker.
  - `.aai/feedback.yaml` modes (`local`/`review`/`auto`), reporting budget,
    cooldown, destination pinning, auto gate (D8).
  - Any GitHub token / network I/O (already structurally excluded in Phase 0).
  - Downstream project rollout (Phases 3–5).

## Affected Area
- The shared universal agent guidance / skill-prompt surface (`.aai/**`).
- `tests/skills/` (new seam-enforcement test + wiring into the runner).
- Possibly `tests/skills/lib/prompt-diet-ledger.sh` + TEST-012 (companion).
- Possibly `.aai/system/PROFILES.yaml` (companion, only if a new file lands).

## Desired Behavior (To-Be)
- Exactly one canonical friction seam exists; every universal skill inherits it.
- When an agent running any AAI skill recognizes an AAI-owned failure class (per
  FRICTION_PROTOCOL taxonomy, exclusions honored), it records one sanitized
  observation via the offline CLI to the local spool, without altering the
  skill's own result or emitting anything user-visible.
- The skill test suite fails if the canonical seam is missing or unreferenced.

## Acceptance Criteria
- AC-001: A single canonical friction seam exists in exactly one host file and
  names FRICTION_PROTOCOL.md + the exact offline record command; grep-assertable.
- AC-002: The universal-skill contract references the seam so every universal
  skill inherits it (no per-prompt duplication of the protocol body).
- AC-003: A skill-suite test asserts AC-001/AC-002 and has a negative control
  that FAILS when the seam is deleted (proves the guard has teeth).
- AC-004: Shadow semantics are documented and enforced: capture is best-effort
  and cannot change a skill's exit/result; a capture failure is swallowed.
- AC-005: No triage/upsert/network/config-mode surface is introduced (Phase 2+
  stays out); grep-assertable absence.
- AC-006: Companion obligations satisfied — prompt-diet ledger trued up with a
  JUSTIFIED_ADDITIONS entry + TEST-012 checkpoint bump if corpus grew; any new
  `.aai/**` file classified in PROFILES.yaml; both suites green.

## Verification
- `bash tests/skills/test-aai-friction.sh` (Phase 0 tests still green).
- New seam-enforcement test green, and RED when the seam is removed (mutation).
- `bash tests/skills/test-aai-prompt-diet.sh` green (ledger trued up).
- `bash tests/skills/test-aai-layer-profiles.sh` green (classification intact).
- `node .aai/scripts/docs-audit.mjs` CLEAN.

## Constraints / Risks
- Prompt-diet cost: the seam grows prompt corpus; keep it MINIMAL (a pointer,
  not a restatement) and true up the ledger. A per-prompt duplication would blow
  the budget — the DRY shared-include placement is the mitigation.
- Shadow silence: capture must be provably incapable of masking a skill result;
  the test must assert the best-effort/swallow contract, not just presence.
- No protected_paths_l3 surface is in scope (keep it L2).

## Open Questions (resolve in Planning)
- OQ1: Seam host — the single DRY location every universal skill transitively
  loads. Recommendation: place the canonical seam in FRICTION_PROTOCOL.md's
  "wiring" section (already core-referenced) and put the THIN inheriting pointer
  in the shared agent contract (`.aai/AGENTS.md` or `.aai/SUBAGENT_PROTOCOL.md`),
  so the protocol body is never duplicated. Confirm exact host in Planning.
- OQ2: What the enforcement test binds to (a literal seam marker string vs. a
  structural reference), chosen to be robust to benign prose edits.

## Notes
- Phase 1 also entails a real-time activity (run shadow for >= 2 weeks) that is
  operational, not code; this work item delivers the CODE that enables it. The
  2-week window and Phase 2 calibration are tracked separately against RFC-0012.
