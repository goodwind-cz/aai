---
id: spec-intake-numbers-some-doc-types-immediately
type: spec
number: 140
status: done
ceremony_level: 1
links:
  requirement: docs/issues/ISSUE-0032-intake-numbers-some-doc-types-immediately.md
  rfc: null
  pr:
    - 269
  commits:
    - c5241d5
---

# Spec — intake must not number a document

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/ISSUE-0032-intake-numbers-some-doc-types-immediately.md
- Rule this scope enforces: .aai/INTAKE_COMMON.md `DURABLE DOC IDENTITY (SPEC-0015 / RFC-0007)`
- Originating specs for that rule: docs/specs/SPEC-0015-parallel-safe-doc-numbering.md, docs/rfc/RFC-0007-parallel-safe-doc-numbering.md
- Surfaces that change: .aai/INTAKE_COMMON.md, the eight .aai/INTAKE_*.prompt.md, .aai/scripts/docs-audit.mjs
- Shared library deliberately NOT touched: .aai/scripts/lib/docs-audit-core.mjs
- Suite that gates this scope: tests/skills/test-aai-intake.sh
- Merge-time twin that already exists (NOT touched): .aai/scripts/allocate-doc-number.mjs `--guard`
- Technology contract: docs/TECHNOLOGY.md

Ceremony justification: level 1. Prompt text plus one new read-only predicate in
an existing non-protected script and its existing library, gated by one existing
suite. No schema, no dependency, no state write, no rename of any existing
document, and no `protected_paths_l3` path — `allocate-doc-number.mjs` is read
by a test and edited by nothing. The intake fixed AC-001 to AC-004 and the cause
was measured before planning began, so Planning froze those four rather than
reopening the approach.

## Summary

Intake is supposed to produce an unnumbered `TYPE-DRAFT-<slug>.md`; the display
number is assigned at merge by `allocate-doc-number.mjs`. Measured on `main`,
four documents entered the corpus already numbered with no DRAFT predecessor:
`DEBT-0001`, `DEBT-0002`, `RES-0001`, `RESEARCH-0001`.

The cause is measured, not inferred. The DRAFT rule lives in exactly one file,
`.aai/INTAKE_COMMON.md`, and is applied by one step, `.aai/SKILL_INTAKE.prompt.md`
STEP 2.4. None of the eight `.aai/INTAKE_*.prompt.md` files contained the string
`DRAFT` or `DURABLE DOC IDENTITY` — zero hits in all eight, re-measured at the
start of this ride. Each said only "save it under `docs/<dir>/`" and "Output
summary + completed markdown + **suggested filename**". For the frequently
exercised types the router applied STEP 2.4; for the rare ones the per-type
prompt's own instruction won and nothing caught it.

The second defect has the same cause. Research documents carry two prefixes,
`RES` and `RESEARCH`, because nothing states the prefix per type, so whichever
the router improvised became precedent.

What already exists is the MERGE-point guard: `allocate-doc-number.mjs --guard`
fails when an unnumbered DRAFT reaches the merge point, and it demonstrably
works — an `ISSUE-DRAFT-...` committed to `main` on 2026-08-20 turned `main` red
on its own push run. What does not exist is anything that fails when a NUMBERED
document is created at intake. This scope adds exactly that, at the one moment
where "created at intake" is observable.

## Design decisions

- **D1 — the check must be scoped to the artifact intake just saved, because
  nothing about a numbered file on disk says when it was numbered.** Two
  alternatives were measured and rejected. (a) A repo-state predicate
  "status: draft implies unnumbered" is FALSE here: `ISSUE-0032` is numbered and
  `status: draft` right now, legitimately — it was numbered by the allocator at
  the merge of its own intake PR and its status flips only at the close of the
  ride that fixes it. (b) A git-history predicate "the introducing commit named
  it DRAFT" is unusable on this repository: PRs are squash-merged, so on `main`
  the DRAFT name never exists and `git log --diff-filter=A -M` reports the
  numbered basename as an ADD for 305 of the 305 docs added since the convention
  landed at `c29457f`, including the ones that did go through a DRAFT stage. The
  only place the ACT of creation is observable is the intake step itself, so the
  gate is a `--intake-file <path>` predicate over the one file intake just wrote.

- **D2 — research is `RES`, and `RESEARCH-0001` is not renamed.** The choice is
  made on evidence, not taste. `.aai/templates/RESEARCH_TEMPLATE.md` frontmatter
  already reads `id: RES-XXXX`, which is the only statement of a research prefix
  anywhere in the repository before this scope. `RES-0001` is also the form the
  corpus actually cites: it is referenced by name from nine `.aai/` prompts and
  templates, four test suites and thirteen CHANGELOG entries, against three
  citations for `RESEARCH-0001`. Neither consumer forces the choice, which is
  why it had to be made deliberately: the index generator derives the display
  prefix from the filename's leading token
  (`/^([A-Z]+(?:-[A-Z]+)*)-(?:DRAFT|\d{1,5})(?=[-.])/`) and accepts either, and
  the allocator reads the prefix from the basename when numbering, so either
  prefix numbers correctly. `RESEARCH-0001` keeps its name under AC-004.

- **D3 — the type-to-prefix table lives in the prompt, once, and the gate reads
  THAT file.** AC-002 asks for one place. The router reads prompts, so the table
  has to be prose the router will actually see; a copy in code would be a second
  place and would drift. So `.aai/INTAKE_COMMON.md` carries the eight-row table
  and `docs-audit.mjs --intake-file` parses it at runtime
  (`parseIntakeTypeTable`). The eight per-type prompts gain a rule that names the
  DRAFT shape and POINTS at that table; not one of them restates a prefix. If
  the table is missing or empty the gate exits 2 with a named error rather than
  passing an unchecked artifact — degrade loudly, never silently permit.

  The two halves of the mapping are single-sourced DIFFERENTLY, and the block
  now says which is which (corrected at remediation, validation round 1 F4).
  The PREFIX is stated in exactly one place — the table — and no prompt may
  restate one. The DIRECTORY is stated in nine: the table, plus the opening
  line of each of the eight per-type prompts ("save it under `docs/<dir>/`").
  That duplication is kept deliberately, because a prompt a role reads in
  isolation has to say where to write; what is removed is the block's false
  claim to be "the ONLY statement of `<TYPE>` and its directory". It now claims
  what it is: the only statement of the prefix and the AUTHORITY for the
  directory. A claim this repository asserts is a claim it pins, so Spec-AC-02
  holds all eight opening lines to their table row rather than trusting nine
  statements to keep agreeing.

  The table holds the eight INTAKE types and nothing else, so `--intake-file`
  refuses a spec (`unknown-type: spec`) — including this document. That is the
  intended boundary, not a gap: the flag is invoked by the intake POST-SAVE
  CHECK on the artifact intake just saved, and Planning's `SPEC-DRAFT-<slug>.md`
  is produced by a different role with its own gates (`spec-lint`,
  `spec-freeze`). Adding a ninth row for `spec` would put a Planning path under
  an intake rule; the two `docs-audit --gate` predicates already own that side.

- **D8 — an absent `number:` key is a finding, not a pass** (added at
  remediation, validation round 1 F2). `fm.number != null` is false for
  `undefined`, so an artifact that simply omitted the key cleared the gate while
  an omitted `status` was caught — an asymmetry with no reason behind it. The
  rule is `number: null`, present and explicit, because the allocator stamps the
  display number INTO that key at merge. The gate now says so. This only ever
  failed open in the UNNUMBERED direction, so it hardens the predicate rather
  than closing a numbered-at-intake escape; the structural argument that no
  numbered artifact can pass is unchanged.

  Measured consequence, named rather than discovered later: seven of the eight
  intake TEMPLATES carry no `number:` key (only `RFC_TEMPLATE.md` and
  `SPEC_TEMPLATE.md` do), so a verbatim template copy now fails the POST-SAVE
  check with `number-absent`. That is the same shape as `status`, which the
  templates do carry, and the remedy is the one the DURABLE DOC IDENTITY block
  already instructs — write `number: null` — with the gate naming it exactly, so
  intake converges in one edit. Adding the key to the seven templates is filed
  as `fu-intake-templates-lack-number-key` (P3), not done here: it is seven more
  files than these three fixes.

- **D7 — the predicate lives in the docs-audit CLI, not in
  `lib/docs-audit-core.mjs`.** The first implementation put the three functions
  in the shared library and was moved out on measured evidence, not taste. That
  library is imported by two dozen suites; `select-suites.mjs` classifies it as
  a shared lib and escalates ANY edit to `FULL_RUN` (81 suites), and
  `tests/skills/test-aai-ceremony-levels.sh` TEST-016 pins it byte-untouched
  with a bare `git diff --exit-code`, which turned this scope red on the first
  full run. Three functions used by one flag do not justify either cost, and
  they are reachable through the CLI, which is how every sibling predicate
  (`--gate-file`, `--lint-body-file`) is already tested. The stale TEST-016 pin
  is left exactly as it is — it passes because the library is byte-untouched —
  and its false-positive-on-every-later-scope shape is filed, not fixed here.

- **D4 — the allocator is read, never written.** `allocate-doc-number.mjs` is
  `protected_paths_l3`. Its `TYPE_MAP` has no `research` and no `hotfix` row, so
  `--type research` is a usage error today. That is a real gap, and it is FILED
  rather than fixed here, because closing it means editing an L3 surface and
  turning this ride into ceremony 3. Nothing on the intake path calls
  `resolveType`: intake names its own file from the table, and the allocator
  numbers it from the basename. Spec-AC-02 asserts the table agrees with
  `TYPE_MAP` for every type `TYPE_MAP` does know, by importing it read-only.

- **D5 — the eight-type demonstration is mechanical, and this spec says so
  rather than implying eight live intakes were run.** An intake is an
  LLM conversation; running eight of them is not a repeatable test and cannot
  gate CI. Spec-AC-01 therefore demonstrates the rule over all eight types in
  two mechanical halves: every one of the eight prompts is asserted to carry the
  rule, and for every one of the eight table rows the guard is run against a
  constructed DRAFT artifact (must pass) and its numbered twin (must fail).

- **D6 — no existing document is renamed, and that is asserted, not intended.**
  Spec-AC-04 pins the four historical numbered documents at their exact paths.

- **D9 — the independent table reader is CROSS-CHECKED against the shipped one**
  (added at code-review remediation, review-20260821T074214Z NB-4). TEST-013
  reads the table with its own single-space `awk` rather than with
  `parseIntakeTypeTable`, deliberately: a tool that reads its own table proves
  nothing. Measured consequence of that independence left half-built — TEST-013
  and TEST-014 take their ENTIRE universe of rows from that one `awk`, while the
  shipped regex allows `\s*`, so a row written with double spaces is live in the
  gate and invisible to every arm. It reddened the suite only incidentally, via
  TEST-014's table-removal fixture whose `grep -v` shares the spacing
  assumption, and with a misleading message. Independence needs a cross-check,
  not just a second reader: TEST-013 now also parses the table with the shipped
  parser (exported for this one purpose; nothing in production imports it) and
  requires the row COUNT and the row SET to agree. The alternative — aligning
  the two spellings — was rejected because it removes the second reading
  entirely. The remaining strictness asymmetry is filed as
  `fu-intake-table-parser-asymmetry`.

- **D10 — an absent or empty flag VALUE is a usage error, and the check is
  written once for every value-taking flag** (added at bot-review remediation,
  PR #269; raised independently by Copilot and Codex, both P2). `main()`
  dispatches on truthiness, so `--intake-file "$FILE"` with `FILE` unset left
  `args.intakeFile` falsy, skipped the predicate and ran a FULL REPOSITORY
  AUDIT: exit 0 on a clean repo, plus a `docs_audit` EVENTS append unless
  `--no-event` happened to be passed too. A gate that never opened the artifact
  answered green — the one property this whole scope exists to remove. Both bots
  reported it on `--intake-file`; the identical three lines produced it for
  `--gate`, `--gate-file`, `--lint-body-file` and `--path`, and the filed item
  `fu-file-flags-empty-value-full-audit` already recorded the remedy as "fix
  once for all three flags (and --path)". So the guard is ONE helper
  (`requireValue`) applied at all five call sites rather than a patch on the
  flag that happened to be reviewed: fixing the reviewed one and leaving four
  known twins is how the same finding gets filed a second time. Exit code 2,
  the existing "could not evaluate" code of every file predicate; the message
  goes to stderr so it cannot be mistaken for digest output. No call site in the
  repository passes an empty value (every one was enumerated), so no caller
  changes behaviour.

- **D11 — the directory/prefix finding is judged on the directory and the
  prefix, and on nothing else** (added at bot-review remediation, PR #269;
  Copilot). `Boolean(draft)` sat inside the `matches.some(...)` predicate, so
  ANY non-DRAFT basename collected `wrong-prefix-or-dir` — including
  `DEBT-0001-<slug>.md` in `docs/issues/` with type `techdebt`, whose directory
  and prefix are both exactly right. The verdict was correct and the diagnosis
  was false, which is worse than it sounds: a wrong reason sends the next reader
  to the wrong fix, and the DRAFT shape already has its own finding
  (`numbered-at-intake`) one line up. The predicate now compares the basename's
  own prefix token — the DRAFT prefix, else the numbered prefix — against the
  table row, and the two conditions each mean what they say.

- **D12 — the gate enforces the slug constraint the document states, rather than
  the document claiming one no tool held** (added at bot-review remediation,
  PR #269; Codex, P2). `.aai/INTAKE_COMMON.md` DURABLE DOC IDENTITY says the
  slug is "kebab-case of the topic (lowercase, ASCII, at most 48 chars)"; the
  basename regex accepted any nonempty run of `[a-z0-9-]`, so
  `ISSUE-DRAFT--.md`, `ISSUE-DRAFT-foo-.md` and a 49-character slug all passed.
  The gate was changed rather than the document, because the constraint is the
  one the allocator's `deriveSlug` already produces (single hyphens between
  alphanumeric runs, truncated at 48) — the document was right and the gate was
  behind it. Two named findings, `slug-not-kebab` and `slug-too-long`, so the
  reader is told which half failed. The DRAFT basename match was widened to
  accept any slug text precisely so a malformed slug is diagnosed as a malformed
  slug instead of `not-a-draft-basename`, which would be the D11 defect again.
  One known gap is named rather than left to be found: `draftFilename(type,
  slug, suffix)` can append a 4-character collision suffix, which would put a
  maximal slug at 53 characters. Nothing on the intake path calls it — intake
  names its own file from the table, and the only callers are in
  `tests/skills/test-aai-doc-numbering.sh` — so the bound is enforced on the
  whole slug token as written, and the code comment says which line has to learn
  about the suffix if that path is ever wired up.

## Implementation strategy
- Strategy: direct
- Rationale: recorded in STATE as `direct` before this ride began. There is no
  algorithm to discover — the rule already exists in prose and the work is to
  state it where it is read and to make one predicate refuse. What can go wrong
  is entirely in the wiring: a prompt that states the rule in words the gate
  cannot check, a table the parser silently reads as empty, a predicate that
  passes an artifact it never actually looked at. Direct does not waive the
  failing-first observation: see the discipline paragraph under the Test Plan.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: prompt text, one predicate and one suite; every fixture is
  a scratch directory outside the repository, and the only repository files the
  new arms read are read-only.
- User decision: undecided
- Base ref: main
- Inline review scope: .aai/INTAKE_COMMON.md, .aai/INTAKE_CHANGE.prompt.md,
  .aai/INTAKE_HOTFIX.prompt.md, .aai/INTAKE_ISSUE.prompt.md,
  .aai/INTAKE_PRD.prompt.md, .aai/INTAKE_RELEASE.prompt.md,
  .aai/INTAKE_RESEARCH.prompt.md, .aai/INTAKE_RFC.prompt.md,
  .aai/INTAKE_TECHDEBT.prompt.md, .aai/scripts/docs-audit.mjs,
  tests/skills/test-aai-intake.sh,
  tests/skills/lib/prompt-diet-ledger.sh, tests/skills/test-aai-prompt-diet.sh,
  tests/skills/test-aai-spec-lint.sh,
  docs/specs/SPEC-0140-spec-intake-numbers-some-doc-types-immediately.md

Code review required: true (production script, prompt corpus and test-suite
change); scope = the explicit path list above as a diff against main.

## Acceptance Criteria Mapping

- Maps to: ISSUE AC-001
- Spec-AC-01: every one of the eight intake types produces an unnumbered
  `<PREFIX>-DRAFT-<slug>.md` with `number: null` and `status: draft`. Two
  mechanical halves, because an intake is an LLM conversation and cannot gate CI
  (D5): each of the eight `.aai/INTAKE_*.prompt.md` files carries the literal
  DRAFT rule and no longer asks for a free "suggested filename", with the
  pointer at the single-source table required INSIDE that rule rather than
  anywhere in the file (remediation, F3: a file-wide grep was already satisfied
  at HEAD by the pre-existing SHARED POLICY line); and for each of
  the eight rows of the single-source table, a constructed DRAFT artifact passes
  `docs-audit.mjs --intake-file` while its numbered twin fails.
  - Verification: `bash tests/skills/test-aai-intake.sh`, arms
    `test_012_every_intake_prompt_carries_the_draft_rule` and
    `test_014_numbered_intake_artifact_fails_the_guard`. Evidence: the arms'
    stdout, naming all eight prompt files and all eight types with the exit code
    observed for each of the sixteen artifacts.

- Maps to: ISSUE AC-002
- Spec-AC-02: the prefix for each type is stated in exactly one place and agrees
  with the tools. `.aai/INTAKE_COMMON.md` carries eight rows, one prefix per
  intake type; no `.aai/INTAKE_*.prompt.md` states a prefix of its own; every
  row whose intake type exists in `allocate-doc-number.mjs` `TYPE_MAP` matches
  that entry's directory and prefix exactly, checked by importing `TYPE_MAP`
  read-only; the research row reads `RES`, the recorded D2 decision; and every
  per-type prompt's own opening directory line names exactly its table row's
  directory and no other, which is what makes INTAKE_COMMON's narrowed claim to
  be the AUTHORITY for the directory true rather than asserted (D3, F4). The
  arm's own independent reading of the table is cross-checked against the
  shipped parser's, so a row the gate honours cannot be outside the universe the
  arm counts (D9).
  - Verification: `bash tests/skills/test-aai-intake.sh`, arm
    `test_013_one_prefix_per_type_matches_the_allocator`. Evidence: the arm's
    stdout, printing each of the eight rows and, per row, either the matching
    `TYPE_MAP` entry or the explicit note that `TYPE_MAP` has no entry for it,
    plus the two-readings-agree line and the in-arm bite line showing the
    double-spaced ninth row read as 8 by the `awk` and 9 by the shipped parser.

- Maps to: ISSUE AC-003
- Spec-AC-03: a test fails when an intake artifact is created already numbered.
  `docs-audit.mjs --intake-file <f>` exits 1 and prints a `numbered-at-intake`
  finding for an artifact created as `DEBT-0003-<slug>.md`, exits 0 for the
  byte-equivalent `DEBT-DRAFT-<slug>.md`, exits 1 for a draft whose frontmatter
  omits the `number:` key entirely (D8), and exits 2 when the artifact or the
  single-source table is unreadable rather than passing something it never read.
  The intake flow reaches the check: `.aai/INTAKE_COMMON.md` POST-SAVE CHECK
  invokes `--intake-file` on the saved artifact. The gate must also be honest
  about its own limits: it exits 2 rather than auditing the whole repository
  when a value-taking flag is given no value (D10), it reports
  `wrong-prefix-or-dir` only for a genuinely wrong prefix or directory (D11),
  and it refuses a slug outside the kebab-case, at-most-48-character shape
  `.aai/INTAKE_COMMON.md` states (D12).
  - Verification: `bash tests/skills/test-aai-intake.sh`, arms
    `test_014_numbered_intake_artifact_fails_the_guard`,
    `test_016_value_flags_refuse_an_empty_value`,
    `test_017_wrong_prefix_finding_means_wrong_prefix` and
    `test_018_slug_shape_matches_the_documented_constraint`. Evidence: the arms'
    stdout with the exit codes and the finding keys, plus the mutation record
    proving each goes red when the predicate is disabled — for TEST-016 to
    TEST-018 the mutation runs IN-ARM against a scratch copy of the CLI, so the
    proof is re-run on every suite execution and no tracked file is ever edited.

- Maps to: ISSUE AC-004
- Spec-AC-04: no existing numbered document is renamed or renumbered. The four
  documents named in the intake evidence still exist at their exact original
  paths, and the working tree contains no rename of any file under `docs/`.
  - Verification: `bash tests/skills/test-aai-intake.sh`, arm
    `test_015_existing_numbered_docs_are_not_renamed`. Evidence: the arm's
    stdout listing the four paths it stat-ed, plus
    `git status --porcelain=v1 -uno` for the ride showing no `R` entry.

## Constitution deviations

None. Checked v1 articles 1 to 7.

Article 1 (evidence before claims): every Spec-AC names one executable command
and one read observable, and each new assertion is mutation-proved with an
unmutated green control. Article 2 (simplicity): no new file, no new dependency,
no configuration knob; one parser, one predicate, one flag. Article 3
(portability): Node stdlib only, bash 3.2 in the suite. Article 4 (degrade and
report): a missing or empty type table exits 2 with a named reason instead of
passing the artifact. Article 5 (additive first): the new flag is additive, no
existing docs-audit mode changes behaviour, and no document is renamed. Article 6
(single-writer state): no STATE write. Article 7 (operator-only merge): no merge
is performed.

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Status |
|----------|------------|------|----------------------|-------------|--------|
| TEST-012 | Spec-AC-01 | int  | tests/skills/test-aai-intake.sh | all eight .aai/INTAKE_*.prompt.md files are read from the repository and each must carry the literal DRAFT-shape rule (the `-DRAFT-` token, `number: null`, `status: draft`) and, INSIDE that same RULES block, a pointer to the .aai/INTAKE_COMMON.md table (anchored so the pre-existing SHARED POLICY line cannot satisfy it), and must no longer ask for a "suggested filename"; the arm also pins that exactly eight such files exist, so a ninth intake type cannot be added without the rule | green |
| TEST-013 | Spec-AC-02 | int  | tests/skills/test-aai-intake.sh | the single-source table is parsed from .aai/INTAKE_COMMON.md and must have exactly eight rows covering the eight intake types with one prefix each; `TYPE_MAP` is imported read-only from .aai/scripts/allocate-doc-number.mjs and every row present there must match on both directory and prefix; the research row must read RES; no .aai/INTAKE_*.prompt.md may contain a bare display prefix of its own; and the set of docs/<dir> paths each per-type prompt names must be exactly its own table row's directory; and the same table is read a SECOND time with the shipped `parseIntakeTypeTable` (imported from .aai/scripts/docs-audit.mjs), with the row count and the row set required to equal the awk's, proved to bite in-arm on a synthetic copy carrying a double-spaced ninth row that the awk reads as 8 and the shipped parser as 9 (D9) | green |
| TEST-014 | Spec-AC-03 | int  | tests/skills/test-aai-intake.sh | in a scratch fixture outside the repository, for each of the eight table rows a numbered artifact and its DRAFT twin are created with identical frontmatter apart from `number`; `docs-audit.mjs --intake-file` must exit 1 with a `numbered-at-intake` finding on all eight numbered ones and exit 0 on all eight drafts; plus a wrong-prefix case (RESEARCH-DRAFT for type research) at exit 1, a DRAFT artifact whose frontmatter omits the number key at exit 1 with a number-absent finding, an unreadable artifact at exit 2, and a fixture whose INTAKE_COMMON.md has had the table removed at exit 2; and .aai/INTAKE_COMMON.md must invoke `--intake-file` in its POST-SAVE CHECK | green |
| TEST-015 | Spec-AC-04 | int  | tests/skills/test-aai-intake.sh | the four documents named in the intake evidence (DEBT-0001, DEBT-0002, RES-0001, RESEARCH-0001) must still exist at their exact original repository paths, and `git status --porcelain=v1 -uno` in the repository must report no rename entry under docs/ | green |
| TEST-016 | Spec-AC-03 | int  | tests/skills/test-aai-intake.sh | each of the five value-taking flags (--intake-file, --gate-file, --lint-body-file, --gate, --path) must exit 2 with a USAGE ERROR both when its value is the empty string and when the value is omitted entirely, while a valid --intake-file value still exits 0 and a plain --quick --no-event audit still exits 0; proved to bite in-arm against a scratch COPY of the CLI whose requireValue call at the --intake-file site has been reverted, on which the empty value must again produce a full audit at exit 0 (D10) | green |
| TEST-017 | Spec-AC-03 | int  | tests/skills/test-aai-intake.sh | a correctly located numbered artifact (DEBT-0001-demo-slug.md in docs/issues with type techdebt) must exit 1 reporting numbered-at-intake and must NOT report wrong-prefix-or-dir, while a wrong PREFIX in the right directory (RESEARCH-DRAFT for type research) and a right prefix in the wrong DIRECTORY (a techdebt draft under docs/rfc) must both still report it; proved to bite in-arm against a scratch COPY with Boolean(draft) put back inside the predicate, on which the false finding reappears (D11) | green |
| TEST-018 | Spec-AC-03 | int  | tests/skills/test-aai-intake.sh | ISSUE-DRAFT--.md and ISSUE-DRAFT-foo-.md must exit 1 with slug-not-kebab and a 49-character slug must exit 1 with slug-too-long, while a slug of exactly 48 characters must exit 0 so the bound is pinned at the boundary rather than at "long"; proved to bite in-arm against a scratch COPY whose slug is read out of the two checks, on which all three malformed shapes are accepted at exit 0 (D12) | green |

Failing-first discipline (strategy `direct`, so exit codes are the record).
TEST-012, TEST-013 and TEST-014 all fail NATURALLY on the pre-change tree: the
eight prompts carry no DRAFT rule, `.aai/INTAKE_COMMON.md` carries no table, and
`--intake-file` does not exist. TEST-015 is GREEN pre-change and is not claimed
otherwise — it is a boundary pin against a change this ride could have made and
deliberately did not, so it is proved by MUTATION only. The load-bearing
evidence is MUTATION with an unmutated green control, recorded in the
Implementation return record: for each new assertion, one named single-point
mutation of the shipped code or prompt that turns exactly the expected arm red
while the control run is green. An assertion verified only by reading is not
accepted.

## Verification

- `bash tests/skills/test-aai-intake.sh` exits 0 with every arm passing
- every suite `node .aai/scripts/select-suites.mjs --files-from <changed files>`
  returns
- `node .aai/scripts/allocate-doc-number.mjs --guard --base-ref origin/main` clean
- `node .aai/scripts/spec-lint.mjs` clean,
  `node .aai/scripts/check-test-registration.mjs` clean,
  `node .aai/scripts/docs-audit.mjs --check --strict --no-event`
- the eight-type demonstration described in D5, run mechanically
- NUL byte counts for every edited file; `git rev-parse HEAD` and
  `git status --porcelain=v1 -uno` line count at the start and end of the ride

## Evidence contract

- The suite's stdout, with the per-type exit codes printed by TEST-014 rather
  than asserted as constants.
- The pre-change run of TEST-012, TEST-013 and TEST-014 showing them red.
- For every new assertion: the mutation applied, the arm that went red, and the
  unmutated control run that stayed green.
- The prompt-diet ledger true-up: the measured byte delta of the corpus and the
  TEST-012 pin move it produces.
- The `git rev-parse HEAD` and `git status --porcelain=v1 -uno` pair for the
  whole ride.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN any of the eight intake types produces an artifact THEN it is an unnumbered PREFIX-DRAFT-slug.md with number null and status draft, and the rule is stated in the per-type prompt the router reads | done | TEST-012 and TEST-014 green; all eight prompts carry the rule and all eight types pass as DRAFT and fail as numbered | — | demonstrated mechanically over all eight types, not by running eight live intakes — see D5, which says so rather than implying otherwise | 
| Spec-AC-02 | WHEN a prefix is needed for a type THEN exactly one place states it and it agrees with the allocator TYPE_MAP for every type TYPE_MAP knows, with research resolved to RES | done | TEST-013 green; eight rows, no prefix restated in any per-type prompt, every TYPE_MAP-known row matching on directory and prefix, and all eight per-type prompt directory lines matching their row | — | the prefix is single-sourced, the directory is not and deliberately so; the table is the prefix's only statement and the directory's authority, and the arm pins the eight prompt lines to it (D3). TYPE_MAP has no research and no hotfix row; that gap is filed, not fixed, because the allocator is protected_paths_l3 (D4) | 
| Spec-AC-03 | WHEN an intake artifact is created already numbered THEN a check fails, and the intake flow runs that check on the artifact it just saved | done | TEST-014, TEST-016, TEST-017 and TEST-018 green; exit 1 with a numbered-at-intake finding, exit 0 on the DRAFT twin, exit 1 on a draft with no number key at all, exit 2 on an unreadable artifact or a missing table, exit 2 on an absent or empty flag value, and exit 1 on a slug outside the documented shape; POST-SAVE CHECK invokes it | — | an absent number key is a finding too (D8), which hardens the unnumbered direction rather than closing an escape. this is the intake-time twin of the allocator merge-time guard, which already exists and works; scoping to the just-saved file is what makes creation observable at all (D1). Three bot-review defects in the shipped gate are fixed here rather than filed: it failed OPEN into a full audit on an empty flag value, for all five value-taking flags (D10, TEST-016); it reported wrong-prefix-or-dir on files whose prefix and directory were both right (D11, TEST-017); and it accepted slugs the document forbids (D12, TEST-018). Each new arm carries an in-arm bite proof against a mutated scratch copy plus an unmutated control | 
| Spec-AC-04 | WHEN this scope ships THEN no existing numbered document has been renamed or renumbered | done | TEST-015 green; the four documents named in the intake evidence still resolve at their original paths and the working tree shows no rename under docs/ | — | a boundary, not a nicety: display ids are durable primary keys and history references them. The arm is green pre-change by construction and is proved by mutation only | 

Status values: planned | implementing | done | deferred | blocked | rejected

Every row reads `implementing` until the close ceremony. This is measured
rather than preferred: `docs-audit`'s false-open heuristic fails CLOSED on a
fully terminal AC Status table whose delivery is un-timestampable — no delivery
commit, no `ac_evidence` event — and reports `probable-false-open`, which
removes the literal `CLEAN` token from the audit output and turns
`tests/skills/test-aai-doc-numbering.sh` TEST-013 red. The same reasoning is
recorded in SPEC-0137, SPEC-0138 and SPEC-0139 and tracked as
`fu-acgate-vs-falseopen-catch22`. The rows flip at the close ceremony, and the
flip must PRECEDE `close-work-item.mjs` rather than follow it
(`fu-ac-flip-must-precede-close`).

## Implementation plan

Components:

- `.aai/INTAKE_COMMON.md` (EDIT) — the `DURABLE DOC IDENTITY` block gains the
  eight-row type table (intake type, frontmatter type, directory, prefix), the
  sentence naming it the only statement of the PREFIX and the authority for the
  directory (narrowed at remediation from a false "only statement of both"
  claim, D3), and the D2 research decision; the `POST-SAVE CHECK` block gains
  the `--intake-file` invocation.
- the eight `.aai/INTAKE_*.prompt.md` (EDIT) — one RULES bullet each naming the
  DRAFT shape and pointing at that table, and `+ suggested filename` becomes
  `+ the DRAFT filename`. No prompt states a prefix.
- `.aai/scripts/docs-audit.mjs` (EDIT) — `parseIntakeTypeTable`,
  `intakeShapeFindings` and `intakeShapeFile` (mirroring the existing
  `gateFile` / `lintFile` shape but kept inside the CLI, D7), the
  `--intake-file <f>` flag and its `runIntakeFile` emitter, exit 1 findings /
  0 clean / 2 unreadable, plus the header usage block. The two helpers it needs
  (`parseFrontmatter`, `normalizeNewlines`) are IMPORTED from
  `lib/docs-model.mjs`, which is read and not modified. At code-review
  remediation `parseIntakeTypeTable` gained the `export` keyword (and the
  comment saying why) so TEST-013 can cross-check its independent reading
  against the shipped one (D9); nothing in production imports it and `main()`
  remains the only caller. At bot-review remediation the CLI gained the
  `requireValue` argument guard on all five value-taking flags (D10), the
  directory/prefix predicate started comparing the basename's own prefix token
  instead of `Boolean(draft)` (D11), and the DRAFT basename match was widened
  with two new slug findings behind it, `slug-not-kebab` and `slug-too-long`
  (D12). The header usage block records both the slug shape and the
  empty-value contract.
- `tests/skills/test-aai-intake.sh` (EDIT) — four new arms TEST-012 to TEST-015
  and their helpers, each wired into `main()`; at code-review remediation
  TEST-013 gained the two-readings-agree cross-check and its bite proof, plus
  the `intake_table_lines_tool` helper (D9); at bot-review remediation three
  more arms TEST-016 to TEST-018 (D10 to D12) and the helpers they share —
  `intake_run_script`, `intake_scratch`, `intake_fixture_root` and
  `intake_mutant_script`, the last of which copies the CLI and its `lib/` into a
  scratch tree and applies one `sed` mutation to the COPY, so every bite proof
  runs on each execution without any tracked file being edited.
- `tests/skills/lib/prompt-diet-ledger.sh` (EDIT) — the ledger true-up entry;
  at code-review remediation the two REMAINING unescaped backtick pairs
  (the `wc -c` substitutions in the `issues-skill` and `universal-routines`
  entries) were escaped, and the new entry's absolute "no backtick in any
  ledger entry" claim was corrected to the invariant that is actually true and
  now enforced: no UNESCAPED backtick.
- `tests/skills/test-aai-prompt-diet.sh` (EDIT) — the TEST-012 pin bump; at
  code-review remediation a new arm `test_021_ledger_has_no_unescaped_backtick`
  sweeps the WHOLE ledger library for the class (rather than the instance a
  diff happened to contain), asserts sourcing from a foreign cwd is silent, and
  carries both a bite fixture and an escaped-backtick negative control so the
  invariant is enforced by a test instead of asserted in prose.

Companion obligations (closed list). PROMPT CORPUS BYTES MOVE: YES — the eight
`.aai/*.prompt.md` files and `.aai/INTAKE_COMMON.md` (which
`tests/skills/test-aai-prompt-diet.sh` TEST-010 counts in its `extra` term) both
grow, so a prompt-diet ledger true-up is owed: one new `JUSTIFIED_ADDITIONS`
entry at the measured delta in `tests/skills/lib/prompt-diet-ledger.sh` and the
matching TEST-012 pin bump in `tests/skills/test-aai-prompt-diet.sh`. NEW
`.aai/**` FILE: NO — every change is inline in an existing file, so no
`.aai/system/PROFILES.yaml` classification is owed. Two further mechanical
obligations apply: every new `test_*` function must be wired into `main()`
(`.aai/scripts/check-test-registration.mjs`), and the `.aai/` branch-diff
allowlist in `tests/skills/test-aai-spec-lint.sh` TEST-011(clarify) needs a case
group for this scope's ten `.aai/` paths. No new suite, so
`tests/skills/suite-map.yaml` needs no new row — `aai-intake` already globs the
intake prompts and `aai-docs-audit` is core.
