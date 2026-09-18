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
