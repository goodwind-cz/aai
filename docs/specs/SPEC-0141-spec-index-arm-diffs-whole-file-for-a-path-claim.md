---
id: spec-index-arm-diffs-whole-file-for-a-path-claim
type: spec
number: 141
status: done
ceremony_level: 1
links:
  requirement: docs/issues/ISSUE-0033-index-arm-diffs-whole-file-for-a-path-claim.md
  rfc: null
  pr:
    - 270
  commits:
    - 2ce6909bcb200d4973621af3699aecbbc3eb91c5
---

# Spec — a path assertion must fail on paths, not on the calendar

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/ISSUE-0033-index-arm-diffs-whole-file-for-a-path-claim.md
- Arm being narrowed: tests/skills/test-aai-docs-audit.sh `test_issue0001_posix_paths_noop`
- Spec that originally froze that arm as its TEST-003: docs/specs/SPEC-0007-parsefrontmatter-crlf-tolerance-and-posix-index-paths.md
- Artifact under test: docs/INDEX.md, produced by .aai/scripts/generate-docs-index.mjs
- Write-time enforcer of index freshness: .aai/scripts/install-pre-commit-hook.sh (marker `AAI:INDEX-AUTOGEN`)
- Registry item this scope closes: `fu-docsaudit-t003-utc-date-bomb` (P1)
- Technology contract: docs/TECHNOLOGY.md

Ceremony justification: level 1. One test suite is edited and nothing else.
No production script, no prompt corpus byte, no schema, no state write, no
`protected_paths_l3` path. `.aai/scripts/generate-docs-index.mjs` is READ by the
new arms and deliberately not modified — the intake forbids changing its output
format, and no change to it is needed. The intake fixed AC-001 to AC-004 and the
cause was measured before planning began, so Planning froze those four rather
than reopening the approach.

## Summary

`tests/skills/test-aai-docs-audit.sh` TEST-003 is named "real-repo INDEX paths
are POSIX-only and the path change is a no-op on POSIX". It proved that by
diffing the ENTIRE committed `docs/INDEX.md` against a fresh regeneration,
stripping only `^Generated:`.

The proxy is wrong because `docs/INDEX.md` carries two more date-derived
surfaces. Measured on `main` at `94ee37d`, on a real generation:

- `Generated: <ISO>` at line 3 — stripped by the old arm.
- `## Overdue reviews (N)` at line 6, heading AND body, computed from
  `row._parsedReviewBy < todayUTC` (`generate-docs-index.mjs:330`) — not stripped.
- `Today (UTC): <date> — counts above use this date for overdue checks.` at
  line 431, written from the same `todayUTC` (`:59-60`, `:575-577`) — not stripped.

Measured directly rather than argued: running the real generator against this
repository with its clock pinned to `2026-08-18` and again with the real clock
on `2026-08-21` produced two files differing in exactly two lines, `Generated:`
and `Today (UTC):`. The old arm strips one of those two. So it reddens at every
UTC midnight, for a reason that has nothing to do with path separators, and it
reports the failure as `POSIX-path change must be a no-op on POSIX`.

The arm silently asserted three things and named one:

1. the index contains no backslash separators — the stated claim;
2. the committed index is a byte-current regeneration — a freshness claim;
3. nothing date-dependent has moved since it was generated — an accident.

It failed on (3) and reported (1). It was misattributed twice in one night, each
time costing a measurement cycle.

## Design decisions

- **D1 — the path claim is asserted on paths, and on nothing else.** The
  narrowed arm makes two statements, both date-free: no line of the index
  carries a backslash, and `toPosix` (the function the path change introduced,
  `lib/docs-model.mjs`) is the identity on every `docs/….md` token the index
  contains. The second is the "no-op on POSIX" claim stated directly instead of
  through a whole-file proxy: it imports the shipped `toPosix` and applies it to
  the real corpus's real emitted paths. A vacuity guard fails the arm when the
  file yields zero path tokens, so an empty or truncated index cannot pass by
  having nothing to check.

- **D2 — the freshness property is KEPT, and re-expressed as membership rather
  than as a byte diff, because a byte diff cannot express it here.** This is the
  AC-003 judgement call and it was made on a measurement, not on taste. The
  generator scans the FILESYSTEM (`walk()` over the `SCAN_DIRS`), so an
  untracked, in-flight document counts. At the moment this spec was written the
  working tree held one untracked document
  (`docs/issues/ISSUE-0033-index-arm-diffs-whole-file-for-a-path-claim.md`),
  and a fresh regeneration therefore differed from the committed index by a
  whole `## Drafts` row. A byte-freshness arm would have been RED for the entire
  duration of this ride, and of every other ride in this repository, because
  every ride writes at least one document before it commits. That is the same
  pathology the intake is about — a recurring red that carries no information —
  only continuous instead of daily.

  What survives is the property that actually matters and that nothing else
  pins: the committed index must not have gone stale against the committed
  corpus. The new arm asserts it as membership in both directions — every
  document git TRACKS under the directories the index itself names in its
  `Source:` line must be listed in the index, and every `docs/….md` path the
  index lists must still exist on disk. Both directions are immune to untracked
  in-flight work and to the clock. The arm is named
  `test_indexarm_index_is_not_stale` and its findings all begin with the literal
  token `STALE`, so its failure says the index is stale and never that paths
  moved.

  The scanned-directory list is read out of the index's own `Source:` line
  rather than copied into the suite, because that line is generated from the
  same `DOC_FAMILIES` registry the scan uses (`generate-docs-index.mjs:417`); a
  hardcoded copy would silently under-check the day a family is added.

  Deliberate asymmetry, named rather than left to be found: the reverse
  direction checks EXISTENCE ON DISK, not trackedness. An index regenerated
  locally while an untracked draft exists legitimately lists that draft, and
  checking trackedness would redden on it. Existence catches the case that
  matters (a deleted document still listed) and is stable under in-flight work.

- **D3 — the earlier-day state is produced by the real generator with a pinned
  clock, not by hand-editing the lines the comparison ignores.** Constructing
  "yesterday's index" by rewriting exactly the lines the new mask skips would
  prove only that the mask is self-consistent. Instead both new constructions
  run the SHIPPED `generate-docs-index.mjs`, unmodified, under a tiny loader
  that replaces `globalThis.Date` with a subclass pinned to `AAI_FAKE_NOW`
  before importing it. Every date-dependent line in the output is then computed
  by the generator's own code for that day. The loader is written into the test
  fixture directory at run time; no tracked file is edited and the generator is
  not copied or patched.

- **D4 — the date-derived surface is enumerated once, and under-masking fails
  loudly.** One helper, `index_strip_dated`, drops the three surfaces named in
  the Summary. If the generator ever grows a fourth, the helper under-masks and
  the AC-001 arm goes RED showing the new line in its diff — which is the safe
  direction. Over-masking would be the silent failure, so the helper masks
  whole named surfaces and never a pattern like "any line containing a date".
  Both arms that use it also assert the RAW diff is NON-empty first, so a mask
  that swallowed the whole file could not produce a green.

- **D5 — the retired proxy is pinned as a negative.** The AC-001 arm also
  applies the OLD comparison (strip `^Generated:` only) to the same two
  snapshots and requires it to be NON-empty. The defect is then recorded
  executably: the suite itself states that the arm as it was would be red on
  this input. Reintroducing the whole-file diff cannot pass silently.

- **D6 — the real index is restored from the suite's EXIT trap, not only from
  each arm's own exit paths.** The real-repo arms regenerate `docs/INDEX.md` in
  place. An abort between a generation and its restore — `set -e` on an
  unrelated line, an interrupt, a node crash — left a tracked file dirty, and
  that is what made an earlier investigation conclude "something keeps reverting
  the index". Every existing per-arm `cp "$backup" "$idx"` is kept exactly as it
  is; the trap is added underneath them as a floor, and it runs before
  `cleanup()` removes the fixture directory the backup lives in.

  Corrected after code review: as first implemented the floor was armed by
  `setup_indexarm_snapshots`, which runs *after*
  `test_spec0006_no_regression_real_repo` has already regenerated the real index
  twice — so "every exit path" was false for the one arm that most needed it.
  Arming moved into `setup_fixture`, ahead of every arm, and the backup pointer
  is now published only after a `cmp -s`-verified copy, so an interrupted `cp`
  cannot leave the trap writing a truncated file over the tracked index. A
  failed restore prints a NOTE instead of being swallowed by `|| true`:
  a tracked file left dirty is the one outcome the operator must hear about.
  Registry: `fu-index-floor-armed-after-first-regen`,
  `fu-index-floor-silent-partial-restore`.

- **D7 — the arm keeps its function name.** `test_issue0001_posix_paths_noop` is
  the name `docs/specs/SPEC-0007-….md` Test Plan row TEST-003 points at, and
  three review and validation reports cite it. The body is narrowed in place and
  the comment above it records both identities. SPEC-0007 is `done` and is NOT
  rewritten: its row describes what that arm asserted when it was frozen, which
  is a historical fact, and this spec is where the narrowing is recorded.

- **D8 — nothing in `.aai/` is touched, so no companion obligation is owed.**
  No prompt-corpus byte moves and no new `.aai/**` file is created, so neither
  the prompt-diet ledger true-up nor a `.aai/system/PROFILES.yaml`
  classification applies. `node .aai/scripts/select-suites.mjs` over the changed
  files returns the three core suites and no others.

## Implementation strategy
- Strategy: direct
- Rationale: recorded in STATE as `direct`, sourced from the intake, before this
  ride began. There is no algorithm to discover — the mechanism was measured
  before planning started and the work is to state each claim as its own
  assertion. Direct does not waive the failing-first observation: the load-bearing
  evidence is MUTATION with an unmutated green control, and every mutation runs
  IN-ARM against a scratch copy so the proof re-runs on every suite execution.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: one test suite and one spec document. The only repository
  file any new arm writes is `docs/INDEX.md`, which is backed up before and
  restored after by both the arm and a new EXIT-trap floor; every fixture lives
  in the suite's own `mktemp -d` directory.
- User decision: inline
- Base ref: main
- Inline review scope: tests/skills/test-aai-docs-audit.sh,
  docs/specs/SPEC-0141-spec-index-arm-diffs-whole-file-for-a-path-claim.md

Code review required: true (test-suite change).

## Acceptance Criteria Mapping

- Maps to: ISSUE AC-001
- Spec-AC-01: an index generated on an earlier UTC day, with no other
  difference, fails no arm. The state is CONSTRUCTED, not waited for: the
  shipped generator runs against this repository under a clock pinned three days
  back, and again under the real clock. The two outputs must differ (so the
  construction is real), must differ in their `Today (UTC):` line, must be
  IDENTICAL once the three date-derived surfaces are masked, and the earlier one
  must satisfy both the path arm's predicate and the staleness arm's predicate.
  - Verification: `bash tests/skills/test-aai-docs-audit.sh`, arm
    `test_indexarm_earlier_day_generation_is_green`. Evidence: the arm's stdout
    printing both `Today (UTC):` values, the raw diff line count, the masked
    diff line count (0), and the old-proxy diff line count (non-zero).

- Maps to: ISSUE AC-002
- Spec-AC-02: a genuine backslash in an index path still fails the path arm, and
  the message names the path problem. The arm asserts no backslash on any line
  and `toPosix(token) == token` for every `docs/….md` token, on both the
  committed index and a fresh regeneration, with a vacuity guard on the token
  count. It is proved to bite IN-ARM: a scratch COPY of the index with one path
  rewritten to `docs\specs\…` must be rejected with a finding containing the
  literal `not POSIX`, while the same copy unmutated is accepted.
  - Verification: `bash tests/skills/test-aai-docs-audit.sh`, arm
    `test_issue0001_posix_paths_noop`. Evidence: the arm's stdout with the token
    count it checked, the mutated copy's finding text, and the control's clean
    result.

- Maps to: ISSUE AC-003
- Spec-AC-03: the freshness property is kept and asserted by a separately named
  arm whose failure says the index is STALE. `test_indexarm_index_is_not_stale`
  requires every git-tracked document under the directories the index's own
  `Source:` line names to appear in the index, and every `docs/….md` path the
  index lists to exist on disk; every finding it prints begins with `STALE`. It
  is proved to bite IN-ARM in both directions against scratch COPIES of the
  index — one with a tracked document's row deleted, one with a fabricated path
  appended — with the unmutated copy as the green control. Why the byte-diff
  form of the claim was NOT kept is recorded in D2 with the measurement behind
  it.
  - Verification: `bash tests/skills/test-aai-docs-audit.sh`, arm
    `test_indexarm_index_is_not_stale`. Evidence: the arm's stdout naming the
    directories it derived and the number of tracked documents and index paths
    it checked, plus the two mutated findings and the control's clean result.

- Maps to: ISSUE AC-004
- Spec-AC-04: an `## Overdue reviews (N)` count that moves because the calendar
  advanced fails no arm. Demonstrated with a FIXTURE whose Review-By is in the
  past, in an isolated repository: one spec carrying a `deferred` AC row with
  Review-By set to yesterday. The shipped generator runs there under a clock
  pinned three days back and again under the real clock; the count must be
  observed moving from 0 to 1 with the row appearing, the raw diff must be
  non-empty, and the masked diff must be empty while both the path predicate and
  the staleness predicate stay clean on both outputs.
  - Verification: `bash tests/skills/test-aai-docs-audit.sh`, arm
    `test_indexarm_overdue_boundary_is_green`. Evidence: the arm's stdout
    printing both `## Overdue reviews (N)` headings, the fixture's Review-By
    date, the raw diff line count and the masked diff line count (0).

## Constitution deviations

None. Checked v1 articles 1 to 7.

Article 1 (evidence before claims): every Spec-AC names one executable command
and one read observable, and every new or narrowed assertion carries an in-arm
mutation proof with an unmutated green control. Article 2 (simplicity): no new
file in the repository beyond this spec, no new dependency, no configuration
knob; three shell helpers and one throwaway loader written at run time.
Article 3 (portability): Node stdlib and bash 3.2 only; every date is computed
through `node -e` rather than through a `date` flag that differs between BSD and
GNU. Article 4 (degrade and report): every new predicate prints a named finding
per line and exits non-zero, and both carry a vacuity guard so an empty input
fails instead of passing. Article 5 (additive first): no production script
changes, no index output format changes, no existing arm is deleted. Article 6
(single-writer state): no STATE write. Article 7 (operator-only merge): no merge
is performed.

## Implementation plan

Components:

- `tests/skills/test-aai-docs-audit.sh` (EDIT) — the only file changed.
  - `cleanup()` gains an unconditional restore of `$PROJECT_ROOT/docs/INDEX.md`
    from `$INDEX_REAL_BACKUP` when that variable is set, placed ABOVE the
    `KEEP_TEST_DIR` early return and above the `rm -rf "$TEST_DIR"` that would
    otherwise delete the backup (D6).
  - `index_strip_dated <file>` — one `awk` dropping the three date-derived
    surfaces: the `Generated:` line, the whole `## Overdue reviews (N)` section
    (heading and body, up to the next level-2 heading), and the trailing
    `Today (UTC):` line (D4).
  - `index_posix_findings <file>` — runs a Node predicate written once into the
    fixture directory. It imports the shipped `toPosix` from
    `.aai/scripts/lib/docs-model.mjs`, prints one finding per offending line and
    exits 1; findings name the path problem (`not POSIX`) (D1).
  - `index_stale_findings <root> <file>` — derives the scanned directories from
    the index's `Source:` line, compares `git ls-files` output against the index
    listing in one direction and index path tokens against the filesystem in the
    other, prints `STALE …` findings and exits 1 (D2).
  - `index_generate_at <root> <iso-instant> <log>` — writes the pinned-clock
    loader into the fixture directory on first use and runs the SHIPPED
    generator under it (D3).
  - `utc_day <offset>` — a UTC `YYYY-MM-DD` at a day offset, computed with
    `node -e` for BSD/GNU parity; all offsets in one arm derive from a single
    captured value so a midnight straddle cannot desynchronize them.
  - `setup_indexarm_snapshots` — backs the real index up once, produces the
    earlier-day and fresh snapshots, restores the real index BEFORE any
    assertion runs, and is called once from `main()` so the three real-repo arms
    read snapshots and never the live file.
  - `test_indexarm_earlier_day_generation_is_green` (NEW, TEST-001).
  - `test_issue0001_posix_paths_noop` (NARROWED IN PLACE, TEST-002) — the
    whole-file `diff` and its `t003.before/after.snap` pair are removed; the
    backslash assertion is kept and joined by the `toPosix` identity assertion
    and the in-arm bite proof.
  - `test_indexarm_index_is_not_stale` (NEW, TEST-003).
  - `test_indexarm_overdue_boundary_is_green` (NEW, TEST-004).
  - `main()` gains the setup call and the three new arm calls.

Data flows: the three real-repo arms read only files under `$TEST_DIR`. The one
write to a tracked file is `setup_indexarm_snapshots`'s two generator runs
against `$PROJECT_ROOT`, bracketed by a `cp` backup and an unconditional `cp`
restore, with the EXIT trap as a floor.

Edge cases: a UTC midnight crossing between the two generator runs (masked, and
the 3-day offset keeps the constructed day distinct either way); a repository
with zero tracked documents or an index with zero path tokens (both fail the
vacuity guards rather than passing); a family directory added to `DOC_FAMILIES`
(picked up from the `Source:` line, no suite edit needed); `docs/canonical/`
absent from disk today (a `git ls-files` pathspec that matches nothing is not an
error, verified).

Companion obligations (closed list). PROMPT CORPUS BYTES MOVE: NO — no
`.aai/*.prompt.md` and no `.aai/AGENTS.md` byte changes, so no prompt-diet
ledger true-up is owed. NEW `.aai/**` FILE: NO — no file is added under `.aai/`,
so no `.aai/system/PROFILES.yaml` classification is owed. No new suite, so
`tests/skills/suite-map.yaml` needs no new row.

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Status |
|----------|------------|------|----------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | int  | tests/skills/test-aai-docs-audit.sh | the shipped generate-docs-index.mjs is run against this repository twice, once under a clock pinned three days back and once under the real clock, and the two outputs must differ, must differ in their Today (UTC) line, must be byte-identical once the three date-derived surfaces are masked, and the earlier one must pass both the POSIX-path predicate and the staleness predicate; the retired proxy (strip Generated only) is applied to the same pair and required to be NON-empty, pinning the defect executably (D5) | green |
| TEST-002 | Spec-AC-02 | int  | tests/skills/test-aai-docs-audit.sh | the committed index and a fresh regeneration must each carry no backslash on any line and must satisfy toPosix(token) == token for every docs path token, with the arm failing when the token count is zero; proved to bite in-arm against a scratch COPY of the index with one path rewritten to backslash separators, whose finding must contain the literal not POSIX, with the unmutated copy as the green control | green |
| TEST-003 | Spec-AC-03 | int  | tests/skills/test-aai-docs-audit.sh | every document git tracks under the directories the index's own Source line names must be listed in the index, and every docs path token the index lists must exist on disk, with both universes required non-empty; every finding begins with the literal STALE; proved to bite in-arm in both directions against scratch COPIES, one with a tracked document's row deleted and one with a fabricated path appended, with the unmutated copy as the green control | green |
| TEST-004 | Spec-AC-04 | int  | tests/skills/test-aai-docs-audit.sh | in an isolated repository holding one spec whose AC row is deferred with Review-By set to yesterday, the shipped generator is run under a clock pinned three days back and under the real clock; the Overdue reviews count must be observed moving from 0 to 1 with the row appearing, the raw diff must be non-empty, the masked diff must be empty, and both the POSIX-path predicate and the staleness predicate must stay clean on both outputs | green |

Failing-first discipline (strategy `direct`, so exit codes are the record).
TEST-001 and TEST-004 fail NATURALLY on the pre-change tree in their essential
half: the old arm's comparison, applied to the two snapshots each of them
builds, is non-empty — that is exactly what TEST-001's D5 clause asserts and it
is measured on the pre-change tree before the arm is written. TEST-002 and
TEST-003 are proved by MUTATION with an unmutated green control, in-arm, against
scratch copies, so the proof re-runs on every execution. An assertion verified
only by reading is not accepted.

## Verification

- `bash tests/skills/test-aai-docs-audit.sh` exits 0, run SERIALLY (no other
  suite against this checkout at the same time), with the arm count recorded
  before and after
- the AC-001 construction run out of band as well: the earlier-day index put in
  place as the real `docs/INDEX.md`, the whole suite run green against it, and
  the real index restored from a backup taken first
- every suite `node .aai/scripts/select-suites.mjs --files-from <changed files>`
  returns, each run serially
- `node .aai/scripts/spec-lint.mjs` clean,
  `node .aai/scripts/check-test-registration.mjs` clean,
  `node .aai/scripts/docs-audit.mjs --check --strict --no-event`
- NUL byte count 0 for every edited file; `git rev-parse HEAD` and
  `git status --porcelain=v1 -uno` line count at the start and end of the ride

## Evidence contract

- The suite's stdout for the four arms, with the counts they print rather than
  asserted as constants: both `Today (UTC):` values, both `## Overdue reviews`
  headings, the raw / masked / old-proxy diff line counts, the path token count,
  and the tracked-document and index-path counts.
- For every new or narrowed assertion: the mutation applied, the finding it
  produced, and the unmutated control that stayed clean.
- The pre-change measurement showing the old proxy non-empty on an earlier-day
  snapshot pair.
- The out-of-band whole-suite run against an earlier-day `docs/INDEX.md`.
- The `git rev-parse HEAD` and `git status --porcelain=v1 -uno` pair for the
  whole ride, and the per-file NUL byte counts.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN the committed index was generated on an earlier UTC day and nothing else differs THEN no arm of the suite fails | done | TEST-001 green: earlier day 2026-08-18 vs today 2026-08-21, raw diff 8 lines, masked diff 0, retired proxy 4 lines. Out of band the whole suite ran green with docs/INDEX.md generated on 2026-08-18 while the real date was 2026-08-21 (151 PASS, 0 FAIL) | — | the earlier-day state is CONSTRUCTED by running the shipped generator under a pinned clock, never waited for; the retired proxy is pinned as a negative on the same pair so the defect cannot return silently (D3, D5) | 
| Spec-AC-02 | WHEN an index path carries a backslash separator THEN the path arm fails and its message names the path problem | done | TEST-002 green: 369 path tokens checked on the committed index and 371 on a fresh regeneration, all POSIX and all toPosix-identical; the backslash mutant is rejected with a finding containing not POSIX and the unmutated control stays green | — | the no-op claim is now stated directly as toPosix identity over every emitted path instead of through a whole-file diff, with a vacuity guard so an empty index cannot pass (D1) | 
| Spec-AC-03 | WHEN the committed index has gone stale against the committed corpus THEN a separately named arm fails saying STALE | done | TEST-003 green: 369 tracked documents and 369 index paths checked in both directions; dropping a tracked row and appending a vanished path both produce STALE findings naming the document, and the unmutated control stays clean | — | the freshness property is KEPT, re-expressed as two-direction membership because the generator scans untracked in-flight documents and a byte-freshness arm would be red for the whole of every ride; the measurement behind that choice and the deliberate existence-not-trackedness asymmetry are in D2 | 
| Spec-AC-04 | WHEN an Overdue reviews count moves because the calendar advanced THEN no arm fails for that reason | done | TEST-004 green: fixture Review-By 2026-08-20 observed moving the heading from Overdue reviews (0) to Overdue reviews (1) with the row appearing, raw diff 18 lines, masked diff 0, both predicates clean on both generations | — | demonstrated with a fixture whose Review-By is in the past and an observed 0 to 1 move, not by reasoning; the raw diff is asserted non-empty first so the masked-empty result cannot be vacuous (D4) | 

Status values: planned | implementing | done | deferred | blocked | rejected

Every row reads `implementing` until the close ceremony. This is measured rather
than preferred: `docs-audit`'s false-open heuristic fails CLOSED on a fully
terminal AC Status table whose delivery is un-timestampable and reports
`probable-false-open`, which removes the literal `CLEAN` token from the audit
output and turns `tests/skills/test-aai-doc-numbering.sh` TEST-013 red. The same
reasoning is recorded in SPEC-0137 through SPEC-0140 and tracked as
`fu-acgate-vs-falseopen-catch22`. The rows flip at the close ceremony, and the
flip must PRECEDE `close-work-item.mjs` rather than follow it
(`fu-ac-flip-must-precede-close`).
