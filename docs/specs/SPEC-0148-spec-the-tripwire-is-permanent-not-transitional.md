---
id: spec-the-tripwire-is-permanent-not-transitional
type: spec
number: 148
status: done
ceremony_level: 2
capability: aai-suite-isolation
links:
  requirement: docs/issues/CHANGE-0160-the-tripwire-is-permanent-not-transitional.md
  rfc: null
  pr:
    - 281
  commits:
    - d83b680d7664d34e04227c88e4da0fb2f32f4cd8
---

# Spec — the tripwire is permanent, and the record must say so

SPEC-FROZEN: true

## Headline: one item closes, fifteen stay open, and the count still reads 16

ARITHMETIC, so nobody audits this by subtraction: the open `tripwire`-id count
is 16 before and 16 after, and after validation round 2 filed its own findings it
is 16 again by a different route. One item closed; new tripwire-named items were
filed by the same rides. **The observable is the NAMED SET below, never the
count.** A reader who diffs the number will conclude nothing happened, and a
reader who is told the number fell will have been misled.

This scope closes **exactly one** registry item, `fu-tripwire-removal-needs-a-gate`
(P2), because its whole content is a precondition for a deletion that is no
longer planned. **Fifteen other open tripwire defects are NOT resolved by this
decision.** They are defects in a layer that now stays, and nothing here fixes
one of them. Reading this ride as "the tripwire registry improved" would be
false: the registry is unchanged apart from one item that stopped being a
precondition for anything, and fifteen items lost their standing excuse.

Enumerated from `docs/ai/decisions.jsonl` (rule: open follow-ups whose `id`
contains the token `tripwire`; 16 total, minus the one that closes):

| # | Registry id | Sev | Defect |
|---|---|---|---|
| 1 | `fu-tripwire-porcelain-class-not-content` | P3 | porcelain=v1 reports a path's change CLASS not content, so a second write to an already-dirty path is invisible |
| 2 | `fu-tripwire-evadable-by-index-flags` | P3 | defeatable by `update-index --assume-unchanged` or an appended `.git/info/exclude` pattern |
| 3 | `fu-tripwire-ratchet-path-glob-widens` | P3 | `tripwire_path_listed` loops over an unquoted `$2`, so a ratchet path list word-splits and glob-expands at run time |
| 4 | `fu-tripwire-ratchet-duplicate-entry` | P3 | a second ratchet entry naming the same suite is dead code and nothing warns |
| 5 | `fu-suite-map-tripwire-row-incomplete` | P3 | the suite-map row omits two files the tripwire suite depends on |
| 6 | `fu-tripwire-fail-hides-suite-log-tail` | P2 | a suite failing on its own exit code AND tripping the tripwire loses the log-tail dump |
| 7 | `fu-tripwire-git-internals-unnamed` | P3 | writes to `.git` internals are invisible and are not named as a limit |
| 8 | `fu-wrapper-tripwire-snapshot-leak` | P3 | the wrapper's mktemp snapshot files leak on a signal (no trap) |
| 9 | `fu-tripwire-allowed-ignores-pre-dirty` | P2 | an allowlisted suite writing an already-dirty non-ratchet path still reads `tripwire ALLOWED` at exit 0 |
| 10 | `fu-tripwire-degrade-not-on-suite-line` | P3 | under the no-hasher degrade a masked writer's own line is a bare PASS and metrics record `tripwire clean` |
| 11 | `fu-tripwire-contract-omits-hash-side` | P3 | the vendor-facing CONTRACT block omits the hash-side functions and states no hash-side limit |
| 12 | `fu-tripwire-unavailable-discards-hash` | P3 | hash evidence is discarded when `tw_state` is `unavailable`, and the lost-snapshot block names no paths |
| 13 | `fu-tripwire-fixture-dirs-leak` | P3 | `new_fixture` runs in a command substitution, so the EXIT trap sees an empty WORKDIRS array |
| 14 | `fu-tripwire-always-watch-floor-uncovered` | P2 | the `TRIPWIRE_ALWAYS_WATCH` floor has no gating arm and is silently revertible |
| 15 | `fu-tripwire-suite-grep-half-pinned` | P3 | the tripwire suite pins the grep binary at 7 of 68 call sites |

Two P2 defects that live in the same layer are deliberately NOT counted above
because their ids do not carry the token (`fu-always-watch-array-unguarded`,
`fu-ratchet-counter-line-undercount`, and others under
`ref_id: drain-the-tripwire-known-offender-list`). The rule is stated so the set
is reproducible, not because 15 is a ceiling — it is a floor.

Do not read the raw open count as the observable: it is 16 before this scope and
16 after, because this scope CLOSES one item and FILES a different new one
(`fu-tripwire-suite-comment-transitional`, D5). The named set is the observable.

## Links
- Requirement: docs/issues/CHANGE-0160-the-tripwire-is-permanent-not-transitional.md
- The frozen spec being corrected: docs/specs/SPEC-0137-spec-suites-must-not-touch-the-shipping-repo.md
- The successor that landed and does not cover the case: docs/specs/SPEC-0138-spec-suites-run-in-a-disposable-worktree.md
- The two isolation-reporting scopes that cite the removal: docs/specs/SPEC-0144-spec-a-run-must-say-whether-isolation-armed.md, docs/specs/SPEC-0145-spec-a-half-seeded-checkout-says-it-is-isolated.md
- Decision records: `docs/ai/decisions.jsonl` — `hitl_decision` 2026-08-19T16:59:51Z (the decision being superseded) and the new entry this scope appends
- Correction shape copied from: docs/knowledge/LEARNED.md line 167 (`**CORRECTION (2026-08-23).**`)
- Technology contract: docs/TECHNOLOGY.md

## Implementation strategy
- Strategy: untested
- Rationale: this scope changes the RECORD and nothing else. AC-005 forbids a
  single line of `.aai/scripts/lib/repo-tripwire.sh`, `tests/skills/test-framework.sh`
  or `.aai/scripts/aai-run-tests.sh` from moving, and the delivery contract is
  that `git diff --stat` names ZERO executable files — so a committed test file
  would itself violate the scope it was written to protect. There is no behavior
  to drive out with a RED test: the acceptance criteria are text-presence and
  ledger-append facts, each decided by one grep or one CLI read-back run against
  the shipped tree. Those commands ARE the verification and their exit codes are
  the evidence; no `docs/ai/tdd/` artifact is demanded.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: six markdown files and two append-only ledger lines. No
  suite is modified, no framework run is required, and the one measurement this
  scope rests on (a worktree's `--git-common-dir`) was taken in a throwaway
  worktree under the session scratchpad and removed with a targeted
  `git worktree remove`.
- User decision: inline
- Base ref: main (07e6d81), branch `docs/tripwire-is-permanent`
- Worktree branch/path: not used
- Inline review scope: docs/specs/SPEC-0137-spec-suites-must-not-touch-the-shipping-repo.md,
  docs/specs/SPEC-0144-spec-a-run-must-say-whether-isolation-armed.md,
  docs/specs/SPEC-0145-spec-a-half-seeded-checkout-says-it-is-isolated.md,
  docs/issues/CHANGE-0151-suites-must-not-touch-the-shipping-repo.md,
  docs/issues/CHANGE-0156-a-run-must-say-whether-isolation-armed.md,
  docs/issues/CHANGE-0157-a-half-seeded-checkout-says-it-is-isolated.md,
  docs/specs/SPEC-0148-spec-the-tripwire-is-permanent-not-transitional.md,
  and the appended lines of docs/ai/decisions.jsonl

## The measurement this decision rests on

Re-taken first-hand on `main` at `07e6d81`, in a throwaway worktree under the
session scratchpad:

```
git -C <shipping repo> worktree add --detach <scratch>/reach-probe-wt HEAD
git -C <scratch>/reach-probe-wt rev-parse --git-common-dir
  ->  /Users/ales/Projects/aai/.git
dirname                                  ->  /Users/ales/Projects/aai
git -C <shipping repo> worktree remove <scratch>/reach-probe-wt
```

A disposable worktree relocates a suite's cwd and its script path. It does not
remove the suite's REACH: the shipping working tree is one `dirname` away from a
value the suite can compute with a single git call, and any absolute path a
suite already holds still resolves. A suite that writes through that path
dirties the shipping repository while the run correctly reports `isolated` —
the `degraded` signal cannot fire, because nothing degraded. Filed as
`fu-isolated-suite-reaches-shipping-repo` (P1), open.

The retirement scope that tried to act on the 2026-08-19 decision measured the
counterfactual end to end: with the tripwire deleted and the proposed
degraded-gate in place, a run exits 0 at `Passed: 2 (100%) / 0 degraded` **with
the write landed**. It stopped on its own AC-002 rather than proceed.

## Decisions

- **D1 — the correction is dated, in place, and leaves the wrong sentence
  visible.** `SPEC-0137` is frozen and `done`. Its transitional claim
  (lines 318-320) is not rewritten to look as if it had always been right;
  a `**CORRECTION (2026-08-23).**` block is inserted immediately after it,
  quoting what the old text promised, naming the measurement that falsified it,
  and citing the superseding `hitl_decision` by timestamp. This is the shape
  `docs/knowledge/LEARNED.md` line 167 already uses for the same problem. The
  alternative — editing the sentence — was rejected: a frozen spec whose bytes
  change to match the present tells a later reader that nobody was ever wrong,
  which is the defect class this programme has spent the week removing.

- **D2 — the superseding decision is reachable from the superseded one by TEXT,
  because an append-only ledger has no back-pointer.** Three mechanisms, and the
  third is the one that actually works:
  1. the new entry carries `supersedes` naming the 2026-08-19 entry's `ts` and
     `ref_id`, so a reader who finds the NEW entry can find the old one exactly;
  2. every prose citation of the old entry is corrected in this same change to
     cite the new one's timestamp as well, so a reader arriving at the ledger
     through a document arrives at both;
  3. the new entry quotes the old decision's distinctive sentence VERBATIM in a
     `supersedes_quote` field. This is the back-pointer: a reader or a grep that
     goes looking for the old claim's text now returns TWO lines, and the later
     one withdraws the earlier. It is measurable — `grep -c` on that sentence
     over `decisions.jsonl` returns 2, where it returned 1.
  Residual risk, stated not solved: a reader who reads the 2026-08-19 line alone
  and greps for nothing still sees a withdrawn claim with no marker on it. That
  is inherent in append-only bytes; the mitigation is (3), not a fix.

- **D3 — the decision names what would reopen it, or it is a mood, not a
  decision.** "The tripwire is permanent" means: its removal is not scheduled
  and no scope may plan for it. The question REOPENS when all three of these are
  measured true, in this order:
  1. `fu-isolated-suite-reaches-shipping-repo` (P1) is closed with evidence that
     a suite running under isolation **cannot** reach the shipping working tree
     — not that it is unlikely to. The measurable form: from inside the suite's
     checkout, no run-time-computable path resolves into the shipping tree
     (today `dirname $(git rev-parse --git-common-dir)` does, in one call);
  2. the counterfactual is re-measured **with the tripwire removed**: a fixture
     suite that writes an absolute path into the shipping tree makes the run
     exit non-zero. Today that same counterfactual exits 0 at
     `Passed: 2 (100%) / 0 degraded` with the write landed;
  3. the isolation report is a GATE, shipped in the SAME change that deletes the
     tripwire, never after — which is the entire content of
     `fu-tripwire-removal-needs-a-gate`, restated here so closing that item
     loses nothing.
  Anything short of all three leaves the tripwire armed.

- **D4 — the owner approval goes in the record NEXT TO the measurement, not
  instead of it.** This scope reverses a decision the owner recorded on
  2026-08-19. The owner approved that reversal in the 2026-08-23 session. The
  new ledger entry carries both: `authority: owner` with the session date, AND
  the measurement, because the approval is what makes the reversal legitimate
  and the measurement is what makes it correct. Neither alone would do.

- **D5 — an executable surface carrying the same false claim is FILED, not
  fixed.** `tests/skills/test-aai-repo-tripwire.sh` lines 529-531 justify an
  uncovered arm with "the ratchet is transitional ... once suites run in a
  disposable worktree". That is the same wrong claim, and AC-005 plus the
  zero-executable-files delivery contract forbid touching it here. Filed as
  `fu-tripwire-suite-comment-transitional` (P3). Fixing it inside this scope
  would break the one boundary this scope exists to respect.

- **D6 — historical records are NOT corrected.** Validation reports, code
  reviews and metrics under `docs/ai/` recorded what was believed on their date
  and are correct AS records. Correcting them would be rewriting history, which
  is the failure mode D1 rejects. Only forward-looking claims a reader would
  take as current truth are corrected: two frozen specs beyond SPEC-0137
  (SPEC-0144, SPEC-0145) and three intake documents (CHANGE-0151, CHANGE-0156,
  CHANGE-0157). Each gets the same dated correction block, not a rewrite.

## Constitution deviations

None.

## Acceptance Criteria Mapping

- Maps to: CHANGE AC-001
- Spec-AC-01: `docs/specs/SPEC-0137-spec-suites-must-not-touch-the-shipping-repo.md`
  carries a `**CORRECTION (2026-08-23).**` block placed after its transitional
  claim, the original claim text is still present unmodified, and the block
  cites both the measurement and the superseding decision's timestamp.
  - Verification: `/usr/bin/grep -c 'CORRECTION (2026-08-23)' <spec>` returns at
    least 1; `/usr/bin/grep -n 'the tripwire, the ratchet and the hashing all go' <spec>`
    still returns line 320; `/usr/bin/grep -c '2026-08-23T' <spec>` returns at
    least 1 for the superseding entry's timestamp.

- Maps to: CHANGE AC-002
- Spec-AC-02: `docs/ai/decisions.jsonl` gains exactly one appended
  `hitl_decision` line dated 2026-08-23 whose `supersedes` names the
  2026-08-19T16:59:51Z entry, whose `supersedes_quote` reproduces that entry's
  removal sentence verbatim, and which states both what changed and the
  three-part reopening condition; the 2026-08-19 line is byte-identical to its
  pre-change form.
  - Verification: `git diff docs/ai/decisions.jsonl` shows additions only and no
    deletions (`git diff --numstat` deletions field is 0); a node read-back
    parses the last line, asserts `type == "hitl_decision"`, a non-empty
    `supersedes.ts == "2026-08-19T16:59:51Z"`, and a non-empty `reopens_when`;
    `/usr/bin/grep -c 'are to be DELETED' docs/ai/decisions.jsonl` returns 2
    where it returned 1.

- Maps to: CHANGE AC-003
- Spec-AC-03: `fu-tripwire-removal-needs-a-gate` reads `done` in the folded
  registry, and the FIFTEEN pre-existing open tripwire items listed in this
  spec's headline are all still `open` — none of them is closed, dropped or
  edited by this scope.
  - Verification: `node .aai/scripts/follow-ups.mjs close --id fu-tripwire-removal-needs-a-gate
    --resolved-by the-tripwire-is-permanent-not-transitional --source <spec path>`
    exits 0 (it re-reads and re-folds the ledger itself), then
    `node .aai/scripts/follow-ups.mjs list --status open --json` is checked
    against the headline list: all fifteen ids present with status `open`, and
    `fu-tripwire-removal-needs-a-gate` absent from the open set and `done` in
    `--status all`.
  - ARITHMETIC NOTE (measured, not predicted): the raw count of OPEN items whose
    id contains `tripwire` is 16 both before and after this scope, and reading
    that as "nothing closed" would be wrong. Before: 15 defects + the gate item.
    After: the same 15 defects + `fu-tripwire-suite-comment-transitional`, a NEW
    P3 this scope filed under D5 because the false claim also sits in an
    executable file it may not touch. One item closed, one different item was
    filed, and the fifteen are untouched. The count is therefore not the
    observable; the named set is.

- Maps to: CHANGE AC-004
- Spec-AC-04 (**NARROWED after three gates, and the narrowing is the finding**):
  the AUTHORITATIVE record — the superseding `hitl_decision`, `SPEC-0137`,
  `SPEC-0138` and `CHANGELOG.md`'s unreleased entries — is corrected in place
  with a dated block. Every other document in the isolation programme carries at
  least one dated block pointing at that record. **Completeness across the whole
  corpus is NOT claimed**, and every instance found after this spec froze is
  marked rather than folded into a claim of having found them all.

  Why the AC changed, since a narrowed criterion is exactly what a reader should
  distrust: as originally written it asserted that a repeat of the sweep returns
  no uncorrected hit, and named that repeat as its own verification — so its
  evidence procedure was its own hypothesis, falsifiable only by disobeying it.
  Three independent gates disobeyed it and each found live hits by a different
  route: validation round 1 a DIRECTORY hole (`CHANGELOG.md` at the repo root),
  round 2 a REGEX hole (present-tense "are deleted" unmatched), code review a
  PER-FILE hole (one correction block placed, later occurrences in the same
  document left standing). Three methods, three misses, all in the detector and
  none in the underlying facts. A fourth pass asserting completeness would be a
  guess wearing a measurement's clothes, which is the defect this whole
  programme exists to remove. The claim is therefore reduced to what was
  actually verified.
  - Verification, and note what it is NOT: the sweep is re-run and every hit it
    returns is either inside a `CORRECTION (2026-08-23)` block, inside a
    historical record under `docs/ai/{validation,reviews,reports,tdd}`, inside
    this scope's own intake or spec, or named by
    `fu-tripwire-suite-comment-transitional`. **A clean re-run is NOT evidence
    of completeness** — it is the same detector that missed a directory, a
    tense, and later occurrences within an already-corrected file. It is
    retained as a cheap regression check on the hits that ARE known, and code
    review flagged that keeping it unqualified after diagnosing it would be the
    contradiction this scope exists to remove. The completeness question is
    answered by reading the enumerated 51 tracked files, which this scope did
    not do and does not claim (`fu-claim-sweep-needs-reading-not-regex`, P2).

- Maps to: CHANGE AC-005
- Spec-AC-05: `git diff --stat` for this scope names ZERO executable files —
  specifically no `.sh`, `.mjs` or `.ps1` path at all, and in particular not
  `.aai/scripts/lib/repo-tripwire.sh`, `tests/skills/test-framework.sh` or
  `.aai/scripts/aai-run-tests.sh`.
  - Verification: `git diff --stat main...HEAD` plus `git status --porcelain`,
    piped through `/usr/bin/grep -cE '\.(sh|mjs|ps1)$'`, returns 0 matches
    (grep exit 1). The three named files are additionally checked by name.

## Acceptance Criteria Status

| Spec-AC    | Description                    | Status      | Evidence       | Review-By   | Notes                          |
|------------|--------------------------------|-------------|----------------|-------------|--------------------------------|
| Spec-AC-01 | SPEC-0137's transitional claim carries a dated correction in place and the original claim text survives unmodified | done | DONE: SPEC-0137 carries dated CORRECTION blocks; the transitional sentence stays visible with the withdrawal beside it. Validation rounds 1 and 2 and two review passes each re-derived the underlying reach measurement independently and it held every time | — | frozen spec corrected the LEARNED.md way |
| Spec-AC-02 | WHEN a reader reaches the 2026-08-19 hitl_decision THEN the superseding 2026-08-23 entry is reachable from it by a verbatim text quote, and the old line is byte-identical | done | DONE: a superseding hitl_decision is appended, never a rewrite. It quotes the withdrawn sentence VERBATIM so a grep for the old claim returns two lines, the later withdrawing the earlier. Measured 1 to 2; re-verified at three later heads. Reopening condition is three measurable clauses, all currently false | — | append-only; no back-pointer exists so one is manufactured in text |
| Spec-AC-03 | Exactly one registry item closes and the fifteen named tripwire defects are all still open and untouched | done | DONE and stated honestly: exactly one item closed (fu-tripwire-removal-needs-a-gate), fifteen tripwire defects stay open, and the open tripwire-id COUNT reads 16 before and after because these rides file new ones as they go. The spec says to audit the named set, never the count | — | the fifteen are listed in this spec's headline; the raw open count stays 16 because this scope FILED one new tripwire-id item - see the arithmetic note under Spec-AC-03 |
| Spec-AC-04 | The authoritative record is corrected and every programme document points at it; corpus-wide completeness is explicitly NOT claimed | done | NARROWED after three gates and the narrowing is disclosed in the AC title. Claims only what was verified: the authoritative record is corrected, every programme document points at it, corpus-wide completeness is NOT claimed. Re-review judged the narrowing honest on the test that goalpost-moving narrows INSTEAD of fixing while this did both | — | six documents corrected, one executable surface filed |
| Spec-AC-05 | git diff --stat names zero executable files | done | DONE: git diff --name-only 07e6d81..HEAD contains zero .sh/.mjs/.ps1, re-derived independently by both validation rounds and both review passes. Ledgers show 0 deletions and main stays a byte-exact prefix | — | hard boundary of the scope |

## Implementation plan

Components affected — documents and ledgers only:
1. `docs/specs/SPEC-0137-...md` — correction block after line 320, and a second
   one after the "mooted by the disposable-worktree successor" sentence (line 335-336).
2. `docs/specs/SPEC-0144-...md` — correction on the "the guard this unlocks the
   removal of" link line and on the "what the next ride removes" conclusion.
3. `docs/specs/SPEC-0145-...md` — correction on the "the guard whose removal this
   is the second input to" link line.
4. `docs/issues/CHANGE-0151-...md` — correction on "the ratchet as a whole is transitional".
5. `docs/issues/CHANGE-0156-...md` — correction on "The tripwire is explicitly transitional".
6. `docs/issues/CHANGE-0157-...md` — correction on "Once the tripwire is gone".
7. `docs/ai/decisions.jsonl` — ONE appended `hitl_decision` line, plus the
   `follow_up_status` line the CLI appends for the close and the `follow_up`
   lines for the two filings.

Data flow: the ledger append is the authority; every document correction cites
its timestamp, which is what makes the append reachable from the documents.

Edge cases:
- The close CLI and the file CLI both append to `decisions.jsonl`; the
  hand-appended `hitl_decision` must not interleave inside a CLI write. Order:
  hand-append first, verify the file parses, then run the CLI commands.
- A document may already be `done`/frozen. That is expected and is exactly why
  the correction is additive.
- The intake's own text and this spec both contain the word "transitional" by
  necessity; the sweep must not treat the scope's own documents as hits.

## Test Plan

Strategy is `untested`: NO test file is created (a committed test would itself
be an executable file in the diff, violating Spec-AC-05). Each row below is a
command run against the shipped tree; its exit code and output are the evidence.

| Test ID  | Spec-AC    | Type       | File path (expected)       | Description                  | Status  |
|----------|------------|------------|----------------------------|------------------------------|---------|
| TEST-001 | Spec-AC-01 | check | no new file — command over docs/specs/SPEC-0137-spec-suites-must-not-touch-the-shipping-repo.md | grep asserts a CORRECTION (2026-08-23) block exists, the original "all go" sentence is still present, and the superseding timestamp is cited | pending |
| TEST-002 | Spec-AC-02 | check | no new file — command over docs/ai/decisions.jsonl | git diff --numstat reports 0 deletions; a node read-back parses the appended hitl_decision and asserts supersedes.ts, supersedes_quote and reopens_when are present and non-empty; the old decision's sentence now matches twice | pending |
| TEST-003 | Spec-AC-03 | check | no new file — command over the folded follow-up registry | follow-ups.mjs close exits 0 with its own re-read confirmation, then the open list filtered on ids containing tripwire returns 16, NOT 15 — this ride and its gates filed new tripwire-named items while closing one, which is exactly why Spec-AC-03 says to audit the NAMED SET and never the count. Codex caught this row still asserting the pre-filing number | pending |
| TEST-004 | Spec-AC-04 | check | no new file — sweep over .aai, docs and tests | the recorded sweep is re-run and every remaining hit is inside a correction block, a historical record, this scope's own documents, or the filed executable surface | pending |
| TEST-005 | Spec-AC-05 | check | no new file — command over the scope diff | git diff --stat and git status --porcelain contain no .sh, .mjs or .ps1 path, and the three named files are absent by name | pending |

## Verification

Commands:

```
# TEST-004 sweep (the authority for Spec-AC-04)
for f in $(/usr/bin/grep -rlniE "tripwire|known.offender|ratchet" .aai docs tests \
      --include="*.md" --include="*.sh" --include="*.mjs" --include="*.yaml" \
      --include="*.yml" --include="*.ps1" --include="*.json" \
    | /usr/bin/grep -vE "^docs/(_archive|ai/(validation|reviews|reports|tdd|briefs))" | sort); do
  /usr/bin/grep -niE "transitional|temporar|will be (removed|deleted|gone)|goes away|go away|all go|to be deleted|is moot|mooted|short-lived|interim|stopgap|no longer needed|scheduled for removal|unlocks the removal|whose removal|once the tripwire" "$f"
done
```

Evidence artifacts: the sweep output before and after; `git diff --numstat` for
`docs/ai/decisions.jsonl`; the `follow-ups.mjs` close read-back; `git diff --stat`.

PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status. This
role leaves every AC row at `implementing`; Validation owns the flip.

## Evidence contract

- ref_id: `the-tripwire-is-permanent-not-transitional`
- Spec-AC and TEST links: as tabled above, 1:1
- command or review scope: the five verification commands; review scope is the
  eight paths listed under `## Isolation and review`
- exit code: recorded per command in the implementation hand-off
- evidence path: command output captured in the hand-off and in
  `<scratch>/permanent-ride-progress.log`
- commit SHA or diff range: base `main` at 07e6d81, branch `docs/tripwire-is-permanent`

### Evidence by strategy

Strategy is `untested`: the evidence this spec demands is the recorded strategy
rationale plus the scoped diff and the exit codes of the five verification
commands. NO stored RED artifact and no test suite is demanded for the scope
itself, and none may be added — a new test file would violate Spec-AC-05.

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
