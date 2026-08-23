# Code Review (round 2, narrow re-review) — the-tripwire-is-permanent-not-transitional

```yaml
review:
  scope: "41d8655..a684442 (narrow re-review); AC-005 measured against base 07e6d81"
  spec: docs/specs/SPEC-DRAFT-spec-the-tripwire-is-permanent-not-transitional.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-04, call: compliant, citation: "narrowed claim verified part by part: authoritative record (hitl_decision 2026-08-23T20:05:00Z; SPEC-0137 x2 blocks; SPEC-0138:80-88; CHANGELOG both unreleased entries at :113 UPDATED and :160 WITHDRAWN) corrected in place; the four instances the previous review named are now marked at CHANGE-0152:70, CHANGE-0156:114 and :122, CHANGE-0157:84; each marker names a CORRECTION block that exists in its own document (CHANGE-0152:35, CHANGE-0156:56, CHANGE-0157:50); completeness explicitly disclaimed" }
      - { ac: Spec-AC-05, call: compliant, citation: "git diff --name-only 07e6d81..a684442 = 15 files, all .md/.jsonl; piped to /usr/bin/grep -cE '\\.(sh|mjs|ps1)$' -> 0 (exit 1); numstat decisions.jsonl 9/0, EVENTS.jsonl 2/0; cmp of base blob vs head's leading N bytes -> PREFIX-MATCH on both (343805 / 348802 bytes)" }
      - { ac: Spec-AC-03, call: compliant, citation: "re-checked because this review filed an item: open tripwire-id count still 16, fu-tripwire-removal-needs-a-gate still done/resolved_by this scope. The item filed below deliberately carries no 'tripwire' substring so AC-003's arithmetic is untouched." }
      - { ac: "Spec-AC-01 / -02", call: not-re-walked, citation: "unchanged by this diff; both re-derived independently at 41d8655 by the previous review" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: "docs/specs/SPEC-DRAFT-spec-the-tripwire-is-permanent-not-transitional.md", line: 278, issue: "the pre-narrowing Verification bullet survived verbatim under the new prose — the AC diagnoses a self-referential procedure as the defect and then keeps that procedure as its verification, unqualified", failure_scenario: "a reader who skims to 'Verification' reads a completeness assertion the paragraph above just retracted. Re-running the recorded sweep myself: every substantive hit sits immediately adjacent to a dated correction, so the bullet is WEAK, not false — but its enumeration also fails to account for its own benign hits (docs/INDEX.md:15/:417, docs/ai/STATE.yaml, and false positives on 'temporarily' at .aai/scripts/aai-run-tests.sh:249 and tests/skills/test-framework.sh:460)" }
      - { rank: NON-BLOCKING, file: "docs/specs/SPEC-DRAFT-spec-the-tripwire-is-permanent-not-transitional.md", line: 197, issue: "D6, the implementation plan (305-317) and the AC-004 Notes cell (300) all still undercount — predecessor's finding, unaddressed and now self-contradictory: AC-004 names SPEC-0138 as part of the authoritative record while D6's enumeration of corrected documents omits it", failure_scenario: "the direction is UNDERstatement (2 specs + 3 intakes claimed, 3 specs + 4 intakes corrected; 'one executable surface filed' where two were), so no reader is told more was covered than was. Filed as fu-spec-d6-enumeration-stale" }
      - { rank: NON-BLOCKING, file: "docs/specs/SPEC-0138-spec-suites-run-in-a-disposable-worktree.md", line: 87, issue: "'closed as moot' unaddressed — 4 occurrences at head (CHANGELOG:160 inside the quoted withdrawn text, which is correct there; CHANGELOG:165, SPEC-0138:87, CHANGE-0152:43 in the reviewer's own voice) against the authoritative wording used at CHANGE-0157 and in the hitl_decision", failure_scenario: "'moot' reads as 'stopped mattering' where reopens_when clause 3 restates the item's content as a live precondition. a684442 did NOT propagate it further — no new occurrence in this diff. Same follow-up" }
      - { rank: NON-BLOCKING, file: "docs/specs/SPEC-DRAFT-spec-the-tripwire-is-permanent-not-transitional.md", line: 258, issue: "the new AC's universal — 'every other document in the isolation programme carries at least one dated block' — does not define the programme set", failure_scenario: "TRUE under the natural reading (SPEC-0137/0138/0144/0145 + CHANGE-0151/0152/0156/0157: measured 1-2 dated blocks each). FALSE under a reading that includes the known-offender drain (SPEC-0146, CHANGE-0158: zero blocks) — though both already state permanence-consistent content (CHANGE-0158:78 'The tripwire is NOT being retired here and must not be') and neither needs correcting. Naming the set would close the only ambiguity left in an AC written to be unambiguous" }
  cannot_verify:
    - { claim: "no fifth uncorrected instance exists anywhere in the corpus", closes_with: "nothing — the spec no longer claims this, by design. Not attempted per dispatch." }
    - { claim: "CHANGE-0160 / SPEC-0148 are the numbers allocated at close", closes_with: "the close ceremony; carried forward unchanged from round 1" }
  overall: pass
```

## 0. Standing hazards

`.aai/SUBAGENT_CONTRACT.md` read in full. HAZ-RESTORE: no restoring git command run — base blobs were extracted with `git show` into the scratch root and compared with `cmp`. HAZ-SCRATCH: the two base-blob copies live under the dispatch's absolute scratch path; nothing was written to the shipping tree except the one append below. HAZ-CD: no `cd` outside the repo root. HAZ-LEDGER: one append to `docs/ai/decisions.jsonl` via `follow-ups.mjs add` (1 insertion, 0 deletions, read back); base remains a byte-exact prefix. HAZ-WORKTREE: none created. The spec's AC Evidence column was not touched.

## 1. The question that decides this: is the narrowed AC-004 honest?

**Honest.** The distinguishing test is not *whether* the criterion narrowed after three failures — it did, and that alone earns suspicion — but *what the narrowing covers*. Goalpost-moving would mean narrowing **instead of** fixing what was found. `a684442` does both: the four instances the previous review named are marked, and the claim is reduced only over the **unknown remainder**. Nothing that was found was written out of scope by the rewrite.

Against that, three properties make the disclosure hard to miss:

- The AC's own title carries it in bold — "**NARROWED after three gates, and the narrowing is the finding**" — so the narrowing is announced before the claim, not buried after it.
- "**Completeness across the whole corpus is NOT claimed**" is bold, in the claim sentence itself, not a footnote.
- A dedicated paragraph names each of the three failures and its distinct route (round 1 directory, round 2 regex, code review per-file) and gives the epistemic reason for stopping: "a fourth pass asserting completeness would be a guess wearing a measurement's clothes". A future reader cannot mistake this text for the original intent — the original wording is quoted inside the explanation.

And the lesson escaped the draft: `fu-claim-sweep-needs-reading-not-regex` (P2, read back `open`) records the same measurement in the durable registry, so the disclosure survives this spec's own archival. That is the difference between disclosing a limit and hiding behind one.

Each half of the narrowed claim was verified rather than trusted:

| Narrowed claim | Measured |
|---|---|
| superseding `hitl_decision` corrected | present, 2026-08-23T20:05:00Z, supersedes-quote verbatim (round 1 result, unchanged by this diff) |
| `SPEC-0137` | 2 dated blocks |
| `SPEC-0138` | 1 dated block (lines 80-88) |
| `CHANGELOG.md` unreleased entries | both — `**UPDATED 2026-08-23**` at :113, `**WITHDRAWN 2026-08-23**` at :160 |
| every other programme document carries >=1 dated block pointing at it | SPEC-0144 (2), SPEC-0145 (1), CHANGE-0151 (1), CHANGE-0152 (1), CHANGE-0156 (1), CHANGE-0157 (1) |

## 2. The four remediated instances

All four are marked, each with the same one-line dated form, and each points at a `CORRECTION` block that exists in the same document — verified by grep, not assumed:

| Instance | Marker | Target block | Followable |
|---|---|---|---|
| CHANGE-0152:69 | :70 | :35 | yes — exactly one block in the file, so "the CORRECTION block in this document" is unambiguous |
| CHANGE-0156:112-113 | :114 | :56 | yes |
| CHANGE-0156:119-120 | :122 | :56 | yes, and the marker adds the arithmetic correction inline ("exactly ONE registry item closed, not thirteen") against the line's "~13 registry items" — accurate |
| CHANGE-0157:83 | :84 | :50 | yes |

The markers are lighter than the nine full correction blocks (one italic line rather than a block citing the measurement and the timestamp), which is the right weight: the full block is one screen away in every case, and repeating it four times would bury the documents' actual content.

## 3. AC-005, independently

```
git diff --name-only 07e6d81..a684442                                  -> 15 files, all .md/.jsonl
  | /usr/bin/grep -cE '\.(sh|mjs|ps1)$'                                -> 0 (exit 1)
git diff --numstat 07e6d81..a684442 -- decisions.jsonl EVENTS.jsonl    -> 9/0 and 2/0 (zero deletions)
cmp base-blob vs head's leading N bytes                                -> PREFIX-MATCH x2 (343805 / 348802)
git status --porcelain (before this review's own filing)               -> empty
```

**Holds.** Re-derived, not carried over.

## 4. Does anything now overstate?

No. The two directions were checked separately:

- **Overstatement**: none found. The strongest residual is the retained Verification bullet (finding 1) — and re-running the recorded sweep at head shows every substantive hit sits immediately adjacent to a dated correction (SPEC-0137:318/320 -> :324, SPEC-0144:31 -> :33, SPEC-0145:35 -> :37, CHANGE-0151:72 -> :75, CHANGE-0156:46/51 -> :56, CHANGE-0157:48 -> :50, `test-aai-repo-tripwire.sh:529` -> named by `fu-tripwire-suite-comment-transitional`). So the bullet is weak, not false.
- **Understatement**: three places (finding 2). Stale enumerations that undercount the work actually done. Wrong, but in the safe direction — the failure mode this whole programme exists to prevent is a reader believing a withdrawn claim is live, and an undercount cannot cause that.

The predecessor's two non-blocking findings were **not** addressed. Neither got worse: `a684442` added no new "moot" text, and D6 was left as it stood. Both are now carried by `fu-spec-d6-enumeration-stale`.

## 5. Verdict

**PASS.** The stopping rule is respected: I have nothing that makes the shipped record **wrong**. What remains is (a) disclosed incompleteness, which the narrowed AC now states outright and which the registry now carries as a P2 lesson, and (b) three stale counts that understate. A fourth remediation round would buy corrections to enumerations no reader is harmed by, at the cost of a fifth gate on a record whose every underlying fact — the `--git-common-dir` reach measurement, the permanence decision, the registry arithmetic — has now held under four independent re-derivations.

The one thing worth an operator's eye at close: three gates failed on the detector and the response was to stop claiming what the detector cannot establish. That is the correct response, and it is also the reason this scope's *documentation* claims should not be reused as a template for a completeness claim elsewhere without `fu-claim-sweep-needs-reading-not-regex` being read first.

## Files changed by this reviewer

`docs/ai/decisions.jsonl` — one appended `follow_up` line (the filing below). This report. Nothing else; no correction was applied (report, do not fix).

## Filed

- `fu-spec-d6-enumeration-stale` (P3, `the-tripwire-is-permanent-not-transitional`) — stale enumerations in D6 / implementation plan / AC-004 Notes, plus the surviving "closed as moot" wording. Read back: `status: open`, `severity: P3`, `resolved_by: null`. Id deliberately excludes the substring `tripwire` so Spec-AC-03's open-count arithmetic (16, re-measured after the append) is unaffected.

## Blockers

None.
