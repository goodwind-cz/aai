```yaml
review:
  scope: "git diff (uncommitted working tree, branch fix/test-018-legacy-spare-attribution vs main; branch has 0 commits ahead of main so main...HEAD is empty — actual diff is the working tree) -- .aai/scripts/aai-reap-tests.sh tests/skills/test-aai-run-tests.sh"
  spec: docs/specs/SPEC-DRAFT-spec-test-018-legacy-spare-attribution.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/aai-reap-tests.sh:170-174,295-301 -- independently reproduced: 2-matched fixture -> 'reaped: 2' + 'reaped pids: <p1> <p2>'; 0-matched fixture -> 'reaped: 0' + 'reaped pids:' (empty tail, line present); identical output under dash" }
      - { ac: Spec-AC-02, call: compliant, citation: "git diff -- .aai/scripts/aai-reap-tests.sh | grep -E '^-' | grep -v '^---' -> 0 lines (reproduced); bash tests/skills/test-aai-run-tests.sh 006 013 015 016 017 -> PASS all 5, unmodified (reproduced)" }
      - { ac: Spec-AC-03, call: compliant, citation: "discriminating external-kill fixture independently reproduced end-to-end: PRE-FIX (main's test file + main's reaper, external kill of fresh_pid injected before the assertion) -> FAIL 'fail-safe broken ... reaper output: reaped: 0' (mis-attribution, matches red-20260724T135656Z-test018-discriminating.log); POST-FIX (working-tree test file + working-tree reaper, same injected kill) -> PASS, exit 0" }
      - { ac: Spec-AC-04, call: compliant, citation: "tests/skills/test-aai-run-tests.sh:672-687 -- extracted-logic repro of reaped_pids_of/reaper_reaped_pid/dump block against 4 synthetic cases: dump fires + assertion PASS on stub reaped>0 with an unrelated pid; dump absent + PASS on reaped:0; dump fires + assertion FAIL when the reaper's own list names fresh_pid; dump fires + PASS on a substring-adjacent pid (123 vs 1234, no false match)" }
      - { ac: Spec-AC-05, call: compliant, citation: "git status --short -- only .aai/scripts/aai-reap-tests.sh, tests/skills/test-aai-run-tests.sh, docs/ai/tests/test-runs.jsonl modified + 2 untracked docs/specs and docs/issues DRAFT docs; no .aai/*.prompt.md, no .aai/AGENTS.md, no new .aai/** path" }
      - { ac: Spec-AC-06, call: cannot-verify, citation: "correctly deferred in the AC Status table, Review-By 2026-08-10 (17 days out, >=14d); spec's Honesty section explicitly forbids claiming the flake 'fixed' and the doc never does (grep confirmed) -- CI evidence is out of scope for a local review" }
  code_quality:
    verdict: pass
    findings: []
  cannot_verify:
    - { claim: "the CI-Linux-only spare-fresh mis-attribution flake is actually eliminated end-to-end under real CI load (Spec-AC-06)", closes_with: "gh run list/view on skill-suite.yml for this branch across >=2 runs, per the spec's own TEST-009 -- explicitly deferred, not claimed done" }
    - { claim: "the evidence-dump's `ps`/etime capture will contain useful data the NEXT time the CI-only race actually recurs (i.e. the dump's practical diagnostic value, as opposed to its firing/silence behavior which was verified)", closes_with: "a real CI recurrence with the dump output attached to the run log" }
  overall: pass
```

# Code review -- test-018-legacy-spare-attribution

## Scope
Working-tree diff against `main` (branch `fix/test-018-legacy-spare-attribution` has 0 commits ahead of `main`, so `git diff main...HEAD` is empty; the actual reviewable diff is the uncommitted working tree, per dispatch):
- `.aai/scripts/aai-reap-tests.sh` (+12/-0)
- `tests/skills/test-aai-run-tests.sh` (+42/-3, one net-additive assertion rewrite)
- `docs/ai/tests/test-runs.jsonl` (+1, telemetry from Validation's local run)
- `docs/specs/SPEC-DRAFT-spec-test-018-legacy-spare-attribution.md`, `docs/issues/ISSUE-DRAFT-test-018-legacy-spare-attribution.md` (new, untracked)

Spec: `docs/specs/SPEC-DRAFT-spec-test-018-legacy-spare-attribution.md`, SPEC-FROZEN: true, ceremony_level 1.

## Spec-AC table walk (evidence reproduced independently, not just cited from prior artifacts)

**Spec-AC-01 (reaper additive `reaped pids:` line) -- compliant.** Read `.aai/scripts/aai-reap-tests.sh` diff line by line: two hunks, both pure `+` (confirmed below under code_quality). Ran three fixtures directly against the edited script:
- 2 matched procs, `AAI_REAP_MIN_AGE_SECS=1`: `reaped: 2` / `reaped pids: <pid1> <pid2>` (exact spawned pids).
- 0 matched (fresh proc, `MIN_AGE=60`): `reaped: 0` / `reaped pids:` (line present, empty tail).
- Same 2-matched fixture run under `dash` explicitly: identical output.

**Spec-AC-02 (decision logic byte-unchanged) -- compliant.**
```
git diff -- .aai/scripts/aai-reap-tests.sh | grep -E '^-' | grep -v '^---' | wc -l
```
returned 0 (verified myself, not just cited). `bash tests/skills/test-aai-run-tests.sh 018 006 013 015 016 017` -- all 6 tests PASS, TEST-006/013/015/016/017 unmodified and green.

**Spec-AC-03 (attribution assertion, THE discriminating row) -- compliant.** Reproduced the full RED->GREEN cycle myself rather than trusting the TDD log:
- Built a pre-fix copy (`git show main:...`) of `test_018` with an injected `kill -9 "$fresh_pid"` immediately after the `reap_run` call and before the assertion (single-case loop for speed), run against `main`'s reaper: **FAIL** -- `fail-safe broken (case='UNSET'): legacy MIN_AGE=60 must still spare the fresh match (reaper output: reaped: 0)`. This is the demonstrable mis-attribution: the reaper's own count says 0, yet the old liveness check fails.
- Applied the same external-kill injection to the working-tree (post-fix) test file, run against the working-tree (post-fix) reaper: **PASS**, exit 0.
This is real behavioral discrimination (old code fails a case the reaper did not cause; new code correctly spares it), not a static/RED-by-absence proof.

**Spec-AC-04 (evidence dump) -- compliant.** Extracted the diff's `reaped_pids_of`/`reaper_reaped_pid`/dump block verbatim into an isolated harness and ran 4 cases: (1) stub `reaped: 1` with an unrelated pid -> dump fires (6 DIAG lines to stderr), assertion still PASSES; (2) normal `reaped: 0` -> dump absent, assertion PASSES; (3) reaper's own list names `fresh_pid` -> dump fires, assertion correctly FAILS; (4) exact-token guard: `fresh_pid=123` against a reported list containing `1234` -> no false match, assertion PASSES (rules out the substring-match bug the dispatch specifically flagged). The dump writes to stderr only (`>&2`), is read-only (`ps`, `grep -F`), and never touches process state.

**Spec-AC-05 (companion obligations) -- compliant.** `git status --short` shows only the two in-scope files + `docs/ai/tests/test-runs.jsonl` (Validation's local test-run telemetry, itself not a companion-obligation trigger) + the two untracked DRAFT docs. No `.aai/*.prompt.md`, no `.aai/AGENTS.md`, no new `.aai/**` path -- prompt-diet ledger and PROFILES.yaml classification correctly do not apply.

**Spec-AC-06 (CI-authoritative, deferred) -- cannot-verify (as expected).** Status table row is `deferred`, Review-By `2026-08-10` = 17 days from today (2026-07-24), clearing the >=14d floor. The spec's Honesty section forbids an outright "fixed" claim; grepped the full document for "fixed"/"de-flaked" phrasing -- the only two hits are the negative-form Honesty statements ("Do NOT claim the flake is 'fixed'", "never sufficient to claim the flake is de-flaked"). No overreach found.

## Code quality (production-safety focus: reaper decision logic)

Read `.aai/scripts/aai-reap-tests.sh` diff line by line against the full file:
- Two hunks, both strictly additive (`git diff | grep '^-' | grep -v '^---'` = 0 lines, confirmed above).
- Hunk 1 (ps-snapshot-failure early-exit path, line ~170-174): adds `echo "reaped pids:"` after the pre-existing `echo "reaped: 0"` / before `exit 0`. Byte-identical `reaped: 0` line preserved.
- Hunk 2 (normal exit path, line ~294-301): adds `echo "reaped pids:$MATCH_PIDS"` after the pre-existing, byte-identical `echo "reaped: $REAPED"` line, before `exit 0`. `MATCH_PIDS` is read-only here -- last write is the existing accumulator loop (`MATCH_PIDS="$MATCH_PIDS $pid"`, line 251, untouched); the new line performs zero computation, zero reordering, zero new guard.
- Grep sanity check: existing consumers' patterns (`grep -qiE "reaped: *[1-9]"`, `grep -qxE "reaped: *0"`) do not accidentally match the new `reaped pids:` line (verified by running the full regression set 018/006/013/015/016/017/017's sibling 021-style boundary check green, and by direct pattern testing) -- and the new line's own parser (`sed -n 's/^reaped pids://p'`) does not match the old `reaped: N` line. The two lines are separate and mutually non-interfering by construction (different prefixes: `reaped:` vs `reaped pids:`).
- POSIX-safety: no `[[`, no `+=`, no arrays, no `${x^^}` in either added line; both are plain `echo`. Verified the added lines execute identically under `dash`.

Test-side (`tests/skills/test-aai-run-tests.sh`):
- `reaper_reaped_pid` uses `[[ "$tok" == "$want" ]]` -- exact string equality per loop token, not substring; independently confirmed `123` does not false-match a reported `1234` (case 4 above).
- Empty-list case: `reaped_pids_of` on an empty tail yields an empty `$()` expansion, the `for tok in ...` loop does not execute, function correctly returns 1 (not-reaped) -- confirmed.
- Absent-line case (defensive, not currently reachable since both reaper exit paths always emit the line): `reaper_reaped_pid` against `out="reaped: 0"` (no `reaped pids:` line at all) returns 1 (not-reaped) rather than erroring -- a safe default, and not exploitable to vacuously pass Spec-AC-03 because the fixture that actually discriminates (Spec-AC-03's RED/GREEN cycle above) runs the real, edited reaper, which always emits the line.
- No margin widening: `MIN_AGE=1` / `MIN_AGE=60` and the `sleep 3` / split-direction structure are textually unchanged (confirmed by diff -- only the block after `reap_run "$invalid" 60` gained the dump + attribution check; direction 1's block is untouched). No retry/loop-until-pass was added anywhere in the diff.
- `aai-reap-tests.ps1` (Windows twin): confirmed untouched (`git status --short` shows no `.ps1` entry).

No BLOCKING or NON-BLOCKING findings. The two items above (absent-line fallback, MATCH_PIDS-as-"matched" vs "confirmed-killed" semantics) are pre-existing design choices explicitly called out in the spec's Design section, carry no failure scenario under the current code (both reaper exit paths always emit the line; the count semantics are unchanged from before this diff), and are noted here as INFO only -- not gating.

## Test quality
- The discriminating fixture (external kill + reaper genuinely reaping 0) was reproduced by this reviewer end-to-end, both directions: RED against the pre-fix code (real `main` reaper + real `main` test logic, not a paraphrase), GREEN against the post-fix code. This is the load-bearing proof that the assertion rewrite is not vacuous.
- `reaped_pids_of`/`reaper_reaped_pid` were exercised directly against 4 hand-built cases including the substring-adjacency case the dispatch specifically asked to rule out -- no vacuous-pass bug found.
- `mktemp` usage: no new `mktemp` calls were introduced by this diff (the evidence dump uses read-only `ps`, no temp files); all pre-existing `mktemp -d "$TMP_ROOT/ws18.XXXXXX"` templates are untouched.
- bash 3.2 compatibility: `local want="$1" tok`, `[[ ... ]]`, `for tok in $(...)` -- no bash-4+ constructs (`+=`, associative arrays, `${x^^}`) introduced.

## Table pipe-count-safety recheck
Row TEST-005 (Test Plan table) contains a shell command with 3 literal `|` characters (`git diff ... \| grep -E '^-' \| grep -v '^---' \| wc -l`); all three are backslash-escaped (`\|`) inside the markdown cell, confirmed by direct read of the raw line. All 18 remaining table rows (AC Status + Test Plan) have a uniform 8-pipe column count; no unescaped-pipe row-count drift found.

## Protected paths / companion obligations
`docs/ai/docs-audit.yaml:protected_paths_l3` (8 entries) directly read; neither `.aai/scripts/aai-reap-tests.sh` nor `tests/skills/test-aai-run-tests.sh` appears in it, matching the spec's claim. Companion obligations (prompt-diet ledger, PROFILES.yaml) confirmed N/A per the diff's actual file list (Spec-AC-05 above).

## Seam check (reaper stdout consumers)
Confirmed `.aai/scripts/aai-run-tests.sh` does not grep/parse reaper stdout at all (no `reaped` reference beyond an unrelated comment). Confirmed every other `test-aai-run-tests.sh` consumer of reaper output uses a per-line `reaped: *[1-9]` / `reaped: *0` pattern that does not collide with the new `reaped pids:` line -- and reran the full unaffected set (018/006/013/015/016/017) green as direct proof, not just static inspection.

## Next steps
No BLOCKING findings; no open WARNINGs requiring a disposition. Recommend proceeding toward PR; Spec-AC-06 remains correctly `deferred` and must stay that way until real CI evidence (TEST-009) lands -- do not let a merge/PR-ready claim upgrade Spec-AC-06 to `done` without it.
