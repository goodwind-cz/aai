---
id: spec-index-schema-warning-prominence
type: spec
number: 314
status: done
mutation_gate: v1
frozen_sha256: f90d55ed50fe1797aa09556dc4a710d45bd8eddac7d2bb58f3bcee0a2cc06971
ceremony_level: 2
links:
  requirement: index-schema-warning-prominence
  rfc: null
  pr: []
  commits: []
---

# The index generator reports a dropped doc last and summarises standing coverage gaps

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/ISSUE-0125-index-schema-warning-prominence.md
  (GitHub issue #577, friction report `missing_or_invalid_artifact`,
  aai-pr / docs-index-regeneration).
- Prior scopes this one builds on (closed, not edited): SPEC-0006 (the
  zero-section coverage invariant and its `Coverage gaps` section), the
  degrade-and-report mode described in the generator's header.
- Technology contract: docs/TECHNOLOGY.md (bash 3.2 suites through
  `.aai/scripts/aai-run-tests.sh`; Node stdlib only).

## Implementation strategy

- Strategy: tdd
- Rationale: the change is to what a guard-like tool prints, and the defect
  is an ordering and volume problem that a happy-path test would not see.
  Each behaviour is first observed failing on the unchanged generator
  (TEST-4070, TEST-4071, TEST-4073), and each test carries a mutation that
  must redden it.

## Isolation and review

- Worktree recommendation: optional
- Worktree rationale: one script and one suite; the main checkout carries
  other sessions' uncommitted files, so the ride already runs in its own
  worktree.
- User decision: worktree (caller directive)
- Base ref: origin/main at 492f8b26
- Worktree branch/path: fix/index-schema-warning-prominence at
  /Users/ales/Projects/aai-worktrees/issue-577-index-noise
- Review required: true
- Review scope (explicit paths): .aai/scripts/generate-docs-index.mjs;
  tests/skills/test-aai-docs-audit.sh; CHANGELOG.md;
  docs/product/docs-index-regeneration.md;
  docs/issues/ISSUE-0125-index-schema-warning-prominence.md;
  docs/specs/SPEC-0314-spec-index-schema-warning-prominence.md.

## Decisions

- D1 (a dropped doc is reported last). The per-doc lines for whole-doc
  schema violations (the `hard` set: not auto-skipped by the legacy window)
  move out of the middle of the run into one block that the generator
  prints as its last output on stderr, after the coverage-gap line, the
  legacy-ratio line, the `Wrote ...` lines on stdout and the trailing
  `N warning(s):` list. The block is:
  a header `WARNING: N doc(s) DROPPED from docs/INDEX.md by schema
  violations — missing from the index until fixed (run with --strict to
  fail):`, one `  - <path>: <reason>` line per violation (the existing
  reason text), and one `  Fix:` line naming the allowed frontmatter status
  values (from `DOC_STATUS_ENUM`), the Review-By forms, and
  `docs/INDEX.violations.md`. The index path in the header is the
  generator's own output path, relative to the project root.
- D2 (standing coverage gaps are summarised). By default the coverage
  invariant prints one line: `WARNING: N doc(s) land in zero placement
  sections — listed under "Coverage gaps" in docs/INDEX.md (run with
  --verbose to list them here, --strict to fail).` A new `--verbose` flag
  adds the existing one-line-per-doc list after it. The index section
  `Coverage gaps (zero placement sections)` is unchanged; it is the full
  list. "Print only when changed" was rejected: it needs state persisted
  between runs, and a run in a fresh clone or in CI would still print the
  whole list.
- D3 (nothing else changes). Exit codes are unchanged in every mode. The
  `--strict` path still prints every violation and every coverage gap
  before it exits 1. The bytes of `docs/INDEX.md` and
  `docs/INDEX.violations.md` do not depend on `--verbose`. Row-level AC
  status violations (the doc stays indexed) and the trailing legacy
  warnings list keep their current output.
- D4 (the hook is not touched). `.aai/templates/git-hooks/pre-commit-index.sh`
  is an L3 protected surface. It runs the generator without flags and lets
  its output through, so D1 and D2 reach every docs commit without a change
  to the hook. The hook's own lines (close gate, body lint, the final
  `regenerated and staged` line) still follow the generator's output.

## Acceptance Criteria Mapping

- Maps to the intake's Expected Behavior bullet 1 -> Spec-AC-01, Spec-AC-04.
- Maps to bullet 2 -> Spec-AC-02, Spec-AC-04.
- Maps to bullet 3 -> Spec-AC-03.
- Product doc and changelog -> Spec-AC-05.
- Verification: `bash tests/skills/test-aai-docs-audit.sh <test_fn>` per
  TEST row, through `.aai/scripts/aai-run-tests.sh`, with `env -u AAI_ROLE`.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN a default run skips a doc for an unknown frontmatter status in a fixture that also holds three coverage-gap docs and one doc without frontmatter, the generator SHALL exit 0 and the last three non-empty stderr lines SHALL be the DROPPED header naming 1 doc, the doc line naming its path and reason, and the Fix line; the DROPPED header SHALL come after the coverage-gap line and after the legacy warnings list; WHEN no doc is skipped, stderr SHALL hold no DROPPED line | done | docs/ai/tdd/index-schema-warning-prominence/red-test_4070_dropped_doc_reported_last.log, docs/ai/tdd/index-schema-warning-prominence/green-test_4070_dropped_doc_reported_last.log, docs/ai/tdd/spec-index-schema-warning-prominence/mutation-TEST-4070.txt; validation docs/ai/validation/VALIDATION-index-schema-warning-prominence-r3.md | — | D1 |
| Spec-AC-02 | WHEN a default run meets three coverage-gap docs, stderr SHALL hold exactly one line containing zero placement sections, that line SHALL name --verbose, and no stderr line SHALL name a coverage-gap doc path; WHEN the same run passes --verbose, stderr SHALL name each of the three paths | done | docs/ai/tdd/index-schema-warning-prominence/red-test_4071_coverage_gaps_summarised.log, docs/ai/tdd/index-schema-warning-prominence/green-test_4071_coverage_gaps_summarised.log, docs/ai/tdd/spec-index-schema-warning-prominence/mutation-TEST-4071.txt; validation docs/ai/validation/VALIDATION-index-schema-warning-prominence-r3.md | — | D2 |
| Spec-AC-03 | WHEN the same fixture is indexed by a default run and by a --verbose run, both SHALL exit 0 and docs/INDEX.md and docs/INDEX.violations.md SHALL be byte-identical between them, with the Coverage gaps section listing all three gap docs; WHEN it runs with --strict and only coverage gaps, it SHALL exit 1 naming each gap doc; WHEN it runs with --strict and the skipped doc, it SHALL exit 1 naming that doc | done | docs/ai/tdd/index-schema-warning-prominence/green-test_4072_bytes_and_strict_unchanged.log, docs/ai/tdd/spec-index-schema-warning-prominence/mutation-TEST-4072.txt; validation docs/ai/validation/VALIDATION-index-schema-warning-prominence-r3.md | — | D3 |
| Spec-AC-04 | WHEN the installed index hook commits a staged doc with an unknown status beside three coverage-gap docs, the commit SHALL succeed, its output SHALL hold the DROPPED header after the coverage-gap line, SHALL name no coverage-gap doc path on its own line, and SHALL end with the hook's regenerated and staged line | done | docs/ai/tdd/index-schema-warning-prominence/red-test_4073_hook_shows_dropped_doc.log, docs/ai/tdd/index-schema-warning-prominence/green-test_4073_hook_shows_dropped_doc.log, docs/ai/tdd/spec-index-schema-warning-prominence/mutation-TEST-4073.txt; validation docs/ai/validation/VALIDATION-index-schema-warning-prominence-r3.md | — | D1 D2 D4 |
| Spec-AC-05 | CHANGELOG.md SHALL hold exactly one unreleased heading for this fix, and docs/product/docs-index-regeneration.md SHALL describe the DROPPED block and the --verbose flag | done | docs/ai/tdd/index-schema-warning-prominence/red-test_4074_changelog_and_product_doc.log, docs/ai/tdd/index-schema-warning-prominence/green-test_4074_changelog_and_product_doc.log, docs/ai/tdd/spec-index-schema-warning-prominence/mutation-TEST-4074.txt; validation docs/ai/validation/VALIDATION-index-schema-warning-prominence-r3.md | — | product doc |

## Implementation plan

- `.aai/scripts/generate-docs-index.mjs`:
  - parse `--verbose` next to `--strict`;
  - in the failures block, keep the `--strict` abort as it is and stop
    printing the non-strict per-doc lines there; keep the `hard` list;
  - coverage invariant: under `--strict` unchanged; otherwise print the one
    summary line, then the per-doc lines only with `--verbose`;
  - at the end of `main()`, after the trailing warnings list, print the
    DROPPED block when `hard` is non-empty.
- `tests/skills/test-aai-docs-audit.sh`: TEST-4070 to TEST-4074, each
  self-contained (own fixture root through `igs_own_root`), registered in
  `main()`.
- Edge cases: zero skipped docs (no block, negative control in TEST-4070);
  only legacy-window skips (no `hard` entries: no block, as today no line);
  coverage gaps without a skipped doc (summary only).

### Seams

- Generator stderr -> the installed `AAI:INDEX-AUTOGEN` hook's commit
  output (TEST-4073 runs a real commit through the installed hook).
- Generator output files -> `--verbose` must not reach them (TEST-4072
  compares bytes across modes).

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-4070 | Spec-AC-01 | integration | tests/skills/test-aai-docs-audit.sh | fixture: one doc with status bogus, three docs with status legacy, one doc without frontmatter; default run exits 0; the last three non-empty stderr lines are the DROPPED header (1 doc), the doc line and the Fix line; the header follows the coverage-gap line and the legacy list; without the bogus doc no DROPPED line; RED on the unchanged generator | target `.aai/scripts/generate-docs-index.mjs`; `sed:s/  reportDropped\(\);//` removes the final block and the case must fail | green |
| TEST-4071 | Spec-AC-02 | integration | tests/skills/test-aai-docs-audit.sh | three coverage-gap docs: default stderr has one zero placement sections line naming --verbose and no gap path; --verbose names all three; RED on the unchanged generator | target `.aai/scripts/generate-docs-index.mjs`; `sed:s/if \(verbose\) for/if (true) for/` lists every gap again by default and the case must fail | green |
| TEST-4072 | Spec-AC-03 | integration | tests/skills/test-aai-docs-audit.sh | same fixture, default vs --verbose: exit 0 both, cmp of INDEX.md and INDEX.violations.md equal, Coverage gaps section lists the three docs; --strict exits 1 naming each gap doc, and with the bogus doc exits 1 naming it | target `.aai/scripts/generate-docs-index.mjs`; `sed:s/for \(const d of coverageGaps\) console.error/for (const d of []) console.error/` drops the strict per-gap lines and the case must fail | green |
| TEST-4073 | Spec-AC-04 | integration | tests/skills/test-aai-docs-audit.sh | installed hook fixture: commit of a bogus-status doc beside three gap docs succeeds; output holds the DROPPED header after the coverage-gap line, no gap path on its own line, and ends with the regenerated and staged line; RED on the unchanged generator | target `.aai/scripts/generate-docs-index.mjs`; `sed:s/  reportDropped\(\);//` removes the final block and the case must fail | green |
| TEST-4074 | Spec-AC-05 | unit | tests/skills/test-aai-docs-audit.sh | grep -c of the CHANGELOG heading equals 1; the product doc names the DROPPED block and --verbose | target `docs/product/docs-index-regeneration.md`; `sed:s/--verbose/--loud/g` drops the flag from the product doc and the case must fail | green |

## Verification

- `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-docs-audit.sh test_4070_dropped_doc_reported_last`
  and the same for `test_4071_coverage_gaps_summarised`,
  `test_4072_bytes_and_strict_unchanged`, `test_4073_hook_shows_dropped_doc`,
  `test_4074_changelog_and_product_doc`.
- The full `tests/skills/test-aai-docs-audit.sh` suite, the selected suites
  and CORE between rounds, one full sweep before close.
- PASS criteria: all TEST rows green with RED and mutation records, every
  Spec-AC done with evidence.

## Evidence contract

- ref_id: index-schema-warning-prominence
- RED/GREEN logs under docs/ai/tdd/index-schema-warning-prominence/,
  mutation records under docs/ai/tdd/spec-index-schema-warning-prominence/,
  validation report under docs/ai/validation/.
- Each record names the Spec-AC, the TEST id, the command, its exit code
  and the evidence path.

Registry items closed by this scope: none

## Residual risks

- A downstream project on an older pin keeps the old output until it runs
  `/aai-update`.
- The trailing `N warning(s):` list of docs without frontmatter is also
  standing output; it is left as it is (the issue names coverage gaps), and
  the DROPPED block now prints after it.
- The block is last in the generator's output, not in the hook's: the
  hook's close-gate and body-lint lines, when they fire, still follow it.
