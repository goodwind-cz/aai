```yaml
review:
  scope: "git diff main...HEAD (branch fix/test-018-workspace-isolation)"
  spec: docs/specs/SPEC-DRAFT-spec-test-018-workspace-isolation.md
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: non-compliant,
          citation: "Behavior itself IS correct: tests/skills/test-aai-run-tests.sh:592 moves `ws=\"$(mktemp -d \"$TMP_ROOT/ws18.XXXXXX\")\"` inside the `for invalid` loop (line 586), before both spawn_marked calls (594, 605), so each of the 6 cases gets a fresh workspace. TEST-001 passes (`awk '/^test_018\\(\\)/,/for invalid/{print}' ... | grep -c 'mktemp -d'` -> 0, matches spec bar). BUT TEST-002, the AC's OTHER required piece of evidence, FAILS as literally specified: `awk '/^test_018\\(\\)/,/^}/{print}' tests/skills/test-aai-run-tests.sh | grep -c 'mktemp -d'` -> 1, not the required >=6. This is not fixable without contradicting the spec's own 'Strategy: loop' (a single per-case mktemp line executed 6x at RUNTIME is always exactly 1 textual occurrence in source; only unrolling the mktemp call 6x — which would violate Art.2 KISS — could satisfy the literal count). The spec's RED-proof note even confirms this: pre-change count was 1 and the GREEN target is >=6, but the loop-based fix the spec itself mandates cannot move that number. TEST-002's command is self-contradictory against the spec's own declared strategy." }
      - { ac: Spec-AC-02, call: compliant,
          citation: "tests/skills/test-aai-run-tests.sh:615 `kill -9 \"$old_pid\" \"$fresh_pid\" >/dev/null 2>&1 || true` runs unconditionally every pass-path iteration, in addition to the pre-existing failure-branch kill at line 600. TEST-003 command (`grep -c 'kill -9 \"\\$old_pid\"'` over the function body) -> 2, matches the >=2 bar." }
      - { ac: Spec-AC-03, call: compliant,
          citation: "tests/skills/test-aai-run-tests.sh:597 `reap_run \"$invalid\" 1` and :607 `reap_run \"$invalid\" 60` both unchanged. TEST-004 (`grep -cE 'reap_run \"\\$invalid\" (1|60)\\)\"'`) -> 2, matches spec bar." }
      - { ac: Spec-AC-04, call: compliant,
          citation: "Ran `bash tests/skills/test-aai-run-tests.sh` locally (macOS): 20/20 tests PASS including 'PASS: invalid/unset/future STEP_START falls back to EXACT legacy MIN_AGE behavior for every case (never global)', exit 0. TEST-005 satisfied." }
      - { ac: Spec-AC-05, call: cannot-verify,
          citation: "`gh run list --workflow skill-suite --branch fix/test-018-workspace-isolation --limit 5` shows exactly ONE run at HEAD 1f725c291cc3bc5e9f211b00bf4212eee237910e, conclusion=success, status=completed. Spec's own TEST-006 bar requires >=2 successful runs at the same HEAD (the pushed run plus one `gh run rerun`); only 1 exists so far. Not a code defect — evidence is simply incomplete at review time; per dispatch instruction this does not block the review." }
  code_quality:
    verdict: pass
    findings: []
  cannot_verify:
    - { claim: "The fix eliminates the historical CI-load-only flake (PR #122/#127 'reaper output: reaped: 1' on a spare-fresh case).",
        closes_with: "A second (and ideally third) green `skill-suite` run at the same HEAD via `gh run rerun`, per Spec-AC-05/TEST-006 — statistical confidence grows with repeated green runs under load, it is never provable from a single run or from the diff alone." }
    - { claim: "No other in-flight branch/worktree depends on the old shared-`$ws` semantics of test_018() (e.g. an external script scraping test output by marker name pattern).",
        closes_with: "Full-repo grep for `ws18` / `vitest_old18_` / `vitest_fresh18_` outside this file (spot-checked: none found in this review, but not exhaustively swept against all branches)." }
  overall: fail
```

# Code Review — test-018-workspace-isolation

**Scope:** `git diff main...HEAD` on branch `fix/test-018-workspace-isolation`
(single commit `1f725c2`, single file `tests/skills/test-aai-run-tests.sh`,
+10/-2, confined to `test_018()`).
**Spec:** `docs/specs/SPEC-DRAFT-spec-test-018-workspace-isolation.md` (frozen, L1)

## Diff summary
- `ws="$(mktemp -d "$TMP_ROOT/ws18.XXXXXX")"` moved from once-above-the-loop
  (old line 568) to the top of the `for invalid` loop body (new line 592) —
  reassigned fresh every iteration, before either direction spawns a marker
  process.
- `reap_run()` (defined once, at line 579, before the loop) reads `$ws` by
  normal bash variable lookup at CALL time, not at definition time — since
  reassignment (line 592) executes before both call sites (597, 607) in every
  iteration, each case's `reap_run` invocations resolve that iteration's
  fresh `$ws`. Confirmed correct by reading and by the full-suite run below.
- Teardown at line 615 changed from `kill -9 "$fresh_pid"` only to
  `kill -9 "$old_pid" "$fresh_pid"`, unconditional, every iteration —
  in addition to the pre-existing failure-branch kill of `old_pid` at line
  600.
- `.aai/scripts/aai-reap-tests.sh` (production reaper) is NOT in the diff —
  confirmed via `git diff main...HEAD -- .aai/scripts/aai-reap-tests.sh`
  (empty output).

## AC table walk (see YAML above for full citations)
| Spec-AC | Call | Note |
|---|---|---|
| Spec-AC-01 | non-compliant | Behavior correct; TEST-002's literal grep bar (>=6) is unsatisfiable by the spec's own "loop" strategy — see below. |
| Spec-AC-02 | compliant | TEST-003 passes (2 >= 2). |
| Spec-AC-03 | compliant | TEST-004 passes (2 == 2), margins unchanged. |
| Spec-AC-04 | compliant | Full local suite: 20/20 PASS, exit 0. |
| Spec-AC-05 | cannot-verify | Only 1/2 required CI runs recorded so far; not a code defect, not blocking per dispatch note. |

### Spec-AC-01 detail — the TEST-002 gap
The actual requirement ("each of the 6 cases uses a FRESH `mktemp -d`
workspace — no single workspace variable assigned once above the loop and
reused") is genuinely met: I read the diff and confirmed the reassignment
site (line 592) sits inside the loop, before use, and re-ran the exact
TEST-001 command from the spec (0 `mktemp -d` calls before the loop — pass).
I additionally ran the full test file locally; TEST-018 passes, proving the
runtime semantics are correct.

However, the spec's OWN required second evidence item for this AC, TEST-002,
tests a static SOURCE-TEXT count (`grep -c 'mktemp -d'` over the whole
function body, expecting `>= 6`) as a proxy for "one workspace per case."
That proxy is structurally incompatible with the "Strategy: loop" the same
spec mandates in its Implementation Strategy section: a single `mktemp -d`
statement executed 6 times at runtime by a `for` loop is, and will always
be, exactly ONE textual occurrence in the source. The spec's own RED-proof
note records the pre-change count as 1; the post-change count is still 1 —
TEST-002 cannot discriminate RED from GREEN for the implementation the spec
itself prescribes. Satisfying TEST-002 literally would require unrolling the
mktemp call six times (or otherwise duplicating it), which is the WORSE
implementation and would violate the spec's own Art.2 KISS/YAGNI evidence
note ("minimal per-case mktemp + one additional unconditional kill line; no
new helper abstraction").

This is a **spec-authoring defect**, not an implementation defect. I am
calling Spec-AC-01 non-compliant strictly because the spec's own stated
evidence bar (TEST-001 AND TEST-002 both green) is not met — TEST-002 is
red — and per the review protocol I must not silently wave off a named,
required piece of evidence that fails as written, however reasonable the
actual code is. Recommended disposition (for the orchestrator, not decided
here): retire or rewrite TEST-002 (e.g., replace the static count with a
check that the `mktemp -d` assignment's line number is greater than the
`for invalid` loop's line number and less than the loop's closing `done` —
which is exactly what TEST-001 already establishes from the other
direction, making TEST-001 alone sufficient structural evidence for
Spec-AC-01), and record the correction as a `docs/ai/decisions.jsonl` entry
citing this review.

## Code quality — findings
None. BLOCKING: none. NON-BLOCKING: none.

Specifically checked and found sound:
- **State isolation correctness:** `$ws` reassignment (line 592) precedes
  both `reap_run` call sites (597, 607) in every loop iteration; bash
  resolves `$ws` at call time inside `reap_run` (dynamic scope, not a
  closure over a stale value), so no cross-iteration/cross-case workspace
  reuse is possible.
- **Teardown correctness:** both `old_pid` and `fresh_pid` are
  unconditionally killed on the pass path (line 615); the pre-existing
  failure-branch kill of `old_pid` (line 600) is preserved. A missed
  `reap-old` under load can no longer leak `old_pid` into a later case.
- **No leaked marker on the fail-fast path:** `log_fail` still `exit`s
  immediately (unchanged, out of scope), and the script-level
  `trap cleanup EXIT` sweep (line 70-71, `rm -rf "$TMP_ROOT"` plus the
  `SPAWNED_PIDS_FILE` tracked-pid sweep) still catches any process still
  alive at that point — consistent with the spec's own documented edge-case
  note.
- **Margins untouched:** `reap_run "$invalid" 1` / `"$invalid" 60` unchanged
  at their original call sites.
- **Portability:** `mktemp -d "$TMP_ROOT/ws18.XXXXXX"` template unchanged
  (full portable template, matches sibling tests' `ws16.XXXXXX`/
  `ws17.XXXXXX` pattern per LEARNED 2026-07-19).
- **Production reaper untouched:** confirmed via targeted diff (empty).
- **No overclaim in the commit:** `git log -1` message explicitly says
  "Honest limit: the flake is load-related and reproduces only under Linux
  CI — the fix removes the MECHANISM (verifiable structurally); CI green
  across a repeated run is the authoritative proof" — correctly hedges,
  does not claim the flake is proven gone by a single lucky run.

## cannot_verify (see YAML)
- CI double-run bar (Spec-AC-05/TEST-006): only 1 of the required 2 runs
  at HEAD `1f725c2` exists so far (`success`). Noted, not blocking per
  dispatch instruction — this is a load/CI-only claim that cannot be closed
  from the diff.
- No cross-branch/external dependency on the old shared-`$ws` marker naming
  was found by a spot-check grep, but this was not an exhaustive sweep.

## Next steps
1. Reconcile Spec-AC-01's evidence: either rewrite/retire TEST-002 (structural
   check incompatible with the mandated loop strategy) or record an explicit
   waiver decision in `docs/ai/decisions.jsonl` citing this report, before
   marking Spec-AC-01 "done" with accurate evidence.
2. Before merge, get a second green `skill-suite` run at the same HEAD
   (`gh run rerun` or a rebase-free empty push) to close Spec-AC-05/TEST-006
   per the spec's own stated bar.
3. No code changes required — the diff itself is correct and complete for
   Spec-AC-02/03/04.
