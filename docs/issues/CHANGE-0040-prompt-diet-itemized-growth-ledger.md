---
id: prompt-diet-itemized-growth-ledger
type: change
number: 40
status: draft
links:
  pr: []
  commits: []
---

# Change — prompt-diet: itemized justified-growth ledger (no magic-number bumps)

## Summary
- Replace the single hardcoded `JUSTIFIED_GROWTH_BYTES` magic number in
  `tests/skills/test-aai-prompt-diet.sh` with a summed array of itemized
  justified-growth entries (each `<bytes> <ref> <rationale>`). The credit
  becomes the auto-computed sum; adding a legitimate prompt addition is a
  one-line data append with its own audit trail, not a recomputed magic
  constant. On a floor breach, the test prints the exact ledger line to add.

## Motivation / Business Value
- Every workflow scope that adds canon-mandated `.aai/*.prompt.md` prose
  (SPEC-0017 diet, CHANGE-0037, CHANGE-0038, CHANGE-0039) re-breaches the
  byte-reduction floor and needs a manual `JUSTIFIED_GROWTH_BYTES` bump — the
  anti-bloat guard only flags it late (when the suite runs), and it was missed
  twice this session (main was red by 764 B until the ISSUE-0016 hygiene fix).
  The itemized comment ledger already exists as prose above the constant; making
  it the computed source of truth removes the magic number, makes each addition
  auditable, and makes the fix a trivial, self-documenting data append.

## Scope
- In scope: `tests/skills/test-aai-prompt-diet.sh` — the JUSTIFIED_GROWTH_BYTES
  definition (array + summation), the breach message (compute + print the exact
  entry to add), and preserving the existing anti-bloat headroom-cap guard.
- Out of scope: BASELINE_PROMPT_BYTES / REQUIRED_REDUCTION_BYTES (the SPEC-0017
  ratchet stays); the prompt corpus itself; any other test.

## Affected Area
- Prompt-diet byte-budget test; workflow ergonomics for prompt-touching scopes.

## Desired Behavior (To-Be)
- `JUSTIFIED_ADDITIONS` is an array of `"<bytes> <ref> <rationale>"` entries;
  `JUSTIFIED_GROWTH_BYTES` = the summed first fields. The three current entries
  (DEBT-0002 6144, CHANGE-0037 1309, CHANGE-0038+0039 1786; sum 9239) are
  migrated verbatim from the existing comment ledger — value byte-identical.
- On TEST-010 breach (reduction < required), the failure message computes the
  exact additional bytes needed and prints a ready-to-paste ledger entry
  (`"<deficit> <REF> <rationale>"`), so fixing it is copy-paste + fill the ref.
- The anti-bloat headroom-cap guard (0 ≤ headroom ≤ CAP) is unchanged and still
  bites (padding a ledger entry beyond real growth still fails).

## Acceptance Criteria
- AC-001: `JUSTIFIED_GROWTH_BYTES` is computed as the sum of an itemized
  `JUSTIFIED_ADDITIONS` array; the summed value equals the current 9239 (TEST-010
  headroom stays 1022/2048); the array entries carry the ref + rationale.
- AC-002: a breach (simulate by shrinking the credit array) prints a suggested
  ready-to-add ledger entry naming the exact deficit bytes; the anti-bloat cap
  guard still fails on an over-padded array. Existing prompt-diet stanzas
  (TEST-001..009, TEST-011) unchanged and green.

## Verification
- `tests/skills/test-aai-prompt-diet.sh` → exit 0; TEST-010 headroom 1022/2048.
- A unit-style check: the summation equals 9239; a padded array trips the cap;
  a shrunk array prints the suggested entry with the correct deficit.

## Constraints / Risks
- Behavior-preserving on the current corpus (sum == 9239). bash-3.2 array
  summation must be portable (the wrapper's Windows/Git-Bash matrix).

## Notes
- Source: ISSUE-0016 process_finding (2026-07-18) — the recurring prompt-diet
  floor re-breach. Completes the DEBT-0002 anti-bloat mechanism by making the
  credit auditable/self-documenting instead of a manually-bumped constant.
