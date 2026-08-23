# Code Review — the-tripwire-is-permanent-not-transitional

```yaml
review:
  scope: "07e6d81..41d8655 (branch docs/tripwire-is-permanent)"
  spec: docs/specs/SPEC-0148-spec-the-tripwire-is-permanent-not-transitional.md
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "docs/specs/SPEC-0137-...md: CORRECTION (2026-08-23) block present twice (grep -c = 2), original 'all go' sentence intact at its original line, superseding ts cited" }
      - { ac: Spec-AC-02, call: compliant, citation: "docs/ai/decisions.jsonl line 453 (hitl_decision); git diff --numstat shows 0 deletions on both ledgers; byte-exact prefix cmp confirmed against 07e6d81 blobs; grep -c 'are to be DELETED' = 2" }
      - { ac: Spec-AC-03, call: compliant, citation: "follow-ups.mjs list --status open/all --json: fu-tripwire-removal-needs-a-gate status=done resolved_by=this ref; open tripwire-id count = 16 (15 headline + fu-tripwire-suite-comment-transitional)" }
      - { ac: Spec-AC-04, call: non-compliant, citation: "docs/issues/CHANGE-0152-...md:69, docs/issues/CHANGE-0156-...md:112-113 and :119-120, docs/issues/CHANGE-0157-...md:83 — see BLOCKER below" }
      - { ac: Spec-AC-05, call: compliant, citation: "git diff --name-only 07e6d81..41d8655 | grep -cE '\\.(sh|mjs|ps1)$' = 0 (own re-run); git status --porcelain empty" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: "docs/issues/CHANGE-0152-suites-run-in-a-disposable-worktree.md", line: 69, issue: "a second, uncorrected restatement of the withdrawn claim ('the tripwire cannot be removed until this lands') sits 25 lines after the document's only CORRECTION block, in the 'Affected Area' section", failure_scenario: "a reader who opens this already-'corrected' document and reads past the Summary into Affected Area sees an unmarked claim implying this change (which has already landed) unblocks tripwire removal — exactly the belief the ride exists to withdraw, with no correction anywhere near it" }
      - { rank: BLOCKING, file: "docs/issues/CHANGE-0156-a-run-must-say-whether-isolation-armed.md", line: 112, issue: "'Do not delete the tripwire in this scope. This change makes deleting it *possible*' — the precise claim the 2026-08-23 hitl_decision falsifies (isolation does NOT make deletion possible; it stopped on its own AC-002) — sits in the Constraints section, ~50 lines after the document's only CORRECTION block", failure_scenario: "an implementer skimming Constraints/Notes (a common entry point, skipped-to more often than Impact prose) reads 'makes deleting it possible' and 'Unlocked but NOT in scope: deleting the tripwire' (line 119-120) as still-current framing" }
      - { rank: BLOCKING, file: "docs/issues/CHANGE-0157-a-half-seeded-checkout-says-it-is-isolated.md", line: 83, issue: "AC-004's own text still reads 'state whether it should become a gate when the tripwire is deleted', 25 lines after the document's only CORRECTION block, inside the Acceptance Criteria section — the part of an intake most likely to be read as a binding checklist", failure_scenario: "a reader auditing this closed change's ACs sees a live acceptance criterion framed around a deletion that will not happen" }
      - { rank: NON-BLOCKING, file: "docs/specs/SPEC-0138-spec-suites-run-in-a-disposable-worktree.md / docs/issues/CHANGE-0152-...md / CHANGELOG.md", line: 87, issue: "three of the nine correction blocks (SPEC-0138, CHANGE-0152, and both CHANGELOG entries) describe fu-tripwire-removal-needs-a-gate as 'closed as moot' — the withdrawn 2026-08-19 decision's own phrase — while the authoritative 2026-08-23 hitl_decision and CHANGE-0157's block use the accurate 'closed as a precondition for a deletion that is no longer planned, not as a defect that was fixed'", failure_scenario: "a reader who compares two of the six-plus corrected documents gets two different characterizations of what closing the one registry item meant; 'moot' reads as 'stopped mattering', but reopens_when clause 3 restates the item's full content as a live precondition, so 'moot' is the misleading word round 2 already flagged for CHANGELOG and it was freshly copied into two more documents by the very commit meant to close round 2 out" }
      - { rank: NON-BLOCKING, file: "docs/specs/SPEC-0148-spec-the-tripwire-is-permanent-not-transitional.md", line: 202, issue: "D6 enumerates 'two frozen specs beyond SPEC-0137 (SPEC-0144, SPEC-0145)' and 'three intake documents (CHANGE-0151, CHANGE-0156, CHANGE-0157)' — the shipped diff corrects a THIRD spec (SPEC-0138) and a FOURTH intake (CHANGE-0152), added by the round-2 remediation commit, without updating D6's own count", failure_scenario: "a reader trusting D6 as the authoritative enumeration of what got corrected undercounts by one spec and one intake and would not think to check SPEC-0138/CHANGE-0152 for completeness — which is exactly how this review found the BLOCKING items above were possible in the first place" }
  cannot_verify:
    - { claim: "D3 condition 2 (counterfactual re-measured with the tripwire actually removed exits non-zero)", closes_with: "a fixture run against a build where the tripwire is actually deleted; out of this scope's own boundary (AC-005 forbids removing it here) and out of this review's boundary to construct" }
    - { claim: "CHANGE-0160 / SPEC-0148 (the numbers cited in both CHANGELOG entries) will be the numbers actually allocated at close", closes_with: "observing the close ceremony; today they are the next free numbers and no other draft is in flight, confirmed by max(CHANGE-0159, SPEC-0147) in docs/issues and docs/specs" }
  overall: fail
```

## 0. Standing hazards (SUBAGENT_CONTRACT.md, read this dispatch)

Read `.aai/SUBAGENT_CONTRACT.md` in full before starting. No restoring git commands were
run (HAZ-RESTORE n/a — read-only review). No `cd` into scratch (HAZ-CD n/a). No worktree
was created (HAZ-WORKTREE n/a — all verification ran against the checked-out tree with
plain `git diff`/`git show`/`git cat-file`). Ledger reads were read-only; no append was
made by this review (HAZ-LEDGER n/a — nothing was written to `decisions.jsonl` or
`EVENTS.jsonl` by this pass). AC Evidence column of the spec's AC Status table was not
touched (per dispatch instruction re: `fu-ac-table-flip-trips-false-open`).

## 1. The enumerate-and-read pass

Dispatch estimated "roughly 25" files. The actual count of **git-tracked** files
mentioning `tripwire`, `ratchet`, or `known.offender` (case-insensitive, whole repo,
`.git` and gitignored paths excluded) is **51**, not ~25. (A naive filesystem grep before
filtering to tracked files returns ~1,900 — almost all of it gitignored per-run
`tests/skills/results/*.tripwire-{before,after}` snapshot artifacts from the isolation
suite's own instrumentation, confirmed via `git check-ignore -v`, not repository content.)

All 51 tracked files were opened and every matching line inspected in context (grep with
context first, then a full-section `Read`/`sed` for anything ambiguous). Below: every file
where the tripwire's future is described at all, and my judgment on whether that
description is now true.

| # | File | Says about the tripwire's future | Now true? |
|---|---|---|---|
| 1 | `docs/ai/decisions.jsonl:289` (2026-08-19 `hitl_decision`) | "the tripwire, its known-offender ratchet and the ratchet-path hashing are to be DELETED" | **False** — left byte-identical by design (D1); withdrawn by the 2026-08-23 entry at line 453, verbatim quote confirmed (`grep -c "are to be DELETED"` = 2) |
| 2 | `docs/ai/decisions.jsonl:453` (2026-08-23 `hitl_decision`) | "PERMANENT: their removal is not scheduled" | **True**, independently re-derived (worktree `--git-common-dir` probe) |
| 3 | `docs/specs/SPEC-0137-...md:318-320` | original: "all go" | **False**, corrected in place, correction accurate |
| 4 | `docs/specs/SPEC-0137-...md:335-342` (2nd correction, "mooted by...") | corrected | accurate |
| 5 | `docs/specs/SPEC-0138-...md:74-77` | original: "They are deleted by a separate change" | **False**, corrected in 41d8655 — correction accurate, but see BLOCKING/NON-BLOCKING findings above for a wording nit |
| 6 | `docs/specs/SPEC-0144-...md:154-166` | original: "is the PRECONDITION for deleting"/"the next ride removes" | **False**, corrected, accurate |
| 7 | `docs/specs/SPEC-0145-...md:37-42` | original: "input to [a] removal" | **False**, corrected, accurate |
| 8 | `docs/specs/SPEC-0145-...md:209` | "Should it become a gate when the tripwire is deleted? No —" | hypothetical whose conclusion is unaffected by the reversal; non-blocking per round 2, still holds |
| 9 | `docs/issues/CHANGE-0151-...md:72` | original: "the ratchet as a whole is transitional" | **False**, corrected, accurate |
| 10 | `docs/issues/CHANGE-0152-...md:31-33` | original: "deleted by a separate one" | **False**, corrected in 41d8655, accurate |
| 11 | **`docs/issues/CHANGE-0152-...md:69`** | "the tripwire cannot be removed until this lands" | **False, UNCORRECTED** — new finding, see BLOCKER |
| 12 | `docs/issues/CHANGE-0156-...md:45-53` | original: "explicitly transitional"/"cannot be removed until..." | **False**, corrected, accurate |
| 13 | **`docs/issues/CHANGE-0156-...md:112-113`** | "This change makes deleting it *possible*" | **False, UNCORRECTED** — new finding, see BLOCKER |
| 14 | **`docs/issues/CHANGE-0156-...md:119-120`** | "Unlocked but NOT in scope: deleting the tripwire" | **False, UNCORRECTED** — new finding, see BLOCKER |
| 15 | `docs/issues/CHANGE-0157-...md:47-48` | original: "second input to deleting" | **False**, corrected, accurate |
| 16 | **`docs/issues/CHANGE-0157-...md:83`** | "state whether it should become a gate when the tripwire is deleted" | **False, UNCORRECTED** — new finding, see BLOCKER |
| 17 | `docs/issues/CHANGE-0158-...md:78` | "The tripwire is NOT being retired here and must not be" | **True**, consistent, no correction needed |
| 18 | `CHANGELOG.md:108-116` | original (SPEC-0138 copy): "Deleting them is a follow-on change" | **False**, corrected, accurate ("recorded as permanent, not pending deletion") |
| 19 | `CHANGELOG.md:145-166` | original (SPEC-0137 copy): "records that ... are deleted" | **False**, corrected, accurate; tense-edit issue round 2 flagged (`records`→`recorded`, `now filed`→`then filed`) was reverted in 41d8655 (confirmed via `git diff 2e2c21c..41d8655 -- CHANGELOG.md`) |
| 20 | `tests/skills/test-aai-repo-tripwire.sh:529-531` | "the ratchet is transitional ... once suites run in a disposable worktree" | **False**, filed (not fixed, correctly — AC-005), `fu-tripwire-suite-comment-transitional`, read back `open`/P3 |
| 21 | `tests/skills/test-aai-suite-isolation.sh:637-639` | "the hard precondition for deleting the tripwire" | **False**, filed in 41d8655, `fu-isolation-suite-presumes-deletion`, read back `open`/P3 |
| 22-51 | remaining 30 tracked files | unrelated `tripwire`/`ratchet` usage (a *different* mechanism: SPEC-0007's legacy-ratio tripwire, SPEC-0143's pipe-grep-q ratchet, CHANGE-0040/0109's diet/phantom-API ratchets, SPEC-0146/CHANGE-0158's known-offender-list drain, the vendored library's own docstring, generated indices/HTML, and 11 historical `docs/ai/reviews/*` reports correctly left untouched per D6) | no live claim; confirmed true negatives by reading each |

Rows 11, 13, 14, 16 are the finding: **four more live, false, uncorrected instances of the
exact withdrawn claim, inside three documents that each already received exactly one
correction block elsewhere in the same file.** All four sit in structurally distinct
sections (Affected Area, Constraints, Notes, Acceptance Criteria) that a reader can reach
without passing the section that was corrected.

## 2. The corrections — accuracy and mutual consistency

Read all nine correction blocks (SPEC-0137 ×2, SPEC-0138, SPEC-0144 ×2, SPEC-0145,
CHANGE-0151, CHANGE-0152, CHANGE-0156, CHANGE-0157) side by side.

- Every block leads with a withdrawal, names the measurement, and cites the superseding
  `hitl_decision` timestamp. None reads as a tidy-up. Each names the honest arithmetic
  ("fifteen tripwire defects stay open") rather than letting closure of one item read as
  progress.
- **Inconsistent phrasing found** (finding above, NON-BLOCKING): SPEC-0138, CHANGE-0152,
  and both CHANGELOG entries use "closed as moot" — the *withdrawn* decision's own words
  — for `fu-tripwire-removal-needs-a-gate`. The authoritative `hitl_decision` and
  CHANGE-0157's block use "closed as a precondition for a deletion that is no longer
  planned, not as a defect that was fixed" — accurate, since `reopens_when` clause 3
  restates the item's full content rather than discarding it. Round 2 already flagged
  this exact imprecision for the CHANGELOG; the 41d8655 remediation reproduced it fresh
  in two more documents instead of converging on the accurate wording it had available
  in CHANGE-0157.
- SPEC-0137's second correction, SPEC-0144's two corrections, and SPEC-0145's correction
  all independently derive and restate the same fact (worktree shares `--git-common-dir`)
  without contradicting each other on the mechanism.

## 3. AC-005, independently

```
git diff --name-only 07e6d81..41d8655   # 14 files, all .md/.jsonl
git diff --name-only 07e6d81..41d8655 | grep -cE '\.(sh|mjs|ps1)$'   -> 0 (exit 1)
git status --porcelain                                               -> empty
git diff --numstat 07e6d81..41d8655 -- docs/ai/decisions.jsonl docs/ai/EVENTS.jsonl
  -> decisions.jsonl  8  0     EVENTS.jsonl  2  0     (0 deletions each)
byte-exact prefix (base blob at 07e6d81 vs head's leading N bytes, cmp) -> PREFIX-MATCH x2
```

**AC-005 holds exactly as claimed**, independently re-derived, not trusted from either
validation round's transcript.

## 4. The superseding mechanism, at this head

`grep -c "are to be DELETED" docs/ai/decisions.jsonl` → 2. The 2026-08-19 entry (line 289)
is untouched — `decision` field still contains the string verbatim, confirmed by direct
node read-back. The 2026-08-23 entry's `supersedes_quote` is character-identical to it.
**Still holds.**

Judged against `fu-decisions-appended-out-of-ts-order` (P3, known, not refiled): the four
2026-08-23T19:5x lines were appended in the same physical order flagged by round 1 — the
`hitl_decision` (ts 20:05:00Z, line 453) still sits physically before three follow_up
lines timestamped 19:54:50Z–19:55:02Z (lines 454-456). The mechanism (text-quote
back-pointer, not physical ordering) is unaffected by this — a reader or grep locates both
lines by content, not position — so the out-of-order append does not defeat D2's mechanism,
only its aesthetics. Consistent with round 1's own judgment; not reopened here.

## 5. The reopening condition (D3), re-verified at this head

| Clause | Measured now | Status |
|---|---|---|
| 1. `fu-isolated-suite-reaches-shipping-repo` closed with "cannot reach" evidence | `follow-ups.mjs list --status all --json`: `status: "open"`, `resolved_by: null` | **FALSE** (correct) |
| 2. Counterfactual re-measured with tripwire removed exits non-zero | nothing in this diff removes the tripwire; not measurable today | **FALSE** (correct) |
| 3. Isolation report ships as a gate in the same change that deletes | nothing here deletes anything | **FALSE** (correct) |

All three remain false, so the decision is self-consistent — nothing here should already
be reopened. **D3 holds.**

## 6. The count claim

```
follow-ups.mjs list --status open --json | filter id contains "tripwire"  -> 16 items
```
The 16 = the 15 headline-named ids (all `open`, unedited — confirmed base-tree id
extraction shows only additions, no edits, already covered by AC-005's byte-exact-prefix
proof) + `fu-tripwire-suite-comment-transitional` (new, `open`). `fu-tripwire-removal-needs-a-gate`
reads `status: "done"`, `resolved_by: "the-tripwire-is-permanent-not-transitional"` in
`--status all`. **The named set is complete and none of its members is already closed.**
Confirmed independently — this is not a re-trust of either validation round's numbers.

## 7. Judgment — should this ship at all?

**No, not as submitted at 41d8655.** The counter-argument the dispatch names is real: every
failure across three rounds (round 1's directory hole, round 2's regex hole, this review's
within-document completeness hole) has been in the *sweep*, and every underlying fact —
the worktree reach measurement, the permanence decision, the registry arithmetic — has
held up under three independent re-derivations, including mine. That is a genuinely strong
signal that the record's *content* is correct.

But the record's *job* is to stop a reader from encountering the withdrawn claim
unmarked, and this review — reading, not grepping, exactly as instructed — found it
unmarked four more times, in three documents each already touched twice (once for their
own correction, once when CHANGE-0152 got its correction added in this final commit). A
sweep that fails a third time, in a third distinct way, on a document set of 14 changed
files and 51 total tripwire-mentioning files, is not bad luck — it is what happens when
"find every instance of a sentence" is implemented as "find the first instance of a
sentence per document" three times running. The base rate the dispatch asked me to weigh
now includes this review's own finding, and it points the same direction: **stop
patching this sweep and instead read each of the nine already-touched documents start to
finish**, which is a fixed, small, enumerable task (nine files, none longer than a few
hundred lines) — not another regex iteration.

**Recommendation: FAIL. Remediate the four new instances (rows 11, 13, 14, 16) with the
existing dated-correction convention** — cheap, `.md`-only, no filing needed since AC-004's
"file it" branch applies only to executable surfaces. Then have the *next* validation round
open each of the nine touched documents in full rather than re-running the recorded sweep
command, because the recorded sweep has now failed to find a live hit in its own declared
scope on its first, second, and third outing.

## 8. Judgment — is AC-004 satisfied in substance or only in form?

**Neither, currently — it is unsatisfied even in form**, because its own verification
text ("a repeat of the sweep returns no uncorrected, unfiled hit") is *literally* false
right now: rows 11, 13, 14, 16 are uncorrected, unfiled hits inside AC-004's own declared
`docs/**` scope. Round 2's structural critique — the AC's evidence procedure is its own
hypothesis, satisfiable only by disobeying it — is not merely still valid, it is the
exact mechanism that let these four instances through a second and third time: nobody
disobeyed the sweep's command to go and read the touched files end to end, so the sweep
kept reporting itself clean. Until AC-004 is rewritten the way round 2 already proposed —
whole-repository scope with an enumerated historical exclusion, plus "read every file that
mentions the term" as the acceptance evidence rather than a maintained regex — it will
keep passing on the recorded command and failing on inspection, which is what has now
happened three times.

## Files changed (by this reviewer)

None in the scope tree. This report only. No `.md` correction was applied (out of scope
per "do not fix what you find — report it"). No worktree created, none to remove. No
ledger entries appended.

## Filed

None. All four new findings (rows 11, 13, 14, 16) are BLOCKING spec_compliance findings
inside `docs/**`/`.md` files — AC-004's own text requires them corrected in place, not
filed, since the "file it" branch is reserved for executable surfaces this scope's AC-005
forbids editing. Filing them as follow-ups would misuse the same escape hatch AC-004
reserves for a narrower case. The two NON-BLOCKING findings (wording inconsistency,
D6 staleness) are recommended for **remediate-in-tree** disposition (cheap, same commit
that fixes the BLOCKING items) rather than a follow-up ref, per H6.

## Blockers

1. `docs/issues/CHANGE-0152-suites-run-in-a-disposable-worktree.md:69` — uncorrected.
2. `docs/issues/CHANGE-0156-a-run-must-say-whether-isolation-armed.md:112-113` — uncorrected.
3. `docs/issues/CHANGE-0156-a-run-must-say-whether-isolation-armed.md:119-120` — uncorrected.
4. `docs/issues/CHANGE-0157-a-half-seeded-checkout-says-it-is-isolated.md:83` — uncorrected.

Each is the same withdrawn claim this ride exists to correct, inside AC-004's own declared
scope, in a document that already received one correction elsewhere. Remediation: add the
same dated `**CORRECTION (2026-08-23).**` block immediately after each, per the D1
convention already used nine times in this diff.
