---
id: spec-followups-cli-hardening
type: spec
number: 135
status: implementing
ceremony_level: 1
links:
  requirement: docs/issues/CHANGE-0149-followups-cli-hardening.md
  rfc: null
  pr: []
  commits: []
---

# Spec — Follow-up registry CLI: four filed defects, one file

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0149-followups-cli-hardening.md
- Prior spec (the registry this change hardens): docs/specs/SPEC-0129-spec-followup-registry.md
- Prior spec (the report that consumes the same fold): docs/specs/SPEC-0108-spec-factory-performance-report.md
- Prior spec (the sibling ride whose suite numbering this continues): docs/specs/SPEC-0134-spec-ride-cost-readout.md
- Product doc updated by this scope: docs/product/aai-decisions.md
- Technology contract: docs/TECHNOLOGY.md

Ceremony justification: level 1 — the whole substance is one existing `.aai`
script, `.aai/scripts/follow-ups.mjs`, plus new arms in the two suites that
already cover it and the one product doc that already documents it. No
`protected_paths_l3` surface appears in the file list (state engine, allocator,
pre-commit guards, `.aai/workflow/WORKFLOW.md`, `docs/CONSTITUTION.md`), no new
file, no new dependency, no network, no prompt-corpus byte. The registry is
report-only: nothing in this scope gates a merge, a close or a CI job, so a
defect's blast radius is a wrong line on a backlog listing. The one exception —
D2 turns exit 0 into exit 2 on one CLI path — is recorded as an explicit
Article 5 deviation below and is measured, not assumed: every `--ledger`
invocation in the repository was enumerated (Spec-AC-02 evidence). Level 1 still
owes a suite re-run plus a targeted probe and a full dual-verdict review; the
Test Plan below IS the declared validation scope and every row names a directly
executable command.

## Summary

`.aai/scripts/follow-ups.mjs` is the tool the factory writes its own memory
with. Four separately-filed registry items live in it. All four were reproduced
against the current tree on 2026-08-18, in a scratch temp directory, before this
spec was written; the reproduction transcript is quoted per design decision
below. They ship as one scope because they share one file, one fold and one
suite — this is the first of six planned cluster rides against a 54-item backlog
that one-item-per-ride cannot drain.

Three facts measured during planning shape every decision below, and each one
contradicts something the intake asserts:

1. **D4 does not live in `generate-factory-report.mjs`.** The intake places the
   malformed-line exclusion note in the report generator and treats folding it
   in as a scope-widening question. It is not there. The string is
   `.aai/scripts/follow-ups.mjs:270`, emitted by `loadRegistry`, and
   `generate-factory-report.mjs:629` merely spreads `registry.notes` into its
   own `notes` array, which `renderHtml` prints under "Data honesty notes".
   Amending one string in `loadRegistry` fixes the CLI text path, the CLI
   `--json` path and the report HTML at once. `generate-factory-report.mjs` is
   NOT edited by this scope.
2. **The CLI does not tolerate an absent ledger.** The intake's AC-003 says an
   absent ledger is "reported as absent, exit 0" and asks that this be
   preserved. Measured: `list --ledger <nonexistent>` exits **2** today
   (`requireReadableLedger` refuses before the read), and
   `tests/skills/test-aai-follow-ups.sh:253` pins that 2. The read-tolerate
   contract belongs to the exported `loadRegistry` function, which the report
   consumes at exit 0 — a different surface. Spec-AC-03 preserves BOTH halves as
   they actually are, which is not what the intake describes.
3. **No caller can break.** Every `--ledger` occurrence in the repository was
   enumerated: 30 in `tests/skills/test-aai-follow-ups.sh`, 1 in
   `tests/skills/test-aai-factory-report.sh:989`, 4 in
   `docs/product/aai-decisions.md`, 3 in one review report, and the script's own
   usage text. Not one passes a directory. The report reaches the ledger through
   `--decisions` and the exported function, never the CLI. The exit-code change
   has no in-repo caller to break, and no existing assertion in either suite
   changes — Spec-AC-06 makes that mechanical rather than asserted.

## Design decisions

- **D1 — a value is a value unless it is EXACTLY a flag this subcommand knows.**
  Reproduced: `add --what "--decisions is undocumented"` exits 2 with
  `flag "--what" requires a value`, because `parseArgs` rejects any next token
  matching `val.startsWith('--')` (`follow-ups.mjs:366`). That predicate is a
  repo-wide convention — the same `startsWith('--')` lookahead appears in about
  twenty-five `.aai/scripts/*.mjs` files — so the fix must be local to this
  script and must not pretend to a house rule that does not exist. Searched
  first, as the dispatch required: **no script in `.aai/scripts/` supports a
  `--flag=value` form and none implements a `--` sentinel.** There is no existing
  convention to reuse.

  The new rule, in the parse loop only:
  1. A token of the form `--flag=value` is split on its FIRST `=`; the remainder
     is the value, whatever it starts with. Today `--id=fu-x` exits 2 as an
     unknown flag, so this form is purely additive — nothing that works today
     changes meaning.
  2. Otherwise the next token is the value UNLESS it is EXACTLY a token this
     subcommand knows: a member of `FLAG_SPECS[sub]`, or `--json`, `--help`,
     `-h`. Exact string equality, never a prefix test. `--decisions is
     undocumented` is not exactly any of those, so it is a value;
     `add --what --why y` still exits 2 with `flag "--what" requires a value`,
     because `--why` is exactly a known flag. A missing value at end-of-argv
     (`val === undefined`) is unchanged.
  3. The `-h` / `--help` pre-scan (`rest.includes('-h') || rest.includes('--help')`,
     line 348) moves INSIDE the loop and fires only for a token in FLAG
     position. Measured: today `add --what "--help" ...` prints the usage text
     and exits 0 — a value silently swallowed into a help request. This is the
     same defect class D1 names, in the same function, and shipping D1 while it
     survives would leave the AC literally false, so it is in scope and named
     here rather than widened silently. `follow-ups.mjs --help` and
     `follow-ups.mjs help` keep working: the first token is still in flag
     position, and `sub === 'help'` is untouched.

  The residual is exact and closed by rule 1: a value that IS exactly a known
  flag token (`--what "--why"`) is still read as a missing value, and must be
  written `--what=--why`. That is the only unambiguous encoding available, it is
  documented in `--help`, and it is recorded as R1.

- **D2 — ENOENT is absent; everything else is unreadable, and unreadable is
  never "empty".** Reproduced: `list --ledger docs/ai` prints
  `shown=0 open=0 closed=0 total=0` plus `NOTE decision ledger absent at
  <dir> — follow-up registry reported as empty` and exits **0**. The root cause
  is one `catch` with no discrimination: `readDecisionsLedger` (line 116) maps
  EVERY `readFileSync` failure to `missing: true`. A directory passes
  `existsSync` and passes `accessSync(R_OK)`, then throws EISDIR on read and
  lands in the absent branch.

  The fix splits that catch by `err.code`:
  - `ENOENT` keeps today's behaviour exactly: `missing: true`, and `loadRegistry`
    emits today's absent note with today's wording. The wording is load-bearing —
    `test-aai-factory-report.sh` test_029 asserts `/decision ledger/i` and
    `/absent/i` — so it is preserved byte-for-byte.
  - Anything else returns `missing: false` and a new `unreadable: {code, message}`
    field, and `loadRegistry` emits a NEW note that names the path and the errno
    and contains neither the word "absent" nor the phrase "reported as empty".
    The two notes must stay discriminable or test_029's absent assertion stops
    meaning anything.

  Two guards, one contract, because the failure has two shapes:
  - `requireReadableLedger` gains `fs.statSync(abs).isFile()`, so a directory is
    refused with a clear message before anything is read. `statSync` follows
    symlinks, so a symlink to a real ledger still passes.
  - Each subcommand checks `reg.unreadable` immediately after its `loadRegistry`
    call and exits 2. This catches EACCES, EIO and the TOCTOU window the
    original review report already named ("a path that loses read permission
    between existsSync and readFileSync"), and in `add` and `close` it fires
    BEFORE `appendLine`, so a refused command still appends nothing.

  Exit 2 is the right code and not a new one: the D6 exit contract already lists
  "unreadable ledger" under 2. This scope makes the code match the contract that
  was already written.

- **D3 — a malformed id is NAMED on three surfaces and STILL COUNTED.** The
  intake's AC-004 asks for the marker AND for exclusion from the open count.
  Reproduced: an entry with id `BAD ID` lists as `open  BAD ID  P1  R  age=229d
  malformed id item` and is counted in `open=2`. **Exclusion is refused, and the
  intake is overruled on this point.** Three reasons:
  1. It would reintroduce D2's own failure mode one layer down. A hand-typed id
     would make a real deferred item vanish from the number the report
     publishes, and the operator would read a smaller backlog as progress. A
     mistyped anything must never read as good news — that is the sentence this
     whole scope exists to enforce.
  2. This file already decided the same question the other way, twice, and both
     decisions are load-bearing comments in the source: a status value outside
     the closed vocabulary "must never SILENTLY hide an item — it stays in the
     backlog and is named" (line 209), and a statusless status record "must
     never silently re-open a closed item" (line 198). A malformed id is the
     same class: a degradation of a real item, not the absence of one.
  3. Exclusion would make D4's understatement clause true for two different
     reasons at once, one of them avoidable. Keeping the item counted leaves the
     understatement claim narrow and honest: only an unparseable LINE can hide a
     follow-up, because only an unparseable line cannot be read at all.

  Where it is surfaced — all three, each using the surface's own existing
  convention:
  - **The listing row** carries the literal token `MALFORMED-ID`, so a human
    reading `list` sees it on the row itself.
  - **The JSON item** carries `id_malformed: true`, a boolean field exactly
    parallel to the existing `derived_id`.
  - **The counts object** gains `malformed_ids: N`, alongside the existing
    `dangling`, `duplicates` and `derived`, and `notes` gains one NOTE naming the
    count and stating that the items are still counted. The NOTE is what
    propagates to the report, since the report renders `registry.notes`.

  NOT the printed header line (`shown= open= closed= total= ledger=`). That line
  is a status projection over items; malformation is a degradation, and this
  file's convention puts degradations in `notes`. `dangling`, `duplicates` and
  `derived` are already in `counts` and already absent from the header — the new
  counter follows them rather than inventing a second habit.

- **D3a — a DERIVED id is never malformed.** The trap that a naive
  implementation walks into: `deriveLegacyId` produces
  `fu-<slug>-<yyyymmddThhmm>`, and `20260811T0520` contains an uppercase `T`, so
  the derived id does NOT match `^fu-[a-z0-9]+(-[a-z0-9]+)*$`. A grammar check
  applied to every folded id would mark every legacy id-less entry as malformed,
  including the live ledger's own and the one `test-aai-follow-ups.sh` test_003
  uses as a close target. The check therefore runs ONLY when `isDerived` is
  false — a tool-constructed id is already named by its own derived note and is
  not a user error.

- **D4 — one string, in `loadRegistry`, reaching all three consumers.** The
  current note names the exclusion and stops:
  `EXCLUDED N malformed decision ledger line(s) (unparseable JSON, skipped —
  comment lines are not counted)`. It gains a clause stating that an excluded
  line may have carried a `follow_up` and that every count may therefore be
  UNDERSTATED. The existing prefix is preserved verbatim because test_029
  asserts `/malformed decision/i` against it. Nothing is added to the report's
  own follow-up caption: `docs/TECHNOLOGY.md` explicitly discourages duplicating
  a caveat across surfaces, and one honest note that all three consumers render
  is strictly better than two that can drift.

- **D5 — the id grammar stays a single constant.** After D3 the grammar is
  consulted at read time as well as write time. Both call the already-exported
  `FOLLOW_UP_ID_RE` and `ID_MAX_LEN`; no second regex literal for that grammar
  may appear in the file. This is the same single-source rule SPEC-0134 D3
  applied to the usage-marker grammar, and it is greppable.

- **D6 — the append-only contract is not touched.** No command gains a write
  path, `appendLine` is unchanged, and every new refusal happens before any
  append. The only writes this scope can perform are the ones the tool already
  performed.

- **D7 — the product doc is in scope.** `docs/product/aai-decisions.md` carries a
  "Degradations are always named" table and a stable exit-code paragraph that
  this change makes incomplete (no row for a malformed id, no row for an
  unreadable path) and, for the directory case, false. Leaving a published
  contract false to save three suites is not a saving. It costs three extra
  selected suites (`aai-overview`, `aai-product-docs`, `aai-userguide-rollup`),
  all of which the selector returns automatically.

## Implementation strategy
- Strategy: direct
- Rationale: four localized defects in one 545-line script whose suite already
  exists, with fixture shapes the suite already builds (`mk_ledger`, `run_fu`).
  There is no new subsystem, no new input and no interface to discover, so a
  RED-GREEN cycle per test would be ceremony over four conditionals. The
  intake's `## Notes` records "Strategy suggestion: direct with targeted tests"
  and carries no `Implementation mode (user choice):` line; STATE's recorded
  `direct` belongs to the `ride-cost-readout` ride (its `source` names that
  spec), so this is Planning's call and it agrees with the suggestion. Direct
  does NOT waive the failing-first observation: all four defects were reproduced
  before this spec was written, and every new arm asserts on an observable that
  does not exist on the pre-change tree. See the failing-first discipline under
  the Test Plan.

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: one script, two test files, one product doc; no
  `protected_paths_l3` surface and no parallel scope on these paths, so
  isolation is not needed for safety. It is offered only because
  `docs/ai/factory-report.html` and `docs/ai/factory-report-data.json` are
  regenerated by `close-work-item.mjs` on EVERY close, so a concurrent close in
  the shared tree rewrites both generated files mid-ride and makes the diff read
  as this scope's work. A dedicated branch is required regardless by the
  one-branch-per-work-item rule `branch-guard.mjs` enforces at PR.
  Implementation Preparation decides.
- User decision: undecided
- Base ref: main
- Worktree branch/path: fix/followups-cli-hardening (proposed)
- Inline review scope: .aai/scripts/follow-ups.mjs,
  tests/skills/test-aai-follow-ups.sh,
  tests/skills/test-aai-factory-report.sh,
  docs/product/aai-decisions.md,
  docs/specs/SPEC-0135-spec-followups-cli-hardening.md,
  docs/issues/CHANGE-0149-followups-cli-hardening.md, CHANGELOG.md

## Acceptance Criteria Mapping

- Maps to: followups-cli-hardening AC-001
- Spec-AC-01: every value-taking flag of every subcommand accepts a value whose
  first two characters are `--`, provided the value is not exactly a token that
  subcommand knows. `add --what "--decisions is undocumented" ...` exits 0 and
  the appended line's `finding` is that exact string. The same holds for
  `--why`, `--source`, `--ref`, `--id`, `--resolved-by`, `--ledger`, `--actor`
  and `list --ref`. A genuinely missing value still exits 2 with a message
  naming the flag, in all three shapes: end of argv (`add --what`), a following
  token that is exactly a known flag of the subcommand (`add --what --why y`),
  and a following token that is exactly `--json`, `--help` or `-h`. The
  `--flag=value` form is accepted for every value-taking flag and takes
  everything after the FIRST `=` as the value, so `--what=--why` yields the
  literal `--why`. A token equal to `-h` or `--help` in VALUE position is a
  value, not a help request, while `follow-ups.mjs --help`, `follow-ups.mjs -h`
  and `follow-ups.mjs help` all still print the usage text and exit 0.
  - Verification: `bash tests/skills/test-aai-follow-ups.sh test_011_flag_values_with_leading_dashes`
    over a scratch ledger, asserting the exit codes and the re-read `finding`
    value for each shape above, plus a seam arm that runs `routine-emit.mjs`
    over the ledger a dashed value was written into and asserts merge
    authorization is still GRANTED. Evidence: suite stdout.

- Maps to: followups-cli-hardening AC-002
- Spec-AC-02: a `--ledger` path that exists but cannot be read as a file exits 2
  on `list`, `add` and `close`, prints a message on stderr naming the resolved
  absolute path and the reason, appends nothing, and prints no line containing
  `total=0`, the word `absent`, or the phrase `reported as empty`. The directory
  case (`list --ledger docs/ai`, which exits 0 today) is refused by an
  `fs.statSync(abs).isFile()` guard, and every other unreadable shape is refused
  by an `unreadable` check placed after `loadRegistry` and before any append.
  No in-repo caller regresses: `grep -rn -- "--ledger"` over the repository
  returns only `tests/skills/test-aai-follow-ups.sh`,
  `tests/skills/test-aai-factory-report.sh:989`, `docs/product/aai-decisions.md`,
  one review report and the script's own usage text, and not one of them passes
  a directory.
  - Verification: `bash tests/skills/test-aai-follow-ups.sh test_012_unreadable_ledger_refused`
    for the directory case on all three subcommands plus a chmod-000 file case
    skipped when the suite runs as root, each asserting exit 2, the stderr
    substrings, the forbidden stdout substrings and a byte-unchanged ledger;
    plus the `grep -rn -- "--ledger"` enumeration recorded in the return record.
    Evidence: suite stdout and the grep output.

- Maps to: followups-cli-hardening AC-003
- Spec-AC-03: the absent-ledger contract is unchanged on BOTH surfaces, as they
  actually are today. On the CLI, `list --ledger <nonexistent>` still exits 2
  with `ledger not found` — the intake's claim that this path exits 0 is wrong,
  and `tests/skills/test-aai-follow-ups.sh:253` already pins the 2. Through the
  exported `loadRegistry`, an absent path still returns `missing: true` with
  zero items and emits the existing absent note with its current wording
  unchanged, so `generate-factory-report.mjs` still reports `open_count: 0`,
  `oldest_age_days: null` and exits 0. The absent note and the new unreadable
  note are mutually exclusive and textually discriminable: the absent note
  matches `/absent/i`, the unreadable note does not.
  - Verification: `bash tests/skills/test-aai-follow-ups.sh test_013_absent_ledger_contract_unchanged`
    asserting the CLI exit 2, and a direct `node --input-type=module` import of
    `loadRegistry` over an absent path and over a directory asserting
    `missing === true` with an `/absent/i` note for the first and
    `missing === false` with an `unreadable` object and a note matching neither
    `/absent/i` nor `/reported as empty/` for the second, and that neither call
    throws. Evidence: suite stdout.

- Maps to: followups-cli-hardening AC-004
- Spec-AC-04: a folded item whose id came from the ledger and does not match
  `FOLLOW_UP_ID_RE`, or exceeds `ID_MAX_LEN`, is named on three surfaces and
  remains in the open count. Its `list` row contains the literal `MALFORMED-ID`;
  its `--json` item carries `id_malformed: true`; `counts.malformed_ids` equals
  the number of such items; and `notes` gains one entry naming that count and
  stating the items are still counted. A well-formed item carries
  `id_malformed: false` and no marker. `counts.open` over a ledger holding one
  well-formed open item and one `BAD ID` open item is 2, not 1. An id produced
  by `deriveLegacyId` is never marked malformed, even though
  `fu-<slug>-<yyyymmddThhmm>` does not match the grammar. No second regex
  literal for the id grammar appears in `.aai/scripts/follow-ups.mjs`.
  - Verification: `bash tests/skills/test-aai-follow-ups.sh test_014_malformed_id_named_and_counted`
    over a ledger holding a well-formed open item, an id of `BAD ID`, an
    over-length id and an id-less legacy entry, asserting the row marker, the
    JSON flag on exactly the two malformed ids, `counts.malformed_ids === 2`,
    `counts.open === 4`, the note text, and `id_malformed === false` on the
    derived-id item; plus `grep -c 'fu-\[a-z0-9\]' .aai/scripts/follow-ups.mjs`
    returning 1. Evidence: suite stdout and the grep count.

- Maps to: followups-cli-hardening AC-005
- Spec-AC-05: whenever `loadRegistry` excludes at least one malformed line, the
  emitted note states both the exclusion and that the counts may therefore be
  understated, and the note reaches all three consumers unchanged: the CLI text
  listing, the CLI `--json` `notes` array, and the report's data-honesty notes.
  The note still begins with the existing `EXCLUDED N malformed decision ledger
  line(s)` text so the pre-existing `/malformed decision/i` assertions keep
  matching. When no line is excluded, no such note is emitted and the word
  `UNDERSTATED` appears in neither output.
  - Verification: `bash tests/skills/test-aai-follow-ups.sh test_015_exclusion_note_states_understatement`
    over one ledger with a malformed line and one without, asserting the clause
    is present in the text and `--json` paths for the first and absent for the
    second. Evidence: suite stdout.

- Maps to: followups-cli-hardening AC-006, AC-007
- Spec-AC-06: the change is additive and nothing that works today changes. The
  append-only contract holds — no command rewrites or removes a line, and for
  every arm that appends, the pre-command bytes are a prefix of the post-command
  file. Non-follow-up record types in the shared ledger
  (`review_disposition`, `routine_authorization`, `note`) fold exactly as
  before. Every pre-existing arm of both suites stays green with NO assertion
  modified or deleted: `git diff --numstat main -- tests/skills/test-aai-follow-ups.sh
  tests/skills/test-aai-factory-report.sh` reports 0 deleted lines in both
  files, so the suites grow by added functions and their `main()` registration
  lines only.
  - Verification: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-follow-ups.sh`
    and `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-factory-report.sh`
    each exiting 0 with zero `FAIL` lines and TEST-001 through TEST-010 and
    TEST-001 through TEST-039 respectively still running; plus the
    `git diff --numstat` deletion counts. Evidence: the two stdouts and the
    numstat output.

- Maps to: followups-cli-hardening AC-002, AC-005
- Spec-AC-07: the producer-to-report seam holds. `loadRegistry` never throws for
  any ledger shape, and `node .aai/scripts/generate-factory-report.mjs` exits 0
  over an absent ledger, an unreadable ledger (a directory passed via
  `--decisions`) and a ledger carrying a malformed line, in each case writing
  `follow_ups.open_count` and `oldest_age_days` and naming the degradation in
  `notes`. For the unreadable case the note names the path and does not claim
  the registry is absent or empty; for the malformed case the note carries the
  understatement clause; and the rendered HTML carries both under the
  data-honesty notes section. `.aai/scripts/generate-factory-report.mjs` is
  byte-unchanged by this scope.
  - Verification: `bash tests/skills/test-aai-factory-report.sh test_040_follow_ups_unreadable_and_understatement`
    for the three ledger shapes, asserting exit 0, the JSON notes and the HTML
    text each time; plus `git diff --stat main -- .aai/scripts/generate-factory-report.mjs`
    being empty. Evidence: suite stdout and the diff stat.

- Maps to: followups-cli-hardening AC-001, AC-002, AC-004
- Spec-AC-08: the published contract is true again. `follow-ups.mjs --help`
  documents the dashed-value rule and the `--flag=value` escape hatch.
  `docs/product/aai-decisions.md` gains one degradation-table row for an id that
  does not match the grammar (named, marked, still counted) and one for a path
  that exists but is not a readable file (refused at exit 2, never reported as
  empty), states the understatement clause in its malformed-line row, and its
  exit-code paragraph names the unreadable-path case as exit 2. Its frontmatter
  `delivered_by` gains this scope's CHANGE id and `updated` is bumped.
  - Verification: `bash tests/skills/test-aai-follow-ups.sh test_017_grammar_and_product_doc_pins`
    grepping the `--help` output and the product doc for each pin and checking
    the two frontmatter fields, plus `node .aai/scripts/docs-audit.mjs --check`
    exiting 0. Evidence: suite stdout and the audit stdout.

## Constitution deviations

Article 5 (additive first) — DEVIATION, explicit and documented. D2 changes a
public boundary: `follow-ups.mjs list --ledger <directory>` returns 0 today and
returns 2 after this change. It is justified because the current 0 is the defect
itself — the command answers a mistyped path with "the registry is empty", which
is the failure mode the whole scope exists to remove, and no backward-compatible
encoding of "this path is wrong" exists inside exit 0. The deviation is bounded
and measured, not assumed: the exit code already documented for this case in the
D6 exit contract IS 2, so the change moves the code toward the published
contract rather than away from it; every `--ledger` invocation in the repository
was enumerated and none passes a directory (Spec-AC-02); no existing test
assertion changes (Spec-AC-06); and the read-tolerate path that consumers
actually depend on, `loadRegistry` through the report, keeps exit 0 for every
ledger shape (Spec-AC-07). Recorded in CHANGELOG as a behaviour change.

Articles 1, 2, 3, 4, 6 and 7: no deviation. Article 2 (simplicity): four
conditionals and one string in one existing file, no new file and no new
dependency. Article 4 (degrade and report): D2 and D3 are that article applied —
each replaces a silent wrong answer with a named one, and D3 refuses the
intake's own suggestion precisely because hiding an item would be the silent
option.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN a value-taking flag is given a value beginning with two dashes that is not exactly a token the subcommand knows THEN the value is accepted verbatim, while a genuinely missing value still exits 2, the flag=value form is accepted for every such flag, and a token equal to -h or --help in value position is a value rather than a help request | done | TEST-011 | — | reproduced twice on 2026-08-17 and again on 2026-08-18; the help pre-scan is folded in because it is the same defect in the same function; pre-fix TEST-011 exit 1 (FAIL: a dashed value must be accepted...) |
| Spec-AC-02 | WHEN --ledger names a path that exists but cannot be read as a file THEN list add and close each exit 2 naming the path and the reason, append nothing, and print no empty-registry line | done | TEST-012 | — | the one boundary this scope can break; every in-repo --ledger invocation enumerated and none passes a directory; pre-fix TEST-012 exit 1 (FAIL: list --ledger <directory> must exit 2, got 0) |
| Spec-AC-03 | WHEN the ledger is absent THEN the CLI still exits 2 and loadRegistry still returns missing true with the existing absent note so the report still exits 0 with open_count 0, and the absent and unreadable notes stay textually discriminable | done | TEST-013 | — | corrects the intake, which claims the CLI exits 0 for an absent ledger; it exits 2 today and a suite arm already pins that; pre-fix TEST-013 exit 1 (FAIL: loadRegistry absent-vs-directory contract violated) |
| Spec-AC-04 | WHEN a folded id came from the ledger and does not match the id grammar THEN the row carries a MALFORMED-ID token, the JSON item carries id_malformed true, counts carries malformed_ids and a note names it, and the item REMAINS in the open count | done | TEST-014 | — | overrules the intake's exclude-from-count clause; a derived id is never marked malformed because the derived form contains an uppercase T; pre-fix TEST-014 exit 1 (FAIL: malformed-id contract violated) |
| Spec-AC-05 | WHEN at least one malformed line is excluded THEN the note states the counts may be understated and reaches the CLI text the CLI json and the report notes unchanged, and when none is excluded the clause appears nowhere | done | TEST-015 | — | one string in loadRegistry reaches all three consumers; the report generator is not edited; pre-fix TEST-015 exit 1 (FAIL: the text note must state the counts may be UNDERSTATED) |
| Spec-AC-06 | WHEN the suites are re-run THEN every pre-existing arm is green with zero deleted lines in either test file and the append-only prefix property holds for every appending arm | done | TEST-016 | — | makes the non-breaking claim mechanical via git diff numstat rather than asserted; both suites green, 0 deleted lines in both files (git diff --numstat main) |
| Spec-AC-07 | WHEN the report generator runs over an absent an unreadable or a malformed-line ledger THEN it exits 0 every time with the degradation named in notes and rendered in the HTML, and the generator file is byte-unchanged | done | TEST-040 | — | SEAM-1; the report reaches the fold through the exported function, never the CLI, so its exit contract must survive D2 untouched; pre-fix TEST-040 exit 1 (FAIL: unreadable-ledger note contract violated: WRONGLY-ABSENT); git diff --stat main -- generate-factory-report.mjs is empty |
| Spec-AC-08 | WHEN the help text and the product doc are read THEN they document the dashed-value rule the flag=value escape hatch the malformed-id row and the unreadable-path exit code, and the product doc frontmatter is bumped | done | TEST-017 | — | the exit-code paragraph is false after D2 unless updated; costs three extra selected suites, all returned by the selector; pre-fix TEST-017 exit 1 (FAIL: --help must document the dashed-value rule) |

## Implementation plan

Components:

- `.aai/scripts/follow-ups.mjs` (EDIT — the whole substance, five touch points):
  - `readDecisionsLedger` (line 111): split the `catch` by `err.code`. ENOENT
    keeps `missing: true`; anything else returns `missing: false` plus
    `unreadable: { code, message }`. Both branches keep returning the same
    `{ records, malformed }` shape so no caller sees a new failure mode.
  - `foldFollowUps` (line 160): compute `idMalformed` per item using the
    existing `FOLLOW_UP_ID_RE` and `ID_MAX_LEN`, ONLY when `isDerived` is false;
    add `id_malformed` to the pushed item, `malformed_ids` to `counts`, and one
    NOTE when the count is above zero. The `open` count computation
    (`items.filter((i) => !i.closed).length`) is deliberately NOT changed.
  - `loadRegistry` (line 265): emit the new unreadable note when `unreadable` is
    set, keep the absent note byte-identical for `missing`, extend the EXCLUDED
    note with the understatement clause, and pass `unreadable` through in the
    returned object.
  - `parseArgs` (line 342): the D1 rules — `--flag=value` split, exact-known-token
    lookahead, and the help check moved inside the loop.
  - `requireReadableLedger` (line 378) plus one `reg.unreadable` check in each of
    `cmdList`, `cmdAdd` and `cmdClose`, placed after `loadRegistry` and before
    any `appendLine`.
  - `USAGE` (line 302): the dashed-value rule and the `--flag=value` escape
    hatch, and the unreadable-path case in the exit-code paragraph.
- `tests/skills/test-aai-follow-ups.sh` (EDIT): six new functions registered in
  `main()` as `test_011` through `test_015` and `test_017`, following the file's
  conventions — `mk_ledger`, `run_fu`, `fsize`, `nlines`, `log_pass`/`log_fail`,
  bash 3.2, scratch temp-dir ledgers only, and here-strings never pipes (the
  suite runs `set -euo pipefail`; see the file header and the
  test-harness-shell-options trap in `docs/knowledge/LEARNED.md`). Numbering
  continues past 010; 006 and 007 stay owned by the factory-report suite, as
  they are today. TEST-016 adds no function — it is the two-suite regression row.
- `tests/skills/test-aai-factory-report.sh` (EDIT): one new function
  `test_040_follow_ups_unreadable_and_understatement` registered in `main()`.
  Numbering continues past 039; 030 and 038 stay unused, as they are today.
- `docs/product/aai-decisions.md` (EDIT): the Spec-AC-08 pins, `delivered_by`
  and `updated`.
- `docs/issues/CHANGE-0149-followups-cli-hardening.md` (EDIT): status flip at
  close, and the four registry ids named in `## Notes` are closed with
  `node .aai/scripts/follow-ups.mjs close --id <id> --resolved-by <ref>` as the
  documented manual step.
- `tests/skills/test-aai-spec-lint.sh` (EDIT, +5/-0 — ERRATUM, see below): not
  named here or in the Inline review scope when the spec was frozen, but
  necessary — stashing it fails `test_clarify_011_no_new_ceremony`. It pays the
  file's own "allowlist tax" convention (the sixth payment, citing
  `fu-test011-branch-diff-allowlist-tax`). Zero deletions, so Spec-AC-06's
  mechanization covers it the same as the two named suite files.
- `CHANGELOG.md`: one `## [unreleased] — <title>` heading carrying this change's
  entry, naming the D2 exit-code change as a behaviour change (per-entry heading
  form, never bullets under a bare scaffold).
- NOT EDITED: `.aai/scripts/generate-factory-report.mjs` (Spec-AC-07 asserts the
  byte-identity), `.aai/scripts/close-work-item.mjs`, and every `.aai/*.prompt.md`.

Data flows:

- argv -> `parseArgs` -> `opts` -> subcommand. The D1 change is confined to the
  token loop; no subcommand sees a new option key.
- ledger file -> `readDecisionsLedger` -> `{records, malformed, missing,
  unreadable}` -> `foldFollowUps` -> `{items, notes, counts}` -> `loadRegistry`
  -> either the CLI renderer or `generate-factory-report.mjs`'s `followUps`
  block and `notes` array. One fold, two consumers, unchanged.

Companion obligations (the closed two-entry list): NEITHER applies. No
`.aai/*.prompt.md` or `.aai/AGENTS.md` byte is added, so no prompt-diet ledger
true-up and no TEST-012 checkpoint bump. No NEW `.aai/**` file is created, so no
`.aai/system/PROFILES.yaml` classification entry.

Edge cases:

- A symlink whose target is a real ledger: `statSync` follows symlinks, so
  `isFile()` is true and the command proceeds. A dangling symlink raises ENOENT
  and is treated as absent, matching today.
- A zero-byte ledger stays readable and folds to `total=0` at exit 0 — the
  existing empty-backlog arm must not be disturbed by the unreadable guard.
- An id that is the empty string or whitespace-only is already coerced to a
  derived id by the existing `id === null` branch and is therefore never marked
  malformed.
- A non-string `id` (a number, an object) falls through the same existing branch
  to a derived id; the grammar check never sees a non-string.
- An id longer than `ID_MAX_LEN` that otherwise matches the grammar is malformed
  — the write path already refuses it, so only a hand-written line can produce
  one.
- `--ledger=docs/ai` exercises D1 and D2 at once: the `=` form must parse, then
  the directory guard must refuse. Worth one assertion.
- A value containing `=` given in the bare form (`--what "a=b"`) is unaffected;
  only a token that itself STARTS with `--` is considered for the `=` split.
- Running the chmod-000 arm as root would not produce EACCES; that arm must skip
  itself rather than fail, using the suite's existing `log_info` degrade
  pattern, never `log_skip` (which exits 42 and reports the WHOLE suite as
  skipped — the trap already recorded in this suite's test_005).

## Seams

- SEAM-1 — `loadRegistry` (producer) and `generate-factory-report.mjs`
  (consumer). The report spreads `registry.notes` and reads `registry.items`. A
  new field, a changed note string or a thrown error on an unreadable path all
  land here first, and the report's contract is "every ledger shape exits 0". A
  unit test on the fold alone would prove nothing about the report. Crossed by
  TEST-040, which runs the REAL generator over three ledger shapes and reads its
  real JSON and HTML output. No mock exists on this path.
- SEAM-2 — `follow-ups.mjs` (writer) and `routine-emit.mjs`'s fail-closed
  authorization reader, over the SAME `docs/ai/decisions.jsonl`. D1 newly admits
  values beginning with `--` into a serialized ledger line. `JSON.stringify`
  escapes them, so the line cannot be malformed by construction — but that is
  the claim, and one malformed line silently revokes merge authorization for
  every scheduled routine with no error near the cause. Crossed by TEST-011's
  seam arm, which writes a dashed value and then runs the real
  `routine-emit.mjs` over that ledger asserting merge is still GRANTED, reusing
  the shape TEST-009 already established.
- SEAM-3 — the read-time id grammar (new) and the write-time id grammar
  (`cmdAdd`). Two consultations of one rule is the classic silent-drift shape: a
  later tightening of the write check that misses the read check would make
  `add` refuse an id that `list` calls well-formed. Crossed by D5's single-constant
  rule, asserted by TEST-014's grep for exactly one grammar literal in the file.
- SEAM-4 — `deriveLegacyId` (producer of ids) and the new grammar check
  (consumer of ids). The derived form is deliberately outside the grammar, so
  the two disagree by construction. Crossed by TEST-014's derived-id assertion;
  without it the live ledger's legacy entry and test_003's close target both
  become "malformed".
- SEAM-5 — the follow-up fold and the OTHER record types sharing the ledger
  (`review_disposition`, `routine_authorization`, `note`, and the 14 backfill
  lines). The parser change must not alter how a non-`follow_up` line is read.
  Crossed by the unchanged TEST-004, TEST-005 and TEST-009 arms re-run under
  TEST-016, all of which read the live ledger.
- SEAM-6 — the CLI text row and the `--json` items. `test_002` derives ids from
  text rows by whitespace splitting; a malformed id containing a space already
  breaks that parse, and the new row marker adds a token to the same row.
  A maintenance seam, not a runtime one: the marker must not be placed where it
  changes the leading `open|done|dropped` word that row-detection depends on.
  Written down so a later failure reads as a signal rather than a mystery.

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Status |
|----------|------------|------|----------------------|-------------|--------|
| TEST-011 | Spec-AC-01 | int  | tests/skills/test-aai-follow-ups.sh | run `bash tests/skills/test-aai-follow-ups.sh test_011_flag_values_with_leading_dashes` — a dashed value is accepted for every value-taking flag on add close and list and re-reads verbatim, a missing value still exits 2 in all three shapes (end of argv, an exactly-known flag, and --json or --help), the flag=value form works including --what=--why, a value equal to -h or --help is a value while --help -h and help in flag position still print usage at exit 0, and routine-emit still GRANTS over the ledger the dashed value was written into | green |
| TEST-012 | Spec-AC-02 | int  | tests/skills/test-aai-follow-ups.sh | run `bash tests/skills/test-aai-follow-ups.sh test_012_unreadable_ledger_refused` — a directory passed to --ledger exits 2 on list add and close naming the resolved path and the reason on stderr, prints no total=0 no absent and no reported-as-empty line, and leaves the ledger byte-unchanged; a chmod-000 file behaves identically or the arm degrades with a named log_info line when running as root; and --ledger=docs/ai exercises the equals form into the same refusal | green |
| TEST-013 | Spec-AC-03 | int  | tests/skills/test-aai-follow-ups.sh | run `bash tests/skills/test-aai-follow-ups.sh test_013_absent_ledger_contract_unchanged` — the CLI still exits 2 on an absent path, and a direct import of loadRegistry returns missing true with an absent-matching note for an absent path and missing false with an unreadable object and a note matching neither absent nor reported-as-empty for a directory, with neither call throwing | green |
| TEST-014 | Spec-AC-04 | unit | tests/skills/test-aai-follow-ups.sh | run `bash tests/skills/test-aai-follow-ups.sh test_014_malformed_id_named_and_counted` — over a ledger holding a well-formed item a BAD ID item an over-length id and an id-less legacy entry, the two malformed rows carry the MALFORMED-ID token, exactly those two items carry id_malformed true, counts.malformed_ids is 2, counts.open is 4 so nothing is hidden, the note names the count and says the items are still counted, the derived-id item is NOT marked malformed, and the source carries exactly one id-grammar regex literal | green |
| TEST-015 | Spec-AC-05 | unit | tests/skills/test-aai-follow-ups.sh | run `bash tests/skills/test-aai-follow-ups.sh test_015_exclusion_note_states_understatement` — a ledger with one unparseable line produces a note that both begins with the existing EXCLUDED malformed decision ledger text and states the counts may be understated, on the text path and in the json notes array, and a ledger with no unparseable line produces neither the note nor the word UNDERSTATED anywhere | green |
| TEST-016 | Spec-AC-06 | int  | tests/skills/test-aai-follow-ups.sh | run `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-follow-ups.sh` then `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-factory-report.sh` — both exit 0 with zero FAIL lines, TEST-001 through TEST-010 and TEST-001 through TEST-039 all still run, and `git diff --numstat main -- tests/skills/test-aai-follow-ups.sh tests/skills/test-aai-factory-report.sh` reports zero deleted lines in both files | green |
| TEST-040 | Spec-AC-07 | int  | tests/skills/test-aai-factory-report.sh | run `bash tests/skills/test-aai-factory-report.sh test_040_follow_ups_unreadable_and_understatement` — the real generator over an absent an unreadable (a directory via --decisions) and a malformed-line ledger exits 0 each time, writes open_count and oldest_age_days, names the unreadable path without claiming absent or empty, carries the understatement clause for the malformed case, renders both under the data-honesty notes in the HTML, and `git diff --stat main -- .aai/scripts/generate-factory-report.mjs` is empty | green |
| TEST-017 | Spec-AC-08 | unit | tests/skills/test-aai-follow-ups.sh | run `bash tests/skills/test-aai-follow-ups.sh test_017_grammar_and_product_doc_pins` — the --help output documents the dashed-value rule and the flag=value escape hatch, docs/product/aai-decisions.md carries the malformed-id degradation row the unreadable-path row the understatement clause and the exit-2 unreadable case, and its frontmatter delivered_by and updated are bumped | green |

Failing-first discipline (strategy `direct`, so exit codes are the record, not a
stored artifact). All four defects were reproduced in a scratch temp directory
on 2026-08-18 before this spec was written, and the transcripts are quoted in
D1, D2 and D3. TEST-011 through TEST-015, TEST-017 and TEST-040 each assert on
an observable that does not exist on the pre-change tree — an accepted dashed
value, an exit 2 for a directory, a `MALFORMED-ID` token, an `id_malformed`
field, the understatement clause, the new help and doc text — so each fails
naturally before the edit. Run every one of those seven on the unmodified tree
FIRST, capture the non-zero exit code and the failing assertion line, and record
both in the Implementation return record's `evidence` list next to the passing
run. An arm that cannot be shown failing before the edit must be reported as
such rather than counted as proof.

TEST-016 is a regression row and cannot fail before the change: a green run of
both suites plus two zero deletion counts is its evidence.

## Verification

Run whatever the selector returns — NOT a hand-picked list. A CORE suite skipped
during validation is what failed CI on CHANGE-0148, and this instruction is
recorded here so the next role inherits it rather than depending on a dispatch
to remember it:

```
node .aai/scripts/select-suites.mjs --files-from <the changed-file list>
```

Measured during planning against the expected file list
(`.aai/scripts/follow-ups.mjs`, `tests/skills/test-aai-follow-ups.sh`,
`tests/skills/test-aai-factory-report.sh`, `docs/product/aai-decisions.md`), the
selector returns eight suites and drops 71: CORE `aai-check-state`,
`aai-docs-audit`, `aai-spec-lint`; SELECTED `aai-factory-report`,
`aai-follow-ups`, `aai-overview`, `aai-product-docs`, `aai-userguide-rollup`.
That is the expected shape, not the authority — re-run the selector against the
ACTUAL changed files and run everything it returns.

Commands:
- `node .aai/scripts/select-suites.mjs --files-from <actual changed files>`,
  then `bash .aai/scripts/aai-run-tests.sh bash tests/skills/<suite>.sh` for
  EVERY suite it returns, CORE rows included
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-follow-ups.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-factory-report.sh`
- `node .aai/scripts/follow-ups.mjs list` over this repository, exiting 0
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event`
- `node .aai/scripts/spec-lint.mjs`
- `git diff --numstat main -- tests/skills/test-aai-follow-ups.sh tests/skills/test-aai-factory-report.sh`
- `git diff --stat main -- .aai/scripts/generate-factory-report.mjs`

Every probe runs in a scratch temp directory against fixture ledgers. The
repository's own `docs/ai/decisions.jsonl` is READ by the live-ledger arms and
never written, and no restoring git command is run against a tracked file.

Evidence artifacts: the selector output naming the suites actually run, suite
stdout with per-TEST pass lines, the failing-first exit codes recorded in the
Implementation return record, the two git diff outputs, and the scope diff
listing.

PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status.

## Evidence contract

Per artifact record: ref_id, Spec-AC and TEST-xxx links, command or review
scope, exit code or review verdict, evidence path, commit SHA or diff range.

### Evidence by strategy

Strategy is `direct`: what this spec demands is the targeted regression arms
green with their exit codes, the failing-first exit codes named above recorded
in the return record, and the scoped diff. No stored per-test RED artifact and
no verification matrix beyond the commands listed under Verification.

## Errata (post-freeze, non-normative — recorded by the independent code review, review-20260818T094328Z-followups-cli-hardening.md)

These correct three predictions this frozen spec got wrong. None changes an
Acceptance Criterion or a Test Plan row; they are recorded here so a later
reader does not re-derive the same surprise.

- **Erratum 1 — Spec-AC-04's own verification command is unachievable.** The
  text specifies `grep -c 'fu-\[a-z0-9\]' .aai/scripts/follow-ups.mjs` returning
  `1`. That pattern is not anchored, so it matches every quoting of the id
  grammar as prose — the comment header, the `FOLLOW_UP_ID_RE` constant
  definition, the `USAGE` string and the `cmdAdd` error message — and returns
  `4` on any tree, before or after this change. The implementer substituted the
  leading-slash-anchored `grep -c '/\^fu-\[a-z0-9\]' .aai/scripts/follow-ups.mjs`
  (matching only the actual `RegExp` literal), documented the substitution
  inline in `test_014_malformed_id_named_and_counted`, and that command is what
  TEST-014 actually runs and what is authoritative. Independently reconfirmed
  during code review, with one narrow residual noted: a *second* regex literal
  for the same grammar written without a leading `^` anchor would escape this
  count — SEAM-3/D5's single-constant rule is the real guard against that, not
  the grep.
- **Erratum 2 — the Verification section's suite-count prediction is wrong.**
  The spec predicts the selector returns eight suites for the expected changed-file
  list. Run against the actual changed files (which additionally include
  `CHANGELOG.md` and `docs/INDEX.md`, both touched by this scope), the selector
  returns ten: the eight named plus `aai-release` (via `CHANGELOG.md`) and
  `aai-doc-numbering` (via `docs/INDEX.md`). The spec's own Verification section
  already disclaims the number as "the expected shape, not the authority" and
  instructs the next role to re-run the selector against the actual changed
  files and run everything it returns — which is what happened. Not a defect;
  recorded because the printed number is otherwise stale.
- **Erratum 3 — `tests/skills/test-aai-spec-lint.sh` was an undeclared file.**
  See the Implementation plan Components list above, now updated in place;
  recorded here for visibility since the file list was frozen without it.
  `STATE.yaml`'s `code_review.scope` has separately been extended to include
  it (orchestrator-owned, not this document).

## Residual risks

- R1 — A value that is EXACTLY a known flag token of its subcommand still reads
  as a missing value; `--what "--why"` must be written `--what=--why`. No bare
  argv grammar can distinguish those two intents, so the residual is a property
  of the problem, not of the fix. Documented in `--help` and asserted in
  TEST-011 as intended behaviour. Accepted.
- R2 — A downstream project that vendors this layer and passes `--ledger` a
  directory would newly exit 2. Only this repository can be enumerated from
  here, and it is clean (Spec-AC-02). Named as a behaviour change in CHANGELOG
  so a downstream reader meets it before their CI does. Accepted, not testable
  from here.
- R3 — Keeping a malformed-id item in the open count means a typo INFLATES the
  backlog rather than deflating it. That is the deliberate direction (D3): an
  overstated backlog is visible and gets fixed, an understated one is invisible.
  The marker and the note make the cause legible. Accepted.
- R4 — The understatement clause is prose, not arithmetic. Nothing can compute
  how many follow-ups an unparseable line might have carried, because the line
  cannot be parsed; the clause states the direction of the error and no more.
  Accepted, by construction.
- R5 — The `MALFORMED-ID` marker changes a `list` row's shape for the marked
  item only. Any future consumer that parses rows positionally rather than
  reading `--json` would need updating. No such consumer exists today (the only
  machine consumer, the report, uses the exported fold). Recorded as SEAM-6.
  Accepted.

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
Three clauses of the intake are deliberately NOT implemented as written and are
overruled above with reasons: its AC-003 (the CLI does not exit 0 on an absent
ledger — it exits 2 today and keeps doing so), its AC-004 (a malformed-id item
is NOT excluded from the open count), and its Affected Area (D4 needs no edit to
`generate-factory-report.mjs`).
