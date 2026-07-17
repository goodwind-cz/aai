---
kind: code-review
ref: spec-lint-duplicate-ac-id
scope: ISSUE-0011 / SPEC-0051
lane: lightweight-L1
reviewer: aai-code-review (dual-verdict, SPEC-0021)
timestamp: 20260717T213126Z
---

```yaml
review:
  scope: "git diff main -- .aai/scripts/spec-lint.mjs tests/skills/test-aai-spec-lint.sh docs/specs/SPEC-0051-spec-lint-duplicate-ac-id.md docs/issues/ISSUE-0011-spec-lint-duplicate-ac-id.md"
  spec: docs/specs/SPEC-0051-spec-lint-duplicate-ac-id.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/spec-lint.mjs:298-303 + TEST-001(dupac) green + reviewer probe (3-raw/2-parse fixture emits duplicate-ac-id, exit 1)" }
      - { ac: Spec-AC-02, call: compliant,
          citation: ".aai/scripts/spec-lint.mjs:302 (message names id, rc, pc, dropped delta) + TEST-001(dupac) asserts exact 'appears in 2 raw ... only 1 survived' string" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "pc>=1 guard .aai/scripts/spec-lint.mjs:300 + TEST-002(dupac) both-parse->ac-id-duplicate only, TEST-003(dupac) vanished->ac-row-unparseable only" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "if(ac.hasGate) gating + AC_ID_RE filter (:280,:296) + (?=\\s|\\|) range exclusion; TEST-004(dupac) compact/range/lean exit 0; reviewer anchoring probe (1-digit/3-digit/range all excluded on both sides)" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "real corpus run: 51 scanned, 0 findings, 0 duplicate-ac-id, exit 0; full suite 18/18 green; test diff numstat 208/0 (purely additive, no existing assertion edited)" }
  code_quality:
    verdict: pass
    findings: []
  cannot_verify:
    - { claim: "Deferred lean-table dropped-duplicate detection is genuinely safe across all real lean specs (not just the L1 fixture)",
        closes_with: "corpus already lints clean at exit 0 with 0 duplicate-ac-id (TEST-005 dupac / TEST-009); deferral is documented residual risk in SPEC-0051 Out-of-scope. No open concern." }
  overall: pass
```

## Scope and spec

Uncommitted diff on `fix/spec-lint-duplicate-ac-id` vs `main`, four paths.
Frozen spec: SPEC-0051 (SPEC-FROZEN: true, ceremony_level 1, L1). Inputs
reviewed: the spec, ISSUE-0011, the diff, and
`docs/ai/reports/validation-20260717T212654Z-spec-lint-duplicate-ac-id.md`
(PASS). No git worktree; explicit path-list scope per dispatch — clean.

## Verdict 1 — spec_compliance: PASS

AC-table walk above: all 5 Spec-AC rows compliant, each independently
re-verified (not just trusted from the validation report). TEST-001..005(dupac)
all exist and pass; the exact delta-message assertion in TEST-001(dupac) pins
Spec-AC-02. Test diff is 208 insertions / 0 deletions — Spec-AC-05's "zero edits
to existing assertions" holds literally.

## Verdict 2 — code_quality: PASS (no BLOCKING, no NON-BLOCKING findings)

Judged independently against the five points of specific attention:

1. **rawCount region scoping (would false-positive on a Test-Plan Spec-AC
   mention).** SAFE. The `rawCount` tally lives inside the SAME loop that emits
   `ac-row-unparseable`, iterating `section[1]` where `section` is
   `## Acceptance Criteria Status` matched by
   `/(?:^|\n)##\s+Acceptance Criteria Status\b[^\n]*\n([\s\S]+?)(?=\n##\s|\n*$)/i`.
   The parsed side (`ac.rows` from `parseAcTable`) uses a **character-identical**
   section regex (docs-model.mjs:554), so raw and parsed anchor to the exact same
   row region — no second parse, no boundary drift. The non-greedy `(?=\n##\s...)`
   stops the region before `## Test Plan`, so a `Spec-AC` reference there is out of
   region; and Test-Plan rows begin `| TEST-xxx`, not `| Spec-AC`, so they cannot
   match the raw regex regardless. No false positive.

2. **The `parsedCount >= 1` guard arithmetic (a third dropped copy slipping).**
   SOUND. The raw regex matches even a cell-count-broken row (its first cell never
   carries the escaped pipe), so every raw `| Spec-AC-NN` row — dropped or not — is
   tallied. A "third dropped copy" therefore pushes `rawCount` to 3, never leaves it
   at 2; nothing slips. Reviewer probe confirmed the mixed 3-raw/2-parsed shape
   (see INFO below). `pc >= 1` correctly hands `pc == 0` (fully vanished) to
   `ac-row-unparseable`.

3. **AC_ID_RE anchoring (`Spec-AC-3`, `Spec-AC-012`).** CORRECT and, critically,
   SYMMETRIC. Reviewer probe: `Spec-AC-3` and `Spec-AC-012` both capture via the
   raw regex's `\d+` but are rejected by `AC_ID_RE` (`^Spec-AC-(\d{2})$`) on the
   raw side (:280) AND by the identical `AC_ID_RE.test` on the parsed side (:296).
   Because BOTH sides exclude them identically, no rc/pc mismatch can arise from a
   1-/3-digit id — no false positive. Range `Spec-AC-02..05` returns `null` from the
   raw regex (the `(?=\s|\|)` lookahead sees `.`), contributing nothing to rawCount,
   exactly as the spec claims.

4. **Finding message names id and a correct, non-misleading delta.** YES. It names
   the id, the raw count `rc`, the surviving count `pc`, and `dropped = rc - pc`
   with correct singular/plural. Placeholder rows (`Spec-AC-xx`, `<...>`) are
   excluded from BOTH counts (raw regex needs `\d`; parseAcTable skips them), so the
   delta never counts a placeholder.

5. **Deferred lean-table case is safe.** YES. The entire new block is inside
   `if (ac.hasGate)`; a lean L0/L1 table has `hasGate === false`, so the block never
   runs — no crash, no partial/wrong finding on a lean table with a dropped
   duplicate. TEST-004(dupac) lean arm confirms exit 0 / zero findings. The
   deferral is documented residual risk in SPEC-0051.

No security, correctness, data-loss, performance, concurrency, or error-handling
defect found. No finding carries a failure scenario, so none gates.

### INFO (non-gating, no disposition duty — not a WARNING)

- **Mixed 3-raw/2-parsed shape emits BOTH `ac-id-duplicate` and
  `duplicate-ac-id`.** SPEC-0051's partition table frames the three shapes as
  "exactly one rule fires." For the *mixed* shape (an id that parses twice AND has a
  third copy dropped), both rules fire — reviewer-confirmed empirically. This is
  NOT a false positive: both findings are true and non-misleading (there really are
  two parsed duplicates and one dropped row), and it is arguably more complete.
  Recording only because the spec's "non-overlapping partition" prose does not name
  this mixed case. Behavior is correct; no change recommended. INFO only.

## cannot_verify

- Whether the deferred lean-table dropped-duplicate path is safe beyond the single
  L1 fixture. Closed in practice by the clean corpus run (exit 0, 0 duplicate-ac-id
  across 51 specs) and the documented, accepted residual-risk deferral. No open
  concern.

## Overall: PASS

Both verdicts pass. No BLOCKING or NON-BLOCKING findings; one INFO note that does
not gate and carries no disposition duty. Merge-ready from the review's standpoint.

## Recording
- `state.mjs set-code-review --status pass` (this report).
- `code_review_completed` event.
