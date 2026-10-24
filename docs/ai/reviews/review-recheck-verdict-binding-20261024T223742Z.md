# Code Review r2 — recheck-verdict-binding (59ee0ff2..5b70bca8, delta f79fa2dc..5b70bca8)

Intended tracked path: `docs/ai/reviews/review-recheck-verdict-binding-20261024T223742Z.md`

```yaml
review:
  scope: 59ee0ff2..5b70bca8 (delta f79fa2dc..5b70bca8 = 6e2db80e check_sticky record, 5b70bca8 wording/D15/Spec-AC-19/amendments)
  spec: docs/specs/SPEC-DRAFT-spec-recheck-verdict-binding.md (L3, amended D13, D14, D15)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "check-binding.mjs planBindCheck dispatch path; TEST-2801/2802 green (suite rc 0)" }
      - { ac: Spec-AC-02, call: compliant, citation: "check-binding.mjs planBindCheck verdict path; TEST-2803/2804 green" }
      - { ac: Spec-AC-03, call: compliant, citation: "recheck.mjs:246-257 reads check_binding + check_sticky only; TEST-2805/2806 green" }
      - { ac: Spec-AC-04, call: compliant, citation: "TEST-2807..2813 green; TEST-2808 re-anchored cell bites (mutation replay fail 1)" }
      - { ac: Spec-AC-05, call: compliant, citation: "TEST-2814/2815 green; D6 amended for check_sticky (amendment 21:48:02Z)" }
      - { ac: Spec-AC-06, call: compliant, citation: "TEST-2816 green" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-2817 green" }
      - { ac: Spec-AC-08, call: compliant, citation: "TEST-2818 green" }
      - { ac: Spec-AC-09, call: compliant, citation: "TEST-2802 green" }
      - { ac: Spec-AC-10, call: compliant, citation: "TEST-2819 green (literal checks); D9 content deviation recorded as B-1" }
      - { ac: Spec-AC-11, call: compliant, citation: "TEST-2820/2821 green; recheck.mjs:76 DEFAULT_ON" }
      - { ac: Spec-AC-12, call: compliant, citation: "TEST-2822..2824 green in r1; no PROFILES/suite-map change in delta" }
      - { ac: Spec-AC-13, call: compliant, citation: "RFC-0017:307 no longer says opt-in; TEST-2825/2821" }
      - { ac: Spec-AC-14, call: compliant, citation: "TEST-2826" }
      - { ac: Spec-AC-15, call: compliant, citation: "TEST-2827" }
      - { ac: Spec-AC-16, call: compliant, citation: "TEST-2828; spec-amend list --strict rc 0 (read directly)" }
      - { ac: Spec-AC-17, call: compliant, citation: "TEST-2829/2830 green" }
      - { ac: Spec-AC-18, call: compliant, citation: "TEST-2831 (retitled to same-block scope) + TEST-2832; TEST-2831 re-anchored cell bites" }
      - { ac: Spec-AC-19, call: compliant, citation: "check-binding.mjs:457-522, recheck.mjs:326-328, ride-handoff.mjs:448-458; TEST-2833..2837 green; each mutation cell bites (fail 1)" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: CHANGELOG.md, line: 32,
          issue: "D9 wording: the CHANGELOG ('Only bind-check writes it and only to raise the flag or add a path') and SUBAGENT_PROTOCOL.md:66 ('only bind-check writes ... only ever raised and extended') state writer exclusivity and raise-only as properties, not comparisons; both are false. ride-handoff.mjs out also writes the block (D15 says so). A bind over a record that has an unparseable item drops that item (another ref's entry disappears), and with a duplicated item it keeps the first one. D15's residual names only 'a worktree STATE created by hand', but the record is per STATE file: a STATE made by check-state.mjs (the tool TEST-2835 itself uses), a STATE re-created in the same checkout, and the origin STATE of a ride resumed inline after worktree rounds (no reverse carry) all start with no raised entry",
          failure_scenario: "Probes on 5b70bca8: HOSTILE (item security turned into the string 'true', then one dispatch bind for hotfix-two) drops ride-one's entry, and the next ride-one false round with a test-only delta gives delta []. DUP (items [false, true] for ride-one, then a bind for another ref) keeps false and gives delta []. BACK (round bound true in the worktree; worktree removed; ride continued on its branch in the origin through set-focus/set-phase/bind-check) gives delta [] with the origin entry false. FRESH (STATE deleted, check-state --repair, two false rounds) gives delta []. A reader of the release notes or the protocol is told the flag can only go up" }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/check-binding.mjs, line: 512,
          issue: "putStickyRaise rebuilds a record that has problems from its parseable items only. Unparseable items are lost, a duplicated ref keeps its first item, and only the ref being written is raised. That turns an ambiguity that reads as full into a lower entry for other refs",
          failure_scenario: "HOSTILE and DUP above: one hand edit plus one legitimate bind for another ref, then delta for the damaged ref. It needs an edit outside state.mjs, so it is inside the D9 trigger, but the outcome is a transformation, not 'taken as written'. Fix: keep unparseable lines verbatim so the reader stays ambiguous, and OR the flags of duplicated items" }
      - { rank: NON-BLOCKING, file: .aai/scripts/ride-handoff.mjs, line: 448,
          issue: "The record is carried origin to worktree only. A flag raised in the worktree never returns to the origin STATE",
          failure_scenario: "Probe BACK (above): the worktree bound security_relevant true; after git worktree remove and git checkout of the ride branch in the origin, two false rounds there and a test-only change give delta. The true report is committed on the branch, but origin STATE does not name it" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-recheck.sh, line: 262,
          issue: "Stale pass line and function name: test_2742_uncommitted_stamp_rewrite_residual logs 'pinned as a known residual (delta under opt-in, full by default)'. The node case now asserts full for both shapes, and Spec-AC-16 requires that the residual is no longer called pinned",
          failure_scenario: "A reader of the suite log is told the residual is still pinned and delta is opt-in: both false" }
      - { rank: NON-BLOCKING, file: CHANGELOG.md, line: 48,
          issue: "The #498 entry heading still reads 'an opt-in slim payload' in the same [unreleased] section that turns the default on. The body (line 62) is corrected; the heading is not",
          failure_scenario: "After the cut, the version's notes carry a heading calling the mode opt-in above an entry that says it is on by default" }
      - { rank: NON-BLOCKING, file: docs/ai/decisions.jsonl, line: 0,
          issue: "The contract amendment of 2026-10-24T21:48:02Z (recheck-verdict-binding) lists D15, Spec-AC-19, TEST-2833..2837, the D4/D1/D6/D14/Risks edits and the TEST-2831/2738 renames. It omits the TEST-2821 row extension (four new checks), Implementation-plan step 9, the new seam line, the D15 mutation-anchor line, the RED-observation line and the AC-mapping line",
          failure_scenario: "A reader auditing the frozen-spec drift from the ledger cannot find the TEST-2821 contract change. spec-amend --strict passes because it checks presence and hash, not coverage" }
  cannot_verify:
    - { claim: "A live ride's delta round after the flip behaves like the fixtures", closes_with: "the first post-merge ride with an eligible round (D12)" }
    - { claim: "Linux CI and the Windows Pester leg for the new sticky code and ride-handoff carry", closes_with: "PR CI run on 5b70bca8" }
    - { claim: "Full sweep", closes_with: "the validator's sweep in /private/tmp/aai-recheck-binding (I ran only aai-recheck, aai-ride-handoff, aai-spec-amend)" }
    - { claim: "Stored RED logs for TEST-2833..2837 on f79fa2dc", closes_with: "Validation replay on f79fa2dc. I verified that each mutation cell bites, not the stored RED itself" }
    - { claim: "Windows core.autocrlf ledger_rewritten behaviour", closes_with: "native Windows run (carried from #498)" }
  overall: fail
```

security_relevant: true

## Scope and preflight

- Scope: `59ee0ff2..5b70bca8`, focused on the delta `f79fa2dc..5b70bca8` (6e2db80e, 5b70bca8). Reviewed in the scratch clone `cr28-work` at `5b70bca8`, with a second clone `cr28-work/revert` for the revert path. The worktree `/private/tmp/aai-recheck-binding` was read only.
- `AAI_RECHECK_MODE=full` for every run of mine; the fixtures set or unset the variable themselves.
- Coaching check: the dispatch listed the round-1 findings and asked for specific probes. It did not pre-rate severity. I reviewed the full delta.

## Evidence I ran

| Command | rc |
|---|---|
| `env -u AAI_ROLE AAI_RECHECK_MODE=full bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-recheck.sh` | 0 |
| same for `test-aai-ride-handoff.sh`, `test-aai-spec-amend.sh` | 0, 0 |
| `node .aai/scripts/spec-amend.mjs list --strict` (rc read directly, no pipe) | 0 |
| decisions.jsonl at 59ee0ff2, f79fa2dc and 6e2db80e is each a byte-exact prefix of 5b70bca8 (`cmp -n`) | ok |
| mutation replay of the changed cells TEST-2808, 2831, 2833, 2834, 2835, 2836, 2837 (pattern hits = 1, file changed, case fails, file restored from a saved copy) | each fail 1 |
| probe file `tests/skills/lib/probe2.test.mjs` in cr28-work (15 probes) | see below |
| revert path: `DEFAULT_ON = false` alone, node cases | 80 pass, 3 fail (TEST-2731, 2738, 2820) |

## Item 1: is r1 B-1 closed? Yes

| Probe | Result on 5b70bca8 |
|---|---|
| A3 (slug refs, set-focus away and back through state.mjs) | full [security_relevant:binding security_relevant:sticky] |
| A (writeKeep switch) | full [security_relevant:binding security_relevant:sticky] |
| B (spec re-point after switch) | full [ceremony_l3] |
| every state.mjs subcommand (set-focus x3 incl. --clear, set-phase x3, set-validation x2, set-code-review x2, set-strategy, set-worktree x2, set-tdd-cycle, set-human-input x2, append-run, amend-run, log-tick, reset-block x2, clear-focus x2) | check_sticky byte-identical after each |
| check-state, check-state --repair, --repair merging two duplicate `metrics:` blocks placed around check_sticky | byte-identical |
| focus across three refs (A true, B, C each judged, back to A, false round) | full |
| metrics-flush partial and full, then the same ref reused for two false rounds | byte-identical; full |
| ride-handoff out twice | the second run refuses (`ref_not_in_origin`) and writes nothing. The worktree entry stays raised; worktree round gives full |
| `git worktree move` | TEST-2834 green |

Out-of-tool paths that lower the record (all reported under B-1 / NB): HOSTILE, DUP, BACK, FRESH give delta. COPY (wt1 STATE copied over wt2) gives full on the first round (binding_other_checkout), then delta after one re-bound round. That is an edit outside state.mjs, inside the D9 residual.

## Item 2: fail-closed parsing of check_sticky

These give full: an inline header `check_sticky: []` and a 4-space item (sticky_record_ambiguous). An extra key and `security: null` also give sticky_record_ambiguous. An empty block and a ref_id differing only by case give sticky_record_absent:binding. A duplicate top-level `check_sticky:` key, in either order, gives binding_ambiguous, through duplicateKeys in readBindingBlock.

These parse equivalently, with no change in meaning: an unquoted JSON item, a `#` comment line, CRLF, a trailing space after the header.

The reader fails closed. The writer does not: see NB-1, where the rebuild drops items.

## Item 3: wording

- r1 B-2 items are fixed. RFC-0017:307 no longer says opt-in. The #498 body reads 'As shipped by this entry the mode was OPT-IN'. CHANGELOG:42-43 now states the downstream first_round. SUBAGENT_PROTOCOL.md:65 names the compared values ('it compares a path string'; 'the `<role>_pending_heads` list is empty' and its tick-only caveat).
- r1 B-3 is closed: the TEST-2831 title is scoped 'inside the same block'.
- New: B-1 above (writer exclusivity, raise-only, and the D15 gap stated as one shape).
- D15's gap is not exact. 'Created by hand' is the wrong condition. The real condition: the ref has no entry in that STATE file and no check_binding block naming it there. Any STATE file that did not receive the entry through `ride-handoff.mjs out` meets it, including the origin after worktree rounds. It is not the only gap; HOSTILE, DUP and COPY need an outside edit.
- The general clause 'no shape outside the D5 table is claimed' formally covers BACK and FRESH. The positive sentences in the CHANGELOG and protocol still claim more than the code does.
- Stale opt-in text: test-aai-recheck.sh:262 (NB), CHANGELOG.md:48 heading (NB). The remaining hits are past tense (SPEC-0250:295, 306, 424, 696; recheck.test.mjs:1572, 2773; spec:74, 718) and correct.

## Item 4: revert recipe (if the owner declines the default flip at merge)

Do NOT run `git revert f79fa2dc`. On 5b70bca8 it conflicts in nine files: CHANGELOG.md, docs/INDEX.md, docs/ai/decisions.jsonl, overview-data.json, overview.html, SPEC-0250, the binding spec, recheck.test.mjs and test-aai-recheck.sh. Resolving decisions.jsonl toward the revert would delete two append-only ledger lines (HAZ-LEDGER). The f79fa2dc commit message ('Revert this commit alone') is no longer true; plan step 9 already says so.

Use one forward commit:

1. Code: `.aai/scripts/lib/recheck.mjs:76` `const DEFAULT_ON = true;` becomes `false`. Also restore the comment at :71-75 and header :7-8 to opt-in wording, and adjust the comments at `canon.mjs` (the f79fa2dc hunk) and `orchestration-dispatch.mjs:1716`. This one toggle reproduces the pre-flip `deltaEnabled` exactly: unset, empty or blank gives false; trimmed and lower-cased `delta` gives true; anything else gives false. Measured: only TEST-2731, TEST-2738 and TEST-2820 go red. TEST-2833..2836 stay green under the default env, because recheckMode still lists every failing reason next to recheck_disabled.
2. Tests: take TEST-2731 and TEST-2738 bodies from `git show f79fa2dc^:tests/skills/lib/recheck.test.mjs`. Invert TEST-2820 (default off) and TEST-2821 (docs state opt-in with `AAI_RECHECK_MODE=delta`; the 5b70bca8 checks for RFC, #498 and SPEC-0250 get inverted too). Update recheck.test.mjs:8-12 (SELF-HOSTING header). In test-aai-recheck.sh, rename `test_2738_default_is_delta` back to `_is_full` and fix the 2820/2821 pass lines and the header.
3. Docs: SUBAGENT_PROTOCOL.md:62 (ON by default) and :72 (the escalation clause 'the default, with the variable unset, is delta'); WORKFLOW.md:68; ORCHESTRATION_PARALLEL.prompt.md:149 '(default on; AAI_RECHECK_MODE=full opts out)'. That prompt byte change needs the prompt-diet-ledger.sh:263 entry, `want_growth` in test-aai-prompt-diet.sh and the test-aai-pr-preflight.sh pin recomputed, exactly as f79fa2dc did (+2 B). Also CHANGELOG:40-43 (the ON bullet), :63 and :81; SPEC-0250:189, 215, 424, 511, Spec-AC-17 (534), the TEST-2738 row (614) and 698-699 (Rollback back to 'leave unset'); RFC-0017:307; the binding spec D7 and Spec-AC-11 (mark them reversed by the owner at merge). ORCHESTRATION.prompt.md:7/:15 can stay ('re-run with AAI_RECHECK_MODE=full' is still right).
4. Ledger, append only: one spec_amendment record per spec (contract, D7 reversed by the owner), the frozen_sha256 re-pin, and a TEST-2820 mutation-cell re-anchor (its current cell `DEFAULT_ON = true` to `false` would then be a no-op).
5. Gate: test-aai-recheck.sh, test-aai-prompt-diet.sh, test-aai-pr-preflight.sh, `spec-amend list --strict` (rc 0), mutation replay of TEST-2820/2821/2731/2738.

Result: a consistent, tested opt-in state with check_binding and check_sticky kept. Steps 2 to 4 are what make it consistent; step 1 alone leaves the docs saying the default is on, and TEST-2821 would still pass.

## Item 5: ledger

- Append-only: the base, f79fa2dc and 6e2db80e versions of decisions.jsonl are each byte prefixes of 5b70bca8.
- `spec-amend list --strict` rc 0.
- The SPEC-0250 amendment matches its word diff: the D1 row, the opt-in-by-proof sentence, the bullet at 424, the Article 5 sentence, Risks, Rollback and the TEST-2738 selector.
- The binding-spec contract amendment omits several edited sections (NB-5).
- The measurement amendment of 22:05:03Z is honest: the re-anchored TEST-2808 and TEST-2831 cells hit exactly once and turn their cases red. The new TEST-2833..2837 cells each hit once and bite.
- The TEST-2834 cell mutates two sites (the record read and the replaced-block fold). The two mechanisms are redundant, so neither alone is guarded by that row. This is disclosed by analogy in the 22:05 record, not for 2834 itself (INFO).

## Warning dispositions (recommended; the orchestrator records them)

- B-1 (BLOCKING): remediate in tree. Rewrite CHANGELOG:32-34 and SUBAGENT_PROTOCOL.md:66 to name what is written and compared, without 'only'. Restate the D15 residual as per STATE file: an entry exists only where bind-check ran or `ride-handoff.mjs out` copied it, with no reverse carry. Name the rebuild, or make it true through NB-1.
- NB-1: remediate in tree (small: keep unparseable item lines verbatim; OR duplicated items). Otherwise promote to a follow-up `fu-sticky-rebuild-drops-entries` (P3).
- NB-2: promote to a follow-up `fu-sticky-no-reverse-carry` (P3), disclosed by the B-1 wording.
- NB-3, NB-4: remediate in tree (one pass line and function name; one heading).
- NB-5: remediate by appending a corrective spec_amendment record naming the omitted sections (append only).
