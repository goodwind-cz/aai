---
id: spec-docs-history-is-one-git-call-per-doc
type: spec
number: null
status: implementing
ceremony_level: 1
links:
  requirement: docs/issues/CHANGE-DRAFT-docs-history-is-one-git-call-per-doc.md
  rfc: null
  pr: []
  commits: []
---

# Spec — one history walk answers what 536 subprocesses answered

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-DRAFT-docs-history-is-one-git-call-per-doc.md
- Engine under change: .aai/scripts/lib/docs-audit-core.mjs (`firstCommitDate`, `runAudit`)
- Out-of-scope single-document caller: .aai/scripts/generate-docs-index.mjs:266
- Suite gaining arms: tests/skills/test-aai-docs-audit.sh
- Prior decision the change must not undo: CHANGE-0002 D13 (no `--follow`)
- Registry item this scope makes closable (not closed here): `fu-docsaudit-suite-at-95pct-timeout` (P1)
- Technology contract: docs/TECHNOLOGY.md

Ceremony justification: level 1. One engine function is added beside an existing
one, one call site in `runAudit` is rewired, and one test suite gains arms. No
prompt-corpus byte, no schema, no state write, no `protected_paths_l3` path, no
change to any output format or exit code.

## Summary

`firstCommitDate` (`docs-audit-core.mjs:301`) spawns one
`git log --diff-filter=A --format=%cs -- <file>` per document. `runAudit` calls
it once per document in its main loop (`:979`), gated on `legacy_until_date`
being configured — and it is (`docs/ai/docs-audit.yaml:4`, `2026-06-12`).

Measured on this repository (intake, `main` at `e0223a7`):

```
docs-audit.mjs --check --strict --no-event   14056 ms
docs-audit.mjs --check --quick  --no-event     125 ms   (skips firstCommitDate)
per-file over the whole corpus              15773 ms   (~29 ms x 536)
one whole-history walk                          49 ms
mismatches                                   0 / 536
```

The pre-commit hook pays this on every commit through
`generate-docs-index.mjs`. One walk of the add-history answers the same question
for every document at once.

**Correction to the intake's headline figure, made during this ride and
confirmed by validation.** The intake read the 14056/125 ms gap above as "the
history loop is 99.1% of the audit's cost". That inference is wrong: `--quick`
skips EVERY git probe, not only this one. Counted under a recording PATH shim,
a strict audit makes 581 git calls before this change and 211 after; 203 of the
survivors are a DIFFERENT per-document probe — `git log -1 --grep=<id>`, the
id-mention check, at about 17-19 ms each — and they are present in identical
number before and after. This change owns the 373 per-file history calls it
removes, which is 12155 ms falling to 3667 ms, a measured 3.31x. It does not
own the rest, and Spec-AC-02 was amended mid-ride to stop claiming it.

This spec changes WHERE the answer comes from and nothing about WHAT the answer
is. Notably it reproduces, deliberately, today's meaning for a document renamed
at its close ceremony: `firstCommitDate` returns the RENAME date, not the date
the draft was authored. Whether that is the right meaning is a separate
decision, recorded in the intake and not taken here.

## Design decisions

- **D1 — the map is a local of `runAudit`, built once, threaded by nothing.**
  A new exported `buildFirstCommitDateMap(root)` returns a `Map<relPath, date>`.
  `runAudit` builds it in ONE `const` above the document loop and the loop's
  existing branch reads `firstCommitMap.get(f.rel)` instead of calling
  `firstCommitDate(root, f.rel)`. No parameter is added to `runAudit`, no option
  is threaded through `docs-audit.mjs` or `generate-docs-index.mjs`, no cache
  outlives the call. The alternative — passing a prebuilt map in through the
  options object — would put the lifetime in the caller's hands and make a stale
  map possible the moment a test fixture commits; the intake rules that out.

- **D2 — the walk covers exactly what the audit can ask about, and a miss costs
  correctness nothing.** Checked, not assumed: `scanAuditDocs` (`:720-763`)
  descends only `SCAN_ROOT` (`'docs'`, `:36`), and `scopePath` only narrows that
  set, so every `f.rel` `runAudit` holds is under `docs/`. The pathspec is
  derived from `SCAN_ROOT` rather than written out again, so it cannot drift
  from the scan.

  Two further facts about the KEYS, both measured rather than reasoned:

  1. `--name-only` prints paths relative to the REPOSITORY ROOT, while `f.rel`
     is relative to `root`. With `root` a subdirectory of the repository the two
     disagree (`proj/docs/specs/SPEC-0001-a.md` versus `docs/specs/SPEC-0001-a.md`)
     and every lookup would miss silently — which reclassifies every document as
     new. `--relative` makes git emit paths relative to the process cwd, which
     IS `root`; at a repository root it is a no-op. It is not optional.
  2. A document absent from the map falls back to the shipped per-file call, not
     to `null`. An absent key legitimately means "never added in this history"
     (untracked, or added outside the walk), for which the per-file call returns
     `null` anyway — one subprocess for a handful of in-flight documents. The
     reason to spend it is the failure mode it forecloses: if the key SHAPE ever
     diverges again, the audit degrades to today's cost instead of silently
     dating every document as new. The intake's own risk note is that a wrong
     date here reclassifies documents; this is the guard that makes that class
     of bug slow rather than wrong.

- **D3 — a failed walk falls back to the shipped path, and reports nothing
  because nothing is degraded.** `buildFirstCommitDateMap` returns `null` when
  the walk cannot be trusted: git absent, no history, a non-zero exit, an
  output that does not parse. `runAudit` then calls `firstCommitDate` per
  document exactly as it does today. Every degraded case therefore produces the
  same verdict as before this change, at the same cost as before this change;
  correctness never rides on the accelerator. The empty-map alternative — treat
  a failed walk as "no document has an add commit" — is rejected explicitly: it
  turns a transient git failure or an exceeded `maxBuffer` into a repository-wide
  reclassification, silently. No message is printed on the fallback: the shipped
  `git()` helper (`:293`) swallows stderr and returns `null` by contract, an
  audit in a git-less checkout would otherwise emit a line on every run, and the
  observable outcome of the fallback is byte-identical output. What Article 4
  asks to be reported is a degraded RESULT, and there is none.

- **D4 — the map is built lazily, under exactly today's gate.** The per-document
  branch is `if (!quick && legacyUntil)`; that condition is loop-invariant, so it
  is hoisted verbatim and the map is built only when it holds. `--quick` and a
  repository with no `legacy_until_date` spawn no git process at all — `--quick`
  stays at its measured 125 ms, which is asserted by an arm rather than assumed.

  The hoist also carries `files.length > 1`, added after code review. The
  original guard was `files.length` (at least one document), which made a SCOPED
  audit — `docs-audit.mjs --check --path <one doc>`, the intake post-save gate —
  pay a whole-corpus walk to answer about a single document: measured 49.9 ms of
  walk against a 27.6 ms per-file call, a ratio that grows with the corpus. With
  `> 1` the single-document case takes the D3 fallback, which is the same code
  path and the same answer at the cheaper price. This is the one place where the
  accelerator was slower than what it replaced.

- **D5 — the record separator is a real NUL, and it is `-z` plus `%x00`.** The
  prototype separated `%cs` lines from path lines with a date-shaped regex
  because argv cannot carry a NUL byte. Argv does not have to: `-z` makes
  `--name-only` emit NUL-TERMINATED paths, and the pretty-format placeholder
  `%x00` puts a literal NUL in the header from an ASCII format string. Both were
  measured on git 2.50.1. This is better than the regex on two counts, one of
  them a live correctness hazard:

  - **`core.quotePath` (default `true`) C-quotes any non-ASCII path in line
    mode.** Measured: a document named `docs/specs/SPEC-0001-café.md` prints as
    `"docs/specs/SPEC-0001-caf\303\251.md"` — a key that matches no `f.rel`, so
    that document silently loses its date. Under `-z` it prints raw. Line mode
    also cannot represent a path containing a newline; `-z` can.
  - The commit header becomes unambiguous rather than merely improbable. With
    `--format=%x00%cs`, splitting the stream on NUL yields an EMPTY token
    immediately before every date token, so header and path are told apart by
    position in the record structure, never by what the token looks like.

  The date shape is still checked, as a guard rather than as the discriminator:
  a token in the header position that is not `YYYY-MM-DD` aborts the whole walk
  into the D3 fallback. A parser that cannot recognise its own stream must not
  guess at it.

- **D6 — `--no-renames` is mandatory, and `--full-history` is deliberately
  absent.** Without `--no-renames`, git reports the close-ceremony
  `CHANGE-DRAFT-x.md → CHANGE-0046-x.md` rename as `R`, `--diff-filter=A` drops
  it, and 23 of 536 documents on this repository lose their date (the intake's
  figure on `e0223a7`; re-measured during implementation by dropping the flag
  from the shipped walk and comparing the whole corpus again, 21 of 536 — the
  corpus moved, the defect did not). That is the
  CHANGE-0002 D13 `--follow` hazard arriving from the other direction, and
  AC-003 pins it. `--full-history` is a different matter: it was in the
  prototype, it changes nothing measurable here (0 mismatches either way, 49 ms
  versus 50 ms), and it is dropped because the shipped per-file call does not
  use it.

  **Correction, from validation round 1 — the reason first given here was
  wrong, and wrong in the direction that gives false assurance.** This
  paragraph originally claimed that omitting `--full-history` AVOIDS a
  divergence class. It does not. Validation built the shape and reproduced the
  divergence with the SHIPPED argv, no `--full-history` present: map
  `2026-02-01` against per-file `2026-03-01`. Adding the flag changes nothing
  either way. The actual cause is that history simplification is computed **per
  pathspec**: a merge can be TREESAME to one parent for a single file while
  being TREESAME to neither for `docs` as a whole, so the bulk walk and the
  per-file call simplify differently no matter which flags are set. The
  divergence is real, it is filed as `fu-histmap-merge-pathspec-divergence`
  (P3), and it is left open deliberately: this corpus is 0 of 536 today, only 6
  of 156 merges touch `docs`, and the AC-001 arm runs against the real
  repository on every suite run — so the shape landing turns the suite RED
  rather than making the audit silently wrong. Dropping the flag remains
  correct; the reason is parity with the per-file call, and nothing more.

- **D7 — the stream is newest-first, so the LAST write for a path wins.** The
  shipped function takes the last line of its own newest-first output, i.e. the
  OLDEST add. The map overwrites on every occurrence and therefore ends holding
  the same value. This is not an incidental detail of the loop: reverse it and
  every re-added document gets the wrong date.

- **D8 — `firstCommitDate` keeps its signature, its export and its body.** It is
  not reimplemented on top of the map, and not deprecated.
  `generate-docs-index.mjs:266` calls it for a single document and is out of
  scope; the D2 and D3 fallbacks call it too. One shipped implementation of the
  question remains, which is also what makes the AC-001 equivalence arm
  meaningful.

## Implementation strategy
- Strategy: direct
- Rationale: the mechanism was measured before planning, a working prototype
  exists, and the corpus-wide equivalence is already at 0/536. There is nothing
  to discover; the work is to place the walk where the gate already is and to
  make the equivalence executable. Direct does not waive failing-first: every
  new assertion is proved by MUTATION with an unmutated green control, in-arm,
  so the proof re-runs on every suite execution.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: one engine file, one suite, one spec. The new arms write
  only inside the suite's `mktemp -d`, except the corpus-equivalence arm which
  READS the real repository and writes nothing.
- User decision: inline
- Base ref: main
- Inline review scope: .aai/scripts/lib/docs-audit-core.mjs,
  tests/skills/test-aai-docs-audit.sh,
  docs/specs/SPEC-DRAFT-spec-docs-history-is-one-git-call-per-doc.md

Code review required: true (shared engine behind the audit, the index generator
and several gates).

## Acceptance Criteria Mapping

- Maps to: CHANGE AC-001
- Spec-AC-01: for every tracked `docs/**/*.md`, `buildFirstCommitDateMap`
  returns the byte-identical value the shipped `firstCommitDate` returns, over
  the WHOLE corpus and not a sample. Asserted as an executable arm against the
  real repository, with a vacuity guard on the document count so a truncated or
  empty corpus fails instead of passing, and with the `null`-agreement cases
  counted separately so agreement-by-both-empty cannot carry the claim.
  - Verification: `bash tests/skills/test-aai-docs-audit.sh`, arm
    `test_histmap_corpus_equivalence`. Evidence: the arm's stdout with the
    document count, the mismatch count (0), the both-null count and the
    dated-document count.

- Maps to: CHANGE AC-002
- Spec-AC-02: `docs-audit.mjs --check --strict --no-event` spawns exactly ONE
  git process for first-commit history regardless of corpus size, its output is
  identical to the pre-change run's on the same corpus, and its wall clock falls
  by at least 3x. Measured in one session on one machine, before and after.
  - Verification: the two timed runs recorded in the evidence contract, plus the
    arm `test_histmap_one_git_call_per_audit`, which pins that `--quick` builds no
    map (D4). Evidence: both durations and the `diff` of the two verdict
    outputs.
  - **Threshold amended mid-ride, and the reason belongs on the record.** The
    intake asked for under 2000 ms. That number came from a faulty inference of
    mine, not from a measurement: I timed `--check --strict` at 14056 ms against
    `--check --quick` at 125 ms and attributed the whole 99.1% gap to
    `firstCommitDate`. `--quick` skips EVERY git probe, not only that one. The
    measured truth is that a strict run makes 211 git calls, of which 203 are a
    DIFFERENT per-document probe — `git log -1 --grep=<id>`, the id-mention
    check, at about 19 ms each. Eliminating this scope's probe took 13569 ms to
    3875 ms; the 3.8 s residue is that other probe and is filed as
    `fu-docsaudit-idmention-probe-per-doc` (P2). The amended criterion states
    the property this change actually owns — one git process instead of N — and
    stops borrowing credit for a cost it does not control.

- Maps to: CHANGE AC-003
- Spec-AC-03: a close-ceremony rename is pinned by a fixture. In an isolated
  repository where `CHANGE-DRAFT-x.md` is added on one day and renamed to
  `CHANGE-0046-x.md` on a later one, the map holds the RENAME date for the
  numbered path, which is what the shipped per-file call returns for it. Proved
  to bite: the same fixture walked WITHOUT `--no-renames` loses the numbered
  path entirely, and the unmutated walk is the green control.
  - Verification: `bash tests/skills/test-aai-docs-audit.sh`, arm
    `test_histmap_rename_needs_no_renames`. Evidence: the arm's stdout with both
    dates, the per-file value it agrees with, and the missing key the mutation
    produces.

- Maps to: CHANGE AC-004
- Spec-AC-04: a document with no add commit in the walk yields `null` and no
  crash, in both shapes that can produce it — a document on disk in a repository
  with NO commits at all (the walk itself fails; D3 fallback), and an untracked
  document in a repository that does have history (the walk succeeds and the key
  is absent). In both, the classification the audit derives is the same one it
  derives today.
  - Verification: `bash tests/skills/test-aai-docs-audit.sh`, arm
    `test_histmap_no_history_yields_null`. Evidence: the arm's stdout showing
    `map=null` for the empty repository and an absent key with a `null` per-file
    agreement for the untracked document, and a clean `--check` exit in both.

- Maps to: CHANGE AC-005
- Spec-AC-05: `firstCommitDate` remains exported with its signature and
  behaviour unchanged, and its out-of-scope single-document caller keeps
  working. Asserted by importing it from the shipped module and calling it for
  one document, and by the corpus arm, which uses it as the reference side of
  every comparison — if it stopped working, AC-001 could not pass.
  - Verification: `bash tests/skills/test-aai-docs-audit.sh`, arms
    `test_histmap_corpus_equivalence` and
    `test_histmap_first_commit_date_still_exported`. Evidence: the arm's stdout
    with the single-document date it returned and the generator run that still
    consumes it.

## Constitution deviations

None. Checked v1 articles 1 to 7.

Article 1 (evidence before claims): every Spec-AC names one executable command
and one read observable; every new assertion carries an in-arm mutation with an
unmutated green control. Article 2 (simplicity): one new function beside the one
it accelerates, no option, no knob, no cache, no dependency. Article 3
(portability): Node stdlib and `git` only; no shell quoting of paths at all
(`execFileSync` with an argv array), and `-z` output parsed by byte rather than
by locale. Article 4 (degrade and report): every failure path returns the
shipped result rather than a wrong one — see D3 for why nothing is printed.
Article 5 (additive first): `firstCommitDate` is untouched, no output format and
no exit code changes. Article 6 (single-writer state): no STATE write. Article 7
(operator-only merge): no merge is performed.

## Implementation plan

Components:

- `.aai/scripts/lib/docs-audit-core.mjs` (EDIT)
  - `buildFirstCommitDateMap(root)` (NEW, exported) — one
    `execFileSync('git', ['log', '-z', '--no-renames', '--diff-filter=A',
    '--format=%x00%cs', '--name-only', '--relative', '--', SCAN_ROOT])` with an
    explicit generous `maxBuffer`, parsed by splitting on NUL: an empty token
    arms the next token as a header, the header is validated against
    `^\d{4}-\d{2}-\d{2}$`, every other token is a path whose leading newline (the
    header-to-name-list separator) is stripped, and each path is written into the
    map unconditionally so the last write — the oldest add — wins (D5, D6, D7).
    Returns `null` on a throw or on an unparseable header (D3).
  - `runAudit` (EDIT, two places) — one `const firstCommitMap = (!quick &&
    legacyUntil && files.length) ? buildFirstCommitDateMap(root) : null;` above
    the loop, and inside the existing `if (!quick && legacyUntil)` branch,
    `const first = firstCommitMap?.has(f.rel) ? firstCommitMap.get(f.rel) :
    firstCommitDate(root, f.rel);`. Nothing else in the loop moves.
- `tests/skills/test-aai-docs-audit.sh` (EDIT) — five new arms, one Node helper
  written into `$TEST_DIR` at run time, and four `main()` calls.

Data flows: the map is created and discarded inside one `runAudit` call. No file
is written by any part of this change.

Edge cases: `root` is a subdirectory of the repository (`--relative`, D2); a
non-ASCII or newline-bearing document filename (`-z`, D5); a repository with no
commits, or without git (D3 fallback); a document added and later deleted (in
the map, never asked for); a document deleted and re-added (oldest add wins, D7);
`--quick` and a missing `legacy_until_date` (no walk at all, D4); a corpus large
enough to exceed the default 1 MB `maxBuffer` (raised explicitly — measured at
36 KB for 639 add records today, so the headroom is four orders of magnitude).

Companion obligations (closed list). PROMPT CORPUS BYTES MOVE: NO — no
`.aai/*.prompt.md` and no `.aai/AGENTS.md` byte changes, so no prompt-diet
ledger true-up is owed. NEW `.aai/**` FILE: NO — an existing library file is
edited, so no `.aai/system/PROFILES.yaml` classification is owed. No new suite,
so `tests/skills/suite-map.yaml` needs no new row.

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Status |
|----------|------------|------|----------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | int  | tests/skills/test-aai-docs-audit.sh | over every tracked docs markdown file in the real repository, the value from buildFirstCommitDateMap must equal the value from the shipped firstCommitDate, with zero mismatches; the arm prints the document count, the mismatch count, the both-null count and the dated count, and fails rather than passes when the corpus is implausibly small or when no document carries a date | green |
| TEST-002 | Spec-AC-02 | int  | tests/skills/test-aai-docs-audit.sh | a quick-mode audit builds no history map at all — asserted by running runAudit with quick true under a git wrapper on PATH that records every invocation, requiring zero recorded git calls, with a non-quick run on the same fixture as the control that records at least one | green |
| TEST-003 | Spec-AC-03 | int  | tests/skills/test-aai-docs-audit.sh | in an isolated repository where a DRAFT document is added on one day and renamed to its numbered basename on a later one, the map must hold the rename date for the numbered path and agree with the per-file call; the same walk with --no-renames removed must lose the numbered path entirely, which is the bite, and the unmutated walk is the green control | green |
| TEST-004 | Spec-AC-04 | int  | tests/skills/test-aai-docs-audit.sh | a repository with a document on disk and no commits at all yields a null map and a per-document null with no crash, and an untracked document in a repository that has history is simply absent from the map while the per-file call returns null; a full audit exits cleanly in both | green |
| TEST-005 | Spec-AC-05 | int  | tests/skills/test-aai-docs-audit.sh | firstCommitDate is still exported from the shipped module and still answers for one document — imported directly and called for a known tracked document, its value must be a date and must equal that document's entry in the map | green |

Failing-first discipline (strategy `direct`, so exit codes are the record).
TEST-003 fails NATURALLY on a walk without `--no-renames`, and that mutation is
performed IN-ARM on every run rather than once during development. TEST-001,
TEST-002, TEST-004 and TEST-005 are equivalence and gating claims whose bite is
proved by mutation with an unmutated green control in-arm. An assertion verified
only by reading is not accepted.

## Verification

- `bash tests/skills/test-aai-docs-audit.sh` exits 0, run SERIALLY (no other
  suite against this checkout at the same time), with the whole-suite wall time
  recorded BEFORE and AFTER the change
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` timed before
  and after in the same session, with the two outputs diffed
- `node .aai/scripts/docs-audit.mjs --check --quick --no-event` timed after, to
  show the quick path did not regress
- every suite `node .aai/scripts/select-suites.mjs --files-from <changed files>`
  returns, each run serially
- `node .aai/scripts/spec-lint.mjs` clean,
  `node .aai/scripts/check-test-registration.mjs` clean
- NUL byte count 0 for every edited file; `git rev-parse HEAD` and
  `git status --porcelain=v1 -uno` line count at the start and end of the ride

## Evidence contract

- The before and after durations for `--check --strict --no-event`, and the
  `diff` of the two runs' output showing no verdict changed.
- The before and after wall time of the whole `test-aai-docs-audit.sh` suite.
- The corpus arm's printed counts: documents compared, mismatches, both-null,
  dated.
- For every new assertion: the mutation applied, the failure it produced, and
  the unmutated control that stayed green.
- The `git rev-parse HEAD` and `git status --porcelain=v1 -uno` pair for the
  whole ride, and the per-file NUL byte counts.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN the bulk map is asked for the first-commit date of any tracked document THEN it returns byte-identically what the shipped per-file function returns | done | TEST-001 green over the whole corpus: documents=538 mismatches=0 both_null=0 dated=538 bite=ok. Validation re-derived it through an independent bash plus git implementation and got 0 of 536, with bulk_absent=0 | — | asserted over the whole corpus as an executable arm, never a sample, with a vacuity guard on the document and dated counts (D8) | 
| Spec-AC-02 | WHEN docs-audit runs --check --strict --no-event THEN first-commit history costs exactly ONE git process whatever the corpus size, the verdict is unchanged and wall clock falls at least 3x | done | git calls counted under a recording PATH shim: 581 before, 211 after, of which exactly 1 is the history walk. Wall clock 12155 ms to 3667 ms, 3.31x, strict output byte-identical at 1130 bytes | — | AMENDED mid-ride. Original threshold was under 2000 ms, taken from a faulty inference by the orchestrator rather than a measurement: the 99.1 percent figure came from a --strict versus --quick delta, and --quick skips EVERY git probe not only this one. Measured after: 13569 ms to 3875 ms, 3.5x, output byte-identical. Of the 211 git calls a strict run now makes, 203 are a DIFFERENT per-document probe, git log -1 --grep for id mentions at about 19 ms each, which is the entire 3.8 s residue. That probe is outside AC-001 to AC-005 and is filed as fu-docsaudit-idmention-probe-per-doc (P2). The amended wording claims only the property this change owns | 
| Spec-AC-03 | WHEN a document was renamed at its close ceremony THEN the numbered path still carries the date the shipped function gives it | done | TEST-003 green; the in-arm bite removes --no-renames and the numbered path is lost. Measured on the real corpus the same way: 21 of 536 documents lose their date without the flag, 0 dates change | — | --no-renames is mandatory; removing it is the in-arm bite and loses the numbered path entirely (D6) | 
| Spec-AC-04 | WHEN a document has no add commit in the walk THEN the lookup yields null, never a crash and never another document's date | done | TEST-004 green: a document with no add commit yields null from both paths. A git-failure shim restores exactly the pre-change 373 per-file calls with byte-identical output, so the degrade is a fallback and not a reclassification | — | two shapes: no history at all takes the D3 fallback, an untracked document is simply an absent key (D2, D3) | 
| Spec-AC-05 | WHEN a single-document caller imports firstCommitDate THEN it still works unchanged | done | TEST-005 green: firstCommitDate imported and called directly returns what it returned before the change. It is also the reference side of TEST-001 and the live fallback for every map miss, 2 per strict audit | — | the function is not reimplemented on the map; it is also the reference side of the AC-001 comparison and the D2/D3 fallback (D8) | 

Status values: planned | implementing | done | deferred | blocked | rejected

Every row reads `implementing` until the close ceremony. This is measured rather
than preferred: `docs-audit`'s false-open heuristic fails CLOSED on a fully
terminal AC Status table whose delivery is un-timestampable and reports
`probable-false-open`, which removes the literal `CLEAN` token from the audit
output and turns `tests/skills/test-aai-doc-numbering.sh` TEST-013 red. The rows
flip at the close ceremony, and the flip must PRECEDE `close-work-item.mjs`
rather than follow it (`fu-ac-flip-must-precede-close`).
