---
review:
  scope: "git diff main...HEAD (tests/skills/test-aai-run-tests.sh, docs/specs/SPEC-0072-*.md, docs/issues/ISSUE-0026-*.md, CHANGELOG.md, docs/INDEX.md, docs/ai/EVENTS.jsonl) plus uncommitted working-tree changes (docs/INDEX.md, docs/ai/EVENTS.jsonl, docs/specs/SPEC-0072-*.md — the table pipe-drop repair + Spec-AC-05 Review-By 2026-07-30->2026-08-06)"
  spec: docs/specs/SPEC-0072-spec-reaper-epoch-survivor-robustness.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "tests/skills/test-aai-run-tests.sh:551-565 — sleep 3 -> sleep 6, arithmetic comment (GRACE(2)+1s truncation=3s boundary; +1s STEP_START quantization=4s conservative) present with explicit DO-NOT-NARROW warning; TEST-001 structural grep evidence in AC table" }
      - { ac: Spec-AC-02, call: compliant, citation: "tests/skills/test-aai-run-tests.sh:672-731 (test_021) — Case A (ref+GRACE) SPARE, Case B (ref+GRACE+2) REAP, registered in ALL_TESTS at line 731; ran locally 4x green + confirmed green in CI Ubuntu run 30002328595 job 89190180419 ([30/42] aai-run-tests PASS 107.0s)" }
      - { ac: Spec-AC-03, call: compliant, citation: "tests/skills/test-aai-run-tests.sh:566-568 — AAI_REAP_MIN_AGE_SECS=999 + non-zero reaped assertion unchanged from pre-diff; `bash tests/skills/test-aai-run-tests.sh 017` exit 0 (verified locally 4x)" }
      - { ac: Spec-AC-04, call: compliant, citation: "git diff --stat main...HEAD -- .aai/scripts/aai-reap-tests.sh -> empty; git diff --stat -- .aai/scripts/aai-reap-tests.sh (working tree) -> empty; grep confirms GRACE=2 default intact in .aai/scripts/aai-reap-tests.sh:200" }
      - { ac: Spec-AC-05, call: compliant, citation: "honestly deferred, Review-By 2026-08-06 (today 2026-07-23 + exactly 14d, satisfies VALIDATION.prompt.md Rule 4's >=14-day floor). Evidence text does not overclaim: both observed CI runs (30002216044, 30002328595) on this branch show overall skill-suite FAILURE, but the failure is isolated to aai-docs-audit/aai-spec-lint self-referential findings against the SPEC-0072 table pipe-drop defect present at commit time (not yet pushed-fixed) — the aai-run-tests job itself (which carries TEST-017/021) PASSED on Ubuntu in both runs ([30/42] aai-run-tests PASS 107.0s). The row correctly states CI evidence is still PENDING/incomplete, not claiming a false green." }
      - { ac: Spec-AC-06, call: compliant, citation: "git diff --name-only main...HEAD confirms no .aai/*.prompt.md or AGENTS.md touched, no new .aai/** path added; AC table row present and 7-pipe-parseable (see code_quality note on the pipe-drop repair)" }
  code_quality:
    verdict: pass
    findings: []
  cannot_verify:
    - { claim: "Spec-AC-05's 'CI skill-suite green on Ubuntu across repeated runs' — the authoritative evidence for the original CI-load-only flake", closes_with: "a fresh push (containing the currently-uncommitted spec-table-pipe-fix + Review-By date change) followed by >=2 green skill-suite CI runs on this branch/PR; the spec's own AC-05 row already names this as the outstanding step and defers honestly to 2026-08-06" }
    - { claim: "The 20-sample empirical probe (macOS, k=0..3 offsets from GRACE) documented in the spec's 'RESIDUAL RISK — EMPIRICAL RESOLUTION' section and referenced in test_021's inline comment", closes_with: "no raw probe log/artifact exists under docs/ai/ for this measurement — it is narrated prose only; a stored log (e.g. docs/ai/tdd/ or docs/ai/reports/) would let this be independently re-verified rather than taken on the implementer's word. Not a spec-compliance failure (Spec-AC-02's own TEST-003 RED-proof stands on its own, via the stub-reaper GRACE=0 override, independent of this narrative), but the specific '0 in all 20 samples' figure is unverifiable from the diff alone." }
  overall: pass
---

# Code Review — reaper-epoch-survivor-robustness (SPEC-0072 / ISSUE-0026)

## Scope
- `git diff main...HEAD`: `tests/skills/test-aai-run-tests.sh` (+80/-10),
  `docs/specs/SPEC-0072-spec-reaper-epoch-survivor-robustness.md` (new, 410
  lines), `docs/issues/ISSUE-0026-reaper-epoch-survivor-robustness.md` (new),
  `CHANGELOG.md` (+24), `docs/INDEX.md`, `docs/ai/EVENTS.jsonl`.
- Uncommitted working-tree changes (reviewed together per dispatch): the
  SPEC-0072 AC-Status-table pipe-drop repair (Spec-AC-06 / TEST-006 rows
  rewritten pipe-free) and the Spec-AC-05 Review-By bump
  (2026-07-30 -> 2026-08-06).
- The only code file in scope: `tests/skills/test-aai-run-tests.sh`.
  `.aai/scripts/aai-reap-tests.sh` (the production reaper) is confirmed
  byte-unchanged on both the committed diff and the working tree (see
  Spec-AC-04 below).

## Spec compliance — AC table walk
All six Spec-AC rows: **compliant**. See the structured `ac_walk` block above
for per-row citations. Highlights:

- **Spec-AC-01** (`test_017` margin widen): the inline comment
  (`tests/skills/test-aai-run-tests.sh:551-561`) states the exact arithmetic
  — lenient model `GRACE(2)+1s(truncation)=3s` (the old, zero-slack boundary)
  and conservative model `+1s(STEP_START quantization)=4s` — and the new
  `sleep 6` clears both with 3s and 2s of slack respectively, matching the
  spec's Arithmetic section (Spec-AC-01) exactly. A "DO NOT NARROW" warning
  is present and names the re-derivation obligation, not just a bare
  admonition.
- **Spec-AC-02** (`test_021`): verified the core safety property called out
  in the dispatch — **`STEP_START` never lands in the future**. Both Case A
  (`ref_epoch+grace`) and Case B (`ref_epoch+grace+2`) are computed from a
  `ref_epoch` captured via `date +%s` *before* the spawn, followed by a
  `sleep 4` and, before Case B, an additional reaper-run + `sleep 1` — by
  Case B's invocation at least ~5s have elapsed since `ref_epoch`, so
  `ref_epoch+4 <= SNAP_NOW` holds with comfortable margin. Confirmed against
  `.aai/scripts/aai-reap-tests.sh:186-196`: epoch mode requires
  `step_start_norm <= SNAP_NOW`, and a future value falls back to the
  SAFETY-CRITICAL legacy fail-safe (`aai-reap-tests.sh:27-30`) — which would
  have made the test assert against the wrong mode entirely. This does not
  happen here; both cases stay in the past by construction. TEST-018 (the
  legacy-fail-safe test) is unmodified and continues to own that path.
- **`grace=2` local constant**: it IS coupled to the reaper's own default
  (`AAI_REAP_GRACE_SECS` default `2`, `aai-reap-tests.sh:200`), and this is
  NOT a hidden/undocumented coupling — it is called out explicitly three
  times: in the test's own header comment ("GRACE below MUST track
  aai-reap-tests.sh's own AAI_REAP_GRACE_SECS default (2)... if the reaper's
  default ever changes, this constant must change with it"), in the spec's
  "Seam analysis" section (naming the residual risk that a future GRACE
  change could go unnoticed, with no automated guard proposed, deliberately
  out of scope), and in Spec-AC-02's own text. No finding.
- **Cleanup on failure paths**: `test_021`'s `survivor_pid` is tracked via
  the existing `spawn_marked` -> `track()` -> `SPAWNED_PIDS_FILE` mechanism
  (`tests/skills/test-aai-run-tests.sh:61,79-85`), which is read by the
  script-global `cleanup()` on `trap cleanup EXIT` (lines 63-74). Because
  `log_fail` calls `exit 1` at the top level (not inside a subshell), ANY
  failure inside `test_021` (Case A or Case B) unwinds through the global
  trap, which `kill -9`s every tracked pid and removes the whole `$TMP_ROOT`
  (including `ws21`). This is the same mechanism every other test in the
  suite (including `test_017`, `test_016`, `test_018`) relies on for
  cleanup, so `test_021` does not deviate from — or weaken — the existing
  contract. Distinct from the ISSUE-0023 defect: that bug was a **shared
  workspace across multiple cases inside TEST-018** causing cross-case
  reaping (fixed by giving each case its own `mktemp -d`); `test_021` uses
  a single workspace (`ws21`) for its one survivor across both of its own
  cases by design (the same survivor is meant to be reaped in Case B after
  surviving Case A), which is a different, correct structure — no shared
  state across DIFFERENT tests exists here.
- **Registration**: `ALL_TESTS` includes `"021"`
  (`tests/skills/test-aai-run-tests.sh:731`). Confirmed by running
  `bash tests/skills/test-aai-run-tests.sh 017 021` (PASS, 3x locally) and
  the full suite `bash tests/skills/test-aai-run-tests.sh` (21/21 PASS
  locally; separately confirmed `[30/42] aai-run-tests PASS (107.0s)` in
  CI Ubuntu run 30002328595).
- **Portability**: `mktemp -d "$TMP_ROOT/ws21.XXXXXX"` — full template, no
  bare `mktemp`. No `date -d`/`-j`, no `ps -o lstart` anywhere in the diff.
  Reaper invoked via `sh "$REAP_SCRIPT"`. Confirmed green on Ubuntu CI
  (above) and macOS (local).
- **No retry/loop-until-pass**: confirmed absent from both `test_017`'s
  change and `test_021` — each case runs the reaper exactly once and asserts
  the outcome directly.
- **Spec-AC-04** (production reaper untouched): both
  `git diff --stat main...HEAD -- .aai/scripts/aai-reap-tests.sh` and
  `git diff --stat -- .aai/scripts/aai-reap-tests.sh` (working tree) return
  empty. `GRACE=2` confirmed intact at `aai-reap-tests.sh:200`.
- **Table parse integrity**: independently re-counted raw `|` per row for
  both the AC Status table (7 rows incl. header, all 7 pipes) and the Test
  Plan table (8 rows incl. header, all 7 pipes) — no row carries a literal
  pipe any more; Spec-AC-06 and TEST-006 are both present and countable.
  Cross-checked with `node .aai/scripts/spec-lint.mjs --path
  docs/specs/SPEC-0072-*.md` -> `LINT PASS: no structural findings` and
  `node .aai/scripts/docs-audit.mjs --gate spec-reaper-epoch-survivor-robustness`
  -> `GATE PASS`. (Note: the CI runs observed on this branch predate the
  working-tree fix and still show the old dropped-row findings — see
  cannot_verify.)
- **Spec-AC-05 deferral honesty**: Review-By `2026-08-06` is exactly 14 days
  from today (2026-07-23), satisfying `VALIDATION.prompt.md` Rule 4's
  "at least 14 days out" floor with no slack to spare but no violation
  either. The deferral is scoped narrowly to the one thing that genuinely
  cannot be produced from a local run — repeated CI-Ubuntu-green evidence
  for a CI-load-only flake — and is not used to dodge evidence for any other
  AC; all other five rows carry concrete, checkable evidence.

## Code quality — findings
None. `BLOCKING`: none. `NON-BLOCKING`: none.

Reviewed for: security, correctness, data loss, performance, concurrency,
error handling — none apply meaningfully to a test-fixture-only diff with no
product code touched, and the specific risk classes named in the dispatch
(future-STEP_START mode-flip, hidden GRACE coupling, leaked marked
processes, missing dispatch registration, non-portable constructs, masked
boundary via retry) were each checked individually above and found absent.

## cannot_verify
1. **Repeated CI-Ubuntu-green for Spec-AC-05.** Both CI runs observed on this
   branch (`30002216044`, `30002328595`) show overall `skill-suite`
   FAILURE — but the failure in each is isolated to `aai-docs-audit` /
   `aai-spec-lint` self-referential findings against the SPEC-0072 table
   pipe-drop defect that existed in the *committed* spec doc at the time of
   those runs (the fix for that defect is currently only in the working
   tree, not yet pushed). The `aai-run-tests` job itself — which runs
   TEST-017 and TEST-021 — **passed** in both runs
   (`[30/42] aai-run-tests PASS (107.0s)`), which is strong corroborating
   evidence the boundary fix holds on the platform where the original flake
   was observed. This closes once the working-tree fix is committed/pushed
   and the `skill-suite` job goes green (ideally across >=2 runs, per the
   spec's own TEST-004 definition). The AC table's Spec-AC-05 row already
   states this honestly as PENDING — not a compliance gap, but flagged here
   per the mandatory cannot_verify contract.
2. **The 20-sample empirical probe** (`k=0..3` offset measurements against
   the real reaper on macOS) cited in the spec's "RESIDUAL RISK — EMPIRICAL
   RESOLUTION" section and in `test_021`'s inline comment. No raw log
   artifact for this measurement exists under `docs/ai/`; it is prose-only.
   Does not affect the pass verdict — `test_021`'s own TEST-003 RED-proof
   (stub reaper with `GRACE=0`) independently demonstrates the test is
   non-tautological regardless of this narrative — but the specific "0 in
   all 20 samples" figure itself cannot be independently confirmed from the
   diff.

## Evidence log
```
$ git diff --stat -- .aai/scripts/aai-reap-tests.sh
(empty)
$ git diff --stat main...HEAD -- .aai/scripts/aai-reap-tests.sh
(empty)

$ bash tests/skills/test-aai-run-tests.sh 017 021
... PASS: epoch mode reaps a genuine pre-step survivor regardless of a high legacy MIN_AGE
... PASS: epoch boundary pinned by arithmetic: SPARE at ref+GRACE, REAP at ref+GRACE+2 (no wall-clock race)
PASS: All selected aai-run-tests tests passed
(repeated 4x total, all green)

$ bash tests/skills/test-aai-run-tests.sh   # full 21/21
... PASS: All selected aai-run-tests tests passed

$ node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0072-spec-reaper-epoch-survivor-robustness.md
LINT PASS: no structural findings.

$ node .aai/scripts/docs-audit.mjs --gate spec-reaper-epoch-survivor-robustness
GATE PASS: AC Status table complete (every row terminal, every done row evidenced, every Review-By valid).

$ gh pr view 131 --json statusCheckRollup
skill-suite FAILURE (both runs) -> isolated to aai-docs-audit/aai-spec-lint
  self-check against the pre-fix table; aai-run-tests job itself:
  [30/42] aai-run-tests PASS (107.0s) in both runs (30002216044, 30002328595)
```

## Next steps
- Commit + push the working-tree SPEC-0072 table repair and Review-By date
  change so a fresh CI run picks up the fix and can produce the repeated
  green evidence Spec-AC-05 is deferred on.
- No BLOCKING or NON-BLOCKING findings to disposition.
