```yaml
review:
  scope: "git diff main...HEAD (branch fix/test-canon-stat-portability); PR #121"
  spec: docs/specs/SPEC-DRAFT-spec-test-canon-stat-portability.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "tests/skills/test-aai-test-canon.sh:516,536,722,735 — all 4 sites now `stat -c %Y \"$f\" 2>/dev/null || stat -f %m \"$f\" 2>/dev/null`; grep -nE 'stat -f %m[^|]*\\|\\| *stat -c %Y' tests/skills/test-aai-test-canon.sh returns empty (exit 1), matching TEST-001" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "bash tests/skills/test-aai-test-canon.sh on this macOS/BSD host (Darwin 25.5.0) → 'Results: 19/19 passed, 0 failed', EXIT:0, incl. TEST-007 and TEST-012 (the two functions containing the 4 swapped sites) both PASS" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "gh run list --workflow skill-suite --branch fix/test-canon-stat-portability → run 29747513866, status completed/success, 7m49s, on PR #121 head commit b2ed7b5" }
  code_quality:
    verdict: pass
    findings: []
  cannot_verify:
    - { claim: "The swap is a genuine correctness fix on real Linux/GNU coreutils (not just CI's specific image) — i.e. GNU `stat -f` on a live Linux box truly returns --file-system output rather than erroring, so the pre-fix ordering silently mis-read.",
        closes_with: "Direct interactive test on a GNU/Linux host running `stat -f %m <file>` and observing non-error, non-mtime output — not reproducible in this macOS/BSD review environment; taken on the LEARNED.md RC2/RC4 precedent (docs/knowledge/LEARNED.md:170-172) and CI's green Ubuntu run as corroborating evidence instead." }
  overall: pass
```

# Code Review — test-canon-stat-portability (fix/test-canon-stat-portability)

## Scope
- Diff: `git diff main...HEAD` on branch `fix/test-canon-stat-portability`, single commit `b2ed7b5` ("fix(test): GNU-first stat for mtime in test-aai-test-canon.sh (RC4 class)").
- File touched: `tests/skills/test-aai-test-canon.sh` only — 4 lines changed (4 insertions / 4 deletions), lines 516, 536, 722, 735.
- PR: #121 (`goodwind-cz/aai`).
- Spec: `docs/specs/SPEC-DRAFT-spec-test-canon-stat-portability.md` (frozen, ceremony_level 1, L1 lane).

## AC table walk

| Spec-AC | Description | Call | Evidence |
|---|---|---|---|
| Spec-AC-01 | 4 sites GNU-first `stat -c`, BSD `stat -f` fallback | compliant | All 4 sites (test-aai-test-canon.sh:516, 536, 722, 735) verified read GNU-first-then-BSD; `grep -nE 'stat -f %m[^|]*\|\| *stat -c %Y' tests/skills/test-aai-test-canon.sh` → empty, exit 1. A positive-match grep for the correct GNU-first ordering (`stat -c %Y[^|]*\|\| *stat -f %m`) confirms exactly 4 hits at the expected line numbers. No 5th stray `stat -f`-first site anywhere in the file. |
| Spec-AC-02 | macOS non-regression | compliant | Ran `bash tests/skills/test-aai-test-canon.sh` on this review host (Darwin 25.5.0, BSD stat). Result: `Results: 19/19 passed, 0 failed`, `EXIT:0`. TEST-007 and TEST-012 — the two test functions containing all 4 modified lines — both report PASS. |
| Spec-AC-03 | Linux CI (`skill-suite`) green | compliant | `gh run list --workflow skill-suite --branch fix/test-canon-stat-portability` shows run 29747513866 for commit b2ed7b5, `completed`/`success`, 7m49s, triggered by `pull_request` (PR #121). |

## Per-site diff verification
Each of the 4 hunks is an identical, isolated operand-order swap; nothing else on the line changed:

- `tests/skills/test-aai-test-canon.sh:516` — `timestamps_before+="$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null):$f "` → `...stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null):$f "`. The `2>/dev/null` on both branches and the trailing `:$f "` accumulator suffix are byte-identical pre/post.
- `:536` — `ts_after=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null)` → GNU-first equivalent. `2>/dev/null` preserved on both branches, no other token changed.
- `:722` — `echo "$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null):$f"` → GNU-first. `2>/dev/null` and `:$f"` suffix preserved.
- `:735` — same pattern as :722, inside the `after_drift` block. `2>/dev/null` and `:$f"` suffix preserved.

Each swapped line's GNU-first form is byte-identical to the already-shipped reference pattern's *intent* at `tests/skills/test-aai-update.sh:245` (`stat -c '%u' ... || stat -f '%u' ... || true`) — same GNU-first-then-BSD ordering rationale, documented in `docs/knowledge/LEARNED.md:170-172` (RC2/RC4 class: "GNU `stat -f` SUCCEEDS on GNU as `--file-system` (wrong data) so `stat -f || stat -c` never falls through — try GNU `stat -c` FIRST").

## code_quality findings
None. This is a minimal, mechanical, behavior-preserving reorder with no new logic, no new edge case, and no touched production code path (test-harness only). No BLOCKING or NON-BLOCKING findings.

## Overclaim check
The spec (ceremony justification, lines 18-26) and the commit message both explicitly state this is "correctness hygiene" / an operand-order portability fix, and both explicitly disclaim curing the intermittent test-canon flake ("does NOT claim to fix the test-canon flake"). Verified: no scope-file, spec section, or commit-message line asserts flake resolution, root-cause diagnosis of the flake, or any behavioral claim beyond the stat-ordering correctness fix. No overclaim found.

## cannot_verify
- The diff and CI green run corroborate that GNU `stat -c` succeeds on Linux and the ordering fix is exercised in CI, but this review runs entirely on macOS/BSD — it cannot directly observe a live GNU `stat -f <file>` invocation returning wrong-but-non-erroring `--file-system` output on a bare Linux shell. This is taken on the LEARNED.md RC2/RC4 precedent and the passing CI run as corroborating (not directly reproduced) evidence.

## Warnings disposition (H6)
No NON-BLOCKING findings were raised; nothing to dispose.

## Verdict
**overall: pass** — spec_compliance pass (3/3 Spec-AC compliant), code_quality pass (0 findings). Ready for merge from a review standpoint.
