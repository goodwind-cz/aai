---
id: cache-friendly-dispatch
number: 101
type: change
status: done
user_visible: false
links:
  pr:
    - 204
  commits:
    - c73720a1401fa25e7a501393dd37475dca4bb9dc
---

# Change — token economics: cache-friendly dispatch ordering + effort routing

## Summary
- Operator request (2026-08-01), from a field article on Claude API cost
  engineering (X: @0x_rody, "Graph Engineering with Opus 5"): prompt caching
  bills repeated stable prefixes at ~10% of base rate, but ONLY when the
  prompt is ordered STABLE-FIRST, VARIABLE-LAST and the stable prefix is
  byte-identical across calls; flipping effort/model mid-session invalidates
  the cache (effort is part of the cache key). The factory dispatches large
  role prompts thousands of times — if stable content (role prompt, CONTRACT,
  LEARNED, canon pointers) does not deterministically precede variable
  content (scope, refs, paths, timestamps), harness prompt-cache savings are
  forfeited on EVERY dispatch. This continues the operator's token-cost line
  (implementation-mode choice, CHANGE-0100).

## Three deliverables
1. CACHE-ORDERING AUDIT + FIX: audit every dispatch-assembled prompt surface
   (ORCHESTRATION dispatch payloads, SUBAGENT_PROTOCOL dispatch template,
   brief emission, role-prompt + scope concatenation order in SKILL_LOOP /
   ORCHESTRATION_PARALLEL) for stable-first/variable-last ordering; fix any
   surface where variable content (ref ids, paths, timestamps, scope text)
   precedes or interleaves the stable corpus. The stable prefix must be
   byte-identical across dispatches of the same role (prompt-hash telemetry
   SPEC-0096 already proves identity — reuse it as the measurement).
2. EFFORT ROUTING (advisory, mirroring MODEL_ROUTING): extend
   .aai/system/MODEL_ROUTING.yaml with a suggested_effort tier per role —
   mechanical roles (Metrics Flush, doc regen, extraction-style work) -> low;
   Planning/Implementation -> default; Validation/Code Review -> high.
   Dispatch surfaces the value next to suggested_model; absent file/field =
   today's behavior (advisory, never binding — same contract as model
   routing when it was introduced).
3. NO-MID-SESSION-FLIP PIN: one rule in SUBAGENT_PROTOCOL (or MODEL_ROUTING
   header): never flip effort/model inside one session — separate dispatches
   per tier (the factory already works this way; pin it so a future edit
   cannot silently regress cache behavior). Grep-pinned.

## Acceptance Criteria
- AC-001: every audited dispatch surface orders stable content before
  variable content; the audit findings (surface -> before/after order) are
  recorded in the spec; any fixed surface keeps byte-identical semantics
  (only order changes, no prose loss — hostile prompt pins stay green).
- AC-002: the stable prefix of a role dispatch is byte-identical across two
  consecutive dispatches of the same role on the same repo state
  (suite-verified via the existing prompt-hash machinery or a direct
  byte-compare of the assembled stable segment).
- AC-003: MODEL_ROUTING.yaml carries suggested_effort per role; dispatch
  emits it (text + --json) alongside suggested_model; absent file or field
  degrades to today's output byte-for-byte (back-compat, suite-verified).
- AC-004: the no-mid-session-flip rule is present and grep-pinned; no
  behavioral surface changed by it (documentation pin only).
- AC-005: no prompt-corpus regression — headroom stays within cap; any byte
  growth carries a RED-first JUSTIFIED_ADDITIONS entry (headroom is ~0 after
  CHANGE-0100 — expect a ledger entry for any prompt addition).

## Verification
- extend tests/skills/test-aai-orchestration-dispatch.sh (suggested_effort
  emission + absent-file back-compat) and the prompt-diet/hygiene suites
  (ordering pins); a new small ordering test only if the audit finds real
  reorder fixes (assert stable-segment byte-identity across two dispatches).
- docs-audit --check; layer-profiles if any new .aai file.

## Constraints / Risks
- Ceremony: L2 expected; orchestration-dispatch.mjs is NOT in
  protected_paths_l3 (verify FIRST — last rides hit surprise L3s; state.mjs
  is protected and must NOT need touching here).
- Effort is advisory because the harness, not the factory, owns actual API
  parameters; the value is a routing hint exactly like suggested_model was
  at introduction. Never binding, never a silent behavior change.
- The audit may find ZERO reorder fixes (surfaces already ordered) — that is
  a legitimate outcome; AC-001 then documents the audit as evidence and
  AC-002 pins the invariant so it cannot regress.

## Acceptance Criteria Status

Reconciled at implementation hand-off. Spec: docs/specs/SPEC-0110-spec-cache-friendly-dispatch.md.

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---------|-------------|--------|----------|-----------|-------|
| AC-001 | Every audited dispatch surface orders stable content before variable; audit recorded; any fix keeps byte-identical semantics | done | audit table in SPEC-0110-spec-cache-friendly-dispatch; hygiene-pack + friction-wiring green | — | zero reorders needed (legitimate outcome) |
| AC-002 | Stable prefix byte-identical across two consecutive same-role dispatches | done | test-aai-orchestration-dispatch TEST-033 pass | — | reuses SPEC-0096 prompt-hash machinery |
| AC-003 | MODEL_ROUTING.yaml carries suggested_effort per role; dispatch emits text plus --json; absent file or field degrades to null | done | TEST-030, TEST-031, TEST-032 pass | — | mirrors suggested_model contract |
| AC-004 | No-mid-session-flip rule present and grep-pinned; documentation-only | done | TEST-034 pass | — | pin in MODEL_ROUTING.yaml header |
| AC-005 | No prompt-corpus regression within cap | done | test-aai-prompt-diet TEST-010 headroom 0/2048; TEST-012 == -4378 | — | zero corpus bytes added (all growth in scripts/system/tests) |

## Notes
- Deliberately NOT adopted from the source article: Graphiti/Neo4j knowledge
  graph (heavy infra vs AAI zero-deps universality; factory memory =
  LEARNED/EVENTS/METRICS/friction already timestamped), Batch API wiring
  (harness-owned, not factory-owned).
- Implementation mode (recommendation for the intake choice): direct +
  targeted tests — mostly audit + config + pins; TDD ceremony would outweigh
  the scope. (Fitting, given this ride IS the token-cost line.)
