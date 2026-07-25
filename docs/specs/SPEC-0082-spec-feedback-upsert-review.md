---
id: spec-feedback-upsert-review
type: spec
number: 82
status: done
ceremony_level: 2
links:
  requirement: CHANGE-0049-feedback-upsert-review
  rfc: RFC-0012
  pr:
    - 148
  commits:
    - a35afd5241e934716765fc5009c2f87a445ffbcf
---

# SPEC — RFC-0012 Phase 2c / Slice C: review-mode GitHub upsert (approval-gated)

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0049-feedback-upsert-review.md
- RFC: RFC-0012 (section 2 upsert; D1 destination; D5 redaction; D7/D8 human gate),
  RFC-0013 (D3 double redaction — transmit pass reuses .aai/scripts/lib/aai-redact.mjs)
- Foundation: aai-feedback-triage.mjs (report), aai-redact.mjs (redactor), FRICTION_PROTOCOL.md
- Technology contract: docs/TECHNOLOGY.md

## Implementation strategy
- Strategy: tdd
- Rationale: Network + privacy critical (first slice that can leave the machine),
  with an approval gate and a redaction boundary — every property (no-write-without-
  confirm, transmit redaction drop, dedup, budget, template) is a deterministic
  RED/GREEN with `gh` mocked. TDD is mandatory per the strategy rule for
  security/privacy surfaces.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: New engine + wrapper + config + tests; reversible; dedicated
  branch; no protected_paths_l3. (The RISK is network, addressed by the design +
  independent validation, not by worktree isolation.)
- User decision: inline
- Base ref: main
- Inline review scope: .aai/scripts/aai-feedback-upsert.mjs, .aai/SKILL_FEEDBACK_UPSERT.prompt.md, .aai/feedback.yaml (destination/budget/labels), .aai/system/PROFILES.yaml, tests/skills/test-aai-feedback-upsert.sh, tests/skills/lib/prompt-diet-ledger.sh + tests/skills/test-aai-prompt-diet.sh

## Acceptance Criteria Mapping
- Spec-AC-01 (AC-001): a plain engine run in `review` mode performs NO GitHub write /
  network mutation — it only writes local drafts (docs/ai/friction/pending-issues/)
  and prints the exact confirmed-write command. Verification: with a mock `gh` on
  PATH that records every invocation, a plain run records ZERO mutating calls
  (no `issue create`, no `-X POST/PATCH`).
- Spec-AC-02 (AC-002): TITLE/BODY are templated from structured fields; a `summary`
  is included ONLY if present AND it passes the transmit redaction; a payload
  free-text field failing redaction is dropped. Verification: template fixture +
  poisoned-summary fixture.
- Spec-AC-03 (AC-003): the transmit redaction reuses aai-redact.mjs — a poisoned
  free-text payload field is dropped (double redaction). Verification: import/grep
  + a poisoned-payload fixture that ends up with the field absent.
- Spec-AC-04 (AC-004): dedup — given a mock search returning an existing issue with
  `v1:<fingerprint>`, the engine prepares an update/skip, NOT a duplicate NEW issue.
  Verification: mock-gh search fixture.
- Spec-AC-05 (AC-005): budget — with `max_new_issues_per_7d` already met in the
  ledger, further NEW issues are prepared-but-deferred (not filed). Verification:
  pre-seeded ledger fixture.
- Spec-AC-06 (AC-006): destination pin read from feedback.yaml; `auto` refused;
  `local`/missing-config/missing-gh degrade to prepare-nothing. Verification: config fixtures.
- Spec-AC-07 (AC-007): the `--publish <fp> --confirm` path re-runs transmit
  redaction + budget immediately before the write and appends to the ledger; the
  write is the ONLY place a mutating `gh` call occurs, and only with `--confirm`.
  Verification: mock-gh confirmed-publish fixture asserts exactly one create call
  + a ledger append; the same command WITHOUT `--confirm` makes no call.
- Spec-AC-08 (AC-008): companion — new `.aai/**` files classified once in
  PROFILES.yaml; prompt-diet trued up; layer-profiles + prompt-diet green.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC    | Description                                              | Status  | Evidence | Review-By | Notes |
|------------|---------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | plain run makes no GitHub write (prepare-only)          | done    | docs/ai/tdd/green-20260725T124732Z-upsert.log | —         | GREEN |
| Spec-AC-02 | templated title/body; summary only if redaction-passes  | done    | docs/ai/tdd/green-20260725T124732Z-upsert.log | —         | GREEN |
| Spec-AC-03 | transmit redaction reuses aai-redact; poisoned dropped  | done    | docs/ai/tdd/green-20260725T124732Z-upsert.log | —         | GREEN |
| Spec-AC-04 | dedup by v1:<fingerprint> marker (no duplicate)         | done    | docs/ai/tdd/green-20260725T124732Z-upsert.log | —         | GREEN |
| Spec-AC-05 | budget: over-limit prepared-deferred, not filed         | done    | docs/ai/tdd/green-20260725T124732Z-upsert.log | —         | GREEN |
| Spec-AC-06 | destination pin; auto refused; degrade to prepare-none  | done    | docs/ai/tdd/green-20260725T124732Z-upsert.log | —         | GREEN |
| Spec-AC-07 | --publish --confirm re-verifies + is the only write     | done    | docs/ai/tdd/green-20260725T124732Z-upsert.log | —         | GREEN |
| Spec-AC-08 | companion PROFILES + prompt-diet true-up                | done    | docs/ai/tdd/green-20260725T124732Z-upsert.log | —         | GREEN |

## Implementation plan
- `.aai/scripts/aai-feedback-upsert.mjs` (node stdlib only; shells out to `gh`
  ONLY on the confirmed-publish path): loadConfig (destination/budget/labels/mode)
  -> readReport -> select review_candidates -> per cluster: buildPayload (template
  + marker) -> transmitRedact (aai-redact) -> dedupSearch (gh search, read-only)
  -> budgetCheck (ledger) -> writeDraft(pending-issues/<fp>.md) + print command.
  `--publish <fp> --confirm` path: re-redact + re-budget + `gh issue create` (the
  ONLY mutating call) + ledger append. Every `gh` call is via a single
  `runGh(args, {mutating})` seam so tests can assert mutation only happens under
  --confirm.
- `.aai/SKILL_FEEDBACK_UPSERT.prompt.md`: thin wrapper; documents prepare-only
  default + the explicit human --confirm write; no daemon.
- `.aai/feedback.yaml`: `destination: goodwind-cz/aai`, `budget.max_new_issues_per_7d: 3`,
  `cooldown_days: 7`, `labels: [aai-friction]`.
- Ledger: docs/ai/friction/upsert-ledger.jsonl (gitignored).
- Classification: PROFILES.yaml entries for the 2 new .aai files.

## Seam analysis (6a)
- SEAM 1 (triage -> upsert): consumes the triage report schema; INTEGRATION TEST
  runs triage then upsert over the produced report end-to-end.
- SEAM 2 (upsert -> gh): the ONLY external surface. A mock `gh` on PATH records
  every call; tests assert (a) prepare-only runs make no mutating call, (b) the
  confirmed path makes exactly one, (c) dedup search is read-only.
- SEAM 3 (payload -> redactor): the transmit pass reuses aai-redact; a poisoned
  payload field must be dropped before it can reach a `gh` argument.
- Residual risk: a real GitHub write is only exercised by a human with --confirm;
  the suite mocks gh (never makes a real network call). Recorded.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                       | Description                                                          | Status  |
|----------|------------|-------------|--------------------------------------------|----------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-feedback-upsert.sh   | plain review-mode run -> mock gh records ZERO mutating calls          | green |
| TEST-002 | Spec-AC-02 | unit        | tests/skills/test-aai-feedback-upsert.sh   | title/body templated from structured fields                          | green |
| TEST-003 | Spec-AC-03 | unit        | tests/skills/test-aai-feedback-upsert.sh   | a poisoned free-text payload field is dropped (transmit redaction)   | green |
| TEST-004 | Spec-AC-04 | integration | tests/skills/test-aai-feedback-upsert.sh   | existing v1:<fp> marker (mock search) -> no duplicate NEW issue       | green |
| TEST-005 | Spec-AC-05 | integration | tests/skills/test-aai-feedback-upsert.sh   | budget met in ledger -> prepared-deferred, not filed                 | green |
| TEST-006 | Spec-AC-06 | unit        | tests/skills/test-aai-feedback-upsert.sh   | destination pin read; auto refused; missing gh -> prepare-none       | green |
| TEST-007 | Spec-AC-07 | integration | tests/skills/test-aai-feedback-upsert.sh   | --publish --confirm -> exactly one create + ledger append; no-confirm -> none | green |
| TEST-008 | Spec-AC-01 | integration | tests/skills/test-aai-feedback-upsert.sh   | static: no mutating gh call outside the confirmed-publish seam        | green |
| TEST-009 | Spec-AC-08 | integration | tests/skills/test-aai-layer-profiles.sh    | new .aai files classified; layer-profiles green                      | green |
| TEST-010 | Spec-AC-08 | integration | tests/skills/test-aai-prompt-diet.sh       | prompt-diet ledger trued up; green                                   | green |

RED-proof: TEST-001..008 written first, observed FAILING against the absent engine
before GREEN. The `gh` binary is MOCKED via a stub on PATH so no real network call
is ever made by the suite.

## Verification
- `bash tests/skills/test-aai-feedback-upsert.sh` (green; RED first; gh mocked)
- `bash tests/skills/test-aai-layer-profiles.sh` + `test-aai-prompt-diet.sh` green
- `node .aai/scripts/docs-audit.mjs` CLEAN
- PASS: all TEST-xxx green AND all Spec-AC terminal (done + evidence)

## Evidence contract
Per artifact: ref_id feedback-upsert-review; Spec-AC + TEST links; command/scope;
exit code/verdict; evidence path; commit SHA when available.

Notes: This document defines HOW, not WHAT/WHY. It does not define workflow.
RFC-0012 D7/D8 require human approval at implementation time — this frozen spec is
presented for OWNER APPROVAL before any network code is written.
