---
id: spec-allocator-research-hotfix-types
type: spec
number: 296
status: done
mutation_gate: v1
frozen_sha256: a97d6c0e0fac9176d0dee9afab4b711cd5de64615fdad8631e1e823e8f985c4c
ceremony_level: 3
links:
  requirement: allocator-research-hotfix-types
  rfc: null
  pr:
    - 563
  commits:
    - 01f6d32c
---

# The allocator knows all eight intake types and runs the same through a symlinked checkout

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/ISSUE-0119-allocator-research-hotfix-types.md
- Carried and closed in the same close transaction:
  docs/issues/ISSUE-0042-intake-doc-identity-table-and-its-pins.md (its last
  open Verification bullet is the TYPE_MAP gap).
- Prior scopes this one finishes (closed, not edited):
  docs/specs/SPEC-0140-spec-intake-numbers-some-doc-types-immediately.md (D4
  filed the TYPE_MAP gap), docs/specs/SPEC-0179-spec-test-framework-sweep.md
  Spec-AC-22 (excluded this file from the realpath fix),
  docs/specs/SPEC-0182-spec-close-ceremony-sweep.md Spec-AC-21 (shipped the
  template half of ISSUE-0042).
- Technology contract: docs/TECHNOLOGY.md (Node stdlib, bash 3.2 suites run
  through `.aai/scripts/aai-run-tests.sh`).

## Implementation strategy

- Strategy: tdd
- Rationale: every rule can be seen failing on the unchanged tree:
  `draftFilename('research', s)` throws, `--type hotfix` exits 2 as unknown,
  TEST-013 logs a missing TYPE_MAP row and passes, and the allocator run
  through a symlink exits 0 with no output. No implementation mode was chosen
  at intake (autopilot).

## Isolation and review

- Worktree recommendation: required (ceremony L3)
- Worktree rationale: `.aai/scripts/allocate-doc-number.mjs` is in
  `protected_paths_l3`; the main checkout is shared and holds uncommitted
  files owned by others.
- User decision: worktree (owner-directed in the session brief of
  2026-11-16, recorded in STATE)
- Base ref: origin/main at c1034b24
- Worktree branch/path: fix/allocator-research-hotfix-types at
  /Users/ales/Projects/aai-worktrees/allocator-research-hotfix-types
- Review required: true (L3: mandatory, most capable tier)
- Review scope (explicit paths): .aai/scripts/allocate-doc-number.mjs;
  tests/skills/test-aai-doc-numbering.sh; tests/skills/test-aai-intake.sh;
  tests/skills/test-aai-doctor.sh; CHANGELOG.md;
  docs/issues/ISSUE-0119-allocator-research-hotfix-types.md;
  docs/issues/ISSUE-0042-intake-doc-identity-table-and-its-pins.md; this
  spec.

## Ceremony

Ceremony level 3. The scope edits `.aai/scripts/allocate-doc-number.mjs`,
which `protected_paths_l3` in docs/ai/docs-audit.yaml lists. L3 brings the
recorded worktree decision (done), mandatory review on the most capable tier
and an operator checkpoint before merge: the owner merges. Round cap: two
rounds, one full sweep before close.

Companion obligations: no `.aai/*.prompt.md` or `.aai/AGENTS.md` bytes and no
new `.aai/**` file, so neither the prompt-diet ledger nor PROFILES.yaml
changes.

Overlap: open PR #535 (branch `codex/singleton-reservation-portability`)
edits the same file in its header comment and the reservation functions
(about lines 14 and 446 to 535). This scope touches only the import line, the
TYPE_MAP block and the main() guard, so the hunks are disjoint; whichever
merges second rebases. #535 is not touched.

## Decisions

### D1. Two TYPE_MAP rows, copied from the table

`TYPE_MAP` gains exactly the two rows the DURABLE DOC IDENTITY table in
`.aai/INTAKE_COMMON.md` declares and nothing else:

- `research: { dir: 'specs', prefix: 'RES' }` (table row
  `| research | research | docs/specs | RES |`; `.aai/INTAKE_RESEARCH.prompt.md`
  saves under `docs/specs/`; `docs/specs/` holds RES-0001 to RES-0004;
  RESEARCH-0001 is the named legacy exception and keeps its name).
- `hotfix: { dir: 'issues', prefix: 'ISSUE' }` (table row
  `| hotfix | issue | docs/issues | ISSUE |`; `.aai/INTAKE_HOTFIX.prompt.md`
  saves under `docs/issues/` from `ISSUE_TEMPLATE.md`, whose Type section
  reads `bug | hotfix`). A hotfix shares the ISSUE counter with `issue`.

No new directory, prefix or counter.

### D2. What "builds a DRAFT path" means for the CLI

The CLI never builds a path from `--type`: `--type` is validated, then
`--path` or `--all` selects. So `--type research` alone still exits 2
`nothing selected`, exactly like `--type issue`. ISSUE-0042's bullet is met
when `draftFilename` builds the path for both types, `--type` is no longer
refused as unknown, and a real allocation of a RES or hotfix ISSUE draft
with that `--type` succeeds.

### D3. TEST-013 stops forgiving a missing row

`tests/skills/test-aai-intake.sh` TEST-013 logged a table type with no
TYPE_MAP entry as "filed not fixed" and passed. With all eight present, a
missing entry becomes a failure, so TYPE_MAP cannot lose a row unnoticed.

### D4. The realpath guard is the shared shape

The main() guard becomes the shape the other 22 resolved `.aai/scripts`
CLIs use: a `realOrResolve` helper (`fs.realpathSync`, falling back to
`path.resolve`) on both `process.argv[1]` and
`fileURLToPath(import.meta.url)`. `tests/skills/test-aai-doctor.sh` TEST-439
drops its by-name exclusion of this file, so the repo-wide grep now covers
all 23 guards.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | TYPE_MAP SHALL map research to specs and RES and hotfix to issues and ISSUE; draftFilename SHALL build docs/specs/RES-DRAFT-x.md and docs/issues/ISSUE-DRAFT-x.md, and each built path holding template frontmatter SHALL pass docs-audit --intake-file; WHEN the allocator runs with --type research on a RES draft and with --type hotfix on an ISSUE draft it SHALL exit 0 and number them RES-0005 and ISSUE-0002 next to a seeded RES-0004 and ISSUE-0001; --type bogus SHALL still exit 2 naming the unknown type | done | RED docs/ai/tdd/allocator-research-hotfix-types/red-TEST-3794.log; GREEN docs/ai/tdd/allocator-research-hotfix-types/green-TEST-3794.log; mutation docs/ai/tdd/spec-allocator-research-hotfix-types/mutation-TEST-3794.txt | — | D1, D2; seam allocator path to intake gate |
| Spec-AC-02 | WHEN any intake type in the .aai/INTAKE_COMMON.md table has no TYPE_MAP entry, test-aai-intake.sh TEST-013 SHALL fail naming that type; with the shipped TYPE_MAP it SHALL pass with all eight rows matching | done | RED docs/ai/tdd/allocator-research-hotfix-types/red-TEST-3795.log; GREEN docs/ai/tdd/allocator-research-hotfix-types/green-TEST-3795.log; mutation docs/ai/tdd/spec-allocator-research-hotfix-types/mutation-TEST-3795.txt | — | D3 |
| Spec-AC-03 | WHEN allocate-doc-number.mjs is invoked through a symlinked checkout it SHALL produce the same stdout, stderr and exit code as through the real path (--type bogus exits 2 naming the type; --help exits 0 printing the usage); test-aai-doctor.sh TEST-439 SHALL check every .aai/scripts main() guard with no file excluded | done | RED docs/ai/tdd/allocator-research-hotfix-types/red-TEST-3796.log, docs/ai/tdd/allocator-research-hotfix-types/red-TEST-3797.log; GREEN docs/ai/tdd/allocator-research-hotfix-types/green-TEST-3796.log, docs/ai/tdd/allocator-research-hotfix-types/green-TEST-3797.log; mutation docs/ai/tdd/spec-allocator-research-hotfix-types/mutation-TEST-3796.txt, docs/ai/tdd/spec-allocator-research-hotfix-types/mutation-TEST-3797.txt | — | D4 |
| Spec-AC-04 | CHANGELOG.md SHALL hold exactly one per-entry heading for this fix in the form unreleased or a rolled vYYYY.MM.DD, then an em dash and fix, naming research and hotfix | done | RED docs/ai/tdd/allocator-research-hotfix-types/red-TEST-3798.log; GREEN docs/ai/tdd/allocator-research-hotfix-types/green-TEST-3798.log; mutation docs/ai/tdd/spec-allocator-research-hotfix-types/mutation-TEST-3798.txt | — | Consumer-visible |

## Implementation plan

Components:
- `.aai/scripts/allocate-doc-number.mjs`: the `node:url` import gains
  `fileURLToPath`; two TYPE_MAP rows; a `realOrResolve` helper and the
  main() guard. Nothing else in the file (overlap with #535).
- `tests/skills/test-aai-doc-numbering.sh`: arms `test_3794_research_hotfix_types`,
  `test_3796_symlinked_invocation`, `test_3798_changelog_entry`, added to
  the arm list.
- `tests/skills/test-aai-intake.sh`: TEST-013's ABSENT branch fails.
- `tests/skills/test-aai-doctor.sh`: TEST-439 drops the exclusion and its
  comment.
- `CHANGELOG.md`: one `## [unreleased] — fix: ...` entry.

Planned anchor lines (the Test Plan mutations target them; TDD may re-anchor
a mutation to the code it writes, disclosed as a measurement amendment):
- `  research: { dir: 'specs', prefix: 'RES' },`
- `  hotfix: { dir: 'issues', prefix: 'ISSUE' },`
- `if (process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url))) {`

Seams crossed (each by a real producer and a real reader):
- `draftFilename` (producer) to `docs-audit.mjs --intake-file` (reader, the
  real intake gate reading the real `.aai/INTAKE_COMMON.md` table):
  TEST-3794.
- TYPE_MAP (producer) to the INTAKE_COMMON table parsed twice by TEST-013
  (reader): TEST-3795.
- The allocator's numbering scan for a RES and a shared ISSUE counter
  (producer: a real allocation in a fixture git repo with a bare origin) to
  the renamed file and its stamped number (reader): TEST-3794.
- Not crossed by a test: an intake role actually calling the allocator with
  `--type research` (intake names its own file from the table; R1).

Edge cases: `--type RESEARCH` (resolveType lower-cases, so accepted);
`--type debt`/`techdebt` and `prd`/`requirement` aliases unchanged; a dangling
symlink argv falls back to `path.resolve`.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3794 | Spec-AC-01 | integration | tests/skills/test-aai-doc-numbering.sh | test_3794_research_hotfix_types: draftFilename for research and hotfix builds the two exact paths; each built path written with template frontmatter passes docs-audit --intake-file against the vendored INTAKE_COMMON.md; in a fixture with RES-0004 and ISSUE-0001 committed, allocating a RES draft with --type research and an ISSUE draft with --type hotfix exits 0 and yields RES-0005 and ISSUE-0002; --type bogus exits 2 naming bogus | target `.aai/scripts/allocate-doc-number.mjs`; `sed:s/  research: \{ dir: 'specs', prefix: 'RES' \},/  research_: { dir: 'specs', prefix: 'RES' },/` unmaps research and the case must fail | green |
| TEST-3795 | Spec-AC-02 | integration | tests/skills/test-aai-intake.sh | test_013_one_prefix_per_type_matches_the_allocator: an intake type with no TYPE_MAP entry fails the arm naming it; the shipped map passes with all eight rows matching | target `.aai/scripts/allocate-doc-number.mjs`; `sed:s/  hotfix: \{ dir: 'issues', prefix: 'ISSUE' \},/  hotfix_: { dir: 'issues', prefix: 'ISSUE' },/` unmaps hotfix and the case must fail | green |
| TEST-3796 | Spec-AC-03 | integration | tests/skills/test-aai-doc-numbering.sh | test_3796_symlinked_invocation: through a symlink to the repo root, --type bogus exits 2 with stderr identical to the real path and naming bogus, and --help exits 0 with stdout identical to the real path | target `.aai/scripts/allocate-doc-number.mjs`; `sed:s/realOrResolve\(process\.argv\[1\]\) === realOrResolve\(fileURLToPath\(import\.meta\.url\)\)/path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)/` restores the unresolved guard and the case must fail | green |
| TEST-3797 | Spec-AC-03 | integration | tests/skills/test-aai-doctor.sh | test_439_argv1_guard_resolves_symlinks with no file excluded: the repo-wide grep finds no unresolved main() guard, allocate-doc-number.mjs included | target `.aai/scripts/allocate-doc-number.mjs`; `sed:s/realOrResolve\(process\.argv\[1\]\) === realOrResolve\(fileURLToPath\(import\.meta\.url\)\)/import.meta.url === pathToFileURL(process.argv[1]).href/` restores the old guard and the case must fail | green |
| TEST-3798 | Spec-AC-04 | unit | tests/skills/test-aai-doc-numbering.sh | test_3798_changelog_entry: CHANGELOG.md holds exactly one unreleased or vYYYY.MM.DD heading with an em dash and fix naming research and hotfix | target `CHANGELOG.md`; `sed:s/— fix: the doc-number allocator accepts research and hotfix/— fix: x/` removes the named heading and the case must fail | green |

## Verification

All runs: `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh <cmd>`
from the worktree root; new test code must pass under the suite's
`set -euo pipefail` (no `printf | grep -q`).

1. RED before GREEN under `docs/ai/tdd/allocator-research-hotfix-types/`:
   RED for TEST-3794 is `unknown --type "research"`; for TEST-3795 TEST-013
   passing with a missing row is RED once the ABSENT branch fails while the
   rows are still absent; for TEST-3796 the symlinked run's exit 0 with
   empty output; for TEST-3797 TEST-439 Part A naming the allocator; for
   TEST-3798 the missing heading.
2. `bash tests/skills/test-aai-doc-numbering.sh`,
   `bash tests/skills/test-aai-intake.sh`, `bash tests/skills/test-aai-doctor.sh`,
   `bash tests/skills/test-aai-doc-number-reservation.sh` exit 0, plus the
   CORE set.
3. Mutation records for TEST-3794..3798 under
   `docs/ai/tdd/spec-allocator-research-hotfix-types/` via `mutation-run.mjs`.
4. ISSUE-0042 Verification, each bullet measured by Validation on the branch:
   (a) template copy passes: test-aai-intake.sh TEST-553;
   (b) `--type research`/`--type hotfix`: TEST-3794;
   (c) a double-spaced row read alike by the awk and `parseIntakeTypeTable`:
   test-aai-intake.sh TEST-013 (D9 in-arm proof);
   (d) an over-length follow-up id refused when written:
   `follow-ups.mjs add` with a 57-char id exits 2 naming the 40 cap, and
   test-aai-follow-ups.sh TEST-549 (verify-closures names it unfilable).
5. One full sweep before close with `AAI_TEST_TIMEOUT=4500`.
6. PASS criteria: every TEST row green, every Spec-AC done with evidence,
   CI green on the PR head.

## Evidence contract

Each artifact records ref_id allocator-research-hotfix-types, its Spec-AC
and TEST links, the command, the exit code and the evidence path, plus the
commit SHA once one exists. RED and GREEN logs under
docs/ai/tdd/allocator-research-hotfix-types/, mutation records under
docs/ai/tdd/spec-allocator-research-hotfix-types/.

### Evidence by strategy

tdd: a stored RED artifact per AC-gating test plus the verification matrix
above.

## Out of scope

- Any other change to `allocate-doc-number.mjs` (reservation, regeneration,
  rewrite trees): #535 owns the reservation path.
- Wiring the allocator into intake (intake names its own file from the
  table; `docs-audit.mjs`'s note about the suffix stays true).
- Editing the frozen texts of SPEC-0140, SPEC-0179 and SPEC-0182: they are
  closed and record what was true when they shipped.
- suite-map globs: allocate-doc-number.mjs is protected L3, which already
  forces a full CI run.

## Registry items closed by this scope

- `fu-typemap-missing-research-hotfix` (P2) — Spec-AC-01, Spec-AC-02
- `fu-issue-0042-half-delivered` (P2) — Spec-AC-01 and the ISSUE-0042 close
- `fu-realpath-allocate-doc-number-l3` (P3) — Spec-AC-03

Checked with `node .aai/scripts/follow-ups.mjs list`; the other ISSUE-0042
members (`fu-intake-templates-lack-number-key`,
`fu-intake-common-fallback-numbers-doc`, `fu-intake-table-parser-asymmetry`,
`fu-intake-dir-pin-is-set-not-opening`, `fu-ledger-backticks-ran-as-command`,
`fu-ledger-no-backtick-claim-is-absolute`, `fu-report-ids-exceed-registry-cap`)
are already closed done, and the unanchored-directory member was dropped by
test-framework-sweep.

## Residual risks

- R1. No intake prompt calls the allocator with `--type`; the rows matter
  for `draftFilename` callers and for the CLI's type check. A future intake
  wiring must also teach `docs-audit.mjs` the 4-char suffix (its own note).
- R2. #535 edits the same file; a textual conflict is not expected (disjoint
  hunks) but the second merge must re-run test-aai-doc-numbering.sh and
  test-aai-doc-number-reservation.sh.
