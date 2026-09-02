---
id: ac-table-premature-flip-recurs
number: 78
type: issue
status: done
links:
  pr:
    - TBD
  commits:
    - cbead77
---

# AC-table premature-flip defect recurs despite a documented rule (needs a mechanical guard)

## Summary
- `.aai/VALIDATION.prompt.md` step 8a documents a rule (AC-FLIP DEFERRAL):
  a spec/issue doc's `## Acceptance Criteria Status` table rows must NOT be
  flipped to a terminal status (`done`) until the close ceremony
  (`close-work-item.mjs`, via SKILL_PR step 4c) flips them in the SAME
  transaction as the frontmatter `status: done` flip.
- `docs-audit.mjs` treats "AC table terminal + evidenced, but frontmatter
  non-terminal" as a "probable-false-open" drift signal and reddens
  `--check --strict`, which cascades into failures across
  `test-aai-doc-numbering.sh` TEST-013, `test-aai-deslop.sh` TEST-028,
  `test-aai-docs-audit.sh`, `test-aai-delta-stage3.sh`,
  `test-aai-doc-number-reservation.sh`, and `test-aai-repo-tripwire.sh`
  TEST-006.
- Despite the rule being written down, this exact mistake happened twice in
  one session: once during the CHANGE-0168/intake-staleness-preflight ride
  (self-caught and self-fixed by the orchestrator before it reached
  Validation), and again as the ISSUE-0046 ride's Validation round 1 FAIL-1
  (caught by Validation, not prevented before it).

## Type
- bug

## Impact
- Who/what is affected? Every ride's Implementation role, which is the point
  where the premature flip is actually introduced (an agent finishes an AC
  and marks the status table row `done` in the same edit, before the close
  ceremony's transactional flip).
- Severity/priority: P2 — never reached `main` in either observed instance
  (caught before merge both times), but each occurrence costs a full extra
  Validation or Remediation round: a genuine regression fix, RED/GREEN proof,
  and a full 84-test-class sweep re-run, purely to correct a mechanical
  formatting mistake that a lint rule could reject at write-time instead of
  catch-time.

## Current Behavior
- The rule exists only as prose in `.aai/VALIDATION.prompt.md` step 8a,
  enforced by Validation reading the diff and by `docs-audit.mjs`'s
  probable-false-open heuristic — both of which fire AFTER the mistake is
  already made and staged, requiring a full remediation round to unwind.
- Nothing at Implementation time (the point where the mistake is actually
  introduced) checks or blocks a same-commit AC-table-terminal +
  frontmatter-non-terminal combination before Implementation hands off to
  Validation.

## Expected Behavior
- A mechanical guard (a lint/check step, not a prose reminder) runs at or
  before Implementation's own hand-off — ideally as part of Implementation's
  existing self-check step or a lightweight pre-Validation script — and
  rejects (or clearly warns on) any diff where an AC-table row is flipped to
  a terminal status while the doc's own frontmatter `status` remains
  non-terminal, catching the exact class of mistake immediately rather than
  one full role-dispatch cycle later.
- Planning decides the precise mechanism (a new dedicated checker script, an
  extension of `docs-audit.mjs`'s existing probable-false-open logic exposed
  as a fast pre-check, or a lightweight grep-based guard invoked from the
  Implementation role prompt itself); this intake does not prescribe the
  implementation, only the requirement that the check runs BEFORE Validation
  rather than only during it.

## Steps to Reproduce (if applicable)
1. During Implementation, finish work satisfying an AC and, in the same
   commit/diff, edit the spec/issue doc's `## Acceptance Criteria Status`
   table row for that AC from `implementing` to `done` with evidence —
   WITHOUT also flipping the doc's frontmatter `status:` field to `done`
   (frontmatter correctly stays `implementing` since the close ceremony
   hasn't run yet).
2. Hand off to Validation and run a full sweep including
   `node .aai/scripts/docs-audit.mjs --check --strict`.
3. Observe: `docs-audit.mjs` flags the doc as a probable false-open (AC table
   terminal + evidenced, frontmatter non-terminal), and every test suite that
   asserts a literal `Verdict: CLEAN` from a full strict docs-audit run turns
   red: `test-aai-doc-numbering.sh` TEST-013, `test-aai-deslop.sh` TEST-028,
   `test-aai-docs-audit.sh`, `test-aai-delta-stage3.sh`,
   `test-aai-doc-number-reservation.sh`, `test-aai-repo-tripwire.sh` TEST-006.

## Verification
- Command(s) and expected results:
  - With the guard in place, reproduce step 1 above (premature flip) at
    Implementation time: the guard must fire immediately (fail-fast or a
    clearly surfaced warning in Implementation's own output), before the
    scope is ever handed to Validation.
  - Negative control: an AC table correctly left at `implementing` until the
    close ceremony (today's correct behavior) must NOT trip the new guard —
    verify on a known-good ride's diff.
  - Negative control: the close ceremony's OWN transactional flip (AC table
    AND frontmatter both flipped to `done` together, by
    `close-work-item.mjs`) must NOT trip the new guard — it is the one
    legitimate place this combination is allowed to appear.

## Constraints / Risks
- The guard must distinguish "AC table terminal, frontmatter non-terminal,
  introduced by Implementation" (the defect) from "AC table terminal,
  frontmatter terminal, introduced transactionally by close-work-item.mjs"
  (the correct end state) — a naive guard that just forbids the AC table
  ever reading `done` while `implementing` is in flight would also need to
  tolerate the split-second the close ceremony itself performs both edits,
  if the check ever runs as a commit-time hook rather than purely at
  Implementation hand-off.
- Should reuse `docs-audit.mjs`'s existing probable-false-open detection
  logic rather than reimplementing the same heuristic a second time, to
  avoid the two drifting apart.
- No secret is referenced by this scope (SECRETS PREFLIGHT skipped).

## Notes
- Filed per operator request after a retrospective review of session
  friction points. Related: [[role-progress-heartbeat]] and
  [[metrics-flush-invalidates-pr-precondition]] are the other two systemic
  friction patterns identified in the same review.
