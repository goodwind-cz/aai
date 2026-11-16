# Code Review — metrics-integrity-fixes (round 1)

```yaml
review:
  scope: "uncommitted diff vs origin/main 16773cdf in /Users/ales/Projects/aai-worktrees/metrics-integrity-fixes, paths: .aai/scripts/lib/metrics-flush-record.mjs; .aai/scripts/validation-outcome-check.mjs; tests/skills/test-aai-merge-cleanup.sh; tests/skills/test-aai-outcome-backcheck.sh; tests/skills/test-aai-role-output.sh; docs/product/telemetry.md; CHANGELOG.md; docs/issues/ISSUE-DRAFT-metrics-integrity-fixes.md; docs/specs/SPEC-DRAFT-spec-metrics-integrity-fixes.md"
  spec: docs/specs/SPEC-DRAFT-spec-metrics-integrity-fixes.md
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "tests/skills/test-aai-merge-cleanup.sh test_026 second half (f026_* helpers, L1/L2 over fixture repo F); TEST-026 PASS this review" }
      - { ac: Spec-AC-02, call: compliant, citation: "test_3771_test_026_is_hermetic; TEST-3771 PASS this review; suite holds none of the five needles" }
      - { ac: Spec-AC-03, call: compliant, citation: "metrics-flush-record.mjs readBaseLedger + recoverStateCopy; TEST-3772 PASS (removed blob kept; noref and nofile recover 1)" }
      - { ac: Spec-AC-04, call: compliant, citation: "metrics-flush-record.mjs inner try around writeFileSync; TEST-3773 PASS" }
      - { ac: Spec-AC-05, call: compliant, citation: "TEST-3774 PASS (plan exit 0, digest equal, keep (ledger_runs_unchecked held ledger temp write failed ()" }
      - { ac: Spec-AC-06, call: compliant, citation: "validation-outcome-check.mjs:391,407,418; TEST-3775 PASS; outcome-backcheck suite exit 0" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-3776 PASS; role-output suite exit 0" }
      - { ac: Spec-AC-08, call: compliant, citation: "CHANGELOG.md:33 heading; docs/product/telemetry.md:210; TEST-3777 PASS" }
    deviations:
      - "D2 step 1 (frozen): 'No such ref (git rev-parse --verify -q <ref>^{commit} exit 1, no stderr)'. readBaseLedger treats every exit 1 as absent and never reads stderr; a broken ref exits 1 WITH stderr and must be step 4 (keep). See CR-1."
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/lib/metrics-flush-record.mjs, line: 198,
          issue: "readBaseLedger classifies rev-parse exit 1 as 'absent' without the spec's no-stderr condition, so a broken base ref is read as 'nothing held' and the recovery writes",
          failure_scenario: "main checkout whose refs/remotes/origin/main is a broken loose ref (truncated/garbage after an interrupted fetch) or points at a non-commit: rev-parse prints 'warning: ignoring broken ref' / 'expected commit type' and exits 1; recoverStateCopy returns keep null, recovered 1 and writes the ride's run with no base ledger held, so a run already merged on the base but not yet pulled is written twice (the exact class fu-held-ledger-git-show-silent closes). Repro exits 1 for both shapes." }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-DRAFT-spec-metrics-integrity-fixes.md, line: 124,
          issue: "spec D2 step 1 itself admits a ref whose object is missing as 'absent': rev-parse --verify -q <ref>^{commit} exits 1 with NO stderr when the ref file names a missing object",
          failure_scenario: "refs/remotes/origin/main names a commit object that was pruned/lost: rev-parse exit 1 silent, classified absent, recovery writes without the base ledger (same double-write class). git ls-tree <ref> on that ref exits 128, so probing existence with rev-parse --verify -q <ref> (no ^{commit}) and letting ls-tree classify would keep the step." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-role-output.sh, line: 1140,
          issue: "new positional selector accepts only function names; the TEST-id form other suites accept (e.g. TEST-3776) is refused as 'unknown selector'",
          failure_scenario: "aai-run-tests.sh bash tests/skills/test-aai-role-output.sh TEST-3776 exits 1 'unknown selector' instead of running the case; before this diff any argument ran the whole suite" }
  cannot_verify:
    - { claim: "Linux/CI git produces the same rev-parse exit codes and stderr for the broken-ref shapes (probe run on git 2.54.0 Apple)", closes_with: "run the repro on the ubuntu CI image" }
    - { claim: "the whole repository suite stays green (only the scope's suites and selected cases ran in this review; the full sweep is owed before close per the validation report)", closes_with: "one full sweep with AAI_TEST_TIMEOUT=4500 on the remediated tree" }
    - { claim: "ENOBUFS / spawn-error branches of readBaseLedger (R3) and an apply run over an unreadable base (spec 'Not crossed by a test')", closes_with: "a fixture that forces maxBuffer overflow or a missing git binary, and an apply-mode case" }
  overall: fail
```

security_relevant: false

## Scope and spec

- Scope: the uncommitted diff of branch `fix/metrics-integrity-fixes` against `origin/main` (16773cdf), worktree mode (STATE `worktree.user_decision: worktree`), the nine paths named in STATE `code_review.scope`. `git status --porcelain` showed only those paths plus `docs/ai/EVENTS.jsonl` (append-only: 18 added lines, base is a byte-exact prefix).
- Spec: docs/specs/SPEC-DRAFT-spec-metrics-integrity-fixes.md (frozen, ceremony 2, tdd).
- Dispatch note: the dispatch relayed the validator's remark about the missing stderr check in D2 step 1. Recorded here as a characterization of an expected finding; the full scope was reviewed regardless, and the finding below rests on an independent probe that reaches a different conclusion from the validator (the validation report NB-3 says exit 1 happens "only for a missing ref"; it does not).

## Verdict 1 — spec_compliance: FAIL

AC walk (all eight rows compliant, each test re-run green in this review):

| Spec-AC | Call | Citation |
|---|---|---|
| Spec-AC-01 | compliant | TEST-026 second half builds F (ride-merged 2099, ride-open, ride-late 2000), L1/L2 via real `spec-amend add`/`classify`, buckets, oracle exit 0 "OK 2 merged contract records" over L1, exit 1 naming the late key over L2, `list --strict` exit 0. PASS. |
| Spec-AC-02 | compliant | TEST-3771: copied `.aai/` + `tests/`, no `.git`/`docs`, exit 0 + `PASS: TEST-026`; five needles absent. PASS. |
| Spec-AC-03 | compliant | TEST-3772 removed-blob keep + noref/nofile controls. PASS. |
| Spec-AC-04 | compliant | TEST-3773 TMPDIR under a regular file: no throw, keep, METRICS unchanged. PASS. |
| Spec-AC-05 | compliant | TEST-3774 plan keep text through the planner. PASS. |
| Spec-AC-06 | compliant | `readStateFocus` path/origin/error text; TEST-3775. PASS. |
| Spec-AC-07 | compliant | TEST-3776 via check-role-output. PASS. |
| Spec-AC-08 | compliant | CHANGELOG heading (count 1), telemetry.md sentence; TEST-3777. PASS. |

Deviation from the frozen spec (fails this verdict): **D2 step 1** defines "absent" as `rev-parse --verify -q <ref>^{commit}` "exit 1, **no stderr**"; everything else is step 4 (keep the step). The implementation (`.aai/scripts/lib/metrics-flush-record.mjs` line 198, `if (has.status === 1) return { absent: true };`) drops the stderr condition. The AC rows do not exercise this, which is why every row passes while the decision is not implemented.

## Verdict 2 — code_quality: FAIL

### BLOCKING CR-1 — a broken base ref is read as "absent" (metrics-flush-record.mjs:197-198)

Failure scenario: the main checkout's `refs/remotes/origin/main` is a broken loose ref (garbage content after an interrupted write) or names a non-commit object. `git rev-parse --verify -q 'refs/remotes/origin/main^{commit}'` exits 1 and prints to stderr (`warning: ignoring broken ref refs/remotes/origin/main` / `error: ... expected commit type, but the object dereferences to tree type`). `readBaseLedger` returns `{ absent: true }`, `recoverStateCopy` runs the recovery without the base ledger and returns `{"would":1,"refs":["foo"],"recovered":1,"keep":null}`. A run merged on the base but not yet pulled is then written a second time, the double write this scope's intake item (2) exists to stop.

Probe (git 2.54.0):

| ref shape | rev-parse rc | stderr | spec D2 class | code class |
|---|---|---|---|---|
| missing | 1 | none | absent | absent |
| garbage content | 1 | `warning: ignoring broken ref` | step 4 keep | **absent** |
| points at a tree | 1 | `error: ... expected commit type` | step 4 keep | **absent** |
| not a repository | 128 | fatal | step 4 keep | step 4 keep |

backed-by: repro /private/tmp/claude-501/-Users-ales-Projects-aai/2071b3a2-d378-409f-946d-cd8edb99948a/scratchpad/cr-repro/repro-broken-base-ref.sh (run as `bash <repro> /Users/ales/Projects/aai-worktrees/metrics-integrity-fixes`; exit 1 = reproduced, both shapes print `DEFECT`). The repro builds a main checkout with one METRICS line committed, replaces the loose ref, writes a ride STATE (focus foo, one Planning run) and a ride METRICS lacking it, then calls `recoverStateCopy({..., origin: <main>, base: "main"})` and checks for the `base ledger unreadable` keep.

Recommended remediation (in tree): treat exit 1 as absent only when `has.stderr.trim() === ''`; otherwise `bad(has, 'git rev-parse')`. Add a TEST-3772 arm with a garbage loose ref (keep `base ledger unreadable (`, METRICS byte-identical) and a matching mutation.

### NON-BLOCKING CR-2 — spec gap: a ref to a missing object is silent (spec D2 step 1)

Failure scenario: `refs/remotes/origin/main` names a commit object that is gone (lost/pruned). `rev-parse --verify -q <ref>^{commit}` exits 1 with no stderr, so D2 as written (and the code, even after CR-1) calls it absent and recovers without the base ledger. `git ls-tree <ref> -- docs/ai/METRICS.jsonl` on the same ref exits 128 (`fatal: not a tree object`), so testing ref existence with `rev-parse --verify -q <ref>` (no `^{commit}`, exit 0 for this ref) and letting the existing `ls-tree` step classify would keep the step. Changing it changes D2's text. Recommended disposition: remediate in tree with the CR-1 fix under the additive-with-disclosure amendment convention, or promote to a follow-up (suggested id `fu-held-ledger-ref-missing-object`, P3; not filed).

### NON-BLOCKING CR-3 — role-output selector refuses the TEST-id form (test-aai-role-output.sh:1140-1146)

Failure scenario: `aai-run-tests.sh bash tests/skills/test-aai-role-output.sh TEST-3776` ends with `unknown selector: TEST-3776` (exit 1), whereas the merge-cleanup suite accepts both `TEST-xxx` and the function name. Before this diff any argument ran the whole suite, so a caller passing an id now gets a failure instead of a (broader) run. Recommended disposition: (d) `accepted residual: test-harness selector shape only (no shipped code, no false record); the function-name form works`, or map `TEST-3776` in the same branch if CR-1 is being remediated anyway.

### Checked, no finding

- D3: temp write inside the inner try, `finally` swallows its own `rmSync` error; `tmp` is only set when there are bytes, and only pushed to `held` after a successful write.
- `keepText`/`fallbackOf` hoisted unchanged in content; `recoverWith` keep text is byte-identical to before (TEST-3756/3761 unaffected, suites green).
- D4: no `.aai/STATE.yaml` remains in `.aai/`, `docs/product/`, or `tests/skills/` except TEST-3775's deliberate negative fixture.
- merge-cleanup.mjs unchanged, 1490 lines (TEST-058 ceiling held).
- New `cd` sites are inside `( ... )` with absolute non-empty targets; `check-cd-subshell-leak.mjs` exit 0.
- New test code under `set -euo pipefail`: `|| rc=$?` / `set +e ... set -e` around every captured rc; no `printf | grep -q`.
- TEST-3771 copies about 16 MB and runs one nested case; it cannot recurse (only TEST-026 is selected in the copy).
- Test names: none claims a universal negative beyond what it asserts (TEST-3771 "runs in a tree without .git and without the live ledger" is exactly what it runs).

## cannot_verify

1. Linux/CI git gives the same rc/stderr for the broken-ref shapes — closes with the repro on the ubuntu CI image.
2. Full repository sweep green — owed before close (validation report: `sweep_owed=1`).
3. ENOBUFS / spawn-error branches (spec R3) and `apply` over an unreadable base — closes with dedicated fixtures.

## Evidence (this review)

| Command | Exit |
|---|---|
| `aai-run-tests.sh bash tests/skills/test-aai-merge-cleanup.sh TEST-026` / `TEST-3771` / `TEST-3772` / `TEST-3773` / `TEST-3774` / `TEST-3777` | 0 each |
| `aai-run-tests.sh bash tests/skills/test-aai-outcome-backcheck.sh` | 0 |
| `aai-run-tests.sh bash tests/skills/test-aai-role-output.sh` | 0 |
| `node .aai/scripts/check-cd-subshell-leak.mjs` | 0 |
| `bash <scratchpad>/cr-repro/repro-broken-base-ref.sh <worktree>` | 1 (defect reproduced, both shapes) |
| git rev-parse probes (missing / garbage / tree / non-repo / missing-object) | see tables above |

## Warning dispositions (H6)

- CR-2: recommended remediate-in-tree with CR-1 (spec amendment, additive-with-disclosure) or promote to follow-up `fu-held-ledger-ref-missing-object` (suggested, not filed). The orchestrator records the choice.
- CR-3: recommended disposition (d): `accepted residual: test-harness selector shape only (no shipped code, no false record); the function-name form works`.

## Next steps

1. Remediate CR-1 (stderr condition) with a RED-proofed TEST-3772 arm (garbage loose ref) and its mutation record.
2. Decide CR-2 (fold into the remediation with a disclosed amendment of D2 step 1, or file the follow-up).
3. Re-validate and re-review (round 2); run the owed full sweep before close.
