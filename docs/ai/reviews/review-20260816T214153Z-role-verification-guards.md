# Code Review — role-verification-guards (round 2, adversarial, fresh context)

```yaml
review:
  scope: >-
    working-tree diff (git diff, no staged changes) over the 18-path declared
    review scope: .aai/scripts/close-work-item.mjs, .aai/scripts/append-event.mjs,
    .aai/scripts/orchestration-dispatch.mjs, .aai/SKILL_TDD.prompt.md,
    .aai/SKILL_TEST_SKILLS.prompt.md, tests/skills/test-aai-close-work-item.sh,
    tests/skills/test-aai-orchestration-dispatch.sh, tests/skills/test-aai-tdd.sh,
    tests/skills/test-aai-prompt-diet.sh, tests/skills/test-aai-spec-lint.sh,
    tests/skills/test-aai-follow-ups.sh, tests/skills/test-aai-doc-numbering.sh,
    tests/skills/lib/prompt-diet-ledger.sh, tests/skills/lib/close-work-item-pin.sh,
    tests/skills/suite-map.yaml, docs/specs/SPEC-0133-spec-role-verification-guards.md,
    docs/issues/CHANGE-0146-role-verification-guards.md, CHANGELOG.md
  spec: docs/specs/SPEC-0133-spec-role-verification-guards.md (SPEC-FROZEN, amended across five rounds)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/close-work-item.mjs:1044-1049 (once-per-invocation call, --dry-run suppressed) + :522-545 (emitPostMergeCloseWarning, stderr, token post-merge-close, names sha/ref/PR); tests/skills/test-aai-close-work-item.sh test_047/test_048" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "tests/skills/test-aai-close-work-item.sh test_049 — PRE_G1_CLOSE_WORK_ITEM_BLOB=4594d98c pinned blob, cmp on stdout + pairwise exit codes, both warning and silent paths" }
      - { ac: Spec-AC-03, call: compliant,
          citation: ".aai/scripts/orchestration-dispatch.mjs:1268-1278 (Date.parse instants, Number.isFinite-guarded, refMatches on the stamp path); tests/skills/test-aai-orchestration-dispatch.sh test_039 incl. the same-second boundary arm derived from the real stamp ts" }
      - { ac: Spec-AC-04, call: compliant,
          citation: ".aai/scripts/orchestration-dispatch.mjs:361-372 (withStaleAdvisory: event status pass AND STATE validation.status pass AND both hashes non-null AND differing); test_040/041/043/044. See NB-2 — the AC's literal text is met; the code comment claims more than the code checks." }
      - { ac: Spec-AC-05, call: compliant,
          citation: "tests/skills/test-aai-orchestration-dispatch.sh test_042 — pure decide() stale-vs-non-stale delta is exactly the advisories key, plus the pinned PRE_G2 blob (4def5f48) run compared after deleting tree_hash/last_validation_verdict; validationRunAtUtc verified OFF snapshot (.aai/scripts/orchestration-dispatch.mjs:845)" }
      - { ac: Spec-AC-06, call: compliant,
          citation: ".aai/SKILL_TDD.prompt.md:244-251 (inside the '### Phase 4' region, verified by reading); tests/skills/test-aai-tdd.sh test_g3_sweep_gate_prompt_contract — five grep contracts, each exactly once" }
      - { ac: Spec-AC-07, call: compliant,
          citation: ".aai/SKILL_TEST_SKILLS.prompt.md:48-53; tests/skills/test-aai-prompt-diet.sh test_020 (three tokens + zero-hit corpus scan + synthetic bite check). Independently re-ran the regex against the prompt: rc=1 (no hit). See NB-5 for the polarity self-trap this leaves behind." }
      - { ac: Spec-AC-08, call: compliant,
          citation: "measured independently — wc -c deltas 485 (SKILL_TDD 16010->16495) + 344 (SKILL_TEST_SKILLS 2727->3071) = 829 <= 900; ledger entry credits 829 naming both files and both deltas (tests/skills/lib/prompt-diet-ledger.sh:166); pin -3747 + 829 = -2918 == tests/skills/test-aai-prompt-diet.sh:651" }
      - { ac: Spec-AC-09, call: compliant,
          citation: "hashes verified independently — HEAD blob sha256 = e55e053f... == allowlist entry 1, current file sha256 = ac38d15a... == allowlist entry 2 (tests/skills/lib/close-work-item-pin.sh:38-39); close_work_item_pin_assert:95-112 is the single hoisted guard, both callers one line (test-aai-follow-ups.sh:519, test-aai-doc-numbering.sh:1519); test_010 shadows the check and drives the REAL assert" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/orchestration-dispatch.mjs, line: 699-712,
          issue: "filterExcludedDiff leaks its `skipping` state across file boundaries: a `diff --git` header git QUOTES (path with a space, non-ASCII, tab, quote or backslash — core.quotepath is on by default) does not match the regex at :705, so `m` is null, the `if (m)` block never runs, and `skipping` keeps whatever the PREVIOUS file set it to. A quoted-path file immediately following an excluded ledger has its whole diff block dropped from tree_hash.",
          failure_scenario: "Working tree has both docs/ai/EVENTS.jsonl (excluded) and a real edit in e.g. docs/ai/prehled r.md (quoted header, sorts after EVENTS.jsonl). Reproduced against an extracted copy of the exact function: the entire second file's hunk — including the line 'IMPORTANT REAL CHANGE' — is filtered out. tree_hash then does not move for that edit, and G2 stays silent about a real post-verdict change. Strictly a false silence (no excluded path contains a quotable character, so it can never produce a false alarm), which is why this is NB and not blocking — but it is an undocumented blind spot on top of the ones D5/RR-2 enumerate, and its blast radius is other files, not the quoted one." }
      - { rank: NON-BLOCKING, file: .aai/scripts/orchestration-dispatch.mjs, line: 361-372,
          issue: "withStaleAdvisory corroborates STATE's validation STATUS but not its REF, while the stamp path at :1272-1275 does check refMatches(validation.ref_id, focus.ref_id). The comment at :344-357 says the advisory fires only while 'STATE and the last stamp AGREE that a pass verdict is standing' — the code only establishes that STATE holds *some* pass verdict.",
          failure_scenario: "Focus ref A was stamped pass. STATE's last_validation later carries a pass verdict for ref B (a leaked/next-scope verdict — the exact condition rules 13/14 exist to catch) while focus is still A, and the tree has moved. The advisory fires naming A and asserts STATE-level corroboration it does not have. Report-only, and rules 13/14 already flag the leaked verdict, so the practical cost is one misleading line — but the comment is stronger than the code, which is the retracted-claim-migrating-into-a-comment shape this scope has already produced twice." }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0133-spec-role-verification-guards.md, line: 523-536,
          issue: "The round-4 'N-3' paragraph now contradicts the list directly above it and contradicts STATE. It says tests/skills/suite-map.yaml was 'Removed here to restore set-equality with STATE (17)' and flags for the operator that 'docs/ai/STATE.yaml's code_review.scope should also gain tests/skills/suite-map.yaml — this spec edit does not perform that STATE write'. The scope list at :512-513 now DOES include suite-map.yaml, and STATE's code_review.scope now carries all 18 paths including it (verified).",
          failure_scenario: "Anyone reading the frozen spec at PR staging or closeout reads a live instruction to remove the path and a live 'flagged for the operator' item that is already done, and either re-removes it (putting a genuinely-changed file back in no scope at all — exactly what round 5 ruled against) or files a second STATE write. A frozen spec that instructs the opposite of the shipped state is the same honesty defect this scope keeps finding one level out." }
      - { rank: NON-BLOCKING, file: .aai/scripts/orchestration-dispatch.mjs, line: 1279-1288,
          issue: "The stale advisory is printed from the PRE-write snapshot on the very tick that re-stamps, so every fresh validation round produces exactly one false 'validation_verdict_stale' line before the new stamp takes effect. The advisory is unpinned on that tick — test_039's B-1 arm asserts the second stamp lands and that the advisory is clear on the FOLLOWING tick, never what it printed on the re-stamp tick itself.",
          failure_scenario: "Modal L2 ride: validation FAILs, implementation remediates (tracked files move), validation records a fresh pass on the current tree, orchestrator runs the canonical `orchestration-dispatch.mjs --human --confirm` (.aai/ORCHESTRATION.prompt.md:6). That tick re-stamps AND prints 'the recorded pass verdict's tree hash no longer matches the tracked tree' about a verdict that was judged on exactly this tree. D1's own rationale — 'a false alarm ... trains people to ignore the line' — applies, and it fires once per validation round, i.e. more often than the true positive does. Smallest fix: capture recordValidationVerdict's return value and skip the print when it re-stamped this tick (the write already returns true/false at :1163-1172)." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-prompt-diet.sh, line: 956-985,
          issue: "TEST-020's corpus scan is polarity-blind (disclosed) AND the newly added G4 teaching now sits one wording change away from tripping it. The scan passes today only because `[^.]*` in OUTPUT_STREAM_WAIT_RE is broken by the '.' in '$RUN_DIR/summary.txt' between 'Wait on' and 'output stream' — verified by running the regex directly against the prompt (rc=1). fu-test020-corpus-regex-thin covers RECALL (offending phrasings that evade the pattern), not this false-positive polarity.",
          failure_scenario: "A later editor tightens G4 to 'Wait on the disk artifact, never on the process output stream.' — a strictly better teaching — and test-aai-prompt-diet.sh TEST-020 goes red on a correct prompt, with a failure message asserting the corpus contains output-stream-wait guidance. Before this change no .aai file carried this phrasing at all, so the trap is newly introduced here. Cheapest disposition: extend fu-test020-corpus-regex-thin's text to name polarity as well as recall (one follow-ups.mjs line, no code change)." }
      - { rank: NON-BLOCKING, file: docs/ai/EVENTS.jsonl, line: 0,
          issue: "Seven working-tree paths sit outside the 18-path declared scope: docs/INDEX.md, docs/ai/EVENTS.jsonl, docs/ai/decisions.jsonl, docs/ai/overview.html, docs/ai/overview-data.json, docs/ai/tests/test-runs.jsonl (all modified) and the untracked docs/ai/reviews/review-*.md reports. Carried over from round 1's NB-8, still open.",
          failure_scenario: "SKILL_PR's staged-vs-scope audit either refuses the commit or the operator stages them silently. All seven are append-only/generated ledgers or review companions (and, not coincidentally, six of them are TREE_HASH_EXCLUDE_PATHS entries), so the correct disposition is to NAME them at PR staging as expected companions, not to widen the review scope." }
  cannot_verify:
    - { claim: "The suites and the 79-suite sweep pass on the current tree.",
        closes_with: "validation round 5 (docs/ai/validation/validation-20260816T210737Z-...round5.md, 79/79). This dispatch instructed no re-run; I read the code and the arms instead and did not execute any suite." }
    - { claim: "G1 fires correctly against a real merged PR with a real remote and a freshly fetched origin/main (RR-5's stale-ref false silence in a long-lived clone).",
        closes_with: "one observed close after a real merge on this repo; the fixtures use a local bare remote pushed in-process, which cannot exhibit ref staleness." }
    - { claim: "G2 behaves under concurrent ticks / multiple clones appending to EVENTS.jsonl.",
        closes_with: "a concurrency arm, or an explicit statement that single-writer-per-clone is assumed. Not raised as a finding: append-event.mjs's single-writer delegation is pre-existing and unchanged here." }
    - { claim: "G3 and G4 change role behavior at all (RR-4 — both are carried entirely by prompt compliance).",
        closes_with: "several L2 rides observed under the new prompt text; nothing in this diff can detect a role that ignores it." }
    - { claim: "D3's cost inputs (~35 min sweep, ~150 min saved on CHANGE-0145, the 1-in-4.3 break-even).",
        closes_with: "measured sweep wall-clock over several rides. The spec already labels this an estimate (RR-3) and the ruling was demoted to RECOMMENDED partly because of it, so it no longer load-bears." }
    - { claim: "NB-1 bites through the real dispatch CLI on this repository today.",
        closes_with: "a fixture with a quoted-path file adjacent to an excluded ledger, driven through orchestration-dispatch.mjs. I reproduced the mechanism against an extracted copy of filterExcludedDiff's exact body and confirmed git's quoting behavior in a scratch repo; I did not build the end-to-end fixture." }
  overall: pass
```

## Scope and spec

Working-tree diff (nothing staged), reviewed against `SPEC-0133-spec-role-verification-guards.md`
(FROZEN, amended across five validation/review rounds). `git status --porcelain` shows 25 paths;
18 are the declared scope (spec inline list and STATE `code_review.scope` are set-equal — verified),
the remaining seven are ledgers/reports (NB-6).

This is a re-review after a FAIL. The round-1 BLOCKING (per-ref-forever stamp) is fixed and the fix
survives the two defects validation round 4 then found in it: `orchestration-dispatch.mjs:1268-1271`
now parses both sides with `Date.parse` under `Number.isFinite` guards, and `withStaleAdvisory:364`
requires STATE's own `validation.status === 'pass'`. Round 1's NB-1 (the retracted byte-identity claim
in a code comment) is fixed at `:336-343`, which now cites test_042/Spec-AC-05 and explicitly names
what it previously overclaimed. NB-2 (G3 REQUIRED → RECOMMENDED), NB-4 (hoisted
`close_work_item_pin_assert`), NB-5 (maxBuffer 64 MB + the two unnamed extras written into D5.5),
NB-6 (append-event comment) and NB-7 (suite-map routing) are all remediated in tree.

## Where I looked, and what held

I concentrated on the seam the last five rounds kept failing at: comparisons and fixtures that cannot
reproduce production.

- **The timestamp comparison** (`:1268-1278`). Both sides are instants now, both guarded, and the
  same-second arm derives its boundary from the *real* stamp's own `ts` rather than a hand-picked
  date — the specific realism gap that let round 3's fix ship broken. The `!lvv` first-observation
  arm is preserved, so the "stamp once, ever" case is untouched.
- **`decide()`'s split** (`:325-326`, `:374`). Pure mechanical extraction: `decideRuleTable` carries
  the original body verbatim, `withStaleAdvisory` is a pure function of `(out, snapshot)`, and there
  is no internal `decide()` recursion anywhere in the file (grepped) that could double-apply the
  wrapper to an inner result.
- **Additive-only.** No other module imports `buildSnapshot`/`decide` (grepped `.aai/scripts/`), the
  `advisories` key collides with nothing in the repo, `validationRunAtUtc` is returned as a sibling
  and never reaches `state_summary` (`:845`), and `needsLlm`/degraded ticks simply never carry the
  key. Spec-AC-05's two-key modulo therefore holds exactly.
- **The pin library.** I recomputed both allowlisted hashes rather than trusting them: the baseline
  entry equals `git show HEAD:.aai/scripts/close-work-item.mjs | shasum -a 256`, and entry 2 equals
  the current file. `close_work_item_pin_assert` asserts the positive OK status and both callers are
  genuine one-line delegations. test_010 drives the real function through a shadowed check — a
  behavioural pin, not the textual one it replaced.
- **The ledger arithmetic.** Measured independently: 485 + 344 = 829 ≤ 900, pin −3747 + 829 = −2918,
  and the suite asserts the constant against an independent re-sum of the array.
- **G4's factual claims.** `tests/skills/test-framework.sh:101` writes `summary.txt` at setup and
  `:249-250` writes the `AAI Skills Test Summary` heredoc — the prompt's "existence is not
  completion" claim is true, not decorative.
- **G1's report-only property.** test_049 is the right shape: one fixture copied *before* either run,
  pre-change script extracted from a pinned blob (not `git archive HEAD`), `cmp` on stdout, exit
  codes compared pairwise, and both the warning and silent paths covered. The no-remote and
  `--dry-run` negatives are real controls.

## Findings

Five NON-BLOCKING, one carried over. No BLOCKING finding. Details, file:line and failure scenarios
are in the YAML block above; dispositions below.

Two things I considered and am deliberately NOT raising as findings:

- **`>` mutated to `>=` survives test_039** (round 5's note). Equality of the two instants requires
  the stamp's `ts` to land on `.000` ms, so `>=` and `>` are behaviourally near-identical here. The
  arm is weaker than it looks, but the mutation it misses has no realistic consequence. INFO.
- **A genuinely new verdict landing inside the prior stamp's second produces no stamp** (round 5's
  note, deferred to `fu-ts-precision-unify-source`). That is the correct fail-closed reading of two
  producers at different precision, it is written down in D2 and in the code comment, and the
  follow-up exists. Correctly deferred.

The one place I disagree with an earlier round's framing: NB-1 is a *new* blind spot of the same
family as B1/B4 — a filter that cannot see a shape production can produce — and it is the only
finding here that degrades what G2 actually detects. It is non-blocking because it can only fail
silent, never loud, and because G2 is report-only by construction. It should not be deferred, though:
the fix is four lines and strictly safer than the current code.

## Warning dispositions (H6)

| Finding | Disposition | Artifact |
|---|---|---|
| NB-1 filterExcludedDiff skip-state leak | remediate-in-tree | key off `line.startsWith('diff --git ')` and set `skipping = !!m && (...)` so an unparseable (quoted) header is never excluded and never inherits the previous file's state; one arm with a space-in-path fixture |
| NB-2 advisory corroborates status but not ref | remediate-in-tree | add `&& refMatches(s.validation.ref_id, s.focus && s.focus.ref_id)` to `withStaleAdvisory` (existing fixtures already match on ref, so no arm churn), or weaken the comment at :344-357 to what the code checks |
| NB-3 spec's stale N-3 paragraph | remediate-in-tree | replace :523-536 with one line recording that round 5 restored the path to both lists and that STATE now carries all 18 |
| NB-4 false advisory on the re-stamp tick | remediate-in-tree | suppress the print when `recordValidationVerdict` returned true this tick; extend test_039's B-1 arm to assert zero stale lines on the re-stamp tick |
| NB-5 TEST-020 polarity self-trap | promote-to-follow-up | extend `fu-test020-corpus-regex-thin` to name polarity (false positives on a correct prohibition) alongside recall |
| NB-6 seven out-of-scope working-tree paths | promote-to-PR-staging note | name the six ledgers + the review reports as expected companions in the PR staging audit (round 1 NB-8, still open) |

## Dispatch coaching (anti-gaming contract)

Recorded as required, without prejudice to the review. The dispatch prompt (a) summarized round 5's
three findings and pre-rated them as non-blocking, (b) characterized the expected shape of findings
("every one of them lived in a fixture or comparison that could not reproduce production"), and
(c) scope-excluded verification ("Do NOT re-run the suite or the sweep"). (c) is a reasonable division
of labour with Validation and I honoured it, naming the consequence in `cannot_verify`; (a) and (b)
are the pattern `fu-dispatch-prompt-coaching-bias` already tracks from round 1. I reviewed the full
scope regardless: NB-1, NB-3, NB-4 and NB-5 were not on the dispatch's list, and I independently
re-derived the two findings that were (NB-2 confirmed; the `>=` mutation downgraded to INFO with
reasoning rather than adopted).

## Next steps

1. Remediate NB-1 through NB-4 in tree; record NB-5 on the existing follow-up; carry NB-6 into PR staging.
2. NB-1 and NB-4 both touch `orchestration-dispatch.mjs` only — neither disturbs
   `tests/skills/lib/close-work-item-pin.sh`'s allowlist, so the Spec-AC-09 pin does not need a third entry.
3. Re-run `tests/skills/test-aai-orchestration-dispatch.sh` after the NB-1/NB-2/NB-4 fixes
   (Validation's call whether the full sweep is owed again at this point).

This earns its place. Four guards, ~1500 lines including tests, no new production script, no exit-code
change on any path, and every one of them fails toward silence. G2 is the only one with real machinery
behind it and it is the one that has been beaten on hardest — five rounds, five blockers, all closed,
each with an arm derived from the real producer rather than a hand-picked fixture. What remains is a
narrow silent blind spot, an over-strong comment, a stale paragraph in the spec, one avoidable false
alarm per validation round, and a latent test trap. None of that should hold the PR.
