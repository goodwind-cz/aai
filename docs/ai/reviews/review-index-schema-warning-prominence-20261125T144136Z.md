```yaml
review:
  scope: "git diff HEAD -- .aai/scripts/generate-docs-index.mjs tests/skills/test-aai-docs-audit.sh CHANGELOG.md + untracked docs/product/docs-index-regeneration.md, docs/issues/ISSUE-0125-index-schema-warning-prominence.md, docs/specs/SPEC-0314-spec-index-schema-warning-prominence.md (worktree fix/index-schema-warning-prominence, base origin/main a83f7b0f, uncommitted)"
  spec: docs/specs/SPEC-0314-spec-index-schema-warning-prominence.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/generate-docs-index.mjs:309-317 (reportDropped), :780 (last call in main, after the trailing warnings list), old mid-run block removed; TEST-4070 rc 0 this review (reason assert now `unknown frontmatter status \"bogus\"`)" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "generate-docs-index.mjs:44 (--verbose), :586-587 (one summary line, per-doc lines only under verbose); TEST-4071 rc 0 this review" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "strict branches :449-454, :466-471, :580-585 unchanged; ARGV feeds only strict/verbose; TEST-4072 rc 0 this review" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "TEST-4073 rc 0 this review (real commit through the installed hook); .aai/templates/git-hooks/pre-commit-index.sh has no diff" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "CHANGELOG.md:33 one `## [unreleased] — fix:` heading; product doc names DROPPED and --verbose; TEST-4074 rc 0 this review and release-tolerant (release-cut roll replay: count 1 before, 1 after)" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/generate-docs-index.mjs, line: 316,
          issue: "NB-FIXLINE (carried): the Fix line offers every DOC_STATUS_ENUM value, including legacy/current",
          failure_scenario: "An author fixing `status: bogus` on a spec picks `legacy`; the doc leaves the DROPPED block and becomes one more count in the coverage-gap summary (still listed under Coverage gaps in docs/INDEX.md). Wording is Spec D1-mandated" }
      - { rank: NON-BLOCKING, file: .aai/scripts/generate-docs-index.mjs, line: 780,
          issue: "NB3 (carried): reportDropped() runs only when main() returns normally",
          failure_scenario: "ENOSPC/EACCES in writeFileSync/writeViolationsReport/writeAuditCompanion after the failures block: the run exits non-zero without the DROPPED block; it fails visibly and the next run prints it" }
  cannot_verify:
    - { claim: "Spec D1 order relative to the stdout `Wrote ...` lines when stdout and stderr go to separate pipes",
        closes_with: "Only the in-process call order and the hook commit with both streams in one file (TEST-4073) are evidenced; a pipe-captured interleaving test" }
    - { claim: "Windows rendering of the three new lines (forward slashes after the toPosix wrap)",
        closes_with: "a run on a Windows host; the code wraps all three in toPosix() (lines 314, 316, 586), no Windows leg runs this suite" }
    - { claim: "DRAFT cross-links (product doc `spec:` frontmatter, intake/spec Links) survive the allocator rename at PR time",
        closes_with: "allocate-doc-number dry run + `spec-amend list --strict` + mutation-gate after the rename (PR ceremony)" }
    - { claim: "Mutation records reflect the current bytes",
        closes_with: "this review ran mutation-gate (GATE PASS 5 rows) but did not re-run the replay; validation r3 reports the replay 5/5 RED with unchanged hashes" }
    - { claim: "The whole tree passes the full sweep",
        closes_with: "the one full sweep the orchestrator owes before close (sweep-plan: full reason=code-delta); not run here per dispatch" }
  overall: pass
```

# Code review: index-schema-warning-prominence (round 2, re-review after remediation)

security_relevant: false

## Scope and spec

- Scope: the explicit path list above in worktree
  `/Users/ales/Projects/aai-worktrees/issue-577-index-noise`, branch
  `fix/index-schema-warning-prominence`, base `origin/main` a83f7b0f. The
  change is uncommitted, so the diff is `git diff HEAD -- <paths>` plus the
  three untracked docs. The other dirty files (docs/INDEX.md, the EVENTS,
  decisions and test-runs ledgers, and the round-1 review report) are outside
  the review scope.
- Contract: the frozen spec (D1-D4, AC table, Test Plan) and the intake
  (the issue #577 quote is read as data).
- Prior round: review-index-schema-warning-prominence-20261125T134047Z.md (FAIL
  on B1). Validation r3 (PASS) was read for context. The verdicts below rest on
  the code and on this review's own runs.
- Dispatch note (anti-gaming contract): the dispatch named the prior findings
  and their dispositions, and set a severity bar ("only raise a BLOCKING
  finding for a real defect that would ship broken behaviour or a failing
  test"). That bar is the skill's own BLOCKING definition, so it does not
  change the review. The whole scope was reviewed again, not only the delta.

## Prior findings: closure check

| Finding | Status | Evidence (this review) |
|---|---|---|
| B1 (BLOCKING): TEST-4074 not release-tolerant | **closed** | test-aai-docs-audit.sh TEST-4074 now counts `^## \[(unreleased\|v[0-9]{4}\.[0-9]{2}\.[0-9]{2}[^]]*)\] — fix: a doc dropped from the docs index is reported last` and requires 1. Replay on a mktemp copy of CHANGELOG.md with `/usr/bin/grep -E`: count 1 before; `release-cut.mjs roll --version v2099.01.01` rc 0; count 1 after (entry now `## [v2099.01.01] — fix: …`). Matches the TEST-3649 precedent |
| NB-REASON: vacuous reason assert in TEST-4070 | **closed** | the assert is now `grep -qF 'unknown frontmatter status "bogus"'`, text the fixture path does not contain; the generator's reason string (generate-docs-index.mjs:357) matches it; TEST-4070 rc 0 |
| NB-WIN: bare path.relative in the new lines | **closed (code)** | `toPosix(path.relative(...))` at :314 (header), :316 (Fix line), :586 (coverage summary); toPosix is imported at :31. The bare calls left over are lines this diff does not touch |
| NB-FIXLINE | accepted residual (unchanged) | wording is Spec D1-mandated |
| NB3 | accepted residual (unchanged) | code unchanged at :780 |

## Evidence gathered by this review

- The five selectors, foreground, `env -u AAI_ROLE AAI_TEST_TIMEOUT=900 bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-docs-audit.sh <fn>`:
  test_4070 rc 0, test_4071 rc 0, test_4072 rc 0, test_4073 rc 0, test_4074 rc 0.
- `mutation-gate.mjs --spec <spec>`: `GATE PASS: 5 row(s) satisfied degraded=0 unstamped=0 uncomparable=0`.
- `spec-lint.mjs --path <spec>`: LINT PASS, 0 findings. `spec-amend.mjs list --strict`: rc 0.
- Whole-doc failure kinds in the generator are only two (:357 unknown status,
  :392 invalid Review-By); the Fix line covers both.
- Exit paths after the failures block (:453, :470, :584) are all `strict`-only,
  so a non-strict run always reaches `reportDropped()` unless an exception is
  thrown (NB3).
- The only in-repo programmatic consumer of the generator's output,
  `merge-cleanup.mjs:592` (regenIndex), reads stderr only on a non-zero exit
  and passes no flags. No script, test or ps1 matches the removed strings
  (`skipped from index (run`, `surfaced as Coverage gaps`).
- The hook template has no diff.
- Product doc: the remediation added "(it stops at the first kind of violation
  it meets)" to the `--strict` sentence, which states base behaviour
  correctly. Round 1 noted the frozen D3 sentence overstates it; that is still
  true of the frozen text and is not a code deviation.

## AC table walk

| Spec-AC | Call | Citation |
|---|---|---|
| Spec-AC-01 | compliant | generate-docs-index.mjs:309-317, :780; TEST-4070 rc 0 |
| Spec-AC-02 | compliant | generate-docs-index.mjs:44, :586-587; TEST-4071 rc 0 |
| Spec-AC-03 | compliant | strict branches unchanged; TEST-4072 rc 0 |
| Spec-AC-04 | compliant | TEST-4073 rc 0; hook untouched |
| Spec-AC-05 | compliant | CHANGELOG.md:33; product doc; TEST-4074 rc 0 and release-tolerant |

Every TEST row named in the Test Plan exists, is registered in `main()` and
passes. Deviations from the frozen spec: none in the code. The frozen D3 text
overstates `--strict` (see above).

## Findings

### BLOCKING

None.

### NON-BLOCKING (with disposition)

- **NB-FIXLINE** (.aai/scripts/generate-docs-index.mjs:316): the Fix line
  offers `legacy`/`current`, which for a spec turn a dropped doc into a
  summarised coverage gap. Disposition: **accepted residual** (d).
  accepted residual: NB-FIXLINE — P3 hint quality; spec-mandated wording; the doc stays listed under "Coverage gaps" in docs/INDEX.md, no false record.
- **NB3** (.aai/scripts/generate-docs-index.mjs:780): the block is lost when
  main() throws after the failures block. Disposition: **accepted residual** (d).
  accepted residual: NB3 — P3 edge; only an I/O exception after the failures block reaches it, the run then fails visibly, and the next run prints the block.

No new NON-BLOCKING findings this round.

### INFO

- With `--verbose` given, the summary line still says "run with --verbose to
  list them here". Cosmetic.
- TEST-4072 compares two INDEX.md writes that embed `Today (UTC)`; a run that
  crosses UTC midnight between the two calls would differ. The window is about
  a second.
- TEST-4074 reads the live CHANGELOG.md. If a future change archived old
  release sections out of the file, the count would drop to 0. Nothing does
  that today.

## cannot_verify

See the YAML block:
- stdout/stderr interleaving under separate pipes;
- the Windows rendering;
- the allocator rename of the DRAFT cross-links;
- the mutation replay, which this review did not re-run (the gate passed);
- the full sweep the orchestrator still owes before close.

## Next steps

1. Orchestrator: run the one full sweep owed before close on this tree.
2. PR ceremony: after the allocator rename, run `spec-amend list --strict` and
   the mutation gate (cross-link survival).
