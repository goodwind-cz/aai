---
id: spec-deslop-corpus-honesty
type: spec
number: 136
status: implementing
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-0150-deslop-corpus-honesty.md
  rfc: null
  pr: []
  commits: []
---

# Spec — the class-4 corpus tells the truth about what was requested

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0150-deslop-corpus-honesty.md
- Prior spec (the engine this change corrects, frozen and done): docs/specs/SPEC-0132-spec-deslop-scope-and-unrequested-engine.md
- Prior requirement (the document that currently hosts the adjudication table): docs/issues/CHANGE-0145-deslop-scope-and-unrequested-engine.md
- Registry items closed: `fu-deslop-all-corpus-specs-only` (P2), `fu-deslop-allcorpus-unreadable-silent` (P3), `fu-deslop-corpus-header-other-bucket` (P3), `fu-deslop-adjudication-self-suppression` (P2)
- Product doc updated by this scope: docs/product/aai-deslop.md
- Suite that owns the engine arms: tests/skills/test-aai-deslop.sh
- Suite that owns the prompt byte budget: tests/skills/test-aai-prompt-diet.sh
- Suite that pins the deslop prompt shape: tests/skills/test-aai-advisory-skills.sh
- Technology contract: docs/TECHNOLOGY.md

## Summary

`resolveAllCorpus` in `.aai/scripts/deslop-unrequested.mjs` decides which
documents count as "a requirement asked for this". Three separately-filed
registry items live in that one function. All three were reproduced against the
current tree on 2026-08-18, read-only, before this spec was written.

The scope is not "make the corpus wider". It is "make the corpus mean what the
header says it means", and the hard part is one coupling the factory already
paid for once.

Five facts measured during planning shape every decision below. Three of them
contradict something the intake or the follow-up registry asserts.

1. **The defect is real and `docs/issues/**` is the load-bearing half.**
   `--all` today reports 65 candidates over a 135-document corpus.
   `--worktree-guard` and `--worktree-baseline` (`.aai/scripts/check-role-output.mjs:136`)
   were requested in `docs/issues/CHANGE-0125-adopt-v2-planning.md:56`;
   `--pr-config` (`.aai/scripts/pr-platform.mjs:78`) was requested in
   `docs/issues/CHANGE-0096-github-no-bots-hardening.md:38`. Measured: widening
   to `docs/specs` plus `docs/rfc` only leaves all three still reported (corpus
   148, candidates 64). Only admitting `docs/issues/**` closes the defect.
2. **Widening without a second move silently reverts a fix that is three days
   old.** Measured on the live tree: widening to the three directories drops
   candidates 65 to 49, and 7 of those 16 vanished rows disappear because
   `docs/issues/CHANGE-0145-...md` names their symbols in its own Adjudication
   Summary — the table the 2026-08-15 remediation deliberately moved there to
   get those rows back into the output. Widening with the table relocated gives
   56 candidates, and the 9 rows that go are the 3 named above plus 6 more that
   a change or RFC document genuinely names. The 7-row difference is the entire
   substance of `fu-deslop-adjudication-self-suppression`.
3. **`fu-deslop-corpus-header-other-bucket` is NOT latent, and its own filed
   text says it is.** The registry entry reads "Currently latent on the real
   corpus (0 parse failures, all statuses covered today)". Measured: the
   resolver walks 137 files under `docs/specs`, includes 135, and prints five
   zero-valued excluded buckets. The other 2 — `docs/specs/RES-0001-...md` and
   `docs/specs/RESEARCH-0001-spec-kit-comparative.md`, both `type: research` —
   are dropped by the `fm.type !== 'spec'` test and appear in no line of the
   output. The filed finding only considered an out-of-vocabulary status and an
   unparseable frontmatter; the live residue comes from the type filter it did
   not mention. The check is closable today, on real data.
4. **`docs/product/**` would change nothing, and is excluded on purpose.** All
   26 product documents carry `status: current`, which is outside the included
   status set, so admitting the directory moves no number at all (measured:
   corpus 330 either way). Excluding it is therefore free, and it is also right:
   a product document describes what was built, not what was asked for.
5. **There is no requirement-typed document anywhere in `docs/` outside the
   three directories this spec admits, and none of the three has a
   subdirectory.** Enumerated across every `.md` under `docs/`: zero documents
   with `type` in spec, change, issue, techdebt or rfc live outside
   `docs/specs`, `docs/issues` and `docs/rfc`. The directory allowlist is exact
   today, not a guess.

Every count in this section is a planning measurement of the PRE-change tree,
or a probe against a patched scratch copy of the engine. None of them is an
acceptance criterion. Spec-AC-07 requires the shipped documents to carry
numbers measured on the POST-change tree.

## Design decisions

- **D1 — the corpus is three directories, a closed requirement-type set and
  the existing status set.** `resolveAllCorpus` walks `docs/specs`,
  `docs/issues` and `docs/rfc`, and a document joins the corpus when its
  frontmatter `type` is one of `spec`, `change`, `issue`, `techdebt`, `rfc` AND
  its `status` is one of `accepted`, `implementing`, `done`. The status set is
  unchanged from D2 of SPEC-0132 and keeps its original reasoning: those three
  statuses are the ones that mean the requirement was agreed.

  Both filters are needed. The directory allowlist keeps template trees,
  `docs/archive`, `docs/project-sessions` and `docs/analysis` out even if a
  requirement-shaped frontmatter appears there later. The type filter keeps the
  two `type: research` documents that live inside `docs/specs` out — and those
  two are exactly the residue D4 makes visible.

  NOT admitted, each for a stated reason rather than by omission:
  `docs/product/**` (fact 4 above: a description of delivered behavior, not a
  request, and admitting it moves no measured number); `docs/analysis/**`
  (findings, see D2); `docs/ai/**` (runtime ledgers and untracked evidence, and
  `docs/ai/decisions.jsonl` carries the follow-up registry, which quotes symbols
  precisely because they are unresolved — admitting it would suppress a symbol
  for being filed as a problem).

- **D2 — the coupling, and the ruling. The corpus widens AND the adjudication
  table moves out of it in the same change.** This is the decision the ride
  exists to make, so the alternatives are recorded, not just the choice.

  The constraint: `fu-deslop-adjudication-self-suppression` records that a
  symbol named anywhere in a corpus document is suppressed. The 2026-08-15
  remediation moved a 10-row table of adjudicated indefensible candidates out of
  the frozen spec and into `docs/issues/CHANGE-0145-...md` to restore those rows
  to the output, and that document's own COUPLING note (round-6 code review
  NB-3) states the remedy in advance: "If that corpus is ever widened to include
  `docs/issues/**` ... move this table to a non-corpus home before making that
  change."

  Rejected, with reasons:
  - **A per-type rule.** `CHANGE-0145` is `type: change`, exactly like
    `CHANGE-0125`, which genuinely requests `--worktree-guard`. No type
    predicate separates a requirement document that happens to contain a
    findings table from a requirement document that does not. Excluding
    `type: change` would reopen the defect this scope closes.
  - **A per-section rule.** Section headings are free text. A rule keyed on the
    literal `## Adjudication Summary` is a stoplist wearing a heading's clothes
    — the same curated-exemption mechanism SPEC-0132's NO STOPLIST rule and
    Constitution article 2 already forbid — and it rots the first time an
    author writes a different heading.
  - **A marked block excluded from the corpus.** A previous validation round
    rejected this as a general-purpose suppression backdoor, and the reasoning
    holds here with the sign flipped: a marker lets any author remove any text
    from the corpus, which means an author can make a symbol read as
    unrequested, unmeasurably and uncheckably. Relocation is checkable — the
    corpus document list is printed in `--json` and can be asserted against.
  - **Accepting the 7-row loss with a reason.** The rows are known noise, so the
    cost looks small. It is still a false suppression produced by a document
    that states the opposite of a requirement, in a ride whose entire purpose is
    to stop the corpus lying about what was requested. Shipping it would make
    the tool quieter and less honest at the same time, and would silently undo a
    deliberate fix three days after it landed.
  - **Declining D1 outright.** Considered seriously, and refused on the
    evidence: the false-positive class is measured (3 named symbols, 9 rows in
    total), the remedy is prescribed by the previous ride's own code review, and
    the remedy costs one relocated document. Declining would preserve a known
    lie to avoid a known chore.

  The move: the Adjudication Summary section of
  `docs/issues/CHANGE-0145-deslop-scope-and-unrequested-engine.md` — its
  preamble, its coupling note, its 10-row table and its closing pointer — is
  relocated verbatim to a NEW tracked document,
  `docs/analysis/deslop-candidate-adjudication-20260815.md`, with frontmatter
  `id: deslop-candidate-adjudication-20260815`, `type: research`, `number: null`,
  `status: done`. `CHANGE-0145` keeps a short pointer section naming the new
  home, why it moved, and the coupling it exists to avoid. The relocated
  document is outside the corpus on two independent grounds — its directory is
  not in the allowlist, and `research` is not a requirement type — and D4 makes
  the type ground countable rather than silent.

  `docs/analysis/` is the established home for this shape: it already holds
  `docs/analysis/unhobbling-audit.md` (`type: research`, `number: null`),
  it is tracked, and `docs-audit --check --strict` is CLEAN over it today.
  `docs/ai/reports/**` is not an option — `.gitignore:21` excludes it, which is
  why the table was made tracked in the first place. The untracked full walk at
  `docs/ai/reports/deslop-candidate-adjudication-20260815.md` is unchanged and
  is not deleted.

  Measured consequence, recorded because it is a real cost: `docs/analysis/**`
  has no `tests/skills/suite-map.yaml` row, so `select-suites.mjs` answers
  `FULL_RUN reason=unmapped` for any changed-file list containing the new
  document. A full suite run is strictly safer than a selected one, and adding a
  suite-map row for a documentation directory would itself be unrequested
  surface in a deslop ride, so the escalation is accepted and named rather than
  engineered away.

- **D3 — an unreadable corpus document is named with the sentence the `--diff`
  path already emits, not a second phrasing.** The wording contract already
  exists in `buildNotes` and has two arms:
  - partial (at least one document readable):
    `NOTE: requirement document(s) unreadable, skipped (not searched): <paths>.`
  - total (no document readable): the EMPTY-corpus note, whose reason names the
    paths, as `resolveDiffCorpus` does with
    `requirement document(s) named by STATE.yaml unreadable: <paths>`.

  The fix is therefore a resolver change, not a reporter change:
  `resolveAllCorpus` stops discarding a failed read and returns `unreadable`
  as an array of repo-relative POSIX paths, in the same field shape
  `resolveDiffCorpus` already returns. The existing `else if (corpus.unreadable
  && corpus.unreadable.length > 0)` branch in `buildNotes` then fires for
  `--all` with no new sentence written. When every corpus document is
  unreadable the empty-corpus reason names the unreadable paths instead of
  claiming no document matched the type and status filter, which is what it
  says today and which would be false. "Named" means the document's
  repo-relative POSIX path appears verbatim in the emitted note; `walk()`
  produces platform separators, so the paths pass through the existing
  `toPosix` helper before they reach the note.

- **D4 — exhaustive bucketing, not a residue counter.** The intake asks that
  "a count that does not add up says so". A leftover counter can only be
  non-zero when the bucketing itself has a bug, so it can never be forced in a
  fixture and can never be shown failing — the latent-but-unclosable shape this
  factory has already had to defend once. This spec ships the closable form
  instead: every document the resolver examines lands in exactly one named,
  printed bucket, and the equation is asserted rather than hoped for.

  Buckets, exhaustive by construction:
  - included
  - excluded by status: the existing five (`draft`, `proposed`, `rejected`,
    `superseded`, `deferred`) plus `other_status` for any status outside that
    closed list
  - `not_requirement_type` — frontmatter parsed, `type` outside the D1 set
  - `unparseable_frontmatter` — read succeeded, no frontmatter block recovered
  - `unreadable` — the read itself failed (also the D3 list)

  The header gains an `examined` count so a human can add the line up, and the
  `--json` payload gains `requirement_corpus.examined` alongside the widened
  `excluded` object. Every bucket is reachable from a fixture: a `status:
  current` document forces `other_status`, a `type: research` document forces
  `not_requirement_type`, a body-only file forces `unparseable_frontmatter`,
  and a dangling symlink named `*.md` forces `unreadable` (`walk()` pushes it
  because it is not a directory; `readFileSync` then fails ENOENT). That last
  fixture is also D3's fixture.

  Measured today: examined 137, included 135, `not_requirement_type` 2,
  everything else 0. Measured under D1's widened corpus: examined 333, included
  330, `draft` 1, `not_requirement_type` 2, everything else 0. Both balance,
  and neither is asserted as a number — Spec-AC-05 asserts the equation.

- **D5 — the header states the rule the code applies.** The human corpus line
  today reads `(type spec, status accepted/implementing/done)`. It is rewritten
  to name the three directories, the five requirement types and the three
  statuses actually used, and the `--json` payload carries the same rule as
  data (`requirement_corpus.dirs`, `.types`, `.statuses`) so a machine consumer
  reads the rule rather than inferring it. The `--diff` scope's `excluded`
  block gains the same new keys, so both scopes emit one shape. CORRECTED
  2026-08-19 (round-5 review NB-2): that block was described, and originally
  written, as uniformly zero-valued. Only the buckets `resolveDiffCorpus`
  cannot produce are structurally zero; `unreadable` is one it CAN produce, and
  hardcoding it to zero beside an `examined` of documents-plus-unreadable broke
  D4's balance rule under `--diff` (count 1, examined 2, sum 0). The bucket now
  carries the measured count.

  CORRECTED AGAIN 2026-08-19 (round-6 validation V-1 and V-2). The correction
  above was applied to `renderJson` and to `resolveDiffCorpus`'s PARTIAL return
  only. Two residues survived it, both now closed:
  - `resolveDiffCorpus`'s FULLY-unreadable early return (every STATE-named path
    unreadable) omitted `unreadable` from its return object, so
    `renderJson`'s `diffUnreadable` fell back to 0 and `examined` with it. A
    STATE naming one dangling symlink printed `count 0 / examined 0 /
    excluded.unreadable 0` beside `empty_reason: requirement document(s) named
    by STATE.yaml unreadable: docs/specs/A.md` — the equation holding only
    because both sides collapsed to zero, which is precisely the residue-hiding
    shape D4 exists to eliminate, and a disagreement with `--all`'s equivalent
    branch (examined 1 / unreadable 1). That return now carries `unreadable`,
    so both scopes report the same shape.
  - The `--all` selection in `renderJson` is guard-free on purpose:
    `resolveAllCorpus` returns `excluded`/`examined` on its empty return too, so
    a `&& !result.corpus.empty` guard would drop a corpus that is empty BY
    FILTER back onto the diff-shaped zero literal while `examined` still
    reported the real walk (count 0 / examined 1 / sum 0). That property was
    stated here but pinned by nothing; Spec-AC-05 now asserts it. The pin also
    covers the combined shape (round-7 validation B-4): an empty-BY-FILTER
    corpus that additionally carries an unreadable member (count 0 / examined
    2 / draft 1 / unreadable 1), which is the case that actually broke —
    a fixture with no unreadable member cannot see an excluded block that
    zeroes only the `unreadable` bucket for an empty corpus.

- **D6 — report-only is untouched, and the JSON grows without breaking.** No
  gate, no exit-code change: 0 for a scan with or without candidates, 2 only
  for a usage error. Every JSON change is a new key or a widened object; no key
  is removed or retyped. CORRECTED during remediation (deslop-corpus-honesty
  ride, 2026-08-18): this bullet originally claimed
  `tests/skills/test-aai-deslop.sh:408`'s existing assertion on
  `requirement_corpus.count === 3` stays true on its fixture with no edit. That
  was asserted, never measured, and D1's directory-independent type filter
  disproves it: the fixture's `SPEC-notaspec.md` (type: issue, status: done)
  becomes a genuine corpus member under D1, so the correct post-change value is
  4, not 3. Shape stability (no key removed or retyped) is real and does hold;
  value stability of an assertion whose expected value is a direct function of
  corpus membership does not follow from it, and this bullet conflated the two.
  Spec-AC-06 is restated below to require re-baselining that one line in place,
  not preserving it byte-for-byte.

- **D7 — which published surfaces move, and which are history.** The corpus
  rule is stated in six places. Three are current-state documents and must
  state the new rule; two are dated records and must NOT be rewritten; one is
  the source itself.
  - `.aai/SKILL_DESLOP.prompt.md:20-22` states the corpus is `docs/specs/**`
    only and cites `fu-deslop-all-corpus-specs-only` as an open caveat. Both
    become false. Rewritten, and one durable convention line is added: findings
    about this tool belong in `docs/analysis/`, outside the corpus. That line is
    what makes the D2 relocation a rule rather than a one-off, and is why
    `fu-deslop-adjudication-self-suppression` can be closed rather than
    re-filed.
  - `docs/product/aai-deslop.md` is `status: current`. Its first Limits bullet
    ("The requirement corpus is `docs/specs/**` only ... roughly a quarter of
    the reported rows") describes the defect as a permanent property, and its
    third ("Naming a symbol in a spec hides it") is now narrower than the truth.
    Both are rewritten from a post-change measurement, and `delivered_by` and
    `updated` are bumped.
  - `.aai/scripts/deslop-unrequested.mjs`'s own header comment block states the
    `--all` corpus rule and points at the adjudication summary's location. Both
    move with the code.
  - `docs/specs/SPEC-0132-...md` is FROZEN and `status: done`. Its D2 corpus
    bullet, its D5 sample output header, its Spec-AC-04 row and its D3
    adjudication pointer all describe the old rule. It gets a dated
    `## Correction` section in the shape its existing `## Amendment` section
    established — naming this scope, stating that D2's `--all` corpus selection
    and the D3 pointer are superseded — plus a one-line inline pointer at each
    of the four sites. Its historical measurements (131 of 133, 70/398, 68/400)
    are NOT rewritten: they were true when taken, and rewriting a dated
    measurement is the failure mode this project already named.
  - `CHANGELOG.md:193` sits inside the RELEASED `## [v2026.08.16]` section. It
    is a record of what shipped and stays byte-identical. The new rule and the
    newly measured counts go in a new `## [unreleased] — <title>` heading (the
    per-entry heading form, never bullets under a bare scaffold).
  - `docs/ai/tdd/deslop-real-repo-all-baseline-*.json` are gitignored, dated
    baselines. Not re-baselined. A new post-change `--all --json` capture is
    recorded as evidence in the Implementation return record.

- **D8 — companion obligations (closed two-entry list).** PROMPT CORPUS BYTES
  MOVE: YES — `.aai/SKILL_DESLOP.prompt.md` is inside the live `.aai/*.prompt.md`
  glob that `tests/skills/test-aai-prompt-diet.sh` TEST-010 measures. Measured
  headroom on the current tree is 1665 of a 2048 cap, so the guard bites in BOTH
  directions: at most 1665 bytes may be added before headroom goes negative, and
  at most 383 bytes may be removed before headroom exceeds the cap. The edit is
  a few lines and is expected to land well inside that window, but the direction
  and size are a measurement, not a prediction: whichever way the measured delta
  falls, a `JUSTIFIED_ADDITIONS` true-up credited 1:1 at the measured delta and
  the matching TEST-012 pin move are in scope, and TEST-029 is the arm.
  NEW `.aai/**` FILE: NO — no file is added under `.aai/`, so no
  `.aai/system/PROFILES.yaml` classification entry is owed. The new document
  lives under `docs/analysis/`.

  Two mechanical obligations outside that closed list also apply, because
  suites in this repo enforce them: every new test function must be registered
  in the suite's `main()` (`.aai/scripts/check-test-registration.mjs`), and
  `tests/skills/test-aai-advisory-skills.sh` pins the deslop prompt's line
  ceiling, table shape, rules block and advisory isolation, all of which the
  D7 prompt rewrite must keep true.

## Implementation strategy
- Strategy: direct
- Rationale: three localized defects in one function of one script whose suite
  already exists and already builds every fixture shape needed, plus a document
  relocation and five text true-ups. There is no new subsystem, no new input
  and no interface to discover, so a RED-GREEN cycle per arm would be ceremony
  over one walk, one array and one counter object. The intake's `## Notes`
  records "Strategy suggestion: direct with targeted tests" and carries no
  `Implementation mode (user choice):` line; STATE's recorded `direct` belongs
  to the `followups-cli-hardening` ride (its `source` names that spec), so this
  is Planning's call and it agrees with the suggestion. Direct does NOT waive
  the failing-first observation — see the discipline paragraph under the Test
  Plan.

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: one script, one suite, one prompt, one new document and
  five text true-ups. No `protected_paths_l3` surface appears in the file list
  (state engine, allocator, pre-commit guards, `.aai/workflow/WORKFLOW.md`,
  `docs/CONSTITUTION.md`), and no parallel scope touches these paths. Isolation
  is offered only because `close-work-item.mjs` regenerates
  `docs/ai/factory-report.html`, `docs/ai/factory-report-data.json` and
  `docs/INDEX.md` on every close, so a concurrent close in the shared tree
  rewrites generated files mid-ride and makes the diff read as this scope's
  work. A dedicated branch is required regardless by the one-branch-per-work-item
  rule `branch-guard.mjs` enforces at PR. Implementation Preparation decides.
- User decision: undecided
- Base ref: main
- Worktree branch/path: fix/deslop-corpus-honesty (proposed)
- Inline review scope: .aai/scripts/deslop-unrequested.mjs,
  .aai/SKILL_DESLOP.prompt.md, tests/skills/test-aai-deslop.sh,
  tests/skills/lib/prompt-diet-ledger.sh, tests/skills/test-aai-prompt-diet.sh,
  docs/analysis/deslop-candidate-adjudication-20260815.md,
  docs/issues/CHANGE-0145-deslop-scope-and-unrequested-engine.md,
  docs/specs/SPEC-0132-spec-deslop-scope-and-unrequested-engine.md,
  docs/product/aai-deslop.md,
  docs/specs/SPEC-0136-spec-deslop-corpus-honesty.md,
  docs/issues/CHANGE-0150-deslop-corpus-honesty.md, docs/ai/decisions.jsonl,
  docs/INDEX.md, CHANGELOG.md

Code review required: true (engine, suite and prompt changes); scope = the
explicit path list above as a diff against main.

## Acceptance Criteria Mapping

- Maps to: CHANGE AC-002
- Spec-AC-01: the corpus the code resolves and the corpus the header describes
  are the same rule. `--all` includes a document exactly when it sits under
  `docs/specs`, `docs/issues` or `docs/rfc`, its frontmatter `type` is one of
  spec, change, issue, techdebt or rfc, and its `status` is one of accepted,
  implementing or done. `requirement_corpus.documents` contains at least one
  path under each of the three directories, contains no path outside them, and
  contains no document whose frontmatter type is outside the five. The human
  header line and the `--json` `requirement_corpus.dirs`, `.types` and
  `.statuses` fields state that same rule, and no output line claims the corpus
  is `type: spec` only.
  - Verification: `node .aai/scripts/deslop-unrequested.mjs --all --json` over
    this repository, with a Node one-liner asserting the three membership
    properties over `requirement_corpus.documents` by re-reading each document's
    frontmatter; plus a fixture tree carrying one document of each admitted type
    in each admitted directory and one in a directory outside the allowlist.
    Evidence: suite stdout and the recorded `--json` capture.

- Maps to: CHANGE AC-001
- Spec-AC-02: a flag or config key named in a committed change, issue, techdebt
  or RFC document with an included status is not reported as a candidate.
  `--worktree-guard`, `--worktree-baseline` and `--pr-config` are each absent
  from `candidates` on this repository, and each is present in a corpus
  document that lives under `docs/issues` or `docs/rfc` — a document the corpus
  admits ONLY under the new rule. Accepting a citation from any corpus document
  would be a tautology on this tree, because this ride's own draft spec sits
  under `docs/specs` and names all three symbols. On a fixture, a symbol named only in a
  `type: change` document with `status: done` is suppressed while the same
  symbol in a `status: draft` document is still reported, so the status filter
  is proven live rather than assumed.
  - Verification: `node .aai/scripts/deslop-unrequested.mjs --all --json` over
    this repository, asserting zero `candidates` entries whose `symbol` is one
    of the three AND that each is cited by a `requirement_corpus.documents`
    entry outside `docs/specs`; plus the fixture arm asserting the suppressed
    and reported halves. Evidence: suite stdout and the recorded `--json`
    capture.

- Maps to: CHANGE Constraints (the adjudication coupling)
- Spec-AC-03: a document that records findings about this tool never suppresses
  the symbols it names. `docs/analysis/deslop-candidate-adjudication-20260815.md`
  exists, carries the 10 adjudication rows and the coupling note,
  `docs/issues/CHANGE-0145-deslop-scope-and-unrequested-engine.md` no longer
  carries those rows and carries a pointer to the new home,
  `requirement_corpus.documents` on this repository contains no path under
  `docs/analysis`, and `.aai/SKILL_DESLOP.prompt.md` states the convention that
  findings belong outside the corpus. On a fixture, a symbol named only in a
  findings document placed outside the allowlisted directories is still
  reported as a candidate while a symbol named in a corpus document is not.
  - Verification: `grep` contracts over the two documents and the prompt, a Node
    assertion over `requirement_corpus.documents`, and the fixture arm.
    Evidence: suite stdout.

- Maps to: CHANGE AC-003
- Spec-AC-04: an unreadable requirement document under `--all` is named using
  the sentence the `--diff` path already emits. With at least one readable
  document, `notes` contains an entry beginning `NOTE: requirement document(s)
  unreadable, skipped (not searched):` and naming every unreadable document's
  repo-relative POSIX path, and the readable documents still suppress the
  symbols they name. With every corpus document unreadable, the EMPTY-corpus
  note's reason names the unreadable paths rather than claiming no document
  matched the filter. Both runs exit 0, and neither aborts the scan.
  - Verification: two fixture trees, each containing a dangling symlink named
    `*.md` under `docs/specs`, run under `--all --json`; the first asserts the
    note text, the named path and a still-suppressed symbol, the second asserts
    `requirement_corpus.empty` true with the path inside `empty_reason`. Both
    assert exit 0. Evidence: suite stdout.

- Maps to: CHANGE AC-004
- Spec-AC-05: the document accounting balances. `requirement_corpus.examined`
  equals `requirement_corpus.count` plus the sum of every value in
  `requirement_corpus.excluded`, on a fixture and on this repository. The
  fixture carries one document per bucket — included, one per excluded status,
  one with a status outside the closed list, one with a type outside the
  requirement set, one with no parsable frontmatter and one unreadable — and
  each corresponding bucket equals 1. The human header prints the examined
  count and every bucket, and the `--diff` scope emits the same `excluded` key
  set so both scopes carry one shape. The equation holds under `--diff` too:
  its corpus is STATE-sourced so its only exclusion reason is `unreadable`, and
  that bucket carries the real count rather than a hardcoded zero — in the
  PARTIAL branch (some STATE-named document readable) and in the FULLY-unreadable
  branch alike, so the two scopes never disagree about the same fact. In both
  scopes `examined` is measured BEFORE the partition it is checked against —
  the directory walk's file count under `--all`, the number of distinct paths
  `current_focus` names under `--diff` — never re-derived from the buckets
  themselves, so the equation is a falsifiable check rather than an identity
  that holds by construction
  (round-6 validation V-1). The equation also holds for an `--all` corpus that is
  empty BY FILTER: a corpus directory holding only a `draft` document reports
  count 0, examined 1 and `draft` 1, never an all-zero excluded block beside a
  non-zero examined (round-6 validation V-2).
  - Verification: the fixture arm asserting each bucket and the equation, plus
    the same equation asserted over `node .aai/scripts/deslop-unrequested.mjs
    --all --json` on this repository, plus a `--diff` run over a fixture whose
    STATE names one readable and one unreadable document, asserting both
    key-set parity of the `excluded` object AND the same equation, plus an
    `--all` run over a fixture whose only corpus document is a `draft`,
    asserting count 0 / examined 1 / `draft` 1 and the equation, plus a
    `--diff` run over a fixture whose STATE names ONLY unreadable documents,
    asserting count 0 / examined 2 / `unreadable` 2 and the equation. Evidence:
    suite stdout.

- Maps to: CHANGE AC-006
- Spec-AC-06: the engine stays report-only. Exit code is 0 for a run with
  candidates, a run without candidates and a run over an empty input set, and
  the only nonzero exit remains 2 for a usage error. A fixture tree is
  byte-identical before and after both scopes, proven by a sha256-per-file
  manifest over the sorted file list compared string-for-string, and no new
  path exists under the fixture root. (Corrected 2026-08-18: this line used to
  say the manifest is compared with `cmp`; the arm has always compared the two
  manifests as shell strings and the suite invokes no `cmp` command. Corrected
  again 2026-08-19, round-5 review NB-4: the earlier wording said the word
  "cmp" appears nowhere in the suite, which is literally false — two
  pre-existing comments at `tests/skills/test-aai-deslop.sh:391` and `:444`
  describe TEST-004(b) as "cmp-proven". The claim that matters, that no `cmp`
  call exists and the manifests are compared as shell strings, is unaffected.)
  - WITHDRAWN 2026-08-18 — the suite-additivity clause, together with the only
    arm that gated it. This AC used to require in addition that no pre-existing
    TEST arm and no pre-existing assertion in `tests/skills/test-aai-deslop.sh`
    be removed: every TEST-001 through TEST-021 still defined and still wired
    into `main()`, and each arm's own assertion-site count not below the
    committed base's count for that same arm, with an in-place re-baseline of
    an expected value explicitly permitted as not-a-removal. That clause was
    gated by exactly one arm, `test_027_suite_stays_green_and_additive`. The
    arm was mechanized FOUR times and failed independent validation FOUR times,
    each round in a new shape, and it has now been removed from the suite. The
    clause goes with it: a `done` AC must not claim evidence that no longer
    exists. Removing it returns to the committed status quo rather than
    regressing anything — the base has 21 arms and has never carried such a
    guard. Corrected 2026-08-19 (round-5 review NB-3): this sentence used to
    say suite additivity survives as "a project convention and a code-review
    duty". The code-review half was an overclaim — no document in this
    repository establishes such a duty, and the only reason it was discharged
    on this ride is that the Verification section below asked for the numstat
    read by hand. What is true: the protection is GONE. Suite additivity is
    convention only, it is NOT mechanically verified, no assertion in this
    repository checks it, and no standing review duty carries it. The gap is
    carried entirely by registry item `fu-deslop-suite-additivity-guard`. No
    replacement duty is asserted here; if one should exist it must be filed and
    written down somewhere that binds, not claimed in a spec that has shipped. The withdrawal, the six defeats and what a real fix would need
    are filed as registry item `fu-deslop-suite-additivity-guard` (P3). The
    re-baseline convention the clause encoded also stands as convention only:
    an expected value may be re-baselined in place when an inline comment at
    that line names the ride and the measured reason the old value stopped
    being true — for example TEST-004's fixture-corpus count, re-baselined 3 to
    4 when D1 made the type filter directory-independent.
  - GUARD HISTORY, kept deliberately rather than deleted: four mechanizations,
    four independent validation failures, six distinct defeats. This is the
    most useful thing the attempt produced. (A fifth shape never shipped:
    `git diff --numstat main -- tests/skills/test-aai-deslop.sh` reporting zero
    deleted lines was rejected pre-ship because it is line-based, not semantic
    — a legitimate one-line in-place re-baseline reads as one deleted plus one
    added line, so it failed the exact case the AC permitted.)
    - Attempt 1, defeated by validation round 1 (V-1). DEFEAT 1, self-
      referential arm list: the check grepped a hardcoded `known_tests` array
      declared inside `tests/skills/test-aai-deslop.sh` against that same file,
      so the search term and the haystack were one artifact and an entry always
      matched itself even after the function body was gutted and its `main()`
      wiring deleted. Its second half compared a WHOLE-FILE `ok=0` aggregate
      against main's whole-file total (188 vs 120), leaving 68 units of slack
      in which one arm's assertions could be deleted as long as another arm's
      grew. Proven by mutation: replacing TEST-001's body with a `log_pass`
      stub destroyed 6 assertion sites and the suite still printed
      `All tests passed!` with the guard reporting PASS.
    - Attempt 2, defeated by validation round 2 (V-3, with V-5 to V-7 in the
      same round). The base moved to `git show main:...`, the committed tip of
      a different branch. DEFEAT 2, a bare `main` degrading to PASS: a bare
      `main` does not resolve on a GitHub `pull_request` checkout (detached
      HEAD, only `origin/main` fetched), and the unreadable source took a SKIP
      path that left `ok` untouched, bypassed every definition, wiring and
      count check, and still reported PASS — with a skip message that falsely
      claimed those checks had run. Proven by mutation in a CI-shaped copy
      (detached HEAD, `refs/heads/main` deleted, only `origin/main` present):
      TEST-001 gutted to a stub, guard still PASS. Fourth occurrence of this
      base-ref class in this repository. Two further holes closed in the same
      round: the per-arm count was a bare `ok=0` substring match over every
      line, so a gutted arm padded with `# ok=0` comment lines kept its count
      (V-5); and the wiring check grepped the arm name anywhere in the file, so
      a dead never-called function mentioning the name kept a de-wired arm
      looking wired (V-6). `main()` also gained `"$@"` handling so the per-arm
      commands this Test Plan documents run the named arm instead of silently
      running the whole suite (V-7) — that fix is independent of the guard and
      is retained.
    - Attempt 3, defeated by validation round 3 (V-8 blocking, V-9 non-
      blocking). DEFEAT 3, unguarded base-side parsers: the base and the
      per-arm data were right, but the two parsers that read the base —
      `arm_table` and `main_dispatch_body` — lived in the file under test and
      ran on both sides of the comparison. `main_src` was checked non-empty;
      its PARSE was not. Three mutations each ran the FULL suite at exit 0 with
      the guard PASS and TEST-001 gutted or de-wired: `arm_table`'s body
      replaced by `awk 'BEGIN { exit 0 }'`; ONE token changed in `arm_table`'s
      header regex (`^test_[0-9]+_` to `^testX_[0-9]+_`); `main_dispatch_body`'s
      body replaced by `cat "$1"`, which stays non-empty and so reopens V-6.
      This refuted the standing claim that a committed base "cannot be
      satisfied by editing the file under test": a mutation need not rewrite
      the base, only stop the base from being parsed. V-9 (non-blocking): the
      arm's header also claimed the per-arm count catches a body hollowed out
      in place, which no count-based check can do.
    - Attempt 4, defeated by validation round 4 — three separate defeats at
      once. The fourth mechanization canaried both parsers against synthetic
      inputs and cross-checked them against a differently shaped grep read of
      the same base blob behind hard floors (21 arms, 120 marker sites, a
      rows-equal-arms agreement, a site ceiling, a per-row name check and two
      dispatch-shape checks). DEFEAT 4, an unguarded `$self` read: all eight
      cross-checks constrained the BASE reading and not one constrained the
      `$self` reading, so a single line, `self_table="$main_table"`, defeated
      the whole arm while editing no parser and no cross-check. DEFEAT 5,
      unreachable-branch wiring: an arm moved into a branch inside `main()`
      that can never execute still read as wired, because the wiring check
      matches text in `main()`'s body rather than proving the call is
      reachable. DEFEAT 6, zero-count arms unprotected: an arm whose base
      assertion-site count is 0 clears the per-arm floor no matter what is done
      to its body.
  - CONCLUSION, and the reason the attempt was ended rather than mechanized a
    fifth time: an in-file guard cannot verify its own file. Every layer of
    every attempt was a reader defined in the artifact it guarded, so the
    guard's source of truth was always reachable from the same mutation surface
    it was supposed to police. The cross-checks raised the price from one token
    to a coordinated multi-site edit; they did not make the guard
    non-recursive, and round 4 paid that price with one line. A real fix needs
    an out-of-file checker that reads this suite AS DATA from a different
    artifact. None exists today and building one is out of scope for this ride;
    it is filed as `fu-deslop-suite-additivity-guard` (P3).
  - Verification (what remains of this AC, and it is fully gated):
    `bash tests/skills/test-aai-deslop.sh test_005_no_write_proof
    test_006_exit_code_contract`. TEST-005 compares a sha256 content manifest
    AND the file list of a fixture tree before and after both scopes run, so a
    byte change or a new path turns it red. TEST-006 asserts exit 0 for a clean
    run, a run with candidates and a run over an empty input set, exit 2 for an
    unknown flag, and proves at source level that no `process.exit` call in the
    engine uses a value other than 0 or 2. Both are pre-existing arms and both
    also run inside the full suite, which exits 0 with zero `FAIL` lines.
    Evidence: suite stdout.

- Maps to: CHANGE AC-005
- Spec-AC-07: every shipped document that states the corpus rule states the new
  one, every published count in a current-state document comes from a
  post-change measurement, and no dated record is rewritten.
  `.aai/SKILL_DESLOP.prompt.md`, `docs/product/aai-deslop.md` and the
  `.aai/scripts/deslop-unrequested.mjs` header comment carry no claim that the
  corpus is `docs/specs` or `type: spec` only, and each names the three
  directories. `docs/specs/SPEC-0132-...md` carries a dated `## Correction`
  section naming this scope, and an inline superseded pointer at its D2 corpus
  bullet, its D5 sample header, its Spec-AC-04 row and its D3 adjudication
  pointer. `CHANGELOG.md` carries one new `## [unreleased]` heading stating the
  new rule with the post-change candidate and suppressed counts, and its
  released `## [v2026.08.16]` section is byte-unchanged. `docs/product/aai-deslop.md`
  frontmatter `delivered_by` gains this scope's ref and `updated` is bumped.
  - Verification: `grep` contracts over each surface for the absence of the old
    claim and the presence of the new one; the in-suite byte compare of the
    `[v2026.08.16]` section against `git show <base>:CHANGELOG.md`, where
    `<base>` resolves `origin/main` then `main` so it also works on a detached
    `pull_request` checkout, showing no line removed or altered inside that
    section (locally reproducible as `git diff main -- CHANGELOG.md`); the
    post-change `--all --json` capture whose counts match the numbers written
    into the product doc and the CHANGELOG entry; `node
    .aai/scripts/docs-audit.mjs --check --strict --no-event` and `node
    .aai/scripts/spec-lint.mjs` both clean. Evidence: suite stdout, the diff,
    the JSON capture and the two tool outputs.

- Maps to: CHANGE Notes (registry items closed by this scope)
- Spec-AC-08: the governance companions are in place and the registry tells the
  truth. `tests/skills/test-aai-prompt-diet.sh` exits 0 with TEST-010's headroom
  inside 0 to 2048 and TEST-012's pin equal to the independent re-sum of
  `JUSTIFIED_ADDITIONS`, with a ledger entry crediting the measured
  `.aai/*.prompt.md` byte delta 1:1 whenever that delta moves the pin.
  `node .aai/scripts/check-test-registration.mjs` exits 0. All four registry
  items — `fu-deslop-all-corpus-specs-only`, `fu-deslop-allcorpus-unreadable-silent`,
  `fu-deslop-corpus-header-other-bucket` and `fu-deslop-adjudication-self-suppression`
  — are closed with `follow-ups.mjs close --resolved-by <this ref>`, and
  `node .aai/scripts/follow-ups.mjs list --status open` names none of them.
  - Verification: `bash .aai/scripts/aai-run-tests.sh bash
    tests/skills/test-aai-prompt-diet.sh` and `... tests/skills/test-aai-advisory-skills.sh`
    each exiting 0, `node .aai/scripts/check-test-registration.mjs` exiting 0,
    and `node .aai/scripts/follow-ups.mjs list --status open --json` asserting
    the four ids are absent. Evidence: the four stdouts.

## Constitution deviations

None. Checked v1 articles 1 to 7.

Article 1 (evidence before claims): every AC above names an executable local
command and a read observable, and the failing-first paragraph under the Test
Plan names where each pre-change exit code is recorded. Article 2 (simplicity):
one walk list, one type set, one counter object and one array in an existing
function; no stoplist, no marker mechanism, no new script, no new dependency,
and D2 records four simpler-looking alternatives that were refused because each
is a suppression mechanism with no measurement behind it. Article 3
(portability): plain Node stdlib, plain Markdown, no service. Article 4
(degrade and report): D3 and D4 ARE this article applied — each replaces a
silent drop with a named, counted one. Article 5 (additive first): every JSON
change is a new key or a widened object, no key is removed or retyped, the
exit-code contract is untouched, and the one behavior change that a consumer can
observe — a smaller candidate list — is the defect being fixed and is recorded
in CHANGELOG. Article 6 (single-writer state): this planning pass writes STATE
only through `.aai/scripts/state.mjs`, and the engine only ever READS
`docs/ai/STATE.yaml`. Article 7 (operator-only merge): no merge is performed.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN the wide-scope corpus resolves THEN it is exactly the documents under docs/specs docs/issues and docs/rfc whose type is one of spec change issue techdebt rfc and whose status is accepted implementing or done, and the header and the json both state that same rule | done | TEST-022 green | — | the directory allowlist plus the type filter are both load-bearing; measured that no requirement-typed document lives outside the three directories today |
| Spec-AC-02 | WHEN a symbol is named in a committed change issue techdebt or RFC document with an included status THEN it is not reported as a candidate, demonstrated on --worktree-guard --worktree-baseline and --pr-config | done | TEST-023 green | — | measured: widening to docs/specs plus docs/rfc alone leaves all three still reported, so docs/issues is the load-bearing half. Round-6 validation V-3 (non-blocking): each of the three symbols has exactly one citation outside docs/specs today, so a status flip archive or move on CHANGE-0125 or CHANGE-0096 turns the citation loop red for a reason unrelated to the corpus rule. The loop still fails closed but now names which of the two worlds it is in (citation drift versus a real corpus-rule regression), and the residual coupling is filed as fu-deslop-ac02-single-citation (P3) |
| Spec-AC-03 | WHEN a document records findings about this tool THEN it never suppresses the symbols it names, proven by the adjudication table living under docs/analysis and by no corpus document path resolving under docs/analysis | done | TEST-024 green | — | the D2 ruling; without the relocation the widening silently reverts the 2026-08-15 fix and costs a measured 7 candidate rows |
| Spec-AC-04 | WHEN a requirement document cannot be read under --all THEN it is named with the same sentence the --diff path already emits, and when every document is unreadable the empty-corpus reason names the paths, both at exit 0 | done | TEST-025 green | — | resolver change only, no second phrasing invented; paths pass through toPosix before reaching the note |
| Spec-AC-05 | WHEN the corpus resolves THEN examined equals included plus the sum of every excluded bucket, on a fixture covering every bucket and on this repository, with the examined count and every bucket printed | done | TEST-026 green; TEST-020 green | — | exhaustive bucketing rather than a leftover counter, so every path is forceable in a fixture; live residue today is 2 research documents. Extended 2026-08-19 (round-6 validation): TEST-020(a) now pins the FULLY-unreadable --diff branch (count 0 examined 2 unreadable 2) which V-1 found zeroing its bucket, and TEST-026 now pins an --all corpus empty BY FILTER (count 0 examined 1 draft 1) which V-2 found unpinned. Both bites proven by mutation under the full suite. Extended again 2026-08-19 (round-7 validation): B-3 mutation-proved the three human-header assertions inert because they were unanchored substring matches (a header printing 101 satisfied "examined: 10"), so they are now whole-line matches; B-4 found the empty-BY-FILTER fixture carried no unreadable member, leaving probe P10 (empty by filter AND one unreadable member, the shape that actually broke at examined 2 versus sum 1) unpinned, so that fixture now also carries a dangling symlink and reads count 0 examined 2 draft 1 unreadable 1. Both bites proven by mutation under the full suite. CORRECTED 2026-08-19 (delta code review NB-2, confirmed by the round-9 confirmation): the P10 control was overstated here. It used a bespoke narrowed mutation; against the regression the pin actually guards (restoring the removed corpus-empty guard), the pre-symlink fixture already bites on two clauses, re-measured independently as draft 1 to 0 and balance true to false. The dangling symlink stays as added coverage of the empty-by-filter-plus-unreadable shape, not for the reason first recorded. See the correcting record in docs/ai/decisions.jsonl |
| Spec-AC-06 | WHEN either scope runs THEN exit is 0 with and without candidates and over an empty input set, 2 remains the only usage-error exit, and the fixture tree is byte-identical after both scopes with no new path created | done | TEST-005 green (sha256 content manifest AND file list of a fixture tree identical before and after both scopes run) and TEST-006 green (exit 0 for a clean run a with-candidates run and an empty-input-set run, exit 2 for an unknown flag, plus a source-level proof that no process.exit call in the engine uses a value other than 0 or 2); full suite green at 28 arms with 0 FAIL lines | — | the suite-additivity half of this AC was WITHDRAWN 2026-08-18. Its only gate, TEST-027, was mechanized four times and failed independent validation four times, defeated by a self-referential arm array, a bare main base that does not resolve on a pull_request checkout and degraded to PASS, unguarded base-side parsers, an unguarded $self read that one line defeated, an arm moved into an unreachable branch inside main() that still read as wired, and zero-count arms that clear the per-arm floor unconditionally. The arm is removed from the suite and the TEST-027 numbering gap is left in place. An in-file guard cannot verify its own file; a real fix needs an out-of-file checker reading the suite as data. Filed as fu-deslop-suite-additivity-guard (P3). Corrected 2026-08-19 (round-5 review NB-3): suite additivity remains a convention only. It is not mechanized and no document establishes a code-review duty for it; the gap is carried by fu-deslop-suite-additivity-guard |
| Spec-AC-07 | WHEN the scope is complete THEN no current-state document states the old corpus rule, every published count comes from a post-change measurement, and no dated record is rewritten | done | TEST-028 green | — | released CHANGELOG section and the frozen spec historical measurements stay as history; the frozen spec gets a dated Correction section plus four inline pointers. Remediated 2026-08-18 (validation round 2, finding V-4): the released-section compare called `git show main:CHANGELOG.md`, which throws on a detached pull_request checkout, so the arm went red claiming the section differed while it was in fact byte-identical - the base now resolves origin/main then main, the node helper distinguishes an unreadable ref from a real difference, and the arm fails closed when neither ref resolves |
| Spec-AC-08 | WHEN the scope is complete THEN the prompt-diet ledger and pin are true-ed up at the measured byte delta, test registration passes, and all four deslop corpus follow-ups are closed in the registry | done | TEST-029 green (test-aai-prompt-diet.sh TEST-012); TEST-030 green | — | measured headroom is 1665 of 2048 so the guard bites in both directions; the fourth follow-up closes because the prompt now carries the findings-outside-the-corpus convention |

Status values: planned | implementing | done | deferred | blocked | rejected

## Implementation plan

Components:

- `.aai/scripts/deslop-unrequested.mjs` (EDIT — the whole engine substance,
  five touch points):
  - the header comment block (lines 62 to 66): the `--all` corpus rule, and the
    adjudication summary pointer inside `buildLimits`.
  - two new module constants beside `EXCLUDED_STATUSES` and
    `INCLUDED_STATUSES`: the corpus directory allowlist and the requirement-type
    set. Both closed lists, both named in the output.
  - `resolveAllCorpus` (line 231): walk each allowlisted directory instead of
    `docs/specs` alone; classify every examined file into exactly one bucket;
    return `examined`, the widened `excluded` object and `unreadable` as an
    array of POSIX paths; when `documents` is empty and `unreadable` is not,
    make the reason name the unreadable paths.
  - `renderHuman` (line 1008): the corpus rule line, the `examined` line and
    the widened excluded line.
  - `renderJson` (line 1030): `examined`, `dirs`, `types`, `statuses`, the
    widened `excluded` object, and the same widened key set in the `--diff`
    zero block so both scopes emit one shape.
  - NOT touched: `resolveDiffCorpus`, `buildCorpusText`, `wholeWordMatch`, both
    extractors, every external-span helper, `scanDiff`'s added-line logic, and
    `buildNotes`'s existing sentences.
- `tests/skills/test-aai-deslop.sh` (EDIT): eight new functions registered in
  `main()` as `test_022` through `test_029`, continuing the file's numbering
  past 021 and following its conventions — `run_engine`, `engine_exit_code`,
  `engine_body`, `node_check`, `log_pass`/`log_fail`/`log_info`, bash 3.2, full
  `.XXXXXX` mktemp templates, `git init -b main` for any git fixture, no bare
  `rc=$?` and no `grep | head` under the suite's shell options, and every
  fixture helper refusing an empty or relative target directory before any
  `git -C`. Zero deletions.
- `docs/analysis/deslop-candidate-adjudication-20260815.md` (NEW): the
  relocated Adjudication Summary, verbatim, with frontmatter
  `id: deslop-candidate-adjudication-20260815`, `type: research`,
  `number: null`, `status: done`, and a back-link to CHANGE-0145 and to the
  untracked full walk.
- `docs/issues/CHANGE-0145-deslop-scope-and-unrequested-engine.md` (EDIT): the
  Adjudication Summary section is replaced by a short pointer naming the new
  home, the date, and the coupling that forced the move.
- `docs/specs/SPEC-0132-spec-deslop-scope-and-unrequested-engine.md` (EDIT): a
  dated `## Correction` section plus four inline superseded pointers. No
  historical measurement is altered and its existing frozen marker line is
  preserved untouched.
- `.aai/SKILL_DESLOP.prompt.md` (EDIT): the corpus sentence, the dropped
  follow-up citation, and the findings-belong-in-docs-analysis convention line.
- `docs/product/aai-deslop.md` (EDIT): the two Limits bullets, `delivered_by`,
  `updated`.
- `tests/skills/lib/prompt-diet-ledger.sh` and
  `tests/skills/test-aai-prompt-diet.sh` (EDIT, conditional on the measured
  byte delta moving the pin): one `JUSTIFIED_ADDITIONS` entry credited 1:1 and
  the matching TEST-012 checkpoint move.
- `docs/ai/decisions.jsonl` (APPEND-ONLY, through
  `node .aai/scripts/follow-ups.mjs close`): four status lines.
- `CHANGELOG.md`: one `## [unreleased] — <title>` heading.
- `docs/INDEX.md`: regenerated for the new document.
- NOT EDITED: `.aai/system/PROFILES.yaml` (no new `.aai/**` file),
  `tests/skills/suite-map.yaml` (no new suite file; the unmapped
  `docs/analysis/**` path escalates the selector to FULL_RUN, which is
  accepted per D2), `docs/ai/reports/deslop-candidate-adjudication-20260815.md`
  (untracked, unchanged), and every `docs/ai/tdd/` baseline.

Data flows:

- `docs/specs` plus `docs/issues` plus `docs/rfc` -> `walk` -> per-file
  `readTextSafe` and `parseFrontmatter` -> one of six buckets -> `documents`
  -> `buildCorpusText` -> `wholeWordMatch` per extracted symbol ->
  `matchAndSplit` -> `candidates` and `suppressed`. Only the first two arrows
  change; everything downstream of `documents` is untouched.
- `resolveAllCorpus().unreadable` -> `buildNotes`'s existing partial-corpus
  branch -> `notes` -> both renderers. No new sentence enters the system.

Edge cases:

- A document under an allowlisted directory whose `type` is a requirement type
  but whose `status` is absent: `status` is undefined, so it matches no known
  status and lands in `other_status`. Counted, never dropped.
- A document whose frontmatter opens with `---` but never closes: `parseFrontmatter`
  returns null, so it lands in `unparseable_frontmatter`. Counted.
- A dangling symlink named `*.md`: `walk` pushes it because it is not a
  directory, `readTextSafe` fails, and it lands in `unreadable` and in D3's
  note. This is the same fixture for both ACs.
- A directory in the allowlist that does not exist (a downstream project with
  no `docs/rfc`): `walk` already returns an empty array on a failed
  `readdirSync`, so the corpus is simply smaller. No note is owed and none is
  added.
- Every allowlisted directory absent: `documents` is empty and `unreadable` is
  empty, so the existing EMPTY-corpus note fires with the filter reason, which
  is then true.
- A symbol named ONLY in the in-flight intake (`status: draft`): still reported
  under `--all`, by design — `--all` is the agreed-requirement corpus, and the
  in-flight intake is exactly what `--diff` reads from STATE's `primary_path`.
  Asserted as intended behavior in Spec-AC-02's fixture, not treated as a gap.
- A symbol named only inside a fenced code block of a corpus document: still a
  match, unchanged from SPEC-0132's D2.
- Windows path separators from `walk`: normalized through `toPosix` before any
  path reaches `documents`, `unreadable` or a note.

## Seams

- SEAM-1 — `resolveAllCorpus` (producer of `unreadable`) and `buildNotes`
  (consumer). The `--diff` resolver already fills that field and `buildNotes`
  already branches on it; the `--all` resolver has never filled it. A producer
  that returns a different shape (a count instead of an array, platform
  separators instead of POSIX) produces a note that is present but wrong, which
  is worse than the silence being fixed. Crossed by TEST-025, which runs the
  real engine over a fixture and asserts the note's literal prefix AND the
  exact path string.
- SEAM-2 — the corpus rule and the documents that publish it. Six surfaces
  state the rule; the code is one of them. Editing the resolver without the
  five text surfaces leaves the tool's own documentation asserting the defect.
  Crossed by TEST-028, which greps every surface for the absence of the old
  claim and the presence of the new one, and by the released-section diff check.
- SEAM-3 — the corpus and the documents that DISCUSS the corpus. This is the
  coupling that defines the ride: a findings document inside the corpus turns a
  finding into its own suppression. A unit test on the resolver cannot see it,
  because the defect is a property of which documents exist, not of the code.
  Crossed by TEST-024's fixture (a findings document outside the allowlist keeps
  its symbols reported) AND by a real-tree assertion that no corpus document
  resolves under `docs/analysis`.
- SEAM-4 — the widened `excluded` object and the existing suite assertion at
  `tests/skills/test-aai-deslop.sh:408`, which pins the corpus count and the
  five status buckets on a fixture. Any retyping or renaming of those keys
  turns a pre-existing arm red. CORRECTED during remediation (deslop-corpus-
  honesty ride, 2026-08-18): this seam originally required TEST-004 to stay
  green unmodified — that was asserted, never measured, against D1's actual
  semantics. Measured: D1's type filter is directory-independent, so the
  fixture's `SPEC-notaspec.md` (type: issue, status: done, built to exercise
  the OLD type-only filter) is a genuine post-D1 corpus member, and the correct
  count is 4, not 3. The unmodified claim was false; `test-aai-deslop.sh:408`
  was re-baselined 3 to 4 with an inline comment naming this ride. Crossed by
  TEST-004 itself, green again at the corrected value. NOTE 2026-08-18: this
  seam used to name a second crossing, TEST-027's
  arm-survival-plus-assertion-count gate, which was meant to permit exactly
  that kind of in-place re-baseline while forbidding outright removal. That arm
  was withdrawn after four failed validation rounds (see the Spec-AC-06
  WITHDRAWN entry and registry item `fu-deslop-suite-additivity-guard`), so the
  re-baseline-versus-removal distinction is now a review convention with no
  mechanical gate. TEST-004 alone crosses this seam.
- SEAM-5 — the deslop prompt and the two suites that measure it:
  `tests/skills/test-aai-prompt-diet.sh` weighs its bytes against a headroom
  band that is currently 383 bytes from its cap in one direction, and
  `tests/skills/test-aai-advisory-skills.sh` pins its line ceiling, table shape,
  rules block and advisory isolation. A prompt rewrite is exactly how both go
  red. Crossed by TEST-029, which runs both suites rather than re-asserting
  their contents.
- SEAM-6 — the new document and the docs governance layer. A new tracked
  document under `docs/analysis/` meets the index generator, the docs audit's
  orphan and status heuristics, and the doc-number guard. `status: done` is
  chosen over `draft` deliberately: a delivered artifact left in a draft status
  is the false-open shape this repository has already been bitten by. Crossed by
  TEST-028's `docs-audit --check --strict --no-event` run.

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Status |
|----------|------------|------|----------------------|-------------|--------|
| TEST-022 | Spec-AC-01 | int  | tests/skills/test-aai-deslop.sh | run `bash tests/skills/test-aai-deslop.sh test_022_corpus_rule_and_header_agree` — over a fixture carrying one document of each admitted type in each admitted directory plus one requirement-typed document in a directory outside the allowlist, the json requirement_corpus.documents holds exactly the admitted ones, dirs types and statuses state the rule as data, and the human header line names the three directories the five types and the three statuses with no claim of type spec only | green |
| TEST-023 | Spec-AC-02 | int  | tests/skills/test-aai-deslop.sh | run `bash tests/skills/test-aai-deslop.sh test_023_change_and_rfc_documents_suppress` — over a fixture where one symbol is named only in a type change status done document and another only in a type change status draft document, the first is suppressed and the second is still reported; and over the REAL repository, none of --worktree-guard --worktree-baseline --pr-config appears in candidates while each appears in the body of a document listed in requirement_corpus.documents that lives OUTSIDE docs/specs, so the citation can only come from a document the widened corpus admits | green |
| TEST-024 | Spec-AC-03 | int  | tests/skills/test-aai-deslop.sh | run `bash tests/skills/test-aai-deslop.sh test_024_findings_document_never_suppresses` — over a fixture where a findings document outside the allowlisted directories names a symbol, that symbol is still a candidate while a symbol named in a corpus document is not; and over the REAL repository, requirement_corpus.documents contains no path under docs/analysis, docs/analysis/deslop-candidate-adjudication-20260815.md carries the ten adjudication rows and the coupling note, CHANGE-0145 carries a pointer instead of the rows, and the deslop prompt states the findings-outside-the-corpus convention | green |
| TEST-025 | Spec-AC-04 | int  | tests/skills/test-aai-deslop.sh | run `bash tests/skills/test-aai-deslop.sh test_025_unreadable_corpus_document_named` — over a fixture with one readable spec and one dangling symlink named as a markdown file under docs/specs, exit is 0, notes carries an entry beginning with the literal requirement document unreadable skipped not searched prefix naming the symlink path in posix form, and the readable document still suppresses its symbol; over a second fixture where every corpus document is unreadable, requirement_corpus.empty is true and empty_reason names the paths, still at exit 0 | green |
| TEST-026 | Spec-AC-05 | int  | tests/skills/test-aai-deslop.sh | run `bash tests/skills/test-aai-deslop.sh test_026_document_accounting_balances` — over a fixture carrying one included document, one per excluded status, one with a status outside the closed list, one with a type outside the requirement set, one with no parsable frontmatter and one unreadable, each bucket equals 1 and examined equals count plus the sum of every excluded value; the same equation holds over the REAL repository; the human header prints the examined count and every bucket; and a --diff run over a fixture whose STATE names one readable and one unreadable document emits the same excluded key set and balances the same equation with unreadable counted rather than zeroed; and an --all run over a fixture whose only readable corpus document is a draft and whose second corpus entry is a dangling symlink reports count 0 examined 2 draft 1 unreadable 1, emits the same excluded key set, prints the examined count and the full bucket line as whole-line matches in the human header and balances the same equation, so an --all corpus that is empty BY FILTER while carrying an unreadable member can never fall back to an excluded block that zeroes a bucket beside a non-zero examined | green |
| TEST-020 | Spec-AC-05 | int  | tests/skills/test-aai-deslop.sh | run `bash tests/skills/test-aai-deslop.sh test_020_unreadable_state_corpus_document_named` — a pre-existing SPEC-0132 arm, extended here: over its fully-stale-STATE fixture (both current_focus paths naming documents that do not exist) the --diff payload reports count 0, examined 2, excluded.unreadable 2 and balances the equation, so the FULLY-unreadable --diff branch counts the documents its own empty_reason names instead of zeroing the bucket beside them | green |
| TEST-005 | Spec-AC-06 | int  | tests/skills/test-aai-deslop.sh | run `bash tests/skills/test-aai-deslop.sh test_005_no_write_proof` — a sha256 content manifest AND the sorted file list of a fixture tree are captured before and after both scopes run against it, and both are identical afterwards, so a byte rewritten in place or a newly created path under the fixture root turns the arm red | green |
| TEST-006 | Spec-AC-06 | int  | tests/skills/test-aai-deslop.sh | run `bash tests/skills/test-aai-deslop.sh test_006_exit_code_contract` — exit is 0 for a clean run with no candidates, for a run with candidates and for a run over an empty input set, exit is 2 for an unknown flag, and a source-level scan of the engine finds no process.exit call carrying a value other than 0 or 2 | green |
| TEST-028 | Spec-AC-07 | int  | tests/skills/test-aai-deslop.sh | run `bash tests/skills/test-aai-deslop.sh test_028_published_surfaces_state_the_new_rule` — the deslop prompt, docs/product/aai-deslop.md and the engine header comment carry no claim that the corpus is docs/specs or type spec only and each names the three directories, SPEC-0132 carries a dated Correction section and four inline superseded pointers with its historical measurements unchanged, CHANGELOG carries one new unreleased heading whose counts equal the post-change json capture, the v2026.08.16 section is byte-identical to `git show <base>:CHANGELOG.md` with `<base>` resolving origin/main then main (a message naming an unresolvable ref when that is the real cause, never a false byte-difference claim, and a fail-closed result when neither ref resolves), the product doc frontmatter delivered_by and updated are bumped, and `node .aai/scripts/docs-audit.mjs --check --strict --no-event` and `node .aai/scripts/spec-lint.mjs` are both clean | green |
| TEST-029 | Spec-AC-08 | int  | tests/skills/test-aai-prompt-diet.sh | run `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh` and `... tests/skills/test-aai-advisory-skills.sh` — both exit 0, TEST-010 reports headroom inside 0 to 2048, TEST-012's pin equals the independent re-sum of JUSTIFIED_ADDITIONS after the measured byte delta is credited 1:1, the four advisory-skills deslop pins still hold, and `node .aai/scripts/check-test-registration.mjs` exits 0 | green |
| TEST-030 | Spec-AC-08 | int  | tests/skills/test-aai-deslop.sh | run `bash tests/skills/test-aai-deslop.sh test_030_registry_items_closed` — `node .aai/scripts/follow-ups.mjs list --status open --json` names none of fu-deslop-all-corpus-specs-only fu-deslop-allcorpus-unreadable-silent fu-deslop-corpus-header-other-bucket or fu-deslop-adjudication-self-suppression, and each of the four appears with status done and a resolved_by naming this scope under `--status all` | green |

Failing-first discipline (strategy `direct`, so exit codes are the record, not a
stored artifact). All three defects were reproduced read-only against the
current tree on 2026-08-18 before this spec was written, and the transcripts are
quoted in the Summary. TEST-022, TEST-024 through TEST-026, TEST-028 and
TEST-030 each assert on an observable that does not exist on the pre-change
tree — a corpus containing an issue document, a findings document outside the
corpus, the unreadable note under `--all`, an `examined` field, the new
document text, and four closed registry items — so each fails naturally before
the edit. Run every one of those six on the unmodified tree FIRST, capture the
non-zero exit code and the failing assertion line, and record both in the
Implementation return record's `evidence` list beside the passing run. An arm
that cannot be shown failing before the edit must be reported as such rather
than counted as proof.

CORRECTED during remediation (deslop-corpus-honesty ride, 2026-08-18, finding
V-2): TEST-023's fixture half (`--flag-done` suppressed, `--flag-draft` still
reported) is genuinely failing-first and is unaffected by this correction. Its
REAL-TREE arm — "the three symbols the intake named are gone from
candidates" — is NOT failing-first on THIS tree, because this scope's own
draft spec (`docs/specs/SPEC-0136-spec-deslop-corpus-honesty.md`, `type:
spec`, `status: implementing`, under `docs/specs`) is itself a corpus member
under BOTH the old and the new rule and names all three symbols in its
Summary. Measured directly: running the PRE-change engine
(`git show main:.aai/scripts/deslop-unrequested.mjs`) against the CURRENT
working tree already reports all three symbols absent, before any code
changed — the observable this arm asserts already existed pre-change on this
particular tree. What the real-tree arm of TEST-023 actually verifies, stated
plainly, is a POST-change correctness check: on the tree as it stands at
verification time, none of the three symbols are candidates, and each is
genuinely named in a document `requirement_corpus.documents` lists — i.e. the
suppression is for the right, cited reason, not an accident of a stale
fixture. The true failing-first evidence for Spec-AC-02's real-repo claim
requires a tree that does NOT yet contain this ride's own spec: a pristine
`main` export (`git archive main | tar -x`) with the pre-change engine reports
all three symbols PRESENT; the same export with the shipped engine reports
them ABSENT. That pristine-export pair, not the real-tree arm inside TEST-023,
is the genuine RED-then-GREEN observation for this AC.

ADDED 2026-08-19 (round-6 validation V-3, non-blocking, dispositioned rather
than left silent). The real-tree citation loop of TEST-023 is coupled to two
specific documents: `--worktree-guard` and `--worktree-baseline` are each cited
outside `docs/specs` only by `docs/issues/CHANGE-0125-adopt-v2-planning.md`, and
`--pr-config` only by `docs/issues/CHANGE-0096-github-no-bots-hardening.md`.
A status flip, archive or move on either turns the loop red for a reason that
has nothing to do with the corpus rule, and the arm's OTHER real-tree assertion
(all three symbols absent from `candidates`) will not go red with it, because
this ride's own spec keeps them suppressed from `docs/specs`. The loop still
fails closed — a genuine D1 revert must stay red — but it now distinguishes the
two worlds in its failure message. The discriminator is
`requirement_corpus.dirs`, not the mere existence of a citing file: with D1
reverted `CHANGE-0125` still sits under `docs/issues` and still names the
symbol, so "a file names it but no corpus member does" describes a regression
and a drifted citation equally well. When the payload no longer declares BOTH
`docs/issues` and `docs/rfc` the message says the corpus rule regressed; when it
still declares both and a `docs/issues`/`docs/rfc` document names the symbol
without being a corpus member, the message says citation drift and names the
drifted paths. The residual coupling is filed as
`fu-deslop-ac02-single-citation` (P3). Both branches were exercised in a
scratchpad copy — D1 reverted, and the three citing documents flipped to
`draft` — and each fails closed with the right message; neither is reachable
from a green run.

CORRECTED AGAIN 2026-08-19 (round-5 review NB-1). The paragraph above described
the tautology accurately but left it in the suite. The real-tree arm now
requires each of the three symbols to be cited by a corpus document OUTSIDE
`docs/specs`, which this ride's own draft spec cannot satisfy. Proven to bite:
with D1 reverted in a scratchpad copy (`CORPUS_DIRS` back to `docs/specs`
alone), TEST-023 goes RED with all three symbols reported as uncited; with D1
in place it is green. The arm is therefore a real post-change check of the
widened corpus rather than a restatement of a pre-existing tree property. The
pristine-export pair described above remains the cleanest failing-first
evidence and is unaffected.

TEST-005 and TEST-006 are pre-existing regression rows and cannot fail before
the change: an identical fixture manifest and the unchanged exit-code contract
are their evidence, and both were already green on the pre-change tree. (They
replace what used to be a single TEST-027 row here. TEST-027 was withdrawn on
2026-08-18 after four mechanizations failed independent validation four times;
the numbering gap between TEST-026 and TEST-028 is left in place deliberately,
since renumbering would churn every reference for no gain.) TEST-029 is
also regression-only unless the measured byte delta moves the pin, in which case
it goes red on the growth before the ledger entry lands, exactly as the diet
guard is designed to.

## Verification

Run whatever the selector returns — NOT a hand-picked list — AND the two suites
the selector has already been proven not to cover. Both halves of this
instruction are recorded here so the next role inherits them rather than
depending on a dispatch to remember:

```
node .aai/scripts/select-suites.mjs --files-from <the actual changed-file list>
```

Measured during planning against the expected file list, the selector answers
`FULL_RUN reason=unmapped` because `docs/analysis/**` carries no suite-map row
(D2). Against the same list minus that one path it returns CORE
`aai-check-state`, `aai-docs-audit`, `aai-spec-lint` plus SELECTED
`aai-deslop` and `aai-release`. That is the expected shape, not the authority —
re-run the selector against the ACTUAL changed files and run everything it
returns.

Regardless of what the selector returns, ALSO run
`tests/skills/test-aai-layer-profiles.sh` and
`tests/skills/test-aai-feedback-upsert.sh`. The two preceding rides proved the
selector's list is not a superset of what CI runs, and a CORE suite skipped
during validation is what failed CI on CHANGE-0148.

Commands:
- `node .aai/scripts/select-suites.mjs --files-from <actual changed files>`,
  then `bash .aai/scripts/aai-run-tests.sh bash tests/skills/<suite>.sh` for
  EVERY suite it returns, CORE rows included
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-deslop.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-advisory-skills.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-layer-profiles.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-feedback-upsert.sh`
- `node .aai/scripts/check-test-registration.mjs`
- `node .aai/scripts/deslop-unrequested.mjs --all --json` over this repository,
  recording the post-change candidate count, suppressed count, corpus count and
  examined count as the numbers the product doc and the CHANGELOG entry must
  carry — measured, never copied from this document's planning probes
- `node .aai/scripts/follow-ups.mjs list --status open` over this repository
- `git diff --numstat main -- tests/skills/test-aai-deslop.sh` (informational
  only — a raw deletion count cannot tell coverage removed from coverage
  re-baselined, which is why it was rejected pre-ship. Nothing mechanically
  gates suite additivity any more: the in-suite replacement, TEST-027, was
  withdrawn on 2026-08-18 after four failed validation rounds. Read this
  number, and the removal of TEST-027 itself, by hand at review time. See the
  Spec-AC-06 WITHDRAWN entry and `fu-deslop-suite-additivity-guard`)
- `git diff main -- CHANGELOG.md`
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` and
  `node .aai/scripts/spec-lint.mjs`

Every fixture probe runs in a scratch temp directory. This repository is READ
by the real-tree arms and never written by the engine, and no restoring git
command is run against a tracked file here.

Evidence artifacts: the selector output naming the suites actually run, suite
stdout with per-TEST pass lines, the failing-first exit codes recorded in the
Implementation return record, the post-change `--all --json` capture, the two
git diff outputs, and the scope diff listing.

PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status.

## Evidence contract

Per artifact record: ref_id `deslop-corpus-honesty`, Spec-AC and TEST-xxx links,
command or review scope, exit code or review verdict, evidence path, commit SHA
or diff range when available.

### Evidence by strategy

Strategy is `direct`: what this spec demands is the targeted regression arms
green with their exit codes, the failing-first exit codes named above recorded
in the return record, the post-change measurement capture, and the scoped diff.
No stored per-test RED artifact and no verification matrix beyond the commands
listed under Verification.

## Residual risks

- R1 — Widening the corpus raises prose suppression generally, not only for the
  symbols a requirement genuinely names. Measured on the live tree with the
  adjudication table relocated, suppressed rises from 408 to 417 while
  candidates fall from 65 to 56; 3 of those 9 rows are the named defect and 6
  are other symbols a change or RFC document mentions. The engine already
  discloses this class every run as the second LIMITS line with its numeric
  count, and that disclosure is unchanged. Accepted, and quantified rather than
  hidden.
- R2 — The relocation fixes the instance, and the prompt convention line makes
  it a rule, but nothing mechanically stops a future author writing a findings
  table into a spec or a change document. The general property is disclosed by
  the second LIMITS line and the convention is written where an agent running
  the pass will read it. A mechanical guard would be a marker mechanism, which
  D2 refuses. Accepted, and the reason it is accepted is recorded so a later
  reader does not read the silence as an oversight.
- R3 — `docs/analysis/**` is unmapped in `tests/skills/suite-map.yaml`, so any
  changed-file list containing the new document escalates CI selection to
  FULL_RUN. Strictly safer, slower, and cheaper than adding an unrequested
  mapping row. Accepted and named.
- R4 — The directory allowlist is exact today (fact 5) but is a list, and a
  future project could put a requirement document somewhere else. The failure
  mode is a false positive, which is the safe direction for this detector, and
  the header now prints the directories it read so the omission is visible in
  every run rather than buried in the source. Accepted.
- R5 — `status: draft` intakes are outside the `--all` corpus, so a flag
  requested in the ride currently in flight still reports as a candidate under
  the wide scope. That is deliberate and matches SPEC-0132's D2 reasoning, and
  `--diff` covers exactly that case by reading `primary_path` from STATE.
  Asserted as intended behavior in TEST-023 rather than left as an unstated
  edge. Accepted.

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
Two items in the inputs are deliberately contradicted above, with reasons: the
intake's framing of D1 as a corpus-width question is narrowed to a corpus-meaning
question whose remedy includes relocating a document (D2), and
`fu-deslop-corpus-header-other-bucket`'s own filed claim that the accounting gap
is latent is wrong — the live residue is 2 documents today (Summary fact 3).
