---
id: prompt-diet-floor-credit-drift
number: 17
type: issue
status: draft
links:
  pr: []
  commits: []
---

# Prompt-diet byte floor drift: verify-gate TEST-006 lacks the justified-growth credit

## Summary
- Two prompt-diet byte floors share the same baseline (357457) and required net
  reduction (28672 B) but only one applies the `JUSTIFIED_GROWTH_BYTES` credit.
  `tests/skills/test-aai-verify-gate.sh` TEST-006 has no credit term and now
  fails on `main` (net reduction 20455 < 28672).

## Type
- bug

## Impact
- `main` is red: `./tests/skills/test-aai-verify-gate.sh` exits 1 (TEST-006).
- Severity: medium — a real gate regression on the default branch; blocks a
  clean full-suite run. No production/runtime behavior affected (test-infra only).

## Current Behavior
- `test-aai-prompt-diet.sh` TEST-010 computes
  `reduction = BASELINE - after - extra + JUSTIFIED_GROWTH_BYTES` where
  `JUSTIFIED_GROWTH_BYTES = 9239` (portable sum of the `JUSTIFIED_ADDITIONS`
  ledger). It PASSES.
- `test-aai-verify-gate.sh` TEST-006 computes
  `reduction = BASELINE - after - extra` (NO credit term) against the same
  BASELINE=357457 and floor=28672, despite its own comment claiming it is the
  "same formula, re-measured here". It FAILS: `20455 < 28672`.
- Root cause: this session's ledger true-ups (CHANGE-0038/0039/0040) legitimately
  grew `.aai/*.prompt.md` and were credited in the prompt-diet ledger ONLY; the
  second (verify-gate) copy of the floor was never given the credit mechanism, so
  the credited growth double-counts as a floor violation there.

## Expected Behavior
- Both floors apply the identical formula (incl. the justified-growth credit) and
  cannot drift apart. `20455 + 9239 = 29694 >= 28672`, so TEST-006 should PASS.

## Steps to Reproduce (if applicable)
1) On `main`, run `./tests/skills/test-aai-verify-gate.sh`.
2) Observe `FAIL TEST-006 prompt-diet floor broken (net reduction 20455 bytes <
   28672; after=328748, new files=8254)` and exit code 1.

## Verification
- `./tests/skills/test-aai-verify-gate.sh` exits 0 (TEST-006 PASS).
- `./tests/skills/test-aai-prompt-diet.sh` still exits 0 (TEST-010/012/013 —
  ledger integrity unchanged: `JUSTIFIED_ADDITIONS` still sums to 9239).
- Both suites read the shared ledger from a single source; changing the ledger in
  one place is reflected in both (drift structurally impossible).

## Constraints / Risks
- Known risks or constraints: `test-aai-prompt-diet.sh` is heavily tested
  (TEST-012/013 assert `declare -p JUSTIFIED_ADDITIONS` exists and re-sums to
  9239); the shared-ledger extraction MUST preserve that array's name, contents,
  and 9239 sum, and keep bash-3.2 / Windows-Git-Bash portability (no `bc`,
  `mapfile`, `declare -A`). Run BOTH suites after the change.
- No secret referenced — SECRETS PREFLIGHT skipped.

## Notes
- This is the recurring "two copies of one gate, only one maintained" drift the
  workflow is meant to eliminate structurally (docs/knowledge/LEARNED.md records
  the DEBT-0002/drift pattern). Fix = single sourceable ledger both suites read,
  e.g. `tests/skills/lib/prompt-diet-ledger.sh`.
- Discovered by a serialized full-suite verification run on 2026-07-19.
