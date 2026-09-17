---
id: spec-close-ceremony-sweep
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: 76c268194f03ac3e346438306381a09db78fd4be0631ce81fe8f6234a15426b2
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-DRAFT-close-ceremony-sweep.md
  rfc: null
  pr: []
  commits: []
---

# Spec — the close ceremony, the docs audit and the generated pages agree with git

SPEC-FROZEN: true

## Links
- Requirement (primary path, unnumbered by design — `allocate-doc-number.mjs`
  assigns the number at the PR and renames the file, so every in-branch
  reference below uses the DRAFT path):
  docs/issues/CHANGE-DRAFT-close-ceremony-sweep.md
- Paired maintenance half: docs/issues/CHANGE-0184-roadmap-gate-admits-only-the-next-pair.md
- Also carried in full: docs/issues/ISSUE-0042-intake-doc-identity-table-and-its-pins.md
- Mandate: docs/project-sessions/2026-09-13-wave-3-subsystem-sweeps.md (sweep 4)
- Roadmap: docs/ai/roadmap.yaml (pair 8, `close-ceremony-sweep` paired with
  `roadmap-gate-admits-only-the-next-pair`, status `planned`)
- Sweep 2 (merged): docs/specs/SPEC-0179-spec-test-framework-sweep.md
- Sweep 3 (merged): docs/specs/SPEC-0180-spec-dispatch-state-sweep.md
- Mutation gate (merged; this is the first sweep planned under it):
  docs/specs/SPEC-0181-spec-mutation-gate-for-tests.md
- Technology contract: docs/TECHNOLOGY.md
- Ceremony table: .aai/workflow/WORKFLOW.md "Ceremony levels"

## Implementation strategy
- Strategy: tdd
- Rationale: recorded at intake ("Ceremony 2, TDD, mutation checks"). Every
  acceptance criterion here is a REFUSAL or a DERIVATION: a gate that must exit
  non-zero on a state it has never been observed refusing, or a page that must
  be built from a source it has never been observed refusing to read. Three of
  the four defects this sweep exists to remove are gates that printed CLEAN, and
  a green run of such a gate is not evidence of anything. The Mutation column
  makes the RED observation non-optional for every row.

## Isolation and review
- Worktree recommendation: required
- Worktree rationale: this scope edits the close ceremony that its own PR runs
  through — `close-work-item.mjs` (content-hash pinned by
  `tests/skills/lib/close-work-item-pin.sh`, sourced by four suites),
  `close-reconcile.mjs`, `nothing-left-behind.mjs`, `check-committed-scope.mjs`
  and `spec-amend.mjs`, the tool that decides whether this very spec may close.
  A half-applied edit inline does not fail a test; it breaks the ceremony that
  would have reported the failure, for every concurrent ride in the shared
  checkout.
- User decision: worktree
- Base ref: main (7270a29c)
- Worktree branch/path: feat/close-ceremony-sweep / ../aai-feat-close-ceremony-sweep
- Inline review scope: not applicable (worktree)

## Ceremony level

`ceremony_level: 2`. The scope deliberately excludes every `protected_paths_l3`
surface named in `docs/ai/docs-audit.yaml`: `state.mjs`, `lib/state-engine.mjs`,
`lib/state-core.mjs`, `allocate-doc-number.mjs`, `pre-commit-checks.sh`,
`pre-commit-checks.ps1`, `.aai/workflow/WORKFLOW.md`, `docs/CONSTITUTION.md`.
Five registry items in this subsystem's bucket need one of those files. They are
deferred BY NAME in `## Registry items deferred to a ceremony-3 ride` below,
stay OPEN, and are re-filed as one owner-schedulable item — not smuggled in
here under a level-2 declaration.

## What is established before this scope starts

Measured on this branch (`a4eca58d`, main `7270a29c` plus the intake commit)
with the named commands and `/usr/bin/grep`, at planning on 2026-09-17.

M1. The registry holds 107 open follow-ups (`node .aai/scripts/follow-ups.mjs
list --status open`: `shown=107 open=107 closed=332 total=439`). The intake's
named bucket is partly STALE: of the ids it names individually, two are already
terminal (`fu-registry-has-no-reopen`, and `fu-closeworkitem-pin-tail-wording`,
closed by SPEC-0181). The set this spec freezes is re-derived from the LIVE open
set, never copied from the intake.

M2. Two delivered maintenance halves sit on main at `status: draft` with empty
`links.pr` and `links.commits`:
`docs/issues/CHANGE-0181-unrecorded-spec-amendment-is-invisible.md` (delivered
by PR 384, merge commit 7270a29c) and
`docs/issues/ISSUE-0040-focus-and-validation-state-go-stale-silently.md`
(delivered by PR 382, merge commit e6aae10b). Both gates that exist to find
exactly this say nothing. `node .aai/scripts/docs-audit.mjs --check` reports
`Scanned: 504 docs ... False-open: 0` and `Verdict: CLEAN`;
`node .aai/scripts/close-reconcile.mjs --check --range 94a983ec..HEAD` prints
`close-reconcile: CLEAN` with rc 0. That is
`fu-close-reconcile-pair-id-convention` and `fu-close-gate-unpaired-draft-intake`
in the flesh, on the two most recent rides in this repository.

M3. `node .aai/scripts/spec-amend.mjs list --strict` reports
`spec_scanned=175 spec_degraded=174 (no freeze anchor)`. Exactly one spec in the
corpus (SPEC-0181) carries `frozen_sha256`, so SPEC-0181's `undisclosed-amendment`
arm is real only for specs frozen from now on — of which THIS spec is the first.
That is why `fu-numbering-rewrites-frozen-spec-body` (P2) is a precondition of
this ride closing at all: at the PR ceremony the allocator rewrites the literal
`SPEC-DRAFT-` paths inside this frozen spec's own body, the anchor stops
matching, and the strict gate refuses the ride.

M4. Prompt-diet headroom is 2046 of a 2048 cap, measured with the suite's own
`compute_reduction_headroom`: `after=340425 extra=19140 credit=32826
reduction=30718`. Two bytes of slack. Any edit to `.aai/*.prompt.md`,
`.aai/AGENTS.md` or the three extras (`.aai/INTAKE_COMMON.md`,
`.aai/STATE_FALLBACK.md`, `.aai/ROLE_COMMON.md`) needs a 1:1 ledger entry and a
TEST-012 pin move, in either direction. `.aai/SUBAGENT_CONTRACT.md` and
`.aai/templates/**` are in neither the glob nor the extras and carry no ledger
cost.

M5. `docs/ai/roadmap.yaml` pair 7 (`mutation-gate-for-tests` paired with
`unrecorded-spec-amendment-is-invisible`) is still `status: active`, because its
maintenance half is one of M2's drafts. `node .aai/scripts/ride-select.mjs gate
--ref close-ceremony-sweep` currently ADMITs. Under Spec-AC-29 admission of a
`planned` pair requires every earlier pair to be done, so closing CHANGE-0181 is
not bookkeeping: it is what keeps this sweep's successor admissible.

M6. `.aai/scripts/close-work-item.mjs` is 2021 lines and content-hash pinned by
`tests/skills/lib/close-work-item-pin.sh` (3 allowed hashes today), sourced by
four suites. Every change this scope makes to that file is batched and ONE new
pin entry is written LAST (Spec-AC-09).

M7. Exactly ONE tracked file in the repository contains a literal NUL byte:
`.aai/scripts/spec-amend.mjs` line 253 (`git ls-files -z` piped through a perl
`/\x00/` probe; the same probe over every other tracked file returns nothing).
Every prose or `/usr/bin/grep` guard over that file is silently blind today —
grep answers `Binary file .aai/scripts/spec-amend.mjs matches`.

M8. None of the three generated pages enumerates tracked content:
`generate-docs-index.mjs` walks the working tree through `docs-model.mjs`'s
`walk()` (`main()` loop, `docs-model.mjs:581-591`), `generate-overview.mjs`
`readdirSync`s per directory (`scanDocs`, `:83-88`), and
`generate-factory-report.mjs` does the same for `docs/releases`
(`releaseMembership`, `:212-216`). The committed `docs/ai/overview-data.json` on
main carries `current_focus = {"ref":"mutation-gate-for-tests", ...}` — one
machine's untracked `docs/ai/STATE.yaml`, baked into a tracked artefact.

M9. A shape check for issue 370 would newly flag exactly 8 documents (probe over
all 504 scanned docs), all `status: done`, all carrying `AC / Status / Evidence`
instead of the canonical six-column set; the status-vocabulary arm would flag 0.
So the check is safe to ship report-only with a `--strict` promotion.

## Decisions

D1. CEREMONY 2 IS A BOUNDARY, NOT A PREFERENCE. An item whose only fix edits a
`protected_paths_l3` path is deferred by name, left OPEN in the registry, and
re-filed once as `fu-l3-surfaces-owed-a-ceremony-3-ride`. Five items take that
route (D2). Nothing in this scope writes to those eight paths, and the review
scope excludes them so a stray edit is visible.

D2. THE ALLOCATOR HAZARD IS REMOVED WITHOUT TOUCHING THE ALLOCATOR.
`fu-numbering-rewrites-frozen-spec-body` names two possible fixes: carve
frozen specs out of the allocator's rewrite trees (L3), or make the rewrite a
DISCLOSED amendment. This scope takes the second: `spec-amend.mjs` grows a
`restamp` subcommand that re-anchors a frozen spec whose only change is an
allocator DRAFT-to-numbered path rewrite, recording the from/to anchors in the
ledger; `.aai/SKILL_PR.prompt.md` step 1b runs it immediately after allocation.
The allocator-side carve stays open under D1. The three sibling allocator items
(`fu-typemap-missing-research-hotfix`, `fu-numbering-rewrites-dated-reports`,
`fu-realpath-allocate-doc-number-l3`) have no non-L3 remedy and are deferred
whole.

D3. ONE TRACKED-CONTENT ENUMERATOR, NOT THREE. The tracked-only walk lands once
in `.aai/scripts/lib/docs-model.mjs` (next to the `walk()` it replaces), copying
the `git ls-files -z` shape `allocate-doc-number.mjs` already uses for its own
guard, and degrading to today's working-tree walk outside a git work tree with a
named NOTE. `generate-docs-index.mjs` and `generate-overview.mjs` both call it.
`generate-factory-report.mjs`'s `releaseMembership` is converted in the same
pass so the three pages cannot diverge again.

D4. THE PAIR IS PART OF THE TRANSACTION, AND ALSO PART OF THE PUSH GATE. Closing
the paired maintenance half is added to `close-work-item.mjs` as an explicit
`--paired <slug>` that joins the SAME snapshot/rollback transaction as `--ref`
and `--spec` (never a second invocation, which could half-close). Because a flag
can be forgotten, `nothing-left-behind.mjs` independently lists a still-open
roadmap-paired half in its `docs_open` class, so the omission stops the push
rather than surviving to main. Two gates, one from the writer's side and one
from the reader's, is the shape M2 proves is needed.

D5. A GATE MAY NOT DECIDE ON WHAT IT WAS HANDED. `nothing-left-behind.mjs` takes
`--ref` on trust today. It keeps the flag, but cross-checks it against
`docs/ai/STATE.yaml` `current_focus.ref_id` and reports a mismatch as an item
rather than printing CLEAN for a ref nobody is shipping. It reads STATE and
never writes it, so Constitution article 6 and the L3 boundary both hold.

D6. THE REGISTRY CLASS READS IDENTITY, NOT A PREFIX. Class 4 keeps
`CEREMONY_FOLLOW_UP_ID_PREFIXES` as a fast path (TEST-008 pins the literal), and
adds a second, content-side arm over `finding`, so an item filed under an
unlisted subject is still caught. Widening the prefix list alone would repeat
`fu-registry-class-trusts-the-filer-id` one subject later.

D7. THE SHAPE CHECK FOR ISSUE 370 IS REPORT-ONLY BY DEFAULT. It lands in
`detectNearMissAcTable` (the existing shape authority) as two new `kind`s,
`column-set` and `status-vocabulary`, surfaces in docs-audit's existing
`### Near-miss AC tables` section, and is promoted to a hard failure only under
`--strict`. M9 measured the live yield at 8 documents, all `done`; promoting it
to a blocking default would redden CI for eight historical docs this ride does
not own.

D8. ONE RE-PIN, WRITTEN LAST. Every change to `close-work-item.mjs` (Spec-AC-06,
07, 08) is batched. The new entry in `tests/skills/lib/close-work-item-pin.sh`
is the LAST edit of the whole ride, after the final TDD run, and its prose
re-affirms both frozen invariants (the 0-to-5 exit contract with the D6
snapshot/rollback transaction and its regen tail; and no `--resolves` wiring
into `follow-ups.mjs`).

D9. THE TWO STALE HALVES ARE FIXED AS DATA, NOT AS A DEMONSTRATION.
CHANGE-0181 and ISSUE-0040 are closed with their real PR numbers and merge
commits through the ceremony this ride is fixing, and `docs/ai/roadmap.yaml`
pair 7 flips to `done`. A code fix that leaves M2's two documents wrong would be
a gate that works on fixtures only.

D10. PROMPT BYTES ARE BUDGETED BEFORE THEY ARE SPENT. M4 leaves two bytes. The
planned in-glob edits are `.aai/SKILL_PR.prompt.md` (step 1b restamp line, step
4c paired-half flag, step 4a/4c/5c committed-blob verification, a pre-push
shared-page conflict check), `.aai/VALIDATION.prompt.md` (one reframed sentence)
and `.aai/SKILL_INTAKE.prompt.md` (the duplicated STEP 0 stanza deleted, -148 B
measured). The planned net is a growth of roughly 1100 to 1500 B; the exact
measured delta is credited 1:1 in ONE new `JUSTIFIED_ADDITIONS` entry and the
TEST-012 pin moves from 32826 by exactly that amount. A net SHRINK is handled the
same way with a negative reclaim entry — headroom must land back at 2046, not
above the 2048 cap.

D11. NO PIPE CHARACTERS IN ANY TABLE CELL OF THIS SPEC, and
`node .aai/scripts/spec-lint.mjs --path <this spec>` is run after every table
edit. `fu-gate-ac-duplicate-id-pipe-drop` is in this scope precisely because a
dropped pipe-broken row reads as CLEAN today.

D12. EVERY TEST PLAN ROW OWNS ITS OWN SELECTOR. `fu-mutation-rows-share-selectors`
recorded the attribution risk of two rows pointing at one test function; no row
below shares a selector with another row.

## Constitution deviations

None. Article 6 (single-writer state) is respected: Spec-AC-02 READS
`docs/ai/STATE.yaml` and writes nothing. Article 7 (operator-only merge) is
unchanged. Article 5 (additive first) holds: `--paired` and `restamp` are new
optional surfaces, and no existing step number in `.aai/SKILL_PR.prompt.md` is
renumbered.

## Acceptance Criteria Mapping

- Spec-AC-01: WHEN `check-committed-scope.mjs --from-state` reads a
  `code_review.scope` stored as a YAML folded block of space-separated paths,
  the system SHALL check every path in it, and SHALL NOT exit 0 on a
  NOTHING CHECKED result with or without `--strict`.
  Verification: a STATE fixture with three space-separated in-scope paths;
  the run names all three as checked, and a fixture with zero resolvable paths
  exits non-zero without `--strict`.

- Spec-AC-02: WHEN `nothing-left-behind.mjs` is given a `--ref` that disagrees
  with `docs/ai/STATE.yaml` `current_focus.ref_id`, the system SHALL report an
  item naming both refs instead of printing CLEAN; and its registry class SHALL
  match a follow-up whose `ref_id` is the doc's display id as well as its slug,
  and SHALL classify from the item's `finding` as well as from the id prefix.
  Verification: three fixtures — a mismatched ref, an item filed
  `--ref CHANGE-0178`, and a ceremony item filed under an unlisted subject.

- Spec-AC-03: WHEN the roadmap pairs the ride being closed with a maintenance
  half whose doc is not terminal, `nothing-left-behind.mjs` SHALL list that half
  in `docs_open` and exit LEFT BEHIND.
  Verification: a roadmap fixture plus a draft maintenance doc; the gate names
  the half. With the half terminal, the same fixture is CLEAN.

- Spec-AC-04: `close-reconcile.mjs --check` SHALL item (a) a doc that is already
  terminal at the range's delivery sha but carries no `links.commits` and no
  `work_item_closed` event, and (b) a non-terminal doc whose frontmatter id a
  range commit names and which has NO paired spec at all.
  Verification: replaying the real ranges of PRs 382 and 384 names
  `focus-and-validation-state-go-stale-silently` and
  `unrecorded-spec-amendment-is-invisible`; the same run on a fully closed pair
  stays CLEAN.

- Spec-AC-05: WHEN a spec and its primary doc do not follow the literal
  `spec-<primary id>` convention, `close-reconcile.mjs` SHALL still pair them via
  the spec's `links.requirement`, and `--apply` SHALL close both halves.
  Verification: a fixture pair named off-convention; `--apply` closes both and a
  second `--check` is CLEAN for the right reason, not for an empty candidate set.

- Spec-AC-06: `close-work-item.mjs --paired <slug>` SHALL close the paired
  maintenance half inside the SAME snapshot-and-rollback transaction as `--ref`
  and `--spec`, and a failure on any one of the three SHALL leave all three
  documents byte-identical to their pre-run state.
  Verification: a three-doc fixture where the paired half is forced to fail the
  post-close audit; all three docs and the EVENTS byte length are unchanged.

- Spec-AC-07: `close-work-item.mjs` SHALL print the remediation commands it had
  already planned when the state-reconcile step skips, and its mutation-gate
  notice SHALL name the `exempt`, `degraded` and `unstamped` counts it collects.
  Verification: a fixture that trips the second reconcile arm after the first
  planned a `set-phase`; the warning carries that command. A second fixture with
  one exempt and one unstamped row shows both numbers in the notice.

- Spec-AC-08: WHEN a product doc under `docs/product/` shares a frontmatter id
  with the ride's intake doc, the post-close self-verify SHALL resolve the doc it
  audits by PATH, so the close does not roll back forever.
  Verification: a fixture intake plus a same-id product doc; the close exits 0
  and the doc statuses are flipped. The fixture is built so the readdir order
  that decides today's `.find` is the adverse one.

- Spec-AC-09: `tests/skills/lib/close-work-item-pin.sh` SHALL carry exactly ONE
  new allowed hash covering every byte this ride changes in
  `.aai/scripts/close-work-item.mjs`, and its entry SHALL re-affirm both frozen
  invariants in prose.
  Verification: `sha256sum .aai/scripts/close-work-item.mjs` equals exactly one
  entry, the file's allowed-hash array grew by exactly one, and the four suites
  that source it pass.

- Spec-AC-10: `docs/issues/CHANGE-0181-unrecorded-spec-amendment-is-invisible.md`
  and `docs/issues/ISSUE-0040-focus-and-validation-state-go-stale-silently.md`
  SHALL be terminal with their real PR numbers and merge commits in `links`, and
  `docs/ai/roadmap.yaml` pair 7 SHALL read `status: done`.
  Verification: frontmatter `status` is `done`, `links.pr` contains 384 and 382
  respectively, `links.commits` contains 7270a29c and e6aae10b, and
  `node .aai/scripts/ride-select.mjs validate` passes.

- Spec-AC-11: WHEN a document carries an Acceptance Criteria table that is
  PRESENT but unparseable — a column set neither the canonical nor the lean
  parser accepts, or a status word outside
  `planned/implementing/done/deferred/blocked/rejected` — `docs-audit.mjs`
  SHALL report it under `### Near-miss AC tables` naming the document, the kind
  and the offending cell, report-only by default and hard-failing under
  `--strict`.
  Verification: the three-column `AC / Requirement / Status` shape from issue
  370 with every row `green` is named; a run over the live corpus names exactly
  the 8 documents of M9 and exits 0 without `--strict`.

- Spec-AC-12: `docs-audit.mjs --gate` SHALL reconcile declared Spec-AC ids by
  MULTIPLICITY, so a duplicate id whose one pipe-broken copy is non-terminal
  fails the gate instead of passing on the terminal copy.
  Verification: a spec fixture with `Spec-AC-01` twice, one row pipe-broken and
  `planned`; `--gate` exits non-zero naming the id, and `--check` is not CLEAN.

- Spec-AC-13: `docs-audit.mjs --ac-flip-check` SHALL see a premature flip in a
  LEAN ceremony-0/1 AC table, and a lean table under the heading
  `## Acceptance Criteria` SHALL NOT be reported as a near-miss by the shape
  check that the gate simultaneously accepts.
  Verification: a lean fixture with a `done` row and delivery-shaped Evidence on
  an open doc is flagged; the same lean fixture without the flip is silent from
  both authorities.

- Spec-AC-14: `spec-lint.mjs` SHALL mask code specimens through the SAME
  implementation `lib/docs-audit-core.mjs` uses, and its local copy SHALL be
  gone.
  Verification: `/usr/bin/grep -c 'maskCodeSpecimens' .aai/scripts/spec-lint.mjs`
  is 0; a triple-backtick inline run no longer swallows a following live
  `NEEDS-CLARIFICATION` marker, and a four-backtick fenced specimen no longer
  leaks as live.

- Spec-AC-15: `docs-audit.mjs` SHALL resolve the id-mention date for the whole
  corpus with ONE `git log` invocation, not one per document.
  Verification: a counting `git` shim on PATH records exactly one `log` call
  carrying no `--grep`, over a fixture corpus of at least three docs, and the
  reported dates equal today's per-doc results.

- Spec-AC-16: The done-row Evidence shape SHALL be stated identically by
  `.aai/templates/SPEC_TEMPLATE.md`, `.aai/ROLE_COMMON.md` and
  `.aai/VALIDATION.prompt.md` — a `docs/ai/tdd/` artifact at hand-off, the
  delivery citation written by the close flip — with no surviving sentence
  offering a commit SHA or calling a non-terminal row the expected state.
  Verification: a suite arm reads all three files and fails on either legacy
  phrasing; `/usr/bin/grep -c 'commit SHA or RUN_ID' .aai/templates/SPEC_TEMPLATE.md`
  is 0.

- Spec-AC-17: `follow-ups.mjs verify-closures` SHALL refuse `--strict=<value>`
  as a usage error, SHALL refuse a corpus run whose document roots resolve to
  nothing, SHALL scan claims appearing before the first CLOSED label, SHALL read
  a bulleted claim list separated from its label by a blank line, and SHALL NOT
  turn an explicit NOT CLOSED disclosure in the same paragraph into a claim.
  Verification: five fixtures, one per clause, each asserting the exit code and
  the named ids.

- Spec-AC-18: WHEN a report names a follow-up id longer than the registry's
  40-character cap, `verify-closures` SHALL report it as unfilable, naming the
  length and the cap, distinctly from an absent item.
  Verification: a report fixture with a 52-character id; the output carries the
  word `unfilable` and both numbers, and a filable-but-absent id still reads
  `absent`.

- Spec-AC-19: A `spec_amendment` record SHALL carry the `from` and `to`
  `frozen_sha256` anchors of the restamp it explains, and the spec write SHALL be
  atomic (temporary file plus rename in the same directory).
  Verification: the appended JSON line carries both keys with 64-hex values; a
  write interrupted after the ledger append leaves the spec byte-identical.

- Spec-AC-20: WHEN the allocator has rewritten `SPEC-DRAFT-` paths inside a spec
  that carries `frozen_sha256`, `spec-amend.mjs restamp` SHALL re-anchor it and
  record the mechanical cause, so `spec-amend.mjs list --strict` does not refuse
  the ride as `undisclosed-amendment`, and `.aai/SKILL_PR.prompt.md` step 1b
  SHALL invoke it immediately after allocation.
  Verification: a frozen fixture spec is renumbered, `restamp` is run, and
  `list --strict` exits 0; without the restamp the same sequence exits 1 naming
  `undisclosed-amendment`.

- Spec-AC-21: A verbatim copy of every intake template SHALL pass
  `docs-audit.mjs --intake-file` with no hand edit.
  Verification: each of the eight templates is copied to its DRAFT path in a
  fixture and audited; all exit 0, and `/usr/bin/grep -c '^number:'` over the
  templates returns 1 for every one of them.

- Spec-AC-22: `generate-docs-index.mjs` and `generate-overview.mjs` SHALL
  enumerate tracked documents only, and SHALL name the degradation when they
  cannot consult git.
  Verification: a fixture repository with one tracked and one untracked doc; the
  regenerated INDEX and overview name the tracked doc only, and a run outside a
  git work tree prints a NOTE naming the fallback.

- Spec-AC-23: The TRACKED overview artefacts SHALL NOT carry values derived from
  the untracked `docs/ai/STATE.yaml`.
  Verification: with STATE present and untracked, `overview-data.json` carries no
  `current_focus`/`in_flight` values; the repository's own committed
  `overview-data.json` is regenerated and no longer names a local focus.

- Spec-AC-24: A degraded input SHALL never be published as good news:
  `generate-factory-report.mjs` reports `open_count: null` for an unreadable
  registry, `generate-userguide-rollup.mjs` no-ops when `docs/USER_GUIDE.md` is
  absent, and the index POSIX predicate exits with a distinct code and folds
  stderr when it fails to run.
  Verification: an unreadable `--decisions` path yields `null` and an `n/a`
  render; a fixture without USER_GUIDE.md leaves no file behind; a predicate
  forced to throw exits 2 with its message captured, not 1 with an empty one.

- Spec-AC-25: `intake-staleness-check.mjs` SHALL be invoked at most once per
  intake, SHALL exit 0 on any unexpected throw, and SHALL clamp every git call —
  not only fetches — to the remaining `--budget-ms`.
  Verification: the router's duplicate invocation site is gone and a suite arm
  proves a single-source instruction; a forced throw exits 0 with no stack; a
  fixture with three submodules and a 500 ms budget completes under 1.5 times
  the budget.

- Spec-AC-26: `intake-staleness-check.mjs` SHALL treat `branch = .` as the
  track-superproject sentinel rather than a refspec, and SHALL parse submodule
  paths containing whitespace.
  Verification: a `.gitmodules` fixture with `branch = .` produces a real
  behind-count instead of a silent skip; a submodule path with a space is
  resolved to the right directory.

- Spec-AC-27: No tracked text file SHALL contain a NUL byte, and a guard SHALL
  prove it by enumerating `git ls-files` and naming any offender.
  Verification: the guard names a planted fixture file and exits non-zero; over
  the live tree it exits 0, which requires the NUL at
  `.aai/scripts/spec-amend.mjs:253` to have been replaced by an escape.

- Spec-AC-28: The `pipe-grep-q` ratchet SHALL distinguish a grep ERROR from a
  file with no matches, and `golden-flow.mjs` `questions_asked` SHALL count only
  steps that actually asked a human.
  Verification: an unreadable file makes the ratchet report an error rather than
  a count of 0; a golden-flow run with two failed steps and zero HITL entries
  reports `questions_asked: 0`.

- Spec-AC-29: `ride-select.mjs gate` SHALL admit an on-roadmap ref only when it
  belongs to the FIRST pair that is not done, naming the pair ahead in every
  refusal, while keeping an already-`implementing` ref and every `blocks:`
  admission unchanged; `ride-select.mjs validate` SHALL refuse a roadmap ref that
  matches no document id; and `orchestration-dispatch.mjs` rule 4a SHALL dispatch
  a single retarget on the live roadmap instead of `multiple_open_intakes`.
  Verification: the fixture matrix of CHANGE-0184 AC-001 to AC-007 plus a
  typo'd-slug roadmap; then `gate` and `validate` against the live
  `docs/ai/roadmap.yaml`.

- Spec-AC-30: Each commit the PR ceremony makes SHALL be verified against what it
  staged, and a push to the base branch that regenerates a shared generated page
  SHALL name the open pull requests it would turn CONFLICTING.
  Verification: a suite arm pins the committed-blob verification at steps 4c and
  5c as well as 4a; a fixture with one open PR carrying `docs/INDEX.md` makes the
  pre-push check name that PR.

- Spec-AC-31: Each convention SHALL be stated once, where its tool reads it: the
  `CHANGELOG.md` preamble names the per-entry `[unreleased]` heading shape that
  `aai-release` enforces, and `.aai/SUBAGENT_CONTRACT.md` states the append-only
  EVENTS rule once.
  Verification: `aai-release --dry-run` still refuses a scaffold with a body; the
  contract's second statement is a cross-reference and a suite arm counts one
  statement, not two.

- Spec-AC-32: The companion obligations SHALL be discharged: ONE new
  `JUSTIFIED_ADDITIONS` entry equal to this ride's MEASURED net prompt-corpus
  delta with the TEST-012 pin moved by exactly that amount, and a
  `.aai/system/PROFILES.yaml` classification for every new `.aai/**` file.
  Verification: `tests/skills/test-aai-prompt-diet.sh` TEST-010 and TEST-012 pass
  with headroom 2046 of 2048; `tests/skills/test-aai-layer-profiles.sh` TEST-001
  passes against the live tree.

## Acceptance Criteria Status

| Spec-AC    | Description                                                        | Status  | Evidence | Review-By | Notes |
|------------|--------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | A folded code_review.scope is read as every path it holds           | planned | —        | —         | —     |
| Spec-AC-02 | nothing-left-behind decides on measured identity, not on its input  | planned | —        | —         | —     |
| Spec-AC-03 | The roadmap-paired maintenance half stops the push while open       | planned | —        | —         | —     |
| Spec-AC-04 | close-reconcile sees the terminal-no-telemetry and unpaired escapes | planned | —        | —         | —     |
| Spec-AC-05 | close-reconcile pairs by links.requirement when the convention fails| planned | —        | —         | —     |
| Spec-AC-06 | close-work-item closes the paired half in one transaction           | planned | —        | —         | —     |
| Spec-AC-07 | The close ceremony's warnings carry what they collected             | planned | —        | —         | —     |
| Spec-AC-08 | The post-close self-verify resolves by path, not by a shared id     | planned | —        | —         | —     |
| Spec-AC-09 | One new close-work-item pin entry, written last                     | planned | —        | —         | —     |
| Spec-AC-10 | CHANGE-0181 and ISSUE-0040 closed with their real PR and commit     | planned | —        | —         | —     |
| Spec-AC-11 | A present-but-unparseable AC table is reported, never silent        | planned | —        | —         | —     |
| Spec-AC-12 | AC ids are reconciled by multiplicity, not presence                 | planned | —        | —         | —     |
| Spec-AC-13 | The lean AC table has one authority and one flip guard              | planned | —        | —         | —     |
| Spec-AC-14 | One specimen masker, shared                                         | planned | —        | —         | —     |
| Spec-AC-15 | The id-mention probe is one git call for the corpus                 | planned | —        | —         | —     |
| Spec-AC-16 | One statement of the done-row Evidence shape                        | planned | —        | —         | —     |
| Spec-AC-17 | verify-closures reads claims honestly and refuses a blind run       | planned | —        | —         | —     |
| Spec-AC-18 | An over-cap id is reported as unfilable, not absent                 | planned | —        | —         | —     |
| Spec-AC-19 | An amendment record carries its from and to anchors, written atomically | planned | —    | —         | —     |
| Spec-AC-20 | Renumbering a frozen spec is a disclosed restamp, not a refusal     | planned | —        | —         | —     |
| Spec-AC-21 | A verbatim intake template copy passes the intake gate              | planned | —        | —         | —     |
| Spec-AC-22 | INDEX and overview derive from tracked content only                 | planned | —        | —         | —     |
| Spec-AC-23 | The tracked overview artefacts carry no untracked STATE             | planned | —        | —         | —     |
| Spec-AC-24 | A degraded input is never published as good news                    | planned | —        | —         | —     |
| Spec-AC-25 | The staleness preflight runs once, never throws, and honours its budget | planned | —     | —         | —     |
| Spec-AC-26 | The staleness preflight parses the sentinel branch and odd paths    | planned | —        | —         | —     |
| Spec-AC-27 | No tracked text file carries a NUL byte, and a guard proves it      | planned | —        | —         | —     |
| Spec-AC-28 | A grep error is not an improvement, and a failure is not a question | planned | —        | —         | —     |
| Spec-AC-29 | The roadmap gate admits only the next pair, on refs that exist      | planned | —        | —         | —     |
| Spec-AC-30 | Every ceremony commit is verified, and a shared-page push is warned | planned | —        | —         | —     |
| Spec-AC-31 | Each convention is stated once, where its tool reads it             | planned | —        | —         | —     |
| Spec-AC-32 | The prompt-diet ledger and PROFILES obligations are discharged      | planned | —        | —         | —     |

## Implementation plan

Components touched, in the order the TDD runs take them (`## Verification`
carries the run slicing):

1. `.aai/scripts/check-committed-scope.mjs` — whitespace-aware scope split;
   NOTHING CHECKED is non-zero without `--strict`.
2. `.aai/scripts/nothing-left-behind.mjs` — STATE cross-check on `--ref`; a
   ref-identity set for the registry class; a content-side class arm; the
   roadmap-paired half in `docs_open`.
3. `.aai/scripts/close-reconcile.mjs` — two new detection arms; pairing falls
   back to `links.requirement`.
4. `.aai/scripts/close-work-item.mjs` — `--paired` inside the existing
   transaction; `planStateReconcile`'s skip keeps its echo; the mutation notice
   names its own counts; the self-verify resolves by path. BATCHED (D8).
5. `.aai/scripts/lib/docs-model.mjs` — tracked-only enumerator (D3); the
   near-miss shape check's two new kinds; the lean-heading suppression.
6. `.aai/scripts/lib/docs-audit-core.mjs` — multiplicity reconciliation; the
   lean fallback in `acFlipCheckDoc`; one batched id-mention pass; the exported
   specimen masker.
7. `.aai/scripts/docs-audit.mjs` — the new near-miss kinds in the report and
   their `--strict` promotion.
8. `.aai/scripts/spec-lint.mjs` — local masker deleted, shared one imported.
9. `.aai/scripts/follow-ups.mjs` — `verify-closures` flag, root, label and
   blank-line handling; the unfilable-id class.
10. `.aai/scripts/spec-amend.mjs` — from/to anchors; atomic restamp write; the
    new `restamp` subcommand; the NUL byte at line 253 replaced by an escape.
11. `.aai/scripts/generate-docs-index.mjs`, `generate-overview.mjs`,
    `generate-factory-report.mjs` — tracked enumeration; no untracked STATE in
    tracked artefacts; `open_count: null` on an unreadable registry.
12. `.aai/scripts/generate-userguide-rollup.mjs` — absent USER_GUIDE.md no-ops.
13. `.aai/scripts/intake-staleness-check.mjs` — `onError`; budget clamp; the
    `branch = .` sentinel; whitespace-safe submodule parsing.
14. `.aai/scripts/ride-select.mjs` — gate consults `nextRide()`'s ordering;
    `validate` resolves every ref to a document.
15. `.aai/scripts/golden-flow.mjs` — `questions_asked` counts HITL entries.
16. `tests/skills/lib/pipe-grep-q-ratchet.sh` — grep exit 2 is an error.
17. Prompts and templates: `.aai/SKILL_PR.prompt.md` (restamp, `--paired`,
    committed-blob verification at 4c/5c, pre-push shared-page check),
    `.aai/VALIDATION.prompt.md` (one reframed sentence),
    `.aai/SKILL_INTAKE.prompt.md` (duplicate STEP 0 deleted),
    `.aai/SUBAGENT_CONTRACT.md`, `.aai/templates/*_TEMPLATE.md`, `CHANGELOG.md`.
18. Data and bookkeeping: CHANGE-0181 and ISSUE-0040 closed,
    `docs/ai/roadmap.yaml` pair 7 done, the three GitHub issues dispositioned,
    the registry closures recorded, `tests/skills/lib/prompt-diet-ledger.sh` and
    `.aai/system/PROFILES.yaml` trued up.
19. LAST EDIT OF THE RIDE: the single new entry in
    `tests/skills/lib/close-work-item-pin.sh`.

Edge cases the plan owns: a repository with no git work tree (D3 degrade); a
roadmap that is absent (the paired-half class must stay silent, not crash); a
spec with no `frozen_sha256` (restamp is a no-op, not an error); a
`code_review.scope` that is null (Spec-AC-01 must not turn null into one bogus
path); and a close whose paired half is ALREADY terminal (idempotent, exit 0).

## Test Plan

Test ids continue the live band; the highest id in the corpus today is TEST-519,
so this scope allocates from TEST-520. Every row names its own selector (D12) and
its own mutation; the evidence for each is
`docs/ai/tdd/spec-close-ceremony-sweep/mutation-<TEST-id>.txt`, produced by
`node .aai/scripts/mutation-run.mjs`.

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Mutation | Status |
|----------|------------|------|----------------------|-------------|----------|--------|
| TEST-520 | Spec-AC-01 | integration | tests/skills/test-aai-learned-routing.sh | test_520_scope_folded_block_split — a STATE fixture whose code_review.scope is a folded block of three space-separated paths reports all three checked; a fixture whose paths all resolve to nothing exits non-zero WITHOUT --strict. | Revert the scope split to comma-only in check-committed-scope.mjs with sed:s/split(REGEXP_WS_OR_COMMA)/split(',')/ so the three paths fold into one unresolvable token. | pending |
| TEST-521 | Spec-AC-02 | integration | tests/skills/test-aai-golden-flow.sh | test_521_gate_refuses_foreign_ref — a STATE fixture whose current_focus.ref_id differs from --ref makes nothing-left-behind name both refs and exit LEFT BEHIND instead of CLEAN. | Delete the STATE cross-check call in runGate with sed:s/const focusMismatch = checkFocusRef/const focusMismatch = () => null; const _unused = checkFocusRef/ so the gate trusts its argument again. | pending |
| TEST-522 | Spec-AC-02 | integration | tests/skills/test-aai-golden-flow.sh | test_522_registry_class_identity — an open item filed with ref_id CHANGE-0178 for a ride whose slug differs is matched by class 4, and a ceremony item filed under an unlisted subject prefix is matched by the content arm. | Narrow the identity set back to the bare slug with sed:s/!refIdentity.has(String(it.ref_id ?? ''))/String(it.ref_id ?? '') !== slug/. | pending |
| TEST-523 | Spec-AC-03 | integration | tests/skills/test-aai-golden-flow.sh | test_523_paired_half_blocks_push — with a roadmap fixture pairing the ride to a draft maintenance doc, docs_open names that half; with the half terminal the same fixture is CLEAN; with no roadmap file the class is silent and the run does not crash. | Drop the paired-half lookup with sed:s/const pairedOpen = roadmapPairedOpen/const pairedOpen = () => []; const _p = roadmapPairedOpen/. | pending |
| TEST-524 | Spec-AC-04 | integration | tests/skills/test-aai-close-reconcile.sh | test_524_terminal_without_telemetry — a doc terminal at the delivery sha with empty links.commits and no work_item_closed event is itemed by --check. | Remove the new arm's guard with sed:s/missingCloseEvidence(d)/false/ so a terminal doc is skipped as before. | pending |
| TEST-525 | Spec-AC-04 | integration | tests/skills/test-aai-close-reconcile.sh | test_525_unpaired_draft_intake — a draft intake with NO paired spec whose frontmatter id a range commit subject names is itemed; a draft intake no commit names is not. | Disable the id-mention-unpaired arm at its call site so a draft intake named only in a touched doc body is no longer itemed; the recorded expression is in mutation-TEST-525.txt (cell rewritten by Amendment 1). | pending |
| TEST-526 | Spec-AC-04 | integration | tests/skills/test-aai-close-reconcile.sh | test_526_replays_the_two_real_ranges — replaying the merge ranges of PR 382 and PR 384 names focus-and-validation-state-go-stale-silently and unrecorded-spec-amendment-is-invisible; a fully closed pair in the same range stays CLEAN. | Drop the third disjunct from the detection arm so only the implementing-or-frozen condition survives, expressed as a mutation-run --sed expression that replaces the call to missingCloseEvidence with the literal false. | pending |
| TEST-527 | Spec-AC-05 | integration | tests/skills/test-aai-close-reconcile.sh | test_527_pairs_by_links_requirement — an off-convention pair is paired through the spec's links.requirement, --apply closes both halves, and the follow-up --check is CLEAN because the candidate set was non-empty. | Remove the fallback with sed:s/ \?\? specByRequirement.get(p.rel)// so only the literal spec-<id> lookup remains. | pending |
| TEST-528 | Spec-AC-06 | integration | tests/skills/test-aai-close-work-item.sh | test_528_paired_close_one_transaction — --paired closes the maintenance half with the ref and the spec; forcing the paired half to fail the post-close audit leaves all three docs and the EVENTS byte length byte-identical to the pre-run snapshot. | Move the paired doc out of the snapshot set with sed:s/snapshotDocs.push(pairedDoc)/void pairedDoc/ so a rollback no longer restores it. | pending |
| TEST-529 | Spec-AC-06 | integration | tests/skills/test-aai-close-work-item.sh | test_529_paired_close_idempotent — a --paired slug that is already terminal exits 0 and writes nothing; an unknown --paired slug is a usage error, exit 2, with nothing written. | Turn the already-terminal branch into a write with sed:s/if (pairedTerminal) return okNoop/if (false) return okNoop/. | pending |
| TEST-530 | Spec-AC-07 | integration | tests/skills/test-aai-close-work-item.sh | test_530_skip_keeps_planned_echo — a fixture that trips the second reconcile arm after the first planned a set-phase prints that command in the warning. | Restore the rebuilding skip with sed:s/return { severity: 'skip', reason, statePath, commands: \[\], echo };/return skip(reason);/. | pending |
| TEST-531 | Spec-AC-07 | integration | tests/skills/test-aai-close-work-item.sh | test_531_mutation_notice_names_counts — a closing spec with one exempt and one unstamped Test Plan row produces a notice naming both numbers; deleting the unstamped field from the notice object reddens this row. | Drop the count from the reason string with sed:s/ unstamped=\$\{n.unstamped\}// so the field is unread again. | pending |
| TEST-532 | Spec-AC-08 | integration | tests/skills/test-aai-close-work-item.sh | test_532_product_doc_shares_an_id — a fixture intake plus a product doc sharing its frontmatter id, ordered so the adverse readdir result wins, closes with exit 0 and flipped statuses instead of rolling back. | Resolve the audited doc by id again with sed:s/d.rel === resolvedRel/d.id === ref/. | pending |
| TEST-533 | Spec-AC-09 | unit | tests/skills/test-aai-close-work-item.sh | test_533_pin_has_exactly_one_new_entry — the live sha256 of close-work-item.mjs matches exactly one entry in close-work-item-pin.sh, the allowed-hash array has grown by exactly one against the merge base, and the new entry's prose names both frozen invariants. | Add a second new hash entry to the pin file, proving the row counts entries rather than only checking membership. | pending |
| TEST-534 | Spec-AC-10 | integration | tests/skills/test-aai-docs-audit.sh | test_534_two_stale_halves_are_closed — CHANGE-0181 and ISSUE-0040 read status done with links.pr 384 and 382 and links.commits 7270a29c and e6aae10b, and docs-audit --check over the live corpus is CLEAN for those two by evidence rather than by blindness. | Revert one of the two documents to status draft in the fixture copy of the corpus, which the row must name. | pending |
| TEST-535 | Spec-AC-10 | unit | tests/skills/test-aai-ride-select.sh | test_535_roadmap_pair_seven_done — docs/ai/roadmap.yaml pair 7 reads status done and ride-select validate passes over the live file. | Set pair 7 back to active in a fixture roadmap copy. | pending |
| TEST-536 | Spec-AC-11 | integration | tests/skills/test-aai-docs-audit.sh | test_536_unparseable_ac_table_shape — a doc with an AC slash Requirement slash Status table whose rows all read green is reported under Near-miss AC tables with kind column-set; a doc using an out-of-vocabulary status word is reported with kind status-vocabulary; both are report-only and hard-fail under --strict. | Restore the early continue with sed:s/if (!cells.includes('Spec-AC') \&\& !cells.includes('AC')) continue;/if (!cells.includes('Spec-AC')) continue;/. | pending |
| TEST-537 | Spec-AC-11 | integration | tests/skills/test-aai-docs-audit.sh | test_537_shape_check_live_yield — over the live corpus the new kinds name exactly the eight documents measured at planning, the run exits 0 without --strict, and --strict exits non-zero. | Promote the new kinds into the default hard-fail set, which must redden the exit-0 half of this row. | pending |
| TEST-538 | Spec-AC-12 | integration | tests/skills/test-aai-docs-audit.sh | test_538_duplicate_ac_id_multiplicity — a spec declaring Spec-AC-01 twice with one pipe-broken planned copy fails --gate naming the id and is not CLEAN under --check. | Reconcile by presence again with sed:s/declaredCount > parsedCount/declaredCount > 99/. | pending |
| TEST-539 | Spec-AC-13 | integration | tests/skills/test-aai-ceremony-levels.sh | test_539_ac_flip_sees_a_lean_table — a lean ceremony-1 table with a done row carrying delivery-shaped Evidence on an open doc is flagged by --ac-flip-check; the same table without the flip is silent. | Restore the hasGate short-circuit by replacing the lean fallback expression with the literal false in acTableDeliverySignal, so the guard again returns early for every lean table. | pending |
| TEST-540 | Spec-AC-13 | integration | tests/skills/test-aai-ceremony-levels.sh | test_540_lean_heading_one_authority — a lean table with an optional Evidence column under the heading Acceptance Criteria is accepted by --gate and produces no near-miss heading warning. | Remove the suppression with sed:s/if (headingAcLike \&\& !headingCanonical \&\& !leanAccepted)/if (headingAcLike \&\& !headingCanonical)/. | pending |
| TEST-541 | Spec-AC-14 | integration | tests/skills/test-aai-spec-lint.sh | test_541_shared_specimen_masker — spec-lint.mjs declares no local masker, a triple-backtick inline run no longer swallows a following live NEEDS-CLARIFICATION marker, and a four-backtick fenced specimen no longer leaks as live. | Break the shared masker's inline-run carve with sed:s/const isInlineSpanNotFence = f \&\& !fence/const isInlineSpanNotFence = false/ in lib. | pending |
| TEST-542 | Spec-AC-15 | integration | tests/skills/test-aai-docs-audit.sh | test_542_id_mention_is_one_git_call — a counting git shim on PATH records exactly one log invocation carrying no --grep over a three-doc fixture corpus, and the resolved dates equal the per-doc results. | Restore the per-doc probe with sed:s/idMentionMap.get(id) ?? null/gitLogGrepDate(root, id)/. | pending |
| TEST-543 | Spec-AC-16 | unit | tests/skills/test-aai-ceremony-levels.sh | test_543_one_done_row_evidence_statement — SPEC_TEMPLATE.md, ROLE_COMMON.md and VALIDATION.prompt.md all state the docs slash ai slash tdd evidence shape, none offers a commit SHA, and none calls a non-terminal row the expected state. | Reinstate the legacy legend wording in SPEC_TEMPLATE.md with sed:s/a docs\/ai\/tdd artifact/a commit SHA or RUN_ID/. | pending |
| TEST-544 | Spec-AC-17 | integration | tests/skills/test-aai-follow-ups.sh | test_544_verify_closures_strict_value — verify-closures --strict=true is a usage error with exit 2 and the bare --strict still enables strict mode. | Re-add --strict to the value-flag list with sed:s/const VALUE_FLAGS_VERIFY = \['--ledger', '--path'\]/const VALUE_FLAGS_VERIFY = ['--ledger', '--path', '--strict']/. | pending |
| TEST-545 | Spec-AC-17 | integration | tests/skills/test-aai-follow-ups.sh | test_545_verify_closures_blind_corpus — a corpus run from a foreign cwd whose doc roots resolve to nothing exits 2 naming both resolved paths and the cwd, instead of exit 0 with zero claims. | Restore the silent empty corpus with sed:s/if (docPaths.length === 0)/if (false)/. | pending |
| TEST-546 | Spec-AC-17 | integration | tests/skills/test-aai-follow-ups.sh | test_546_claim_before_first_label — a fu- id named in prose BEFORE the first CLOSED FULLY label is checked, and the same prefix opening with the none sentinel is not. | Drop the prefix scan with sed:s/segments.unshift(body.slice(0, labels\[0\].start));/void 0;/. | pending |
| TEST-547 | Spec-AC-17 | integration | tests/skills/test-aai-follow-ups.sh | test_547_bulleted_claims_after_blank_line — a Registry items closed by this scope label followed by a blank line and a bullet list yields every id in the list, and an unrelated paragraph after the list does not. | Restore the blank-line cut with sed:s/if (blank !== -1 \&\& segHasId) cut = Math.min(cut, blank);/if (blank !== -1) cut = Math.min(cut, blank);/. | pending |
| TEST-548 | Spec-AC-17 | integration | tests/skills/test-aai-follow-ups.sh | test_548_not_closed_disclosure_is_not_a_claim — an inline paragraph that closes two ids and states in the same sentence that a third stays NOT CLOSED yields two claims, not three. | Remove the inline label segmentation with sed:s/const inlineSegments = splitByLabels(after);/const inlineSegments = [after];/. | pending |
| TEST-549 | Spec-AC-18 | integration | tests/skills/test-aai-follow-ups.sh | test_549_over_cap_id_is_unfilable — a report naming a 52-character fu- id is reported unfilable with the length and the cap, while a filable absent id still reads absent. | Remove the length branch with sed:s/id.length > ID_MAX_LEN ?/false ?/. | pending |
| TEST-550 | Spec-AC-19 | integration | tests/skills/test-aai-spec-amend.sh | test_550_amendment_record_anchors — an added record carries from_frozen_sha256 and to_frozen_sha256 as 64-hex values matching the spec before and after, and a restamp interrupted after the ledger append leaves the spec byte-identical. | Restore the non-atomic write with sed:s/fs.renameSync(tmpSpec, absSpec)/fs.writeFileSync(absSpec, out)/. | pending |
| TEST-551 | Spec-AC-20 | integration | tests/skills/test-aai-spec-amend.sh | test_551_restamp_after_renumbering — a frozen fixture spec whose DRAFT paths the allocator rewrote passes spec-amend list --strict after restamp, and fails with undisclosed-amendment without it. | Make restamp a no-op with sed:s/fmBody = setFrontmatterScalar(fmBody, 'frozen_sha256', nextHash);/void nextHash;/. | pending |
| TEST-552 | Spec-AC-20 | unit | tests/skills/test-aai-doc-numbering.sh | test_552_skill_pr_runs_the_restamp — SKILL_PR step 1b names the restamp invocation immediately after the allocator call, and the allocator's own completion output is what the step keys on. | Delete the restamp line from the prompt with sed:s/spec-amend.mjs restamp/spec-amend.mjs list/. | pending |
| TEST-553 | Spec-AC-21 | integration | tests/skills/test-aai-intake.sh | test_553_templates_pass_intake_file — each of the eight templates copied verbatim to its DRAFT path passes docs-audit --intake-file, and every template carries exactly one number key. | Delete the number key from one template with sed:s/^number: null$// in ISSUE_TEMPLATE.md. | pending |
| TEST-554 | Spec-AC-22 | integration | tests/skills/test-aai-docs-audit.sh | test_554_index_tracked_only — a fixture repository with one tracked and one untracked doc regenerates an INDEX naming the tracked doc only, and a run outside a git work tree prints a NOTE naming the fallback. | Restore the working-tree walk with sed:s/walkTracked(ROOT, dir)/walk(path.join(ROOT, dir))/ in generate-docs-index.mjs. | pending |
| TEST-555 | Spec-AC-22 | integration | tests/skills/test-aai-overview.sh | test_555_overview_tracked_only — the same fixture regenerates overview-data.json and overview.html naming the tracked doc only. | Restore the per-directory readdir with sed:s/walkTracked(ROOT, dir)/fs.readdirSync(path.join(ROOT, dir))/ in generate-overview.mjs. | pending |
| TEST-556 | Spec-AC-23 | integration | tests/skills/test-aai-overview.sh | test_556_no_untracked_state_in_tracked_pages — with an untracked STATE.yaml present, overview-data.json carries no current_focus or in_flight values, and the regenerated repository artefact no longer names a local focus. | Reinstate the unconditional state read with sed:s/stateIsTracked ? state : null/state/. | pending |
| TEST-557 | Spec-AC-24 | integration | tests/skills/test-aai-factory-report.sh | test_557_open_count_null_when_unreadable — an unreadable --decisions path publishes open_count null and renders n slash a, matching the oldest_age_days convention two lines below it. | Restore the zero with sed:s/registry.unreadable ? null : openFollowUps.length/openFollowUps.length/. | pending |
| TEST-558 | Spec-AC-24 | integration | tests/skills/test-aai-userguide-rollup.sh | test_558_rollup_noops_without_userguide — a fixture with no docs slash USER_GUIDE.md leaves no file behind and exits 0 with a named no-op line. | Remove the existence guard with sed:s/if (!fs.existsSync(outPath))/if (false)/. | pending |
| TEST-559 | Spec-AC-24 | integration | tests/skills/test-aai-docs-audit.sh | test_559_posix_predicate_infra_exit — the index POSIX predicate forced to throw exits 2 with its stderr folded into the captured output, while a genuine path finding still exits 1. | Collapse the two exits with sed:s/process.exit(2)/process.exit(1)/ in the predicate. | pending |
| TEST-560 | Spec-AC-25 | integration | tests/skills/test-aai-intake.sh | test_560_preflight_once_and_never_throws — the router carries one invocation instruction, a forced non-ExitSignal throw exits 0 with no stack trace, and a three-submodule fixture with a 500 ms budget completes within 1.5 times the budget. | Remove the onError handler with sed:s/runMain\(\(\) => main\(\), \{ onError\(\) \{\} \}\)/runMain(() => main())/. | pending |
| TEST-561 | Spec-AC-26 | integration | tests/skills/test-aai-intake.sh | test_561_sentinel_branch_and_odd_paths — a .gitmodules carrying branch equals dot resolves through origin HEAD and produces a real behind count, and a submodule path containing a space resolves to the right directory. | Restore the literal sentinel with sed:s/if (b \&\& b !== '\.') return b;/if (b) return b;/. | pending |
| TEST-562 | Spec-AC-27 | integration | tests/skills/test-aai-hygiene-pack.sh | test_562_no_nul_in_tracked_text — the guard names a planted NUL fixture and exits non-zero, and over the live tree it exits 0, which requires spec-amend.mjs line 253 to have been de-NULed. | Change the guard's sentinel with sed:s/\\u0000/\\u0001/ so a planted NUL is no longer detected. | pending |
| TEST-563 | Spec-AC-28 | integration | tests/skills/test-aai-hygiene-pack.sh | test_563_pgq_error_is_not_zero — an unreadable file makes pgq_scan report an ERROR row naming it rather than a count of 0 that reads as an improvement. | Restore the swallow with sed:s/_pgq_rc=\$\?/_pgq_n=0/ in pipe-grep-q-ratchet.sh. | pending |
| TEST-564 | Spec-AC-28 | integration | tests/skills/test-aai-golden-flow.sh | test_564_questions_are_not_failures — a golden-flow run with two failed steps and zero HITL entries reports questions_asked 0 while the questions problem log still holds both entries. | Restore the length count with sed:s/questions.filter\(\(q\) => q.hitl_entries > 0\).length/questions.length/. | pending |
| TEST-565 | Spec-AC-29 | integration | tests/skills/test-aai-ride-select.sh | test_565_gate_admits_only_the_next_pair — with three planned pairs and nothing started, gate admits pair 1 and refuses pairs 2 and 3 naming pair 1; with pair 1 implementing, its maintenance is admitted and pair 2 stays refused; with pair 1 done, pair 2 is admitted; an implementing ref in a later pair stays admitted as in flight; an off-roadmap ref carrying blocks is admitted unchanged; --override stays one-shot and logged. | Restore the any-capability admission with sed:s/if (isFirstUnfinished(pair, roadmap))/if (true)/. | pending |
| TEST-566 | Spec-AC-29 | integration | tests/skills/test-aai-ride-select.sh | test_566_validate_refuses_unknown_refs — a roadmap pair naming a capability slug that matches no document id makes validate exit non-zero naming the slug and its pair, while the live roadmap passes. | Remove the resolution with sed:s/if (!findDoc(a.docs, ref))/if (false)/. | pending |
| TEST-567 | Spec-AC-29 | integration | tests/skills/test-aai-orchestration-dispatch.sh | test_567_rule_4a_single_retarget — a STATE and roadmap fixture matching the live roadmap with three open intakes dispatches one retarget instead of needs_llm multiple_open_intakes. | Bypass the gate in buildOpenIntakes with sed:s/if (!rideGateAdmits(ref))/if (false)/. | pending |
| TEST-568 | Spec-AC-30 | unit | tests/skills/test-aai-learned-routing.sh | test_568_every_ceremony_commit_is_verified — SKILL_PR steps 4c and 5c each name a committed-blob verification alongside step 4a's, and the verification names the paths it expects rather than the exit code. | Delete the 4c verification line with sed:s/git show --stat HEAD/git status/ in SKILL_PR.prompt.md. | pending |
| TEST-569 | Spec-AC-30 | integration | tests/skills/test-aai-pr-platform.sh | test_569_shared_page_push_names_open_prs — a fixture with one open PR whose file list carries docs slash INDEX.md makes the pre-push check name that PR and refuse; with no overlapping PR it is silent. | Query merged PRs instead with sed:s/--state open/--state merged/ in the helper. | pending |
| TEST-570 | Spec-AC-31 | integration | tests/skills/test-aai-release.sh | test_570_changelog_shape_is_documented — the CHANGELOG preamble names the per-entry unreleased heading shape and the two exits that enforce it, and aai-release --dry-run still refuses a scaffold carrying a body. | Change the documented heading shape in the preamble so it no longer matches what the engine enforces. | pending |
| TEST-571 | Spec-AC-31 | integration | tests/skills/test-aai-docs-lock.sh | test_571_ledger_rule_stated_once — SUBAGENT_CONTRACT.md states the append-only EVENTS rule once and cross-references it from the single-writer list. | Restore the second statement with sed:s/(HAZ-LEDGER)/(the append-only, commutative audit log)/. | pending |
| TEST-012 | Spec-AC-32 | unit | tests/skills/test-aai-prompt-diet.sh | test_012_growth_sum_matches_ledger — the existing ledger checkpoint, re-pinned to 32826 plus this ride's measured net prompt-corpus delta, with TEST-010 reporting headroom 2046 of 2048. | Change the appended JUSTIFIED_ADDITIONS entry's leading byte field by one so the independent re-sum disagrees with the pin. | pending |
| TEST-572 | Spec-AC-32 | unit | tests/skills/test-aai-layer-profiles.sh | test_572_new_aai_files_classified — every new .aai file this ride adds appears exactly once in PROFILES.yaml core, and the union still equals the live tree. | Remove one new path from the core list so the live-tree union check reddens. | pending |

Test status values: pending to red to green. Every Spec-AC above has at least one
row; every row names exactly one Spec-AC. Mutation cells are written as
`mutation-run.mjs --sed` expressions in JavaScript RegExp form, and no cell
contains a pipe character (D11).

## Seams

S1. `close-work-item.mjs` writes documents that `docs-audit.mjs` then classifies
in the same process (the post-close self-verify). Spec-AC-08 and Spec-AC-11 both
land on that crossing: the shape check must not turn a legitimately closed doc
into a self-verify problem. TEST-532 and TEST-537 together cross it — the first
closes a real fixture, the second runs the new check over the live corpus.

S2. `nothing-left-behind.mjs` (Spec-AC-03) and `close-work-item.mjs --paired`
(Spec-AC-06) are two independent readings of one fact: which maintenance half
belongs to this ride. TEST-523 and TEST-528 produce on one side and assert on
the other — the same roadmap fixture drives both.

S3. `spec-freeze.mjs` writes `frozen_sha256`; `allocate-doc-number.mjs` rewrites
the body it hashed; `spec-amend.mjs list --strict` judges the result. Spec-AC-20
crosses all three, and TEST-551 runs the real sequence rather than mocking the
allocator.

S4. `generate-docs-index.mjs`, `generate-overview.mjs` and the pre-commit
INDEX-AUTOGEN hook share the enumeration D3 replaces. TEST-554 drives the
generator and asserts on the INDEX the hook would stage.

S5. The prompt corpus is shared by the ledger (`prompt-diet-ledger.sh`), the
byte floor (TEST-010) and the pin (TEST-012). Spec-AC-32 crosses it; every other
AC that edits a prompt feeds it.

S6 (NO AUTOMATED CROSSING — residual). GitHub issues 338 and 339 are structured
friction records with no prose and no surviving local observation
(`docs/ai/friction/` does not exist on this tree). Their disposition is decided
by reading, not by a test; see `## GitHub issues`.

## Residual risks

R1. The shape check of Spec-AC-11 is report-only by decision D7. A project that
never runs `--strict` gains a report, not a gate. Measured trade: promoting it
would redden eight historical documents this ride does not own.

R2. `fu-registry-class-trusts-the-filer-id` is narrowed, not eliminated: the
content arm reads `finding`, which is still prose a filer wrote. The residual is
smaller than the prefix-only rule but it is not zero.

R3. Five items are deferred to a ceremony-3 ride (D1). Until that ride,
`--type research` and `--type hotfix` still exit 2, the allocator still rewrites
dated review reports and still exits silently through a symlinked checkout, and
`pre-commit-checks.sh` still decides with six pipefail-exposed `grep -q` pipes.

R4. This spec is the first in the corpus to carry `frozen_sha256` through a full
ride (M3). Spec-AC-20 is the mitigation, but the failure mode it guards is on
this ride's own critical path: if the restamp is wrong, the PR cannot close. The
implementer runs TEST-551 before the first PR attempt, not after.

R5. The ride is large: 32 acceptance criteria across 11 TDD runs. The review-round
cap of two finding-bearing rounds applies per the operator contract; if a third
round is needed the remaining runs are split into a follow-on PR rather than
re-verified.

## Verification

Commands, in the order the runs take them. Each TDD run ends with the SELECTED
plus CORE suites (`node .aai/scripts/select-suites.mjs --files-from`), and ONE
full `bash tests/skills/test-framework.sh` runs before the close ceremony, with
`AAI_TEST_TIMEOUT=3000`.

- Run 1 (Spec-AC-01, 02, 03): tests/skills/test-aai-learned-routing.sh,
  tests/skills/test-aai-golden-flow.sh
- Run 2 (Spec-AC-04, 05): tests/skills/test-aai-close-reconcile.sh
- Run 3 (Spec-AC-06, 07, 08): tests/skills/test-aai-close-work-item.sh
- Run 4 (Spec-AC-11, 12, 13): tests/skills/test-aai-docs-audit.sh,
  tests/skills/test-aai-ceremony-levels.sh
- Run 5 (Spec-AC-14, 15, 16): tests/skills/test-aai-spec-lint.sh,
  tests/skills/test-aai-docs-audit.sh, tests/skills/test-aai-ceremony-levels.sh
- Run 6 (Spec-AC-17, 18): tests/skills/test-aai-follow-ups.sh
- Run 7 (Spec-AC-19, 20, 21): tests/skills/test-aai-spec-amend.sh,
  tests/skills/test-aai-doc-numbering.sh, tests/skills/test-aai-intake.sh
- Run 8 (Spec-AC-22, 23, 24): tests/skills/test-aai-docs-audit.sh,
  tests/skills/test-aai-overview.sh, tests/skills/test-aai-factory-report.sh,
  tests/skills/test-aai-userguide-rollup.sh
- Run 9 (Spec-AC-25, 26, 27, 28): tests/skills/test-aai-intake.sh,
  tests/skills/test-aai-hygiene-pack.sh, tests/skills/test-aai-golden-flow.sh
- Run 10 (Spec-AC-29, 30, 31): tests/skills/test-aai-ride-select.sh,
  tests/skills/test-aai-orchestration-dispatch.sh,
  tests/skills/test-aai-pr-platform.sh, tests/skills/test-aai-release.sh,
  tests/skills/test-aai-docs-lock.sh
- Run 11 (Spec-AC-09, 10, 32): tests/skills/test-aai-prompt-diet.sh,
  tests/skills/test-aai-layer-profiles.sh, tests/skills/test-aai-ride-select.sh,
  then the close-work-item re-pin and the four suites that source it

Corpus-level checks before the close: `node .aai/scripts/spec-lint.mjs --path
docs/specs/SPEC-DRAFT-spec-close-ceremony-sweep.md`,
`node .aai/scripts/mutation-gate.mjs --spec <this spec>`,
`node .aai/scripts/mutation-run.mjs --replay --spec <this spec>`,
`node .aai/scripts/spec-amend.mjs list --strict`,
`node .aai/scripts/docs-audit.mjs --check --strict`,
`node .aai/scripts/follow-ups.mjs verify-closures --strict`,
`node .aai/scripts/nothing-left-behind.mjs --ref close-ceremony-sweep`.

PASS criteria: every TEST row green (or terminal-not-green with a disclosed
reason and a non-empty Mutation cell), every Spec-AC terminal, the mutation gate
exiting 0 with every degrade named, and the registry disposition below matching
the ledger.

## Evidence contract

- ref_id: `close-ceremony-sweep`
- Spec-AC and TEST links: the Test Plan table above is the authority in both
  directions.
- Command or review scope: the review scope is the branch diff against main,
  MINUS the eight `protected_paths_l3` files, which must not appear in it.
- Exit code or verdict: recorded per TDD run in `docs/ai/tdd/spec-close-ceremony-sweep/`.
- Evidence path: `docs/ai/tdd/spec-close-ceremony-sweep/<TEST-id>.log` for the
  RED and GREEN observations, and
  `docs/ai/tdd/spec-close-ceremony-sweep/mutation-<TEST-id>.txt` for the mutation
  record — the ONLY sanctioned location for the latter.
- Commit SHA or diff range: recorded at the close flip, never in an AC Evidence
  cell before it.

Strategy `tdd` means this spec may demand a stored RED artifact per AC-gating
test plus the full verification matrix, and it does.

## Registry items closed by this scope

Re-derived at planning on 2026-09-17 from
`node .aai/scripts/follow-ups.mjs list --status open` (107 open), by subject,
not from the intake's list (M1).

CLOSED FULLY, each by the named Spec-AC, each with a test a named mutation
reddens:

- `fu-check-committed-scope-folded` — Spec-AC-01
- `fu-gate-trusts-the-ref-it-is-given` — Spec-AC-02
- `fu-gate-ref-id-shape-mismatch` — Spec-AC-02
- `fu-registry-class-trusts-the-filer-id` — Spec-AC-02 (narrowed, see R2)
- `fu-close-gate-status-trigger-blind` — Spec-AC-04
- `fu-close-gate-unpaired-draft-intake` — Spec-AC-04
- `fu-close-reconcile-pair-id-convention` — Spec-AC-05 and Spec-AC-06
- `fu-reconcile-skip-drops-commands` — Spec-AC-07
- `fu-gate-notice-field-unread` — Spec-AC-07
- `fu-product-doc-id-collides-with-intake` — Spec-AC-08
- `fu-mask-duplicates-docs-audit-core` — Spec-AC-14
- `fu-docsaudit-idmention-probe-per-doc` — Spec-AC-15
- `fu-gate-ac-duplicate-id-pipe-drop` — Spec-AC-12
- `fu-ac-flip-guard-lean-table-blind` — Spec-AC-13
- `fu-lean-ac-heading-two-authorities` — Spec-AC-13
- `fu-spec-template-legend-offers-sha` — Spec-AC-16
- `fu-rolecommon-ac-row-canon-conflict` — Spec-AC-16
- `fu-verify-closures-strict-value-off` — Spec-AC-17
- `fu-verify-closures-claim-before-label` — Spec-AC-17
- `fu-verify-closures-corpus-cwd-silent` — Spec-AC-17
- `fu-inline-claim-blankline-dropped` — Spec-AC-17
- `fu-closure-claim-extractor-greedy` — Spec-AC-17
- `fu-report-ids-exceed-registry-cap` — Spec-AC-18
- `fu-amend-record-lacks-from-to-hash` — Spec-AC-19
- `fu-numbering-rewrites-frozen-spec-body` — Spec-AC-20 (via the spec-amend
  side, D2; the allocator-side carve is deferred under D1)
- `fu-intake-templates-lack-number-key` — Spec-AC-21
- `fu-index-regen-eats-untracked` — Spec-AC-22
- `fu-overview-regen-eats-untracked` — Spec-AC-22
- `fu-overview-bakes-untracked-state` — Spec-AC-23
- `fu-openct-unrdbl-report` — Spec-AC-24
- `fu-rollup-creates-userguide` — Spec-AC-24
- `fu-posix-predicate-exit-conflates-infra` — Spec-AC-24
- `fu-stale-check-router-double-invoke` — Spec-AC-25
- `fu-stale-check-runmain-no-onerror` — Spec-AC-25
- `fu-stale-check-budget-not-clamped` — Spec-AC-25
- `fu-stale-check-submodule-branch-dot` — Spec-AC-26
- `fu-stale-check-submodule-path-whitespace` — Spec-AC-26
- `fu-no-nul-guard` — Spec-AC-27
- `fu-pgq-grep-error-reopened` — Spec-AC-28
- `fu-golden-flow-questions-vs-failures` — Spec-AC-28
- `fu-ride-select-validate-ref-exists` — Spec-AC-29
- `fu-verify-staged-set-after-commit` — Spec-AC-30
- `fu-main-push-conflicts-open-pr` — Spec-AC-30
- `fu-changelog-unreleased-shape-undoc` — Spec-AC-31
- `fu-contract-ledger-rule-stated-twice` — Spec-AC-31

CLOSED WITHOUT CODE — measured already fixed on main, closed with the evidence
that fixed them:

- `fu-expect-branch-ignores-argument` (P3) — all three ceremony scripts now pass
  the argument through (`check-committed-scope.mjs:94`, `close-work-item.mjs:1719`,
  `close-before-push-guard.mjs:101`) and `branch-guard.mjs:546` compares it;
  TEST-455 in `tests/skills/test-aai-branch-guard.sh` is the covering test.
- `fu-factory-report-stale-draft-path` (P2) — `resolveDraftMentions`
  (`generate-factory-report.mjs:808-811`, applied at `:696`) strips the DRAFT
  token before render; the live `docs/ai/factory-report.html` carries zero
  `<TYPE>-DRAFT-<slug>` tokens, so the stale-draft-ref guard cannot fire even
  with `fu-amend-friction-upsert-channel-ba7701` still open.
- `fu-ac-flip-must-precede-close` (P3) — `.aai/SKILL_PR.prompt.md:200-210` orders
  FLIP THE AC TABLE FIRST before the close ceremony, and
  `tests/skills/test-aai-close-work-item.sh` TEST-050 asserts the ordering in the
  prompt itself. No orchestrator source dispatches the opposite order.

DROPPED, with the measured reason:

- `fu-stale-check-events-false-ac-status` (P2) — the premise is gone. The eleven
  `ac_status` records are still in the append-only ledger, but
  `docs/specs/SPEC-0158-spec-intake-staleness-preflight-warning.md` is now
  `status: done` with a `work_item_closed` event, so the records are EARLY, not
  FALSE. There is nothing to fix and nothing an append-only ledger allows to be
  corrected in place.

## Registry items deferred to a ceremony-3 ride

Each needs a `protected_paths_l3` file, which a level-2 spec may not edit (D1).
They stay OPEN in the registry, and ONE new item,
`fu-l3-surfaces-owed-a-ceremony-3-ride`, is filed so the owner can schedule the
ride that carries all five together:

- `fu-typemap-missing-research-hotfix` (P2) — `.aai/scripts/allocate-doc-number.mjs`
  `TYPE_MAP` has no `research` and no `hotfix` row; `--type research` exits 2.
- `fu-numbering-rewrites-dated-reports` (P3) — `docs/ai/reviews` is in the
  allocator's `REWRITE_TREES` and belongs in `EXCLUDED_TREES` beside
  `docs/ai/reports`.
- `fu-realpath-allocate-doc-number-l3` (P3) — the allocator's `main()` guard is
  the last of 24 that is symlink-blind.
- `fu-pre-commit-checks-pipe-grep-q` (P2) — six `echo | grep -q` pipes under
  `set -o pipefail` in `.aai/scripts/pre-commit-checks.sh`, whose `.ps1` twin
  must move in lockstep. The ratchet's own `PGQ_SHIPPING_DEFERRED_L3` constant
  already names this file and this item.
- `fu-clearfocus-announces-unwritten-phase` (P3) — `.aai/scripts/state.mjs`
  `clear-focus` announces a phase it never wrote. Also a sweep-3 subject.

## Registry items rejected by this scope

NOT CLOSED, owned elsewhere, named so they are not lost:

- Sweep 5 (`update-installs-ref-guard-undisclosed`): `fu-sync-hash-compare-fails-open`,
  `fu-agents-tree-not-synced`, `fu-gitignore-crlf-exact-line`,
  `fu-release-fallback-branch-unguarded`, `fu-routing-file-overwritten-on-update`,
  `fu-update-installs-ref-guard-undisclosed`.
- Sweep 6 (`friction-channel-sweep`): `fu-friction-label-missing-in-destination`,
  `fu-existinglabels-discards-status`, `fu-upsert-refusal-prints-exit-zero`,
  `fu-learned-append-style-drift`, `fu-learned-ledger-merge-procedure`,
  `fu-triage-undated-learned-log`.
- Sweep 7 (`canon-is-a-build-artifact`, whose maintenance half is
  `mutation-gate-for-tests`): `fu-mutation-gate-skips-pester`,
  `fu-replay-vanished-target-counter`, `fu-tdd-block-needs-fail-line-grammar`,
  `fu-deferred-row-empty-mutation-cell`, `fu-runmain-runs-main-on-import`,
  `fu-test439-single-line-guard-grep`, `fu-testplan-fallback-wrong-cell`,
  `fu-sed-replacement-dollar-trap`, `fu-writerecord-rotates-before-patch-copy`,
  `fu-mutation-rows-share-selectors`, `fu-spec-ac05-lacks-stale-cause`,
  `fu-clone-untracked-copy-not-nul-split`, `fu-mutation-target-symlink-unchecked`,
  `fu-tree-hash-nul-split-untested`, `fu-spec-d6-enumeration-stale`,
  `fu-contract-ledger-rule-stated-twice` is the ONE canon item taken here because
  Spec-AC-31 already opens that file.
- Sweep 2 residuals (test framework): `fu-pester-red-under-isolation`,
  `fu-pindirfast-gitdir-untested`, `fu-prompt-diet-fixture-real-root-race`,
  `fu-ps1-quality-outside-sweep-glob`, `fu-seed-partial-verdict-unasserted`,
  `fu-seeded-copies-lesson-no-guard`, `fu-watchdog-3000-exceeds-ci-timeout`,
  `fu-test454-4c-arm-uses-guard-proxy`, `fu-tripwire-attributes-concurrent-writes`,
  `fu-follow-ups-test021-fifo-eintr`.
- Sweep 3 residuals (dispatch and state): `fu-dispatch-text-detector-self-ref-fp`,
  `fu-verdict-coverage-same-second-true`, `fu-ledger-shrink-arm-unpinned`.
- Sweep 1 residuals (telemetry): `fu-cost-blend-silent-default`,
  `fu-spec-0085-info-line-wording-drift`.
- `fu-azure-live-proof-on-adoption` (P3) — needs a real Azure adopter; no code in
  this repository can close it.
- The seven `fu-amend-*` items are OWNER SIGN-OFFS, not defects. They stay open
  and untouched by this ride, and are presented to the owner as one menu.

## GitHub issues

- Issue 370 (`aai-docs-audit / drift-detection`, medium) — FIXED by Spec-AC-11.
  The reporter's requested shape check lands as two new near-miss kinds,
  report-only by default per D7, with the measured live yield of eight documents
  (M9) named in the closing comment. The two smaller notes in the same issue
  (three-digit `evidence_ref` ids, `blocked_dedup_unavailable` masking a rate
  limit) belong to sweep 6 and are named as such in the reply, not silently
  dropped.
- Issue 339 (`SKILL_PR / close_pre_commit`, low, reproducible) — CLOSED WITH
  EVIDENCE. Its `evidence_ref` is `docs/ai/factory-report.html`, and the
  deterministic close-time pre-commit failure over that file was the stale
  DRAFT-reference guard, fixed by `resolveDraftMentions` (measured above under
  `fu-factory-report-stale-draft-path`). The closing comment cites the function,
  the guard and the covering suite arm. If the implementer's reading of the
  record contradicts that, the issue stays open and is re-filed as a registry
  item — disclosed here, never silently.
- Issue 338 (`aai-pr / post_open_sweep`, high, contract_violation) — TRIAGED. The
  record carries no prose by design and no local observation survives
  (`docs/ai/friction/` does not exist on this tree, S6). The contract it names is
  `.aai/SKILL_PR.prompt.md` step 5d, whose enforcement is prose only. Spec-AC-30
  hardens two neighbouring prose-only ceremony contracts in the same file; the
  step-5d sweep itself is NOT mechanized here, because a sweep-completion gate is
  a new capability rather than a defect fix. The issue is closed with a comment
  stating exactly that, and the mechanization is filed as
  `fu-post-open-sweep-has-no-mechanism`, a new registry item the owner can rank.

## Amendment 1 (post-freeze, 2026-09-18 — TEST-525 Mutation cell, TDD run 2)

The TEST-525 Mutation cell is the one cell of this spec that was REWRITTEN, not
left verbatim, and this section is its disclosure. Two reasons, both measured:

- **The frozen cell broke the table.** It carried the JavaScript OR operator,
  i.e. two literal pipe characters, inside a Markdown table cell. The row split
  into 11 raw cells instead of 9, so the parsed Mutation cell was truncated and
  the parsed Status cell was wrong. `spec-lint` passed it (the gap Spec-AC-12
  of this very spec closes). The frozen text read: "Restrict the id-mention arm
  to paired docs with sed:s/if (!primary) continue;/if (!primary OR
  !primary.spec) continue;/." (OR written out here so this section cannot break
  a parser either).
- **The named expression has no target.** Run 2 built the arm as a
  `missingPairedSpecMention` helper behind the shared `missingCloseEvidence`
  dispatcher instead of restricting the BLOCKING-1 pairing loop, so the line the
  frozen cell edits does not exist. The recorded mutation
  (`docs/ai/tdd/spec-close-ceremony-sweep/mutation-TEST-525.txt`, verdict RED)
  replaces the guard at the `id-mention-unpaired` call site with `false`: the
  same property (an unpaired draft intake named in a touched doc body is itemed)
  is what reddens.

No Spec-AC, test id, selector or file path changed. Sign-off: none (tracked).

## Notes

This document defines HOW, not WHAT or WHY. It does not define workflow. Plain
Markdown headings and body text; no emoji.
