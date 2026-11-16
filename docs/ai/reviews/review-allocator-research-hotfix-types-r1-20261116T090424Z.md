# Code Review — allocator-research-hotfix-types (round 1, L3)

```yaml
review:
  scope: "origin/main...HEAD (base c1034b24, head 9ac8a661) in /Users/ales/Projects/aai-worktrees/allocator-research-hotfix-types, branch fix/allocator-research-hotfix-types"
  spec: docs/specs/SPEC-DRAFT-spec-allocator-research-hotfix-types.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/allocate-doc-number.mjs:88-89; TEST-3794 (tests/skills/test-aai-doc-numbering.sh test_3794_research_hotfix_types) rc 0 under bash 3.2" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "tests/skills/test-aai-intake.sh:659-661 (ABSENT -> ok=0); TEST-3795 = TEST-013 selector rc 0 shipped, rc 1 with hotfix unmapped" }
      - { ac: Spec-AC-03, call: compliant,
          citation: ".aai/scripts/allocate-doc-number.mjs:1257-1258; TEST-3796 rc 0 (rc 1 with unresolved guard); TEST-3797 = test_439 rc 0, exclusion removed at tests/skills/test-aai-doctor.sh:2381-2385" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "CHANGELOG.md:33; TEST-3798 rc 0; release-cut.mjs roll on a scratch copy rolls it to '## [v2026.11.16] — fix: ...' rc 0" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-doc-numbering.sh, line: 1927,
          issue: "TEST-3796 creates its symlink dir with mktemp under ${TMPDIR:-/tmp}, outside $TEST_DIR; every log_fail before the final rm -rf exits the arm subshell, and the suite trap only cleans $TEST_DIR, so a failing arm leaks the dir",
          failure_scenario: "any TEST-3796 assertion fails (e.g. the unresolved-guard mutant from the Test Plan, or a mutation-run replay): $TMPDIR/aai-alloc-symlink.XXXXXX (a symlink to the repo root plus d.err/s.err) is left behind; reproduced with TMPDIR=<scratch>/tmp -> 1 leftover dir" }
  cannot_verify:
    - { claim: "the new arms pass on the Linux CI runner (bash 5, GNU tools)",
        closes_with: "CI green on the PR head SHA" }
    - { claim: "the realOrResolve guard behaves on Windows exactly as on macOS",
        closes_with: "Windows CI leg green; the shape is byte-identical to round-budget.mjs/release-cut.mjs/hook-gate.mjs, so parity is inherited, not measured here" }
    - { claim: "the whole test framework stays green (full sweep owed, select-suites FULL_RUN reason=protected-l3)",
        closes_with: "one full sweep before close with AAI_TEST_TIMEOUT=4500 (spec Verification 5)" }
    - { claim: "the post-#535 merge result keeps both suites green",
        closes_with: "re-run test-aai-doc-numbering.sh and test-aai-doc-number-reservation.sh after whichever PR merges second (spec R2); textual merge measured clean only" }
  overall: pass
```

security_relevant: false

## Scope and spec

- Scope: `git diff origin/main...HEAD`, base c1034b24 (= merge-base), head 9ac8a661,
  2 commits. `git status --porcelain` in the worktree shows only the dispatch-time
  `docs/ai/EVENTS.jsonl` append, outside the reviewed diff.
- Spec: docs/specs/SPEC-DRAFT-spec-allocator-research-hotfix-types.md (frozen, L3).
- Files in the diff: `.aai/scripts/allocate-doc-number.mjs` (+4/-3),
  `tests/skills/test-aai-doc-numbering.sh` (+147), `tests/skills/test-aai-intake.sh`
  (+14/-3), `tests/skills/test-aai-doctor.sh` (+2/-8), `CHANGELOG.md` (+6), the intake
  draft, the spec, `docs/INDEX.md` (generated) and `docs/ai/EVENTS.jsonl` (append).
- Dispatch note: the dispatch listed areas to check and described INDEX/EVENTS as
  generated telemetry. That names no expected finding and no severity. I reviewed the full
  scope anyway: the INDEX diff adds the spec and the draft rows only, and the EVENTS base
  blob is a byte-exact prefix of the head blob (`cmp` over the first base-length bytes).
- All experiments ran in a scratch clone of the worktree under
  /private/tmp/claude-501/-Users-ales-Projects-aai/2071b3a2-d378-409f-946d-cd8edb99948a/scratchpad/cr.
  No tracked file in the worktree was changed. The only write is this report.

## Verdict 1 — spec_compliance: pass

| Spec-AC | Call | Evidence (this review) |
|---|---|---|
| Spec-AC-01 | compliant | TYPE_MAP rows at allocate-doc-number.mjs:88-89 match the table rows in `.aai/INTAKE_COMMON.md:52,54`. `.aai/INTAKE_RESEARCH.prompt.md:4-5` saves under docs/specs/ from RESEARCH_TEMPLATE. `.aai/INTAKE_HOTFIX.prompt.md:4-5` saves under docs/issues/ from ISSUE_TEMPLATE, whose Type section reads `bug \| hotfix`. docs/specs holds RES-0001..0004 plus the legacy RESEARCH-0001. `test_3794_research_hotfix_types` selector run: rc 0. On a scratch clone of the real corpus, `--dry-run --type research` numbers RES-0005 (RESEARCH-0001 is not counted) and `--type hotfix` numbers ISSUE-0119 on the shared ISSUE counter. The base copy exits 2 with `unknown --type "research"`. |
| Spec-AC-02 | compliant | The ABSENT branch now sets `ok=0` (test-aai-intake.sh:659-661). Selector run of TEST-013 on the shipped map: rc 0, 8 rows "matches TYPE_MAP". With `hotfix` renamed to `hotfix_` in a scratch copy: rc 1, naming `intake type 'hotfix' has no TYPE_MAP entry`. |
| Spec-AC-03 | compliant | The guard at allocate-doc-number.mjs:1257-1258 is the shared `realOrResolve` shape. Measured through a dir symlink with absolute argv, through a dir symlink with relative argv (cwd inside the link), through a file symlink, and with `--preserve-symlinks-main`: all exit 2 `unknown --type "bogus"`. The base copy through a symlink exits 0 with no output. TEST-3796: rc 0, and rc 1 with the Test Plan's unresolved-guard mutant. TEST-439 (`test_439_argv1_guard_resolves_symlinks`): rc 0 with the by-name exclusion removed. |
| Spec-AC-04 | compliant | CHANGELOG.md:33 reads `## [unreleased] — fix: the doc-number allocator accepts research and hotfix, and runs through a symlinked checkout`. It is a per-entry heading under the scaffold, and exactly one matches. `release-cut.mjs roll` on a scratch copy: rc 0, rolled to `## [v2026.11.16] — fix: ...`, which the TEST-3798 regex still accepts. |

TEST-xxx existence: TEST-3794, TEST-3796 and TEST-3798 are new arms registered in the
doc-numbering arm list. TEST-3795 is the existing TEST-013 and TEST-3797 the existing
TEST-439. All five pass here under /bin/bash 3.2.57. Their mutation records and replays are
cited in validation r2 (mutation-gate GATE PASS 5 rows; replay 5/5 redden). I did not
re-run the recorded replays. I re-ran two of the mutants by hand, TEST-3795 and TEST-3796,
and both reddened.

Deviations from the frozen spec. All are disclosed and none narrows an AC:
- D-1: `test-aai-intake.sh` main() gains a single-test selector (lines 1967-1975). It is not
  in the Implementation plan. It is needed so `mutation-run.mjs` can isolate TEST-013.
- D-2: the TEST ids were added to the TEST-013 log_fail (intake:820) and the TEST-439
  log_fail (doctor:2408).
- D-3: the remediation commit 9ac8a661 rewrote TEST-3794 step 1 to import by absolute path
  through an env var instead of a `cd` in a command substitution. Behaviour is unchanged,
  and check-cd-subshell-leak.mjs exits 0.
- D-4: the D4 text says "the other 22 resolved CLIs". The repo has more `realOrResolve`
  guards than that (51 argv[1] comparison lines, all of them resolved). That is a
  measurement in the spec text, not a defect in the code.

Allocator minimality (#535 overlap): three hunks: the import swap, the two TYPE_MAP rows,
and the guard. `pathToFileURL` has no remaining use in the file. `git merge-tree
--write-tree HEAD <#535 head b1c76b98>` auto-merges allocate-doc-number.mjs with no
conflict. The conflicts it reports are in other files, from #535's older base.

Blast radius: TYPE_MAP is read only by `resolveType`, and `resolveType` only by
`draftFilename` and the `--type` check in main(). No other script consumes it, so the two
rows cannot change scanning, guard or backfill behaviour.

### ISSUE-0042 close (--paired): its Verification holds in full

| Bullet | Measured here |
|---|---|
| A verbatim template copy passes both post-save checks | All 8 templates carry exactly one `number:` line (`/usr/bin/grep -c`). TEST-3794 step 2 passes `--intake-file` on verbatim RESEARCH and ISSUE template copies. Validation r2 covers all 8 pairs × 2 checks. |
| `--type research` / `--type hotfix` build a DRAFT path | `draftFilename` returns `docs/specs/RES-DRAFT-probe.md` and `docs/issues/ISSUE-DRAFT-probe.md` (TEST-3794 step 1). The CLI accepts both (dry-run above). D2 reads a bare `--type` as still "nothing selected", the same as for `issue`. |
| A double-spaced row is seen identically by awk and `parseIntakeTypeTable` | TEST-013 output: "both readings agree: 8 rows, identical row set" and "bite proven: double-spaced ninth row". |
| An over-length follow-up id is refused at write | `follow-ups.mjs add` with a 55-char id: rc 2, "is 55 chars (max 40)", ledger stays 0 bytes. The registry lists `fu-report-ids-exceed-registry-cap` as done. |

Expected Behavior bullet 2 ("the allocator knows every type the table declares") is now
pinned both ways by TEST-013. That also anchors the concern of the dropped
`fu-intake-dir-unanchored-research-hotfix`: the research and hotfix rows can no longer
drift together while the suite stays green. ISSUE-0042 can close done.

## Verdict 2 — code_quality: pass

### Realpath guard
The guard is correct for every shape I measured: an absolute or relative symlinked argv,
a file symlink, `--preserve-symlinks-main`, and an import where argv[1] is a non-file
word such as `node -e ... research` in TEST-013. In that last case `realpathSync` throws,
the guard falls back to `path.resolve`, gets no match, and main() does not run.
- A dangling argv[1] cannot be the running entry script. A dangling or unresolvable
  argv[1] on one side gets the `path.resolve` fallback, which can only produce no match.
  That is the old fail-silent behaviour, not a new one.
- `node -e 'import(<allocator>)' <allocator-path>` runs main() on import, because argv[1]
  then names the module. This is unchanged from the base guard (same equality), and no
  harness in the diff passes the module path as argv[1]: TEST-3794 deliberately uses
  ALLOC_MOD.

### Test code: set -euo pipefail and bash 3.2
- No `printf | grep -q` and no pipe into an early-closing reader. `grep -qF ... <<<"$s_err"`
  uses here-strings. Every rc is captured as `rc=0; (...) || rc=$?` and then checked.
  The TEST-3798 count uses `|| n=0` (grep -c exits 1 on zero matches).
- `bash -n` is clean on all three suites. All five arms pass under /bin/bash 3.2.57.
  check-cd-subshell-leak.mjs exits 0.
- `/usr/bin/grep` in TEST-3798 has precedent in 34 suites.
- Flake potential: none found. The arms are deterministic. There are no timing
  assertions, and the stderr comparison runs the same binary with the same environment on
  both sides. TEST-3794 fixtures live under `$TEST_DIR`: the git identity is set by
  `setup_iso_repo`, the repo is created with `git init -b main`, and the suite trap
  cleans it.
- Temp-dir leak: TEST-3796 only. See NB-1.

### Selector mode in test-aai-intake.sh (exit contract)
- It is placed after `check_deps` and `setup_test_env`, so a missing dependency still
  exits 42 and the trap still cleans up.
- An unknown name exits 2. That matches the doctor and doc-numbering suites, and
  hygiene-pack test_094 (which now enumerates this suite) requires a nonzero exit.
- A failing arm exits 1. The arm's final `... || log_fail` returns 1 as the last command
  of the AND-OR list, so `set -e` ends the shell before "Selected test passed." prints.
  Measured: rc 1 with hotfix unmapped, rc 0 on the shipped tree. This is the same
  fail-fast semantics the suite's no-argument path already has.
- With no argument, the run is unchanged.

### Findings
- **NB-1 (NON-BLOCKING, P3)** — tests/skills/test-aai-doc-numbering.sh:1927.
  `symdir="$(mktemp -d "${TMPDIR:-/tmp}/aai-alloc-symlink.XXXXXX")"` sits outside
  `$TEST_DIR`, and every `log_fail` before line 1946's `rm -rf "$symdir"` exits the arm
  subshell. The suite trap cleans only `$TEST_DIR`.
  - Failure scenario: any failing TEST-3796 assertion leaks the directory, which holds a
    symlink to the repo root and two small files. That covers every mutation replay of
    TEST-3796 and every real regression. Reproduced with `TMPDIR=<scratch>/tmp` and the
    unresolved-guard mutant: one leftover `aai-alloc-symlink.*` directory.
  - No bite on a passing run, and no false record.
  - Fix: `mktemp -d "$TEST_DIR/aai-alloc-symlink.XXXXXX"`, which is one token.
  - Recommended disposition: (d) accepted residual, see the line below. Remediating in
    tree is acceptable but costs a validation round on an L3 ride with a two-round cap.

accepted residual: NB-1 — TEST-3796 leaks one small $TMPDIR dir (a repo symlink plus two stderr captures) only when the arm fails; a passing run cleans up, nothing reads the leftover, and no record is falsified (P3 maintenance).

### INFO (never gate)
- I-1: intake:820. `log_fail "FAIL TEST-013 ..."` prints as `✗ FAIL TEST-013 ...` because
  log_fail already marks the line. This is cosmetic. It is kept deliberately so
  mutation-run's first-fail detection names the TEST id.
- I-2: TEST-3798 pins CHANGELOG text for good. The rolled `vYYYY.MM.DD` form keeps it
  green after a release. Archiving the CHANGELOG would need the pin moved.
- I-3 (pre-existing, validation N-02): `--type` is not cross-checked against the `--path`
  prefix. `--type research --path docs/issues/ISSUE-DRAFT-x.md` numbers an ISSUE. The
  frozen D2 reading leaves this unchanged.

## cannot_verify
1. The new arms on Linux CI (bash 5, GNU). Closes with CI green on the PR head SHA.
2. Windows parity of the guard. The shape is inherited from about 30 existing scripts and
   was not measured here. Closes with the Windows CI leg green.
3. The full test-framework sweep is owed (FULL_RUN reason=protected-l3). Closes with one
   full sweep before close, with `AAI_TEST_TIMEOUT=4500`.
4. Post-#535 suite health. Only the textual merge was measured. Closes with the spec R2
   re-run after the second merge.

## Warning dispositions (H6)
- NB-1: recommended (d), with the `accepted residual:` line above. The orchestrator
  records the final choice in code_review.notes.

## Next steps
- Run the owed full sweep, then the close ceremony (`--paired` ISSUE-0042), then the PR.
  The owner merges (L3).
