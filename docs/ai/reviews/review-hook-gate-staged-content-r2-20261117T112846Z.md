# Code Review — hook-gate-staged-content — round 2

```yaml
review:
  scope: "git diff origin/main (65113785) over .aai/scripts/lib/docs-audit-core.mjs, .aai/scripts/docs-audit.mjs, .aai/templates/git-hooks/pre-commit-index.sh, .aai/scripts/pre-commit-checks.sh, tests/skills/test-aai-docs-audit.sh, tests/skills/test-aai-pre-commit-checks.sh, tests/skills/suite-map.yaml, CHANGELOG.md, docs/product/docs-close-gate.md, docs/issues/ISSUE-DRAFT-hook-gate-staged-content.md, docs/specs/SPEC-DRAFT-spec-hook-gate-staged-content.md (EVENTS.jsonl / decisions.jsonl: appended lines only, 0 removed)"
  spec: docs/specs/SPEC-DRAFT-spec-hook-gate-staged-content.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "docs-audit-core.mjs scanGateEntries {staged} -> readStagedDocSet; TEST-3860 rc 0 (reviewer re-run)" }
      - { ac: Spec-AC-02, call: compliant, citation: "readStagedDocSet HEAD: fallback, untracked not listed; TEST-3861 rc 0" }
      - { ac: Spec-AC-03, call: compliant, citation: "pre-commit-index.sh:99 --staged; TEST-3863 rc 0" }
      - { ac: Spec-AC-04, call: compliant, citation: "docs-audit.mjs:467-476 usage checks before any mode; TEST-3862 rc 0 (incl. --gate/--intake-file/--gate-file+--gate with --staged); r1 B1 repro rc 0. Deviation listed: an own-table doc never enters staged mode, so outside git it exits 0/1 (NB-2)" }
      - { ac: Spec-AC-05, call: compliant, citation: "pre-commit-checks.sh:71,105,130 cat-file -e :0:, blob reads :74,113,135; TEST-3864 rc 0" }
      - { ac: Spec-AC-06, call: compliant, citation: "pre-commit-checks.sh:86 .env|.env.*|*.env; TEST-3865 rc 0; TEST-3833 rc 0" }
      - { ac: Spec-AC-07, call: compliant, citation: "pre-commit-checks.sh:65-66 diff --cached --name-only -z into array; TEST-3866 rc 0" }
      - { ac: Spec-AC-08, call: compliant, citation: "TEST-3454 (39 29) and TEST-3461 (333/245) rc 0; whole suites rc 0 per VALIDATION r4 (23 / 192 PASS)" }
      - { ac: Spec-AC-09, call: compliant, citation: "CHANGELOG.md:33 one heading; docs/product/docs-close-gate.md 'from the index' + HEAD; TEST-3868 rc 0" }
      - { ac: Spec-AC-10, call: compliant, citation: "readStagedDocSet fromHead/indexIds filter; TEST-3869 rc 0; reviewer probe p2 (intake AND spec renamed in one close commit)" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: docs/ai/decisions.jsonl, line: 3067,
          issue: "NB-1: the filed follow-up fu-precommit-staged-blob-process-count records the cost of the reverted scratch-copy variant ('about 1.7x ... 14.6 s vs 8.4 s'); the shipped code is the per-check cat-file -e + git show shape measured at ~3.7-3.9x",
          failure_scenario: "a later triage reads the ledger, sees 1.7x, and ranks the item below its real cost: 600 staged .js files take 29.0 s vs 7.8 s (review r1) / 31 s vs 8 s (VALIDATION r4 probe-colon-perf.out) on the shipped script" }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/docs-audit-core.mjs, line: 2260,
          issue: "NB-2: staged mode (and its 'outside a git work tree exits 2') applies only when the gated doc has no AC table of its own and gates through linked specs; Spec-AC-04's second clause, the CHANGELOG ('outside a git work tree the staged gate exits 2') and the product doc ('or outside a git work tree, exits 2') state it unconditionally",
          failure_scenario: "outside any git work tree, `docs-audit.mjs --gate-file docs/specs/SPEC-7001-a.md --staged` on a spec with its own reconciled table prints GATE PASS and exits 0, not 2 (reviewer probe p1). The verdict itself is correct (an own-table doc reads nothing from the index or the working tree), so nothing false passes; the documented exit contract is overstated" }
  cannot_verify:
    - { claim: "Windows (Git Bash / Windows git) behaviour of the NUL-separated read, process substitution and git cat-file --batch output", closes_with: "the Windows CI leg green on the PR head" }
    - { claim: "Linux CI behaviour of the new tests (GNU tools, runner without identity)", closes_with: "GitHub Actions green on the PR head" }
    - { claim: "Full-sweep non-regression; the hook template is read by test-aai-git-hook-templates.sh, test-aai-hygiene-pack.sh, install-parity.mjs and install-pre-commit-hook.Tests.ps1, none run by this review (L3 surface forces FULL_RUN)", closes_with: "the one full sweep the orchestrator runs before close" }
  overall: pass
```

security_relevant: true

## Scope and inputs

- Diff: `git diff origin/main` in /Users/ales/Projects/aai-worktrees/hook-gate-staged-content (branch
  fix/hook-gate-staged-content, base 65113785, uncommitted tree). Whole diff reviewed, not only the delta since r1.
- Spec: docs/specs/SPEC-DRAFT-spec-hook-gate-staged-content.md (sha256 c13ffcd4..., ceremony 3, Spec-AC-01..10,
  one disclosed post-freeze amendment D1/Spec-AC-10). Intake: docs/issues/ISSUE-DRAFT-hook-gate-staged-content.md.
- Read: round-1 report and its B1 repro, VALIDATION r4 (PASS), decisions.jsonl lines 3064-3068.
- Coaching check: the dispatch summarised the remediation since r1 and named the dispositions already
  filed; it did not pre-rate new findings or exclude any area. The full scope was reviewed.
- Ledgers: `git diff origin/main` on EVENTS.jsonl and decisions.jsonl removes 0 lines (append-only holds).

## Verdict 1 — spec_compliance: PASS

Tests re-run by the reviewer, one function at a time, foreground, through `aai-run-tests.sh`, all rc 0:
docs-audit 3860, 3861, 3862, 3863, 3869; pre-commit 3864, 3865, 3866, 3868, 3454, 3461, 3832, 3833.
The r1 B1 repro (docs/ai/reviews/review-hook-gate-staged-content-r1-20261117T105216Z-repro-B1.sh) now exits 0:
`--gate ISSUE-5990 --staged` rc 2 with USAGE ERROR.

| AC | Call | Citation |
|---|---|---|
| 01 | compliant | scanGateEntries `{staged}`; TEST-3860 |
| 02 | compliant | HEAD fallback, untracked not read; TEST-3861 |
| 03 | compliant | hook passes `--staged`; TEST-3863 |
| 04 | compliant | usage checks now first in `main()`; TEST-3862 covers bare, `--gate`, `--intake-file`, `--gate-file`+`--gate`; non-git intake rc 2. Deviation: NB-2 |
| 05 | compliant | index-existence test + staged blob reads; TEST-3864 |
| 06 | compliant | `*.env` in the basename override; TEST-3865 |
| 07 | compliant | `-z` list into an array; TEST-3866 |
| 08 | compliant | moved pins 39/29, 333/245; TEST-3454/3461; suites per VALIDATION r4 |
| 09 | compliant | one CHANGELOG heading, product doc statement; TEST-3868 |
| 10 | compliant | rename filter; TEST-3869; probe p2 |

Deviations from the frozen spec (listed even where reasonable):
- Spec-AC-04 second clause / D2 "Outside a git work tree, staged mode cannot evaluate and exits 2": holds for
  a doc that gates through linked specs (the only case in which staged mode reads anything). A doc with its own
  AC table is gated on its own content and exits 0/1 outside git (probe p1 below). The call stays compliant
  because D2 ties exit 2 to "staged mode cannot evaluate", and for an own-table doc staged mode has nothing to
  evaluate: no index read, no working-tree read, the verdict is the same in every directory. The consumer
  wording is broader than the code; see NB-2.
- D1 "Without the option the working-tree scan is unchanged": now true; the r1 NB2 catch wraps only the staged
  branch (docs-audit-core.mjs:2268-2277), so the working-tree error path is origin/main's again.

## Verdict 2 — code_quality: PASS (no BLOCKING finding)

### Closed since r1
- B1 (BLOCKING): closed. `main()` refuses `--staged` without `--gate-file` and with `--gate`/`--intake-file`
  before any mode dispatches (docs-audit.mjs:467-476). Repro rc 0; TEST-3862 extended.
- NB2: closed. try/catch only around the staged scan; the message reads "staged mode could not read the index".
- NB1 (process count): carried, filed as `fu-precommit-staged-blob-process-count` — but see NB-1 here.

### NON-BLOCKING NB-1 — the process-count follow-up records the wrong cost (P3, false record)
- File: docs/ai/decisions.jsonl:3067. The finding text says "about 1.7x origin/main on 600 staged files,
  14.6 s vs 8.4 s". Those figures were measured on the scratch-copy variant that VALIDATION r3 rejected and
  that was reverted. The shipped script is the per-check `git cat-file -e` + `git show | grep` shape: 29.0 s vs
  7.8 s (review r1) and 31 s vs 8 s (VALIDATION r4, probe-colon-perf.out), about 3.7-3.9x.
- Failure scenario: triage ranks the follow-up on a cost less than half the real one.
- Recommended disposition: (a) remediate the record — append a correcting decision line for the same id
  through the ledger CLI (never edit line 3067; HAZ-LEDGER). Not eligible for (d): it leaves a false record.

### NON-BLOCKING NB-2 — "outside a git work tree exits 2" is broader in the docs than in the code (P3)
- File: .aai/scripts/lib/docs-audit-core.mjs:2260 (`own.missingTable && gatesThroughLinkedSpecs` guards the
  only git read); CHANGELOG.md:35 and docs/product/docs-close-gate.md ("`--staged` without `--gate-file`, or
  outside a git work tree, exits 2").
- Probe p1 (fresh mktemp fixture under the review scratch directory, no git repository above it): a spec with
  its own reconciled table, `node .aai/scripts/docs-audit.mjs --gate-file docs/specs/SPEC-7001-a.md --staged`
  -> `GATE PASS: AC Status table complete`, rc 0.
- Failure scenario: a caller relying on the documented contract (exit 2 = staged gate cannot run here) outside
  a work tree receives rc 0 for an own-table doc. No false verdict results; the hook always runs inside a work
  tree.
- Recommended disposition: remediate in tree (narrow the two consumer sentences to "a doc that gates through
  its linked specs", or make `runGateFile` refuse `--staged` outside a work tree up front with one
  `git rev-parse --is-inside-work-tree`), or promote to a follow-up ref (suggested: `fu-staged-gate-non-git-own-table`).

### INFO (no gate)
- docs/product/docs-close-gate.md frontmatter `updated: 2026-11-16` was not bumped with the edit.
- Reviewer probe p2 (close-commit shape): intake DRAFT and spec DRAFT both `git mv`-ed to numbered names in one
  commit, intake flipped done; staged spec reconciled + unstaged regression -> rc 0 naming SPEC-7100 only;
  staged spec open + worktree reconciled -> rc 1 naming SPEC-7100. The rename filter also covers the intake's
  own `self` lookup.
- Read-through of the remaining surface found no new defect: `readBlobs` header parsing cannot misread a
  "missing" line (names start with `:` or `H`, never hex); NUL list + bash 3.2 empty-array guard; pipes into
  `grep -c`/`grep -n` consume the whole stream (no early-closing reader under pipefail); `git show` on a blob
  applies no textconv by default; CHECK 7 keeps its own newline list (disclosed residual risk in the spec).

## cannot_verify

- Windows behaviour of the NUL read / process substitution / `cat-file --batch` — closes with the Windows CI leg
  green on the PR head.
- Linux CI behaviour of the new tests — closes with GitHub Actions green on the PR head.
- Full-sweep non-regression, including the four other readers of the hook template — closes with the
  orchestrator's one full sweep before close.

## Warning dispositions (H6)

- NB-1: recommended (a) remediate the record (append a correcting ledger line for `fu-precommit-staged-blob-process-count`).
- NB-2: recommended remediate in tree (wording or an up-front work-tree check) or promote to a follow-up
  (suggested id `fu-staged-gate-non-git-own-table`, P3).
- The orchestrator records the chosen artifact; this reviewer filed nothing.

## Next steps

1. Record NB-1 and NB-2 dispositions (decisions.jsonl / review notes).
2. Full sweep before close (L3), then the PR ceremony.
