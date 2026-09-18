# Code Review — spec-close-ceremony-sweep

```yaml
review:
  scope: git diff main..HEAD (feat/close-ceremony-sweep @ e53f2848, base main 7270a29c) — 85 files, +9359/-444, 49 commits
  spec: docs/specs/SPEC-DRAFT-spec-close-ceremony-sweep.md (35 Spec-AC, 72 Test Plan rows, 22 Amendments)
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,      citation: "check-committed-scope.mjs REGEXP_WS_OR_COMMA split; TEST-520 (test-aai-learned-routing.sh); round1 C1 held the second arm under mutation" }
      - { ac: Spec-AC-02, call: compliant,      citation: "nothing-left-behind.mjs checkFocusRef + refIdentity set; TEST-521/522; round1 NB-4/NB-5 name the residual narrowness, not a gap in the AC" }
      - { ac: Spec-AC-03, call: compliant,      citation: "nothing-left-behind.mjs roadmapPairedOpen; TEST-523" }
      - { ac: Spec-AC-04, call: compliant,      citation: "close-reconcile.mjs missingCloseEvidence; TEST-524/525/526; round1 T2 (both conjuncts unpinned) closed by Amendment 16's conjunct-level mutation" }
      - { ac: Spec-AC-05, call: compliant,      citation: "close-reconcile.mjs specByRequirement fallback; TEST-527" }
      - { ac: Spec-AC-06, call: compliant,      citation: "close-work-item.mjs:1795 `slugs = [ref, ...spec, ...paired]` joins the existing resolve/plan/snapshot/rollback pipeline; TEST-528/529; round1 V2 verified no second invocation" }
      - { ac: Spec-AC-07, call: compliant,      citation: "close-work-item.mjs:1670-1679 (skip preserves collected commands) + :1189 formatMutationNotice; TEST-530/531. See NB-6: two shapes now produce severity 'skip'" }
      - { ac: Spec-AC-08, call: compliant,      citation: "close-work-item.mjs:1338-1352 findProblems resolves by `d.rel === rel`; TEST-532" }
      - { ac: Spec-AC-09, call: compliant,      citation: "close-work-item-pin.sh allowed-hash array 15->16, one entry; TEST-533; round1 V2 re-verified the exit contract and regen tail byte-identical" }
      - { ac: Spec-AC-10, call: compliant,      citation: "CHANGE-0181 / ISSUE-0040 status done with real PR+commit; TEST-534/535" }
      - { ac: Spec-AC-11, call: compliant,      citation: "docs-model.mjs:1173-1280 column-set + status-vocabulary kinds; docs-audit-core.mjs:1203-1214 terminal partition; TEST-536/537/582. Design objection in BLOCKING-2 / NB-1, not an AC gap" }
      - { ac: Spec-AC-12, call: compliant,      citation: "docs-audit-core.mjs declaredCount > parsedCount; TEST-538" }
      - { ac: Spec-AC-13, call: compliant,      citation: "docs-model.mjs:1182-1187 leanAccepted suppression; TEST-539/540. Scope caveat in NB-2 (doc-level fact, table-level decision)" }
      - { ac: Spec-AC-14, call: compliant,      citation: "spec-lint.mjs:96 `import { maskSpecimens as maskCode }`; no second masker remains (grep: one import, one call site); TEST-541" }
      - { ac: Spec-AC-15, call: compliant,      citation: "docs-audit-core.mjs idMentionMap one-git-call probe; TEST-542. Selector-name deviation disclosed by Amendment 16 after round1 NB-9" }
      - { ac: Spec-AC-16, call: compliant,      citation: "SPEC_TEMPLATE.md legend names a docs/ai/tdd artifact; TEST-543" }
      - { ac: Spec-AC-17, call: compliant,      citation: "follow-ups.mjs BULLET_STRUCTURAL_LABEL_RE + requiredStatus; TEST-544..548/578/579; round1 C2 held under mutation" }
      - { ac: Spec-AC-18, call: compliant,      citation: "follow-ups.mjs ID_MAX_LEN unfilable branch; TEST-549; round1 C3 held in both directions" }
      - { ac: Spec-AC-19, call: compliant,      citation: "spec-amend.mjs renameSync atomic write; TEST-550" }
      - { ac: Spec-AC-20, call: compliant,      citation: "spec-amend.mjs restamp; TEST-551/552; round1 V9 exercised the restamp on this ride's own spec" }
      - { ac: Spec-AC-21, call: compliant,      citation: "intake templates carry `number:`; TEST-553. Round1 NB-12: the finding's own arithmetic (seven vs six) was off; the fix is complete" }
      - { ac: Spec-AC-22, call: compliant,      citation: "docs-model.mjs:643-674 walkTracked + :617-627 existsOnDisk; TEST-554/555/576/577/581. Round1 T4 (ENOENT distinction unpinned) closed by TEST-581" }
      - { ac: Spec-AC-23, call: compliant,      citation: "docs-model.mjs:676-687 isTrackedFile; generate-overview.mjs `stateIsTracked ? state : null`; TEST-556; round1 V5 verified the committed artefact" }
      - { ac: Spec-AC-24, call: compliant,      citation: "generate-factory-report.mjs registry.unreadable null; userguide-rollup existence guard; docs-audit exit split; TEST-557/558/559" }
      - { ac: Spec-AC-25, call: compliant,      citation: "intake-staleness-check.mjs runMain onError; TEST-560" }
      - { ac: Spec-AC-26, call: compliant,      citation: "intake-staleness-check.mjs `b !== '.'` sentinel; TEST-561" }
      - { ac: Spec-AC-27, call: compliant,      citation: "tests/skills/lib/no-nul-guard.sh; TEST-562" }
      - { ac: Spec-AC-28, call: compliant,      citation: "pipe-grep-q-ratchet.sh rc capture; golden-flow hitl_entries filter; TEST-563/564" }
      - { ac: Spec-AC-29, call: compliant,      citation: "ride-select.mjs isFirstUnfinished + findDoc + readIntake via parseFrontmatter/DOC_TYPE_ENUM; TEST-565/566/567/583/588. Round1 B5 (planned-pair exemption) closed by Amendments 16/17/18" }
      - { ac: Spec-AC-30, call: non-compliant, citation: "the AC's own second clause — 'each commit the PR ceremony makes SHALL be verified against what it staged' — is delivered (SKILL_PR 4c/5c, TEST-568), but CHANGELOG.md carries NO entry for this ride: SKILL_PR step 3b names root CHANGELOG.md an expected companion for every feat/fix scope and the branch has ~30 of them. See BLOCKING-3" }
      - { ac: Spec-AC-31, call: non-compliant, citation: "CHANGELOG.md:12 ADDS a second statement of a convention .aai/SKILL_PR.prompt.md:146 already made on main (verified: `git show main:.aai/SKILL_PR.prompt.md` line 135). The AC says 'stated once'; the ride went from one statement to two. It also names `<type>: <title>` as the shape 'aai-release enforces', but aai-release.sh's awk entry classifier matches only `^## \\[unreleased\\] — `. TEST-570 greps the preamble and never counts statements, so nothing catches it. See BLOCKING-2" }
      - { ac: Spec-AC-32, call: compliant,      citation: "prompt-diet-ledger.sh two entries (+2359, +232) = +2591 measured; TEST-012/572; round1 V1 and round5 §9 both recomputed to the byte" }
      - { ac: Spec-AC-33, call: compliant,      citation: "append-event.mjs:169-221 + lib/pr-sweep.mjs sweepContradictions/parseSweepCount; TEST-573/584/585/586. The four named contradictions are enforced. The open `reviewer_bots` vocabulary is outside the AC's four and is filed as NB-3" }
      - { ac: Spec-AC-34, call: cannot-verify,  citation: "lane-gate.mjs --sweep-check + claude-hook-gate.sh merge gate exist and deny correctly for a missing/lane-mismatched/contradictory record (TEST-574/587). But (a) the PreToolUse overlay that would run the hook is not installed in this repo (round1 B2-EXTRA, disclosed in the AC text itself), so the gate is not in force on this ride's own merge, and (b) the read side accepts an outcome value the writer refuses — see BLOCKING-1. The AC's literal text ('a claim WITHOUT that record is refused') survives; its purpose does not" }
      - { ac: Spec-AC-35, call: compliant,      citation: "generate-docs-index.mjs violations companion terminal filter; TEST-575; round1 V6 verified no companion is written on this branch" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/lane-gate.mjs, line: 462,
          issue: "The read side of the pr_sweep gate never validates the outcome vocabulary. lib/pr-sweep.mjs exports PR_SWEEP_OUTCOMES as a closed set and append-event.mjs:180 refuses anything outside it, but lane-gate.mjs imports only sweepContradictions — and sweepContradictions has no rule for an unrecognized outcome, so every per-outcome branch falls through and the record reads as consistent.",
          failure_scenario: "Reproduced in a scratch fixture: a hand-appended line {\"event\":\"pr_sweep\",\"payload\":{\"pr\":999,\"lane\":\"heavy\",\"reviewer_bots\":\"none\",\"threads_seen\":0,\"threads_unresolved\":0,\"outcome\":\"totally_fine\"}} yields `SWEEP-CHECK allowed pr=999 lane=heavy outcome=totally_fine`, rc=0 — the merge is allowed on an outcome append-event.mjs would refuse to write. A hand-appended EVENTS line is the exact and only threat model this read side exists for (validation-round1 NB-2, the reason lib/pr-sweep.mjs was created)." }
      - { rank: BLOCKING, file: CHANGELOG.md, line: 12,
          issue: "Spec-AC-31 ('each convention stated once, where its tool reads it') is implemented by ADDING a second statement of the [unreleased] heading convention that .aai/SKILL_PR.prompt.md:146 already carried on main, and the added sentence attributes to aai-release an enforcement it does not perform (the `<type>: <title>` portion is unmatched by aai-release.sh:262).",
          failure_scenario: "A maintainer edits the convention in one of the two places. aai-release keeps working (it never read either), SKILL_PR keeps instructing the old shape, and TEST-570 — which only greps the preamble for the literal `## [unreleased] — <type>` — stays green. This is the duplication class the AC was written to remove, created by the AC's own delivery." }
      - { rank: NON-BLOCKING, file: .aai/scripts/check-vendored-script-deps.mjs, line: 455,
          issue: "The v3.1 fix masks quoted strings but not `#` comments, so the stated property ('a name is a call edge only when it sits in COMMAND POSITION') is still false, and the SCOPE section does not name the gap. Measured on the live corpus: 21 call edges exist only because a function name appears in a comment, three of them of the exact validation-round5 B1-R5 shape (test-aai-branch-guard.sh test_006 -> main, test-aai-deslop.sh test_002_diff_scope_added_symbol_only -> main, test-aai-git-ref-guard.sh test_301_guarded_refusal -> main).",
          failure_scenario: "Not load-bearing today — I re-ran the checker with comments stripped and it stays CLEAN, 0 violations, 77 sites, and no comment-derived edge originates from a vendoring function. It bites the first time a vendoring function's body carries a comment naming a helper (e.g. `# built on top of setup_iso_repo`), which silently grants that function the helper's whole coverage — v2's rejected file-wide masking, revived through a comment instead of a string." }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/docs-audit-core.mjs, line: 1205,
          issue: "The comment justifying the terminal/non-terminal partition asserts a mechanism that does not exist: 'A terminal doc ... cannot newly reach done with a broken table — the table only gates OPEN work'. Nothing requires a `--check --strict` run while a document is open (validation-round1 NB-7, still unremediated at HEAD).",
          failure_scenario: "A document created `draft` with a bare-`AC` table and flipped to `done` inside one PR reaches main with the malformation permanently exempt; every later strict run reports it under `### Near-miss AC tables` and exits 0. The exemption is a defensible trade; the stated reason is not the reason it holds." }
      - { rank: NON-BLOCKING, file: .aai/scripts/lane-gate.mjs, line: 391,
          issue: "resolveDefaultSpecFromState is a near-verbatim copy of readStrategy (:168 in the same file): same indent-scanning loop, same degrade-to-null, differing only in the top-level block name and the leaf key.",
          failure_scenario: "A STATE.yaml shape change (indentation, a quoted scalar, a comment on the key line) must be fixed in two places in one file; fixing one leaves the other silently returning null, which for --sweep-check means 'no spec' -> heavy lane -> a lane-mismatch DENY on a fast-lane ride. One `readStateScalar(statePath, block, key)` collapses both." }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/pr-sweep.mjs, line: 19,
          issue: "`reviewer_bots` is the only field in the pr_sweep record with an open vocabulary — lane is fast|heavy, outcome is a closed set, the counts and --pr are integer-validated, but --reviewer-bots accepts any non-empty string (append-event.mjs:179 checks truthiness only). Both contradiction rules that read it compare against the exact literal 'expected'.",
          failure_scenario: "Reproduced: `--reviewer-bots expectd --outcome internal_substituted --threads-seen 0` is accepted by the writer and then allowed by --sweep-check. A one-character typo in the field that means 'bots were expected' converts the record into a legal 'I reviewed it myself instead' claim. Close it with a REVIEWER_BOTS enum beside PR_SWEEP_OUTCOMES." }
      - { rank: NON-BLOCKING, file: .aai/scripts/claude-hook-gate.sh, line: 133,
          issue: "The deny-on-unresolvable-PR fires before the capability check. The gate resolves (or fails to resolve) the PR number at :116-131 and exits 2 at :132-141, but whether the sweep check can run at all is only tested at :143 (`command -v node` and `[ -f lane-gate.mjs ]`). It also sits against the file's own header claim at :4 ('contains ZERO gate logic of its own') — 20 lines of argv parsing plus a verdict now live in the adapter.",
          failure_scenario: "An operator-directed `gh pr merge --squash` on a machine with no node (or a layer install missing lane-gate.mjs), or offline so `gh pr view` fails, is denied with a message about a sweep record that nothing would have checked. Hoisting the two capability tests above the PR resolution makes the refusal-to-guess fire only where the gate could actually have judged." }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/docs-model.mjs, line: 1052,
          issue: "The module now holds three jobs: document vocabulary + markdown parsers (pre-existing), git-index queries that spawn subprocesses (isGitWorkTree/existsOnDisk/walkTracked/isTrackedFile, :591-687, new), and a close-ceremony artefact inventory (SHARED_GENERATED_PAGES, :1052, new). See 'The docs-model question' below for the split and its cost.",
          failure_scenario: "Recurring tax rather than a bug: validation-round5 §2 measured that lib/docs-model.mjs is the one path that escalates suite selection to FULL_RUN (reason=shared-lib). Every future edit to the eight-page list — a list that changed three times inside this ride alone — therefore costs a full 95-suite sweep. This ride edited docs-model.mjs in 6 commits." }
      - { rank: NON-BLOCKING, file: .aai/scripts/close-work-item.mjs, line: 1586,
          issue: "planStateReconcile now produces `severity: 'skip'` two different ways: the `skip()` helper at :1586, which always empties commands/echo, and the inline return at :1679, which preserves them. Nothing in the code says which a new skip path should use.",
          failure_scenario: "A future third skip condition added after the work-item arm reaches for the obvious `skip(reason)` helper and silently re-introduces the exact bug Spec-AC-07 fixed (a collected set-phase command dropped from the returned plan). `skip(reason, { commands, echo })` with one shape removes the choice." }
      - { rank: NON-BLOCKING, file: .aai/scripts/check-vendored-script-deps.mjs, line: 414,
          issue: "The v1/v2/v3 design rationale is written out twice, near-verbatim, inside one file (:52-81 in the header docstring and :414-458 as an inline comment), and a third time in the spec's Amendment 21. The file is 640 lines of which 314 (49%) are comment; across the whole diff, 1230 of 2651 added .aai/scripts lines (46%) are comment-ish, much of it round-by-round archaeology ('validation-round5 B2-R5', 'NB-2 (validation-round2)', 'v3 (this version, as first shipped)').",
          failure_scenario: "A maintainer fixing the call-graph design updates one copy. The other keeps asserting the superseded rationale, and the next reviewer cannot tell which is current — the same failure the ride's own amendment convention exists to prevent, reproduced inside a source file. Keep ONE statement of 'why not the simpler design' (it is load-bearing); move the round narration to the amendments, where it already lives." }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-DRAFT-spec-close-ceremony-sweep.md, line: 554,
          issue: "The AC Status table is internally inconsistent about which canon rule it follows. Spec-AC-29/30/31 were flipped to `done` with tdd-log Evidence at commit 0ecb03db while the doc's frontmatter is `status: implementing` (the ROLE_COMMON G4 pre-handoff shape); the other 32 rows stay `planned` with empty Evidence (the VALIDATION 8a AC-FLIP DEFERRAL shape). Nothing in the spec says why three rows are different.",
          failure_scenario: "Measured: `docs-audit.mjs --gate spec-close-ceremony-sweep` exits 1 naming all 32 planned rows; `--ac-flip-check` exits 0. A reader of the table cannot tell `planned` = 'not built' from `planned` = 'built, flip deferred', and the close ceremony's flip will have to distinguish them by hand. Pick one rule for the table and say which in the Verification section." }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-DRAFT-spec-close-ceremony-sweep.md, line: 1005,
          issue: "Three commits carry another ride's document ids: 1d2f95b9, 15a178fc and 838869fe are subtitled `(CHANGE-0186 / SPEC-0180, Amendment 19/20/21)`. CHANGE-0186 / SPEC-0180 is the dispatch-state-sweep ride, already merged to main as #382; this ride's own docs are CHANGE-DRAFT-close-ceremony-sweep / SPEC-DRAFT-spec-close-ceremony-sweep, both `number: null`.",
          failure_scenario: "After merge, `git log --grep=SPEC-0180` attributes three close-ceremony commits to a spec that never asked for them, and any provenance walk from SPEC-0180's links.commits forward finds work it does not own. Still cheap to fix by reword before the PR; unfixable in shared history afterwards." }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/docs-model.mjs, line: 1187,
          issue: "`leanAccepted` and `neitherParses` are document-level facts computed once (:1182-1187) but consumed inside the per-table loop. For `neitherParses` that is the documented intent; for `leanAccepted` it is not — it suppresses the `heading` warning for EVERY table in the document.",
          failure_scenario: "A spec carrying a gate-accepted lean AC table plus a second, malformed table under an '## Acceptance Criteria (draft)' heading gets no `heading` warning for the malformed one, because the other table parses. The near-miss report exists precisely to say 'this table reads as absent, the verdict may be inaccurate', and here it stays silent. The single-AC-table assumption is pre-existing in this module; the new dependence on it is not." }
      - { rank: NON-BLOCKING, file: .aai/scripts/close-work-item.mjs, line: 1795,
          issue: "The three slug slots (--ref, --spec, --paired) are concatenated with no distinctness check, and the ride added the third without adding one.",
          failure_scenario: "`--spec X --paired X` (a plausible copy-paste when the paired half IS the spec-adjacent doc) resolves the same document twice, so it appears twice in `plan` and `refPairs`; the second pass mutates an already-mutated file and the ceremony emits two work_item_closed events for one doc into an append-only ledger. One `new Set(slugs)` (or an explicit usage error) closes it; no Test Plan row covers the case." }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/pr-sweep.mjs, line: 44,
          issue: "`parseSweepCount(raw, field)` is now the parser for `--pr` as well (append-event.mjs:197), but its name says 'count' and its own doc comment at :34 still says 'A pr_sweep count field (--threads-seen / --threads-unresolved)'. The PR-specific rule (no PR 0) then lives outside it, at append-event.mjs:207.",
          failure_scenario: "A maintainer relaxing the count rule (e.g. to allow a count of `-1` for 'unknown') silently relaxes PR-number parsing too, and the `pr === 0` guard three lines away is the only thing left holding the PR floor. Rename to `parseNonNegativeInt` and let the two callers keep their own floors, or give it an explicit `{ min }`." }
  cannot_verify:
    - { claim: "Spec-AC-34's merge gate actually stands between this ride and its own merge.",
        closes_with: "A .claude/settings.json (or user-level settings) wiring PreToolUse Bash -> claude-hook-gate.sh merge. validation-round1 B2-EXTRA measured that no such wiring exists in this worktree, the primary checkout, or ~/.claude. The AC's text is honest about the overlay being opt-in; nothing in this diff installs it." }
    - { claim: "The full test-framework sweep is green at HEAD (e53f2848).",
        closes_with: "One `env -u AAI_ROLE AAI_TEST_TIMEOUT=3000 bash tests/skills/test-framework.sh` at e53f2848. validation-round5 measured 95/95 at 2762264e; two production commits (838869fe's guard rewrite, 1f942686's +305/-27) and one telemetry commit landed after that measurement. I did not re-run the sweep (Validation's job, running concurrently)." }
    - { claim: "check-vendored-script-deps.mjs's SCOPE section is complete about what it cannot see.",
        closes_with: "It is demonstrably not complete for comments (measured above). The three ESM shapes (dynamic import, re-export, side-effect import) are named; the per-line quoting model's behaviour on a double-quoted string spanning lines is neither named nor measured — my own cross-line probe was defeated by heredoc quoting and returned no trustworthy number. A heredoc-aware cross-line measurement would close it." }
    - { claim: "The 22 amendments' factual claims about counts, bytes and prior states are all true at HEAD.",
        closes_with: "Rounds 1-5 checked Amendments 1-21 sentence by sentence and found (and corrected) four false ones. Amendment 22 — the newest, answering round 5 — has had no independent round against it; its 'the guard's own claims are now true' headline is the one I measured and partially falsified (comments, above)." }
    - { claim: "No downstream consumer of the AAI layer breaks on ride-select.mjs's new sequential roadmap admission.",
        closes_with: "A dry run of `ride-select.mjs gate` against a consumer project's own docs/ai/roadmap.yaml. The change turns 'any capability on the roadmap passes' into 'only the first unfinished pair passes'; that is a behaviour change visible to every vendoring project and it has no CHANGELOG line (BLOCKING-3)." }
  overall: fail
```

## Scope and method

Reviewed `git diff main..HEAD` in `/Users/ales/Projects/aai-feat-close-ceremony-sweep` (never the primary checkout), `AAI_ROLE=subagent`, read-only: no file in the tree was edited, no commit made, no STATE written. Two probes ran against throwaway copies of the checker under the session scratchpad and one against a scratch fixture repo; `docs/ai/EVENTS.jsonl` line count was identical before and after every command I ran (2324).

I read `.aai/ROLE_COMMON.md`, `.aai/SKILL_CODE_REVIEW.prompt.md`, the frozen spec, and validation rounds 1 and 5 in full. **Note on the dispatch:** it named `validation-round{1..6}.txt` and "five validation rounds"; the tree holds five (`validation-round1..5.txt`, no round 6). The dispatch also named 84 files / 47 commits; measured, `git diff main..HEAD` is 85 files / +9359/-444 over 49 commits.

**Coaching-attempt note (anti-gaming contract).** The dispatch named the areas to "look hardest at" and, in two places, characterised what I would find there ("it has become this ride's junk drawer", "is the partition principled or is it a shape fitted to keep eight historical documents quiet"). Recorded as required; I reviewed the whole diff and reached my own calls, including disagreeing with part of the junk-drawer framing below. The dispatch also located the specimen masker, `splitRawTableCells`, `TERMINAL_DOC_STATUS` and the table-header resolution in `lib/docs-model.mjs`; the masker lives in `lib/docs-audit-core.mjs:1104` (`maskSpecimens`), and the other three were already on main before this ride.

## The three findings that matter

### 1. The merge gate allows a record its own writer would refuse (BLOCKING)

`lib/pr-sweep.mjs` exists because validation-round1 NB-2 showed the read side re-checked one of four contradictions. The fix was right: one predicate, imported by both sides. But the module exports *two* things — `sweepContradictions` **and** `PR_SWEEP_OUTCOMES` — and only the writer imports the second.

```
$ node lane-gate.mjs --sweep-check --pr 999 --repo-root <fixture>
SWEEP-CHECK allowed pr=999 lane=heavy outcome=totally_fine     rc=0
```

The record was hand-written into `docs/ai/EVENTS.jsonl`. `append-event.mjs`'s `PR_SWEEP_OUTCOMES` check would have refused it. `sweepContradictions` has a rule for each of the three legal outcomes and no rule for a fourth, so an unrecognized outcome matches nothing and reads as consistent; `lane-gate.mjs:462` then prints it and exits 0.

A hand-appended ledger line is not an edge case for this gate — it is the entire threat model it was built for, stated in `lib/pr-sweep.mjs:6-9` and in `lane-gate.mjs`'s own comment at :450 ("a hand-appended line (bypassing the writer entirely) can carry any combination of fields"). The fix is one line at `lane-gate.mjs:456`, immediately before the `sweepContradictions` call:

```js
if (!PR_SWEEP_OUTCOMES.has(recOutcome)) { /* deny reason=unknown-outcome */ }
```

and one more import name. I would also move the check *into* `sweepContradictions` so the two sides cannot diverge again by import list — which is the shape the module's own header already promises.

### 2. Spec-AC-31 delivers the duplication it was written to remove (BLOCKING)

The AC: *"Each convention SHALL be stated once, where its tool reads it: the `CHANGELOG.md` preamble names the per-entry `[unreleased]` heading shape that `aai-release` enforces."*

Measured:

- `git show main:.aai/SKILL_PR.prompt.md` line 135 already said ``add a `## [unreleased] — <type>: <title>` entry``. That statement is untouched at HEAD (`.aai/SKILL_PR.prompt.md:146`).
- This ride added `CHANGELOG.md:12`, which states the same shape again.
- `aai-release.sh`'s awk entry classifier matches `/^## \[unreleased\] — /` and nothing more. The `<type>: <title>` half is not enforced anywhere, so the preamble names a shape its tool does *not* read — the precise inversion of the AC's own wording.
- `TEST-570` greps the preamble for the literal `## [unreleased] — <type>` and asserts exits 12 and 13 are named. It never counts statements, so the AC's central property is unpinned.

The SUBAGENT_CONTRACT half of the AC was done correctly — a cross-reference, with `TEST-571` pinning one statement rather than two. The CHANGELOG half did the opposite and no test noticed. Either make `SKILL_PR.prompt.md:146` a cross-reference to the CHANGELOG preamble (the AC's own pattern), or drop the preamble addition and point the preamble at SKILL_PR. Then give TEST-570 a corpus count, the way TEST-571 has one.

### 3. The checker built to end false-completeness claims still carries one (NON-BLOCKING, but this is the one I would not let pass unnamed)

`check-vendored-script-deps.mjs:455` says the v3.1 fix means "a name is a call edge only when it sits in COMMAND POSITION — never inside a quoted string literal". Comments are not command position and are not masked.

Measured on the live corpus by re-running the shipped scanner against a comment-stripping variant: **21 call edges exist only because a function name appears in a `#` comment.** Three are the exact `test_fn -> main` shape that validation-round5 B1-R5 called blocking:

```
tests/skills/test-aai-branch-guard.sh   test_006                              -> main
tests/skills/test-aai-deslop.sh         test_002_diff_scope_added_symbol_only -> main
tests/skills/test-aai-git-ref-guard.sh  test_301_guarded_refusal              -> main
```

It is **not load-bearing today**: with comments stripped the checker still reports `CLEAN — 0 violation(s) (77 vendored engine site(s) checked)`, and none of the 21 edges starts at a function that vendors an engine. So this is a NON-BLOCKING finding, not a fourth round of the same bug. But the SCOPE section — the section whose honesty round 5 made a blocking issue — does not name it, and the inline comment states the opposite. Two fixes, in order of preference: strip `#` comments in `maskQuotedRegions` (four lines, and my probe shows the verdict is unchanged), or, if that is out of scope, add the measured 21 to the SCOPE list the way B2-R5's 15-of-77 was added.

Worth stating plainly, because it is the pattern: this file has now made a completeness claim in three consecutive rounds (Amendment 21's "cannot break this fixture silently again", v3's "never to an unrelated function", v3.1's "only in COMMAND POSITION") and each has been narrower than claimed. The class is not the regex; it is writing the claim in the same commit as the fix, before anything measures it. A cheap structural answer: make the SCOPE section's numbers a `--json` output the suite asserts, so the docstring cannot be more confident than the corpus.

## The docs-model question

Asked directly: is `lib/docs-model.mjs` one module with one job?

No — three, and two of them arrived this ride. At HEAD it is 1386 lines and 40 exports:

1. **Document vocabulary and markdown parsers** (pre-existing): the status/type enums, `parseFrontmatter`, `parseAcTable`, `parseLeanAcTable`, `parseTestPlanTable`, `splitRawTableCells`, `resolveTestPlanHeaderKey`, `detectNearMissAcTable`. Coherent. This is the module's job.
2. **Git-index queries** (:591-687, new): `isGitWorkTree`, `existsOnDisk`, `walkTracked`, `isTrackedFile`. These spawn subprocesses. A pure-text parsing library now imports `node:child_process` and has failure modes that include "git is not installed".
3. **A close-ceremony artefact inventory** (:1052, new): `SHARED_GENERATED_PAGES` — eight paths that are a fact about what `close-work-item.mjs`'s regen tail writes, not a fact about documents. Its two consumers are `pr-platform.mjs` and `orchestration-dispatch.mjs`; nothing inside docs-model reads it.

What I would split, and what it costs:

- **`lib/generated-pages.mjs`** for (3): ~8 lines plus its comment block, two import-line changes. **The real benefit is measured:** validation-round5 §2 found `lib/docs-model.mjs` is the one path that escalates suite selection to `FULL_RUN reason=shared-lib`. The page set changed three times inside this ride; each future change currently buys a full 95-suite sweep. Split, it buys the two suites that read it. This also gives round 5's B3-R5 (the `aai-pr-platform` suite-map row) a precise anchor instead of a shared-lib blanket. Cost: one PROFILES `core:` entry, one suite-map row, and the new import edge must be carried by any fixture that vendors `pr-platform.mjs` — which the ride's own `check-vendored-script-deps.mjs` will now catch. Perhaps 30 minutes.
- **`lib/git-tracked.mjs`** for (2): ~100 lines moved, four import sites (`generate-docs-index.mjs`, `generate-overview.mjs`, `lib/docs-canon-core.mjs`, and `allocate-doc-number.mjs`'s own disclosed copy of `isGitWorkTree`, which stays where it is until a ceremony-3 ride). Benefit is smaller and mostly hygienic: the parser module goes back to being testable without a git work tree. Cost is the same mechanics plus more fixture churn.

Recommendation: do the page-set split; it pays for itself in sweep time. Treat the git-query split as a tracked follow-up, not a merge blocker — it changes no behaviour and this ride is seven remediation rounds deep. **Neither belongs in this PR**: a module split at this point is churn on a branch whose remaining risk is in its claims, not its structure.

## The Amendment 3 partition

Is the terminal/non-terminal partition principled, or fitted to keep eight documents quiet?

It is a **proxy, not a principle** — but the trade it makes is right and I would not block on it.

The near-miss check is structural: can the audit engine parse this table? A document's frontmatter lifecycle status has no causal relationship to whether its markdown table is well-formed. `TERMINAL_DOC_STATUS` was picked because all eight live near-miss documents happen to be `done` (the amendment says so in its own first paragraph: "8 documents, all `done`"), and because it was already imported. That is fitting, not deriving.

The property actually wanted is "pre-existing, not newly introduced" — and this repository already has a purpose-built mechanism for exactly that, used three times in this very diff: a recorded baseline with a `--record` mode (`cd-subshell-leak-baseline.tsv`, `base-ref-pin-baseline.tsv`, `degenerate-pass-baseline.tsv`). A baseline pins the exemption to eight *named documents*; the status partition exempts a class of unbounded future membership, including every document a generator writes with `status: done`.

Two consequences, one already on record and one not:

- validation-round1 NB-7: the amendment's stated justification ("a document cannot newly reach a terminal status with such a table, because it fails strict while it is open") is not a mechanism — nothing forces a strict run while a doc is open. The claim is still in the source comment at `lib/docs-audit-core.mjs:1205` and is still wrong. That is the NON-BLOCKING finding above.
- Not previously recorded: the exemption is evaluated at audit time against *current* status, so it also covers `deferred`, `rejected`, `superseded`, `legacy` and `current` — statuses that were never part of the eight-document population the trade was measured on.

Cost of the principled alternative: one baseline TSV, a `--record` flag, and the honest downside a ratchet always carries — recording a baseline is a signed statement, and the next person to run `--record` can widen it without noticing (the exact hazard validation-round1 B1b named on `degenerate-pass-baseline.tsv`). Weighed against sixteen suites and a CI workflow that would have gone red, and against the ride's budget, the shipped trade is defensible. What is not defensible is the comment. **Fix the sentence, keep the partition, and file the baseline as a follow-up.**

## The `--paired` transaction

This is the cleanest work in the diff. `--paired` adds one element to an existing list (`close-work-item.mjs:1795`) and inherits resolution, status validation, the mutation plan, the snapshot map, both rollback call sites and the self-verify without a single new branch in the transaction body. The Spec-AC-08 change that lands beside it (`findProblems` resolving by `rel` instead of `id`, :1338-1352) is a genuine fix-at-cause for an id collision that would have rolled back a clean close forever. The `--stamp-pr` mutual exclusion is enforced at parse time (:298), and `runStampPr`'s own slug list at :1394 correctly does not grow. The one re-pin (Spec-AC-09) is a single new hash entry and validation-round1 V2 verified the exit contract and regen tail are byte-identical to main — the discipline the `close-work-item hash pin` rule asks for.

Two small things, both filed above: there is no distinctness check across the three slug slots, and `planStateReconcile` now has two shapes for one `skip` severity.

## The twenty-two amendments

Measured: the amendment block is lines 1005–1817 of an 1820-line spec — **812 lines, 45% of the document**. The frozen body is 1004 lines. The spec was touched in 23 commits after its freeze commit, 14 of them `docs(spec): Amendment N` with empty bodies.

Can a maintainer reconstruct what happened and why? **Yes, and better than most.** The convention holds: no amendment is edited in place, corrections are made by name in a later section, and validation-round5 §7 verified Amendments 1–19 byte-identical across two remediation commits. Four amendments correct an earlier amendment's factual sentence (18 §7 corrects 16; 20 §2 corrects 19; 21 corrects 20's TEST-567 diagnosis; 22 corrects 21's guard claims). That is an honest record and it is rare.

Can a maintainer tell what is **still true**? Not without reading all 812 lines in order. There is no superseded-marker, no index, and the corrections are prose paragraphs inside later sections rather than annotations at the point of the wrong sentence. A reader who opens Amendment 16 to understand the baseline re-record has no signal that Amendment 18 §7 says its sentence is false.

So: not "a changelog with a spec attached" — the frozen body is still the contract and is still intact. But the amendment block has outgrown the form. One cheap fix, four lines, at the head of the block:

```
Superseded sentences: A16 §baseline -> corrected by A18 §7 · A19 §NB-refs -> A20 §2
· A20 §TEST-567 -> A21 · A21 §"permanent guard" -> A22
```

That is the difference between a record that can be reconstructed and one that can be *read*.

## Commit hygiene

- **Wrong doc ids in three commit subjects** (filed above): `1d2f95b9`, `15a178fc`, `838869fe` cite `CHANGE-0186 / SPEC-0180`, which is the dispatch-state-sweep ride merged as #382. This ride's docs are `close-ceremony-sweep` / `spec-close-ceremony-sweep`, both `number: null`. Fixable by reword now; permanent after merge.
- **Two commit types with zero precedent** in main's 632 commits: `intake(change):` (`a4eca58d`) and `plan(spec):` (`7a2c291a`).
- **Subjects that mix concerns**, most notably `838869fe` — subject says "fixtures carry their own dependencies", body ships a new 388-line production guard plus PROFILES and suite-map registration plus edits to five unrelated suites. `1f942686` then rewrites that one-commit-old file by +305/−27 (a 72% rewrite).
- **Self-correction chain**: seven commits exist only to repair an earlier commit on the same branch, three of them consecutive ("TDD run 10 correction" ×3), one of which (`d396a0c2`) concedes in its own subject that it fixes "a Spec-AC-22 behaviour change this ride introduced".
- **Run numbering contradicts itself**: runs 1–5 say `N/11`, runs 6–12 say `N/12`, `80a23eb2` (labelled 12/12) is committed *before* three commits labelled 11/12, and `3d60f1fc`'s body says "run 11/11". No commit explains the re-plan.
- **12 of 49 commits lack the `Claude-Session:` trailer**; all 49 carry `Co-Authored-By`.
- Four `chore(telemetry)` commits (`74a42075`, `1a9f3445`, `2762264e`, `e53f2848`) are clean 3-line EVENTS+INDEX appends with no production code, but three have entirely empty bodies.

None of these is a code defect. The doc-id one is a false record, which in this codebase's own value system is the serious one.

## CHANGELOG

`.aai/SKILL_PR.prompt.md:144-151` makes root `CHANGELOG.md` an expected companion for every feat/fix scope, with 3–10 bullets naming the ref ids. This branch touches `CHANGELOG.md` **once**, adding the six-line preamble paragraph of Spec-AC-31, and adds **no `## [unreleased] —` entry of its own** across ~30 feat/fix commits and 9359 added lines.

The entry, when written, has to cover at least these user-visible changes, none of which is currently described anywhere an operator reads:

1. `ride-select.mjs` — the roadmap gate now admits only the first unfinished pair (was: any capability on the roadmap passes). **Behaviour change visible to every vendoring project.**
2. New guard `check-vendored-script-deps.mjs`, wired `core:` and into suite-map — a new hard gate.
3. New refusal `pr-platform.mjs --check-shared-page-conflicts`.
4. New CI workflow `.github/workflows/docs-numbering.yml`.
5. The `pr_sweep` record + `lane-gate.mjs --sweep-check` + the merge-hook obligation.
6. `follow-ups.mjs verify-closures` now refuses a blind or over-cap run.
7. `close-work-item.mjs --paired` (new flag, new usage refusal).
8. `spec-amend.mjs` — a renumbered frozen spec restamps instead of refusing (a reversal of a prior user-facing refusal).
9. docs-audit now reports present-but-unparseable AC tables and reconciles duplicate ids by multiplicity.
10. `docs-canon.mjs` stages its own writes and both sides of every move.
11. The intake staleness preflight moved to STEP 0; SKILL_INTAKE's block count went six → five.
12. INDEX and overview now derive from git-tracked content only.

Item 1 is the one that matters most: it is a refusal downstream projects will start seeing with no note telling them why.

## Warning dispositions (H6)

Recommended disposition per NON-BLOCKING finding — the orchestrator records these; I do not file refs.

| Finding | Recommended disposition |
|---|---|
| check-vendored-script-deps comment-derived call edges | remediate-in-tree (4 lines, verdict verified unchanged) |
| docs-audit-core:1205 comment states a mechanism that does not exist | remediate-in-tree (one sentence) + follow-up ref for the baseline alternative |
| lane-gate resolveDefaultSpecFromState duplicates readStrategy | remediate-in-tree (one helper) |
| pr_sweep `reviewer_bots` open vocabulary | remediate-in-tree (one enum beside PR_SWEEP_OUTCOMES) |
| claude-hook-gate deny-before-capability-check | remediate-in-tree (hoist two tests) |
| docs-model carries three jobs | promote-to-follow-up-ref (page-set split first; measured sweep-cost payoff) |
| close-work-item two `skip` shapes | remediate-in-tree (one parameter) |
| check-vendored-script-deps duplicated rationale block | remediate-in-tree (delete one copy) |
| AC table mixes G4 and AC-FLIP-DEFERRAL shapes | remediate-in-tree at the close flip; say which rule in Verification |
| three commits cite CHANGE-0186 / SPEC-0180 | remediate-in-tree (reword before the PR; impossible after merge) |
| `leanAccepted` doc-level fact, table-level use | promote-to-follow-up-ref (bounded by a pre-existing module assumption) |
| no distinctness check across --ref/--spec/--paired | remediate-in-tree (one `new Set`) or follow-up ref |
| `parseSweepCount` name/doc no longer match its use | remediate-in-tree (rename) |

## Verdict

**spec_compliance: fail** — Spec-AC-30 and Spec-AC-31 are non-compliant (the CHANGELOG obligation and the "stated once" inversion); Spec-AC-34 is cannot-verify. The other 32 rows are compliant with the citations above. The spec's own PASS criterion "every Spec-AC terminal" is, correctly, deferred to the close flip.

**code_quality: fail** — two BLOCKING findings.

Both are cheap: one line plus an import in `lane-gate.mjs`, and a decision about which of two files states the CHANGELOG convention. Nothing in this review asks for a redesign, and the three areas I attacked hardest (the `--paired` transaction, the shared-page derivation, the amendment discipline) are the strongest work I have reviewed in this repository.

---

# Round 2 — remediation review

```yaml
review_round2:
  scope: git diff e53f2848..d4be7112 (12 files, +722/-30, 1 commit) + one confirmation pass over round 1's NON-BLOCKING list
  spec_compliance:
    verdict: pass
    changed_rows:
      - { ac: Spec-AC-30, call: compliant, was: non-compliant,
          citation: "CHANGELOG.md now carries `## [unreleased] — feat(ceremony): ... (CHANGE-DRAFT-close-ceremony-sweep / SPEC-DRAFT-spec-close-ceremony-sweep)` with 9 bullets. `bash .aai/scripts/aai-release.sh --dry-run` (re-run here) rolls it up as the first entry, rc=0, and the notes preview renders it. The second clause (commit-vs-staged verification) was already delivered." }
      - { ac: Spec-AC-31, call: compliant, was: non-compliant,
          citation: "SKILL_PR.prompt.md:145-149 no longer restates the shape; it cross-references \"CHANGELOG.md's own preamble\" by name. The preamble now separates what aai-release.sh's awk classifier actually matches (`^## \\[unreleased\\] — `) from the `<type>: <title>` house convention, which is exactly true against aai-release.sh:261. TEST-570 now COUNTS (measured below). Residual, filed: two statements of the shape predate this ride on main (aai-release.sh:383 prints `'## [unreleased] — <title>'`, a DIFFERENT shape; SPEC-0063:75 states a third variant with `(<refs>)`), and TEST-570's count is scoped to two named files, so neither is seen." }
      - { ac: Spec-AC-33, call: compliant, unchanged_call_stronger_evidence:
          "sweepContradictions now validates outcome/lane/pr/threads_seen/threads_unresolved inside the one predicate. Round-1 NB-3 (reviewer_bots) is unchanged and widens — see R2-NB-1." }
      - { ac: Spec-AC-34, call: cannot-verify, was: cannot-verify,
          citation: "Limb (b) — the read side accepting a record the writer would refuse — is CLOSED (my repro is now denied; full matrix below). Limb (a) is unchanged: `.aai/templates/hooks/settings-hooks.json:2` says of itself 'OPT-IN: nothing installs this automatically', and this worktree has no `.claude/settings.json` at all, so the merge gate is still not in force on this ride's own merge. The AC's text discloses this; I keep the row at cannot-verify rather than downgrading it." }
  code_quality:
    verdict: pass
    blocking_1: closed
    blocking_2: closed
    findings:
      - { rank: NON-BLOCKING, id: R2-NB-1, file: .aai/scripts/lib/pr-sweep.mjs, line: 30,
          issue: "The new header comment says sweepContradictions is judged so that 'every field append-event.mjs validates before it will write a record must be judged here too', and Amendment 23 repeats it ('judges every field append-event.mjs validates'). Measured false for one field: the writer refuses a missing --reviewer-bots (`append-event.mjs:179`, verified: rc=2 'pr_sweep requires --reviewer-bots'), the reader does not.",
          failure_scenario: "Measured: a hand-appended record with NO reviewer_bots key at all, lane heavy, counts 0, outcome internal_substituted reads `SWEEP-CHECK allowed pr=999 lane=heavy outcome=internal_substituted`, rc=0. It reaches nothing round-1 NB-3's one-character typo did not already reach, so the RANK is unchanged — but the parity CLAIM is now stated twice and is measurably not true. Three lines (`if (!p.reviewer_bots) bad.push(...)`) make the sentence true and close NB-3's presence half at the same time." }
      - { rank: NON-BLOCKING, id: R2-NB-2, file: CHANGELOG.md, line: 42,
          issue: "The pr_sweep bullet tells an operator that \"`claude-hook-gate.sh`'s `merge` gate denies ... a merge with no matching, consistent record for that PR and lane\" with no mention that the PreToolUse overlay carrying that hook is opt-in and installed nowhere by default.",
          failure_scenario: "This is the ride's own cannot_verify #1 restated as an operator-facing fact. A vendoring project reads the changelog, believes merges are gated, and never runs `aai-bootstrap.sh --with-claude-hooks`; nothing denies anything. One clause ('when the hooks overlay is installed') fixes it." }
      - { rank: NON-BLOCKING, id: R2-NB-3, file: docs/specs/SPEC-DRAFT-spec-close-ceremony-sweep.md, line: 2019,
          issue: "Amendment 23's Verification paragraph names EIGHT staled rows (TEST-585; 538/539/541/542; 552/568; 570) and then says 'All seven were re-run LAST'. The work was done — all eight records carry mtimes 19:46:30–19:51:08 — only the count is wrong.",
          failure_scenario: "Not a defect in the work; a defect in the record, in the same paragraph class round 6 had just corrected two arithmetic errors in (62->58, 62+13=75!=71). Cheap to fix while the spec is still editable." }
      - { rank: NON-BLOCKING, id: R2-NB-4, file: CHANGELOG.md, line: 15,
          issue: "The rewritten preamble describes ONE of exit 12's two arms. aai-release.sh's awk marks MALFORMED both for a bare `## [unreleased]` with non-blank body (named) AND for any `## [unreleased]` heading carrying trailing text that is not the `— ` form (`:264-269`, the else branch) — which the shell's own refusal message at :326 does name ('unexpected trailing text or a stray heading-only body').",
          failure_scenario: "Conservative direction (the preamble under-claims rather than over-claims, which is the opposite of round 1's complaint), but an author who writes `## [unreleased] v2` gets exit 12 with nothing in the preamble having warned them." }
  cannot_verify:
    - { claim: "The full 95-suite framework sweep is green at d4be7112.",
        closes_with: "One `env -u AAI_ROLE AAI_TEST_TIMEOUT=3000 bash tests/skills/test-framework.sh`. I ran six suites' worth of targeted evidence (test-aai-release.sh full, plus the mutation gate, the vendored-deps checker, cd-subshell-leak and aai-release --dry-run); the sweep itself is Validation's, not mine." }
    - { claim: "Spec-AC-34's merge gate stands between this ride and its own merge.",
        closes_with: "Unchanged from round 1 and now measured at the source: the overlay template's own `_comment` declares it opt-in, and `.claude/` here holds only `skills/`." }
  overall: pass
```

## BLOCKING-1 — closed, and the vocabulary probed past the repro

My round-1 repro, re-run verbatim against a scratch fixture carrying `lane-gate.mjs` + `lib/` at d4be7112 (the worktree itself was never written; `docs/ai/EVENTS.jsonl` is 2324 lines before and after, `git status` clean):

```
round1-repro-unknown-outcome  rc=5  SWEEP-CHECK denied reason=contradictory-record ... outcome must be one of swept|skipped_fast_lane|internal_substituted, got "totally_fine"
```

The fix is in the right place. Putting the vocabulary check inside `sweepContradictions` rather than adding a second import to `lane-gate.mjs` means the two sides cannot diverge by import list again — which is what the module header promised and did not deliver. Full matrix I ran (18 records, one per line, `--sweep-check --pr 999`):

| record | verdict | denied by |
|---|---|---|
| `outcome: "totally_fine"` | DENIED rc=5 | the new vocabulary rule |
| unknown lane `"orbit"` | DENIED rc=5 | the **lane-mismatch** check, which fires first — the new `lane` rule is unreachable through the CLI, and TEST-574's fourth arm correctly pins it at the predicate level instead, disclosing exactly that |
| `threads_seen: -1` | DENIED rc=5 | new integer rule |
| `pr: 999.5` | DENIED rc=5 | `readPrSweepRecords`' `Number(...) === pr` filter never matches it -> missing-record |
| `threads_seen` key absent | DENIED rc=5 | new integer rule (`got undefined`) |
| **`reviewer_bots` key absent** | **ALLOWED rc=0** | nothing — see R2-NB-1 |
| extra field `merge_me: true` | ALLOWED rc=0 | nothing; the writer builds the payload from six fixed keys, so no consumer reads it — harmless, worth knowing |
| duplicate `outcome` keys, bad then good | ALLOWED rc=0 | JSON last-wins: a line a human reads as `totally_fine` is judged as `swept` |
| duplicate `outcome` keys, good then bad | DENIED rc=5 | same last-wins rule, other direction |
| record `pr` != `--pr` | DENIED rc=5 | filtered out -> missing-record |
| `pr: "999"` (string) | DENIED rc=5 | new type rule — and this one matters, because `Number("999") === 999` means the filter DID find it |
| `pr: "0x3e7"` | DENIED rc=5 | same |
| `threads_seen: "3"`, `threads_unresolved: "0"` | DENIED rc=5 | new type rule |
| `reviewer_bots: "expectd"` (round-1 NB-3) | ALLOWED rc=0 | unchanged, disclosed |
| `reviewer_bots: {}` | ALLOWED rc=0 | unchanged |
| `payload: null` | DENIED rc=5 | missing-record |
| `threads_unresolved: true` | DENIED rc=5 | new integer rule |

**Answer to the question as asked: identically-ish, not identically.** Five of the six payload fields are now judged by the same rule on both sides, verified in both directions. `reviewer_bots` is the sixth, and the divergence there is not only the open vocabulary round 1 filed — the writer refuses the field's *absence* and the reader does not. The remediation's own comment and Amendment 23 both assert full parity; that sentence is false by one field. I am not blocking on it, because it reaches nothing the already-NON-BLOCKING typo does not, but it is three lines from being true.

I also verified the RED side of the amendment's claim rather than taking it: with `lib/pr-sweep.mjs` reverted to e53f2848 in the fixture, all three hook-level arms return `rc=0 SWEEP-CHECK allowed` and the direct predicate call returns `CLEAN`. The four new TEST-574 arms are real RED-verified arms, not assertions written green.

One side effect worth recording: `append-event.mjs` now refuses a bad count twice (`parseSweepCount` at parse, `sweepContradictions` after). TEST-585's re-recorded mutation shows it — under mutation the writer still refuses, and the row reddens only because the message no longer names `--threads-seen`. The row still reddens, but it now pins a message string rather than the refusal itself. Disclosed in the record; no action asked.

## BLOCKING-2 — closed, judged as an operator

**Does the entry name what a consumer will notice?** Yes, and it leads with the right one. Bullet 1 is `ride-select.mjs`'s gate, stated as a behaviour change with the before-state named and an action for the reader ("re-run against your own `docs/ai/roadmap.yaml`"). Bullet 2 is the `--strict` near-miss hard-fail, and it names the partition precisely — `draft/proposed/accepted/implementing/frozen` hard-fail, the six terminal statuses report-only — which is more useful than the AC's own wording. Ten of the twelve items my round-1 list said the entry would have to cover are there; the two absent are the intake-staleness STEP 0 move and SKILL_INTAKE's block count, both AAI-internal and fairly dropped. `aai-release.sh --dry-run` rolls it up correctly (rc=0, rendered above the nine prior entries, scaffold preserved on top).

**Is the convention stated once, where its tool reads it?** The inversion my round-1 finding named is gone: the ride no longer *creates* a duplicate, SKILL_PR cross-references instead of restating, and the preamble now says precisely what the parser matches versus what is house style. That is the AC's property, delivered by the AC's own cross-reference pattern.

It is still not literally once in the corpus, and both extra statements predate this ride on main (`git show main:` confirms both):

- `.aai/scripts/aai-release.sh:383` prints, to the operator, `Add a '## [unreleased] — <title>' section for each` — a **different shape**, missing `<type>:`, inside the tool itself.
- `docs/specs/SPEC-0063-spec-aai-release-skill.md:75` states a third variant, `## [unreleased] — <type>: <title> (<refs>)`.

Not this ride's regression, so not a blocker on this ride — but the ride now ships a counting test, and the count does not see either. Filed.

**Does TEST-570 really count?** Yes. The suite passes at HEAD (`test-aai-release.sh`: ALL TESTS PASSED, TEST-570 green). I ran the new count block verbatim against mutated copies:

| mutation | TEST-570 |
|---|---|
| baseline | PASS |
| a third statement added inside `CHANGELOG.md` | **FAIL** `changelog_hits=2 (want 1)` |
| the SKILL_PR restatement re-added | **FAIL** `skill_pr_hits=1 (want 0)` |
| the cross-reference phrase removed from SKILL_PR | **FAIL** `missing cross-reference` |
| a statement added to a **third file** (`.aai/SKILL_RELEASE.prompt.md`) | PASS — invisible |

So the answer is: it counts, in the two files the finding named, in all three directions. It is a two-file count, not a corpus count, and `aai-release.sh:383` is live proof that a third file is where the next one actually lives. Widening the count to a corpus grep is the same three lines.

## The three truth-fixes

**1. `docs-audit-core.mjs` — the terminal partition.** Correct, and it now says what I asked and a little more: it names `TERMINAL_DOC_STATUS` a PROXY, states the counterexample (a doc created `draft` with a broken table and flipped to `done` in one PR reaches main exempt), names why the proxy holds today (all eight measured documents are and always were `done`), and names the baseline alternative with the three baseline files this same diff already uses. The diff is comment-only; behaviour is untouched. This is the fix, not a hedge.

**2. `#`-comment masking — verified by measurement, not by reading.** I instrumented the shipped checker and a variant with the four-line `#` branch removed, dumped every call edge from both, and diffed the sets:

```
edges v3.2 (shipped) = 6622    edges v3.1 (no # masking) = 6643
removed by # masking = 21      added by # masking = 0
```

The 21 removed are exactly the comment-derived edges I measured in round 1, including all three `test_fn -> main` cases (`test-aai-branch-guard.sh test_006`, `test-aai-deslop.sh test_002_...`, `test-aai-git-ref-guard.sh test_301_...`). Nothing was over-masked. Both variants report `CLEAN — 0 violation(s) (77 vendored engine site(s) checked)`, so the corpus verdict and the site count are unchanged, as claimed.

The word-boundary rule holds. Unit-probing `maskQuotedRegions` directly:

```
"n=${#arr[@]}; helper_a"        -> unchanged; names: n, helper_a
"base=${var#pattern}; helper_b" -> unchanged; names: base, helper_b
"v=${var##*/}; helper_c"        -> unchanged; names: v, helper_c
"if [ $# -gt 0 ]; ..."          -> unchanged
"echo \"count=${#list[@]}\"; helper_e" -> dquote-masked only; names: echo, helper_e
"helper_f # built on top of setup_iso_repo" -> names: helper_f  (setup_iso_repo gone)
"x=\"$(helper_g --flag)\"  # note helper_h" -> names: x, helper_g  (helper_h gone)
```

`${#...}` and `${var#...}` are preceded by `{` and `r`, never whitespace, so the branch cannot fire on them — bash's own rule, implemented as bash implements it. I also verified the round-6 correction behind the SCOPE rewrite independently: instrumenting the pre-round checker (`838869fe`) at its `existsSync` push point prints `SITES 58`, so `58 + 13 + 6 = 77` closes and the old "62" did not.

**3. The superseded/corrections index.** Present at lines 1005-1013, immediately before Amendment 1, four entries, each pointing at the correcting amendment's own text rather than restating the correction. It is the shape I proposed and it does the job: a reader opening Amendment 16 now has a signal three sections earlier that one of its sentences is superseded. The one thing it does not do is annotate at the point of the wrong sentence — deliberately, since no amendment is edited in place. Accepted as-is.

## Amendment 23, sentence by sentence

Checked every factual claim I could measure. **Amendments 1-22 are byte-unchanged**: `git diff e53f2848..d4be7112` on the spec removes exactly one line in the whole file (`frozen_sha256`, the restamp) and inserts at exactly two places — line 1002 (the index, before Amendment 1) and line 1814 (after Amendment 22's last line). No hunk touches an existing amendment.

True and verified: the BLOCKING-1 diagnosis and repro quotation; "fixed inside `sweepContradictions` itself, not by adding a second import"; the four TEST-574 arms and their RED-against-pre-fix claim (I reproduced all four); the `readPrSweepRecords` `Number(payload.pr) === pr` reasoning behind the string-`pr` arm; the lane arm being unreachable through the hook path; the BLOCKING-2(b) awk citation (`hline ~ /^## \[unreleased\] — /` and nothing more); the TEST-570 count and its three directions; all three truth-fix descriptions; the `SITES 58` arithmetic; `mutation-gate.mjs` GATE PASS 72/degraded 0/unstamped 0 (I re-ran it); `check-vendored-script-deps` CLEAN at 77 (re-run); `aai-release.sh --dry-run` rolling up the new entry (re-run); `check-cd-subshell-leak.mjs` UNSAFE 0 (re-run, 596 occurrences) and the baseline widening 28 -> 32 for `test-aai-hooks-overlay.sh` alone; the working tree clean.

Two sentences I would change:

- **"`sweepContradictions` now judges every field `append-event.mjs` validates before it will write"** — false for `reviewer_bots`' presence, measured above. The next sentence disclaims the *vocabulary* half of `reviewer_bots` but not the *presence* half, so the disclosure does not reach the overclaim. (R2-NB-1.)
- **"All seven were re-run LAST"** — the same sentence names eight rows (TEST-585; 538/539/541/542; 552/568; 570), and all eight records were in fact re-recorded (mtimes 19:46:30 through 19:51:08, checked individually). The work is right; the count is off by one. (R2-NB-3.)

**The disclosed replay.** "A full `mutation-run.mjs --replay --spec <this spec>` (all 72 rows) was started as a further check but did not finish in reasonable time and was killed unconfirmed — disclosed rather than claimed: the PASS this verification relies on is `mutation-gate.mjs`'s own target_sha256 match over all 72 rows plus the seven rows individually re-run and reddened above, not a full replay." This is the sentence I most wanted to find, and it is the right one: it names what was attempted, that it failed, that it was killed, and — critically — it restates what the remaining evidence actually is instead of letting the reader assume the replay stood in for it. Coming from a ride that has had to correct four claims-written-before-they-were-true, writing this paragraph is worth more than the replay would have been. (The "seven" is the count error above; the rows themselves are right.)

## Round 1's NON-BLOCKING list — disposition

For the record, the list is **thirteen**, not fourteen (the round-1 `findings` block holds 2 BLOCKING + 13 NON-BLOCKING; the Warning-dispositions table has the matching 13 rows). Amendment 23 counts them the same way.

**Closed by this remediation (2):**

- `check-vendored-script-deps.mjs:455` comment-derived call edges — closed by class (21 edges gone, 0 added, verdict unchanged), not by disclosure. This was the one I said I would not let pass unnamed; it is the one they fixed hardest.
- `docs-audit-core.mjs:1205` comment asserting a mechanism that does not exist — closed; the comment now states the proxy honestly and names the baseline alternative.

**Aggravated (1):** `check-vendored-script-deps.mjs:414` duplicated rationale — the file went 639 -> 667 lines, comment lines 314 -> 337, comment ratio 49% -> 50%. The v3.1/v3.2 narration is now written out in both the header docstring and the inline comment, one round deeper. Still NON-BLOCKING, still the same fix (keep one statement of "why not the simpler design", move the round archaeology to the amendments where it already lives).

**Widened (1):** `lib/pr-sweep.mjs` `reviewer_bots` — round 1 filed the open vocabulary; round 2 measures that the field's *absence* is also accepted by the reader and refused by the writer.

**Unchanged, still open (10):** the remaining round-1 rows are untouched by this diff, which is correct — the dispatch bounded the round and Amendment 23 says so explicitly.

## Registry items handed back

Fourteen, verbatim-filable. None carries a `fu-close-` / `fu-index-` / `fu-stamp-` / `fu-allocator-` prefix; all ids are <= 40 characters.

| id | severity | what | why |
|---|---|---|---|
| `fu-sweep-reviewer-bots-unvalidated` | medium | Give `reviewer_bots` a closed enum (or at minimum a presence check) inside `sweepContradictions`, beside `PR_SWEEP_OUTCOMES`. | The writer refuses a missing/empty `--reviewer-bots` and the reader accepts a record without the key at all (measured `rc=0 allowed`); a one-character typo (`expectd`) likewise converts "bots were expected" into a legal "I reviewed it myself". Three lines also make the module's own stated parity claim true. |
| `fu-changelog-merge-gate-optin` | low | Add the opt-in qualifier to the `pr_sweep` bullet in CHANGELOG.md's new entry. | It tells operators the merge gate denies, while the overlay carrying that hook declares itself "OPT-IN: nothing installs this automatically" and is installed nowhere in this repo. |
| `fu-amend23-staled-row-count` | low | Amendment 23's Verification says "All seven were re-run" while naming eight rows; all eight were in fact re-recorded. | A count error in a paragraph whose whole purpose is that the evidence is exactly what it says; still cheaply fixable while the spec is editable. |
| `fu-changelog-shape-third-statement` | low | Widen TEST-570's statement count to the corpus and reconcile `aai-release.sh:383`, which prints a divergent `'## [unreleased] — <title>'` hint. | Spec-AC-31's "stated once" is satisfied for the two files the test counts; two further statements (one of them a different shape, inside the tool itself) live on main and the new count cannot see them. |
| `fu-changelog-exit12-second-arm` | low | Name exit 12's second arm in the CHANGELOG preamble (a `## [unreleased]` heading with trailing text that is not the `— ` form). | `aai-release.sh`'s own refusal message names both arms; the preamble names one, so `## [unreleased] v2` fails closed with nothing having warned the author. |
| `fu-lanegate-readstate-duplicate` | low | Collapse `lane-gate.mjs:391 resolveDefaultSpecFromState` and `:168 readStrategy` into one `readStateScalar(path, block, key)`. | Near-verbatim twins in one file; a STATE.yaml shape change fixed in one leaves the other returning null, which for `--sweep-check` means heavy lane and a spurious lane-mismatch DENY on a fast-lane ride. |
| `fu-hookgate-capability-before-deny` | low | Hoist `claude-hook-gate.sh`'s two capability tests (`command -v node`, `-f lane-gate.mjs`) above the PR resolution at :116-141. | An operator-directed merge on a machine with no node, or offline so `gh pr view` fails, is denied with a message about a check that could never have run. Also restores the file's own ":4 ZERO gate logic of its own" claim. |
| `fu-docsmodel-split-generated-pages` | medium | Move `SHARED_GENERATED_PAGES` out of `lib/docs-model.mjs` into `lib/generated-pages.mjs`. | Measured payoff: `docs-model.mjs` is the one path that escalates suite selection to `FULL_RUN reason=shared-lib`; the page list changed three times inside this ride, and each change currently buys a full 95-suite sweep instead of two suites. |
| `fu-cwi-skip-shape-unify` | low | Give `close-work-item.mjs planStateReconcile` one `skip(reason, { commands, echo })` shape. | Two different constructions now produce `severity: 'skip'` — one always empties commands, one preserves them — and nothing says which a new skip path should use; reaching for the obvious helper re-introduces the exact bug Spec-AC-07 fixed. |
| `fu-vendordeps-rationale-stated-twice` | low | Keep one statement of the v1/v2/v3 design rationale in `check-vendored-script-deps.mjs`; move the round-by-round narration to the amendments. | Written out twice near-verbatim in one file (header docstring + inline comment) and a third time in the spec; now 337 of 667 lines (50%) are comment, up from 49% this round. A maintainer updating one copy leaves the other asserting the superseded rationale. |
| `fu-spec-ac-table-two-rules` | low | Pick one rule for the spec's AC Status table and state it in Verification. | Spec-AC-29/30/31 are `done` with Evidence (ROLE_COMMON G4 shape) while the other 32 rows are `planned` with empty Evidence (VALIDATION 8a deferral shape); a reader cannot tell `planned` = not built from `planned` = built, flip deferred, and the close flip has to distinguish them by hand. |
| `fu-commits-cite-wrong-doc-ids` | medium | Reword `1d2f95b9`, `15a178fc`, `838869fe`, whose subjects cite `CHANGE-0186 / SPEC-0180` — the dispatch-state-sweep ride merged as #382. | **Do this before the PR or never**: after merge it is a permanent false record, and any provenance walk from SPEC-0180's `links.commits` finds three commits it does not own. Verified still present at HEAD. |
| `fu-leanaccepted-doc-level-scope` | low | Make `docs-model.mjs:1182-1187`'s `leanAccepted` a per-table fact, as `neitherParses` is documented to be. | A document-level fact consumed inside the per-table loop suppresses the `heading` warning for EVERY table, so a spec with one gate-accepted lean table plus one malformed table reports nothing about the malformed one. |
| `fu-cwi-slug-distinctness` | low | `new Set(slugs)` (or an explicit usage error) across `--ref` / `--spec` / `--paired` in `close-work-item.mjs:1795`. | `--spec X --paired X` resolves one document twice, mutates an already-mutated file and emits two `work_item_closed` events into an append-only ledger; no Test Plan row covers it. |
| `fu-parsesweepcount-name-mismatch` | low | Rename `parseSweepCount` to `parseNonNegativeInt` (or give it `{ min }`) and fix its doc comment, which still says "a pr_sweep count field (--threads-seen / --threads-unresolved)" though `--pr` now uses it. | Relaxing the count rule silently relaxes PR-number parsing; the `pr === 0` guard three lines away is the only thing left holding the PR floor. |

## The replay

**The gate's per-row evidence is enough. Do not spend the full replay before the PR.** Three reasons, in order of weight:

1. I re-ran `mutation-gate.mjs --spec <this spec>` myself: `GATE PASS: 72 row(s) satisfied degraded=0 unstamped=0`. That is a measurement, not a claim relayed from the amendment, and it means every row's recorded mutation is anchored to a `target_sha256` that matches the file as it stands at d4be7112.
2. Every row this round could have staled did stale and was re-recorded. I checked the eight records individually: mtimes 19:46:30 (TEST-585), 19:46:59 (570), 19:48:05/19:48:07/19:48:42/19:50:17 (538/539/541/542), 19:51:06/19:51:08 (552/568) — after the edits, before the commit.
3. The one structural gap the gate cannot see is a *test* edited without its *mutation target* being edited, since the record is keyed on the target's hash. This round has exactly one such row — TEST-574, whose recorded target is `.aai/scripts/claude-hook-gate.sh` (untouched) while the test gained four new arms. **I closed that gap by hand rather than asking for the replay**: I reverted `lib/pr-sweep.mjs` to e53f2848 in a scratch fixture and confirmed all three new hook-level arms return `rc=0 SWEEP-CHECK allowed` and the direct predicate call returns `CLEAN`, then GREEN at HEAD. The row a replay would have added evidence for now has independent evidence in this report.

A full replay would buy re-execution of 71 other rows whose targets are byte-identical to when they were recorded and whose tests this round did not touch. That is the definition of evidence the gate already carries. Against a ride eight remediation rounds deep and a replay that has already once failed to terminate, the cost is not justified.

## Verdict

**spec_compliance: pass.** Spec-AC-30 and Spec-AC-31 move from non-compliant to compliant on the evidence above. Spec-AC-34 stays cannot-verify for the one reason the AC's own text already discloses (the hooks overlay is opt-in and not installed here); its read-side limb is closed. The other 32 rows keep round 1's calls.

**code_quality: pass.** Both BLOCKING findings are closed, each verified by re-running my own round-1 reproduction rather than by reading the fix. Four NON-BLOCKING findings are added (three of them sentences, not code) and thirteen round-1 rows are dispositioned above.

**Would I merge this now?** Yes — with one thing done first that cannot be done after: reword the three commit subjects citing `CHANGE-0186 / SPEC-0180`. Everything else on the list survives the merge and can be filed.
