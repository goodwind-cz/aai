---
id: spec-canon-is-a-build-artifact
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: 1223f04b8112704150a4bfbee6ea50a298c6a0b2272f7eeafbb6e7fb9c794b6a
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-0191-canon-is-a-build-artifact.md
  rfc: null
  pr: []
  commits: []
---

# Spec — the rules that bind agents are assembled and asserted, not pasted

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0191-canon-is-a-build-artifact.md
- Paired maintenance half: docs/issues/CHANGE-0167-operator-waiver-unblocks-pr.md
  (see `## The pairing, settled` — the intake names a different half and is wrong)
- Debt intakes this scope drains: docs/issues/DEBT-0005-hazard-canon-delivery-and-duplication.md,
  docs/issues/DEBT-0007-withdrawn-claim-sweeps-are-not-verifiable.md
- Machine-clustered intakes whose surviving members this scope owns:
  docs/issues/ISSUE-0050-contract-prefix-order-unenforced.md,
  docs/issues/ISSUE-0070-sweep-scope-excludes-repo-root.md (both already `superseded`)
- Mandate: docs/project-sessions/2026-09-13-wave-3-subsystem-sweeps.md (sweep 7, the last)
- Owner decision this scope writes into canon: `hitl_decision` 2026-09-12,
  `ref_id: wave-2-roadmap`, `owner_signoff: true`, STANDING DECISION (a),
  docs/ai/decisions.jsonl:800
- Round-cap decision it amends: `hitl_decision` 2026-09-05T16:46:24Z,
  `ref_id: review-round-cap`, `owner_signoff: true`
- Withdrawal this scope makes checkable: `hitl_decision` 2026-08-23T20:05:00Z,
  `ref_id: the-tripwire-is-permanent-not-transitional`, docs/ai/decisions.jsonl:453
- Sweep 6 (merged, the model for this one): docs/specs/SPEC-0185-spec-friction-channel-sweep.md
- Mutation gate: docs/specs/SPEC-0181-spec-mutation-gate-for-tests.md
- Ceremony table: .aai/workflow/WORKFLOW.md "Ceremony levels"
- Technology contract: docs/TECHNOLOGY.md

## The pairing, settled

The intake's Summary says "Paired maintenance half: `mutation-gate-for-tests`".
That is STALE and this spec does not follow it. Measured on 2026-09-25:

- `docs/ai/roadmap.yaml:42-44` — the machine form, and the only input
  `.aai/scripts/ride-select.mjs` reads — carries
  `capability: canon-is-a-build-artifact` / `maintenance: operator-waiver-unblocks-pr`,
  `status: planned`, and it is the last pair.
- `docs/ai/roadmap.yaml:30-32` carries `capability: mutation-gate-for-tests` /
  `maintenance: unrecorded-spec-amendment-is-invisible`, `status: done`.
  `mutation-gate-for-tests` is a CAPABILITY of its own and is already shipped;
  it cannot also be this ride's maintenance half.
- The intake's wording is the pre-reorder table at
  `docs/project-sessions/2026-09-13-wave-3-subsystem-sweeps.md:63`. The
  re-order of 2026-09-14 at `:86-88` (owner menu answer A, `hitl_decision`,
  `ref_id: wave-3-subsystem-sweeps`) promoted `mutation-gate-for-tests` to a
  capability paired with CHANGE-0181 and moved `canon-is-a-build-artifact`
  last. `roadmap.yaml` was updated to match; the intake prose was not.
- `node .aai/scripts/ride-select.mjs next` answers `canon-is-a-build-artifact`.

So the paired maintenance half is `operator-waiver-unblocks-pr`
(docs/issues/CHANGE-0167). The close ceremony flips THAT pair. CHANGE-0167 is
also a false-open document: its code shipped in PR #303 (commit `c40dfbd8`,
`.aai/scripts/validation-waiver.mjs`, `tests/skills/test-aai-pr-waiver.sh`)
while its frontmatter still reads `status: draft`, and `docs/ai/overview.html`
still lists it as in progress. Spec-AC-12 delivers the guard that half still
owes, and the close ceremony flips the document.

## Scope cut — what the intake asked for, and what this spec carries

The intake lists SEVEN in-scope items. Three are already delivered and two are
already closed; carrying them would make this ride's Test Plan assert
properties other rides own. Each cut below is a MEASUREMENT, not a judgement.

CUT — already shipped by `mutation-gate-for-tests` (SPEC-0181, merged):

1. "`spec-lint` mutation-section gate". SHIPPED. `.aai/scripts/spec-lint.mjs:261`
   `mutationGateApplicability()`, findings `mutation-cell-missing` (:616) and
   `mutation-cell-malformed` (:617), frontmatter marker `mutation_gate: v1`.
2. "TDD role records one mutation per test in the evidence contract". SHIPPED.
   `.aai/SKILL_TDD.prompt.md:166-167` ("GREEN is not complete until the test has
   been reddened by its Mutation cell's named mutation, via mutation-run.mjs"),
   `:184` (a `mutation-run.mjs` RED record must exist per TEST id),
   `.aai/scripts/mutation-gate.mjs`.

CUT — already closed in the registry, by rides that shipped:

3. `fu-allowlist-count-is-prose-not-asserted` — `status: done`,
   `resolved_by: test-framework-sweep`, `source: TEST-421`.
4. `fu-empty-path-cd-stays-in-shipping-repo` — `status: done`,
   `resolved_by: test-framework-sweep`, `source: TEST-427`.
   (Also `fu-contract-ledger-rule-stated-twice`, done by `close-ceremony-sweep`;
   `fu-metrics-flush-advises-git-restore`, `fu-usage-marker-omission-unfixable`
   and `fu-overview-shows-closed-ride-inflight`, done by `dispatch-state-sweep`;
   `fu-tripwire-suite-comment-transitional` and
   `fu-isolation-suite-presumes-deletion`, done by `test-framework-sweep`
   TEST-438. Nine of DEBT-0005's and DEBT-0007's twelve members are already
   drained by the six sweeps that ran before this one.)

CARRIED — the three registry items that are still live, all three routed HERE
by name, plus the two canon texts and the maintenance half:

5. `fu-contract-prefix-order-unenforced` (P2) — `status: dropped`,
   `resolved_by: test-framework-sweep`,
   `source: "wrong subsystem: the subagent contract and dispatch payload assembly, sweep 7"`.
   REOPENED by this ride; it is the capability itself (Spec-AC-01..07).
6. `fu-sweep-scope-excludes-repo-root` (P2) and
   `fu-sweep-regex-misses-present-tense` (P2) — both `status: dropped`,
   `source: "wrong subsystem: withdrawn-claim sweeps, DEBT-0007, sweep 7"`.
   REOPENED by this ride (Spec-AC-08..11).
7. `fu-spec-d6-enumeration-stale` (P3, open, age 32d) — Spec-AC-11.
8. `review-round-cap-in-validation-canon` (wave-2 item, standing decision (a))
   — Spec-AC-13.
9. `operator-waiver-unblocks-pr` — the paired half — Spec-AC-12.

NO SPLIT IS PROPOSED. After the cut the residue is four workstreams and 15
acceptance criteria — smaller than sweeps 4, 5 and 6, each of which carried
more and closed. Nothing is DEFERRED to a successor, because this is the LAST
sweep of wave 3: an item deferred here has no next ride and would simply be
abandoned. The two items that were `dropped` with "sweep 7" as their reason are
the proof of that hazard, and they are reopened rather than re-dropped.

## Implementation strategy
- Strategy: tdd
- Rationale: every criterion in this spec is an ASSERTION ABOUT AN ABSENCE —
  a section that must not be missing, a count that must not be wrong, a
  sentence that must not appear twice, a withdrawn claim that must not still
  read as current, a grammar that must not have drifted from the code. Every
  one of those passes trivially when the code implementing it is absent or
  inert: a checker that finds nothing and a checker that looks at nothing print
  the same line and exit the same 0. That is precisely the defect class this
  whole wave kept finding, and it is the debt this ride exists to repay, so a
  green run here proves nothing unless the same test has been SEEN to fail.
  Every Test Plan row therefore names the mutation that must redden it, the RED
  is recorded first under `docs/ai/tdd/spec-canon-is-a-build-artifact/`, and
  `mutation-run.mjs --patch` (not `--sed`) is used wherever the target string
  occurs more than once in its file.

## Isolation and review
- Worktree recommendation: required
- Worktree rationale: this scope edits `.aai/ORCHESTRATION.prompt.md`,
  `.aai/SUBAGENT_CONTRACT.md`, `.aai/SUBAGENT_PROTOCOL.md` and
  `.aai/VALIDATION.prompt.md` — the files every role in this repository is
  dispatched FROM. A half-applied edit in the shared checkout does not fail a
  test; it changes the instructions a concurrent session is running under,
  mid-ride. STATE already records `user_decision: worktree`.
- User decision: worktree (already recorded in STATE, source intake)
- Base ref: main (3edb9368)
- Worktree branch/path: feat/canon-is-a-build-artifact at
  /Users/ales/Projects/aai-feat-canon
- Inline review scope: not applicable (worktree)
- Code review: required. Scope is the branch diff against main 3edb9368.

## Ceremony level

Level 2. Verified, not assumed: `protected_paths_l3` in
`docs/ai/docs-audit.yaml:84-92` lists `.aai/scripts/state.mjs`,
`lib/state-engine.mjs`, `lib/state-core.mjs`, `allocate-doc-number.mjs`,
`pre-commit-checks.sh`, `pre-commit-checks.ps1`, `.aai/workflow/WORKFLOW.md`
and `docs/CONSTITUTION.md`. Not one file this scope edits is on that list, and
Spec-AC-12 is deliberately written so that `validation-waiver.mjs` gains no new
runtime dependency and `state.mjs` is not touched at all. The merge is covered
by the standing internal merge authorization of 2026-09-12 under the wave-3
mandate: nothing here changes a consumer's git behaviour.

## What is established before this scope starts

Measured on 2026-09-25 against the worktree at main `3edb9368`.

- NO CODE ASSEMBLES A DISPATCH PAYLOAD. `.aai/scripts/orchestration-dispatch.mjs`
  (1712 lines) emits a decision — role, tier, model, ref — and never a payload.
  The payload's composition lives as prose in
  `.aai/ORCHESTRATION_PARALLEL.prompt.md:142-143` ("a copy of
  .aai/SUBAGENT_CONTRACT.md (stable, first), then scope and inputs") and in
  `.aai/ORCHESTRATION.prompt.md:5-9`. `grep -rn 'SUBAGENT_CONTRACT'`
  over `.aai/scripts/` returns exactly one hit,
  `.aai/scripts/lib/prompt-hash.mjs:27` — a HASH input, not an assembly step.
- THE ONE EXISTING PIN IS OF FILE BYTES, NOT OF A PAYLOAD.
  `computeEffectivePromptHash()` hashes the role prompt, then
  `.aai/SUBAGENT_CONTRACT.md`, then `docs/knowledge/LEARNED.md`, in that fixed
  order (`prompt-hash.mjs:5-12`). It proves what the FILES said; it cannot
  prove the dispatch carried them, which is exactly the gap
  `fu-contract-prefix-order-unenforced` names.
- THE COUNTS ARE UNASSERTED. `.aai/SUBAGENT_CONTRACT.md` declares 5 standing
  hazards (`grep -c '^- HAZ-'` returns 5: HAZ-RESTORE, HAZ-SCRATCH, HAZ-CD,
  HAZ-LEDGER, HAZ-WORKTREE). No test reads that number. Deleting one hazard
  leaves the suite green.
- THE MECHANICAL-CHECK PATTERN ALREADY EXISTS AND WORKS.
  `.aai/scripts/check-dispatch-text.mjs` turned one prose dispatch rule into a
  closed detector set with negative controls. This scope follows that pattern
  rather than inventing one.
- THE WITHDRAWN CLAIM IS PARTLY UNRETRACTED.
  `docs/specs/SPEC-0138-spec-suites-run-in-a-disposable-worktree.md:74-75`
  still reads "They are deleted by a separate change" in the document's own
  voice, above a `**CORRECTION (2026-08-23).**` block; `CHANGE-0152:32-33`
  is the same shape. The "closed as moot" wording IS now corrected in both
  (`grep -rn 'closed as moot'` over `docs/` and `CHANGELOG.md` returns only
  `CHANGELOG.md:1856`, which carries a `**WITHDRAWN 2026-08-23**` annotation,
  plus the append-only ledger and two historical review reports). What remains
  live is the ENUMERATION: `SPEC-0148:203-210` D6 names "two frozen specs
  (SPEC-0144, SPEC-0145) and three intake documents (CHANGE-0151, CHANGE-0156,
  CHANGE-0157)" while the diff also corrected SPEC-0138 and CHANGE-0152 — 3
  specs and 4 intakes. Nothing re-derives that number, which is
  `fu-spec-d6-enumeration-stale`.
- THE WAIVER GRAMMAR HAS ONE CODE SOURCE AND SEVERAL UNCHECKED PROSE COPIES.
  `validation-waiver.mjs:167-179` builds `WAIVER_RE` from `WAIVER_SENTINEL` and
  `WAIVER_VERSION`, and `generate-factory-report.mjs:49` imports `scanWaivers` /
  `normalizeWaiverRecord` from it, so the two CONSUMERS cannot diverge. The
  grammar is ALSO written out by hand at `validation-waiver.mjs:18` and `:22`,
  and 20+ `AAI-VALIDATION-WAIVER v2` literals are hard-coded across
  `tests/skills/test-aai-pr-waiver.sh` and
  `tests/skills/test-aai-factory-report.sh`. Bumping `WAIVER_VERSION` to 3
  leaves every one of those stale and no check notices.
- THE ROUND-CAP CANON IS ONE DECISION BEHIND.
  `.aai/VALIDATION.prompt.md:185-188` states "TWO ROUNDS MAX (owner decision
  review-round-cap, 2026-09-05)". The 2026-09-12 STANDING DECISION (a)
  (`docs/ai/decisions.jsonl:800`, `owner_signoff: true`) amends it — one extra
  finding-bearing round without asking when the hazard was INTRODUCED BY THE
  FEATURE UNDER DELIVERY — and that amendment is nowhere in the prompt corpus.
  The citation that IS there resolves (`hitl_decision` 2026-09-05T16:46:24Z,
  `ref_id: review-round-cap`, `owner_signoff: true`), but nothing checks that
  it does.
- BUDGETS THIS SCOPE MUST RESPECT. `.aai/ORCHESTRATION.prompt.md` is 42 lines
  against a 45-line ceiling (`tests/skills/test-aai-prompt-diet.sh:350-351`);
  the live prompt corpus (`.aai/*.prompt.md` plus `.aai/AGENTS.md`) is
  367806 bytes; `HEADROOM_CAP=2048` in
  `tests/skills/lib/prompt-diet-ledger.sh`.
- TEST ID BAND. The highest real id in the corpus is TEST-673 (SPEC-0185); the
  synthetic TEST-900 and TEST-9xxx bands in SPEC-0181 are excluded by the same
  convention sweeps 5 and 6 used. This scope allocates from TEST-674.

## Decisions

- **D1 — ONE new script, not three.** The intake names
  `build-dispatch.mjs (or equivalent)`. This scope ships
  `.aai/scripts/canon.mjs` with subcommands `build`, `check` and `claims`,
  because all three read the same declaration and shipping three files would
  cost three PROFILES rows, three main guards and three refusal vocabularies
  for one mechanism. Disclosed here because it deviates from the intake's
  literal wording.
- **D2 — the declaration is a file, and it is the only place a count lives.**
  `.aai/system/CANON.yaml` declares: the ordered dispatch sections and their
  source paths; the asserted counts; the byte ceiling; the uniqueness
  exceptions, each with a reason; the withdrawn claims and their superseding
  ledger records; the declared waiver-grammar versions. A number that is not in
  this file is not asserted, and a number in it that reality contradicts is a
  refusal. No count lives in a log string.
- **D3 — assertions read the ASSEMBLED PAYLOAD, never the manifest.** A check
  that reads the declaration and reports the declaration is the vacuous-control
  shape this wave keeps finding. Every order, count and uniqueness assertion in
  Spec-AC-01..05 parses `canon.mjs build` STDOUT. Spec-AC-01's TEST-675 proves
  it by reordering the manifest and asserting the payload order MOVED.
- **D4 — fail closed, and name the reason.** Every refusal prints a named
  reason token (`canon-section-absent`, `canon-count-mismatch`,
  `canon-duplicate-rule`, `canon-over-budget`, `claim-live-assertion`,
  `claim-record-unresolvable`, `waiver-grammar-drift`, `citation-unresolvable`)
  plus the offending `file:line` and, for a count, BOTH numbers. An absent
  input is never a silent pass: this is the `evidence tree absent` shape
  recorded against `mutation-gate.mjs` in R3 below, and it is not repeated
  here.
- **D5 — a historical record is exempt only by DECLARATION.** The claims check
  excuses a hit when the file is in `CANON.yaml`'s `historical:` glob list
  (`docs/ai/decisions.jsonl`, `docs/ai/reviews/**`, `docs/ai/reports/**`,
  `docs/archive/**`) or when a declared annotation marker
  (`**CORRECTION (<date>).**`, `**WITHDRAWN <date>**`) appears within a
  declared line window after the hit. Both routes are visible in the file. An
  undeclared exemption cannot exist, which is what separates this from the
  hand-chosen path set that produced `fu-sweep-scope-excludes-repo-root`.
- **D6 — this scope does NOT rewrite frozen history.** SPEC-0148's stale D6
  enumeration is corrected by a dated ADDITIVE block naming the true set, not
  by editing D6, in keeping with SPEC-0148's own D6 and Constitution article 5.
- **D7 — the waiver grammar gains NO runtime coupling.** `canon.mjs check`
  RENDERS the grammar from `validation-waiver.mjs`'s exported constants and
  asserts the prose surfaces match. `validation-waiver.mjs` does not read
  `CANON.yaml` at runtime: a shipping PR gate must not acquire a new file
  dependency that a downstream project can be missing.
- **D8 — the wiring is a prompt line that a test EXECUTES.** Spec-AC-07's test
  extracts the `node .aai/scripts/canon.mjs build ...` command line from
  `.aai/ORCHESTRATION.prompt.md` and RUNS IT, asserting exit 0 and a
  contract-first payload. Asserting that a prompt CONTAINS a string would be
  prose checking prose — the very debt this ride repays.

## Constitution deviations

None. Article 1 (evidence before claims) is what the whole scope is; article 2
(simplicity) drives D1 and D7; article 3 (portability) is honoured —
`CANON.yaml` is a plain git-diffable file parsed line-based with node stdlib
only, like `.aai/system/PROFILES.yaml`; article 4 (degrade and report) is D4;
article 5 (additive first) is D6 and the additive `CANON.yaml`; article 6 is
untouched (D7 keeps `state.mjs` out of scope); article 7 is unaffected.

## Acceptance Criteria Mapping

- Maps to: CHANGE-0191 "The dispatch prefix a role receives is produced by one
  script whose output a test asserts: order, uniqueness, counts, byte size."

- Spec-AC-01: WHEN `node .aai/scripts/canon.mjs build --role Validation --ref <r>`
  runs against `.aai/system/CANON.yaml`, it SHALL exit 0 and write to stdout a
  payload whose section-marker lines appear in exactly the order the manifest
  declares, with the subagent contract FIRST and the variable scope/inputs
  section LAST, and reordering the manifest SHALL move the order in the
  PAYLOAD.
  Verification: run the command, then
  `grep -n '^<<<AAI-CANON-SECTION ' <payload>` and compare the extracted id
  sequence against the manifest's; repeat against a fixture manifest whose
  first two sections are swapped and assert the payload sequence swapped too.
  Evidence: the payload file, both grep outputs, both exit codes.

- Spec-AC-02: WHEN a declared canon section's source file is absent or empty,
  the build SHALL refuse with a non-zero exit and print
  `canon-section-absent: <section-id> <path>`, and SHALL NOT emit a payload
  missing that section.
  Verification: fixture manifest pointing at an absent contract path; assert
  non-zero exit, assert the named token on stderr, and assert stdout is empty
  (a truncated payload must never be written).

- Spec-AC-03: The manifest SHALL declare `standing_hazards: 5`, and the build
  SHALL refuse with `canon-count-mismatch: standing_hazards declared=<d> found=<f>`
  when the number of `- HAZ-` rules in the ASSEMBLED payload differs.
  Verification: live tree builds clean at 5; a fixture contract carrying a
  sixth hazard refuses and prints both numbers.

- Spec-AC-04: No declared canon rule line SHALL appear twice in the assembled
  payload, including twice within one source file; a duplicate SHALL refuse
  with `canon-duplicate-rule` naming the normalized text and BOTH line numbers,
  and the only admitted duplicates SHALL be those listed in the manifest's
  `uniqueness_exceptions:` with a reason, each of which the check SHALL print.
  Verification: fixture with a duplicated HAZ line refuses and names two line
  numbers; the same fixture with that text declared as an exception exits 0 and
  prints the exception with its reason.

- Spec-AC-05: The build SHALL print the payload's measured byte size on
  success and SHALL refuse with `canon-over-budget: measured=<m> ceiling=<c>`
  when it exceeds the manifest's declared ceiling.
  Verification: live build prints a size that equals `wc -c` of the captured
  payload; a fixture ceiling one byte below that size refuses and prints both
  numbers.

- Spec-AC-06: `node .aai/scripts/canon.mjs build --role <R> --print-hash`
  SHALL print a digest equal to `computeEffectivePromptHash('.aai/<R>.prompt.md')`
  for the same tree, and a one-byte change to `.aai/SUBAGENT_CONTRACT.md` SHALL
  change both to the same new value.
  Verification: compare the two digests in a fixture tree; mutate one byte of
  the fixture contract and compare again; assert equality both times and
  inequality across the mutation.

- Spec-AC-07: `.aai/ORCHESTRATION.prompt.md` step 2 SHALL carry a single
  runnable `node .aai/scripts/canon.mjs build ...` command line, and a test
  SHALL EXTRACT that line from the prompt and EXECUTE it, asserting exit 0 and
  a contract-first payload; the file SHALL stay within its 45-line ceiling.
  Verification: extract with a pinned pattern, run the extracted string, assert
  exit 0, assert the first section marker is the contract, assert
  `wc -l` is at most 45.

- Spec-AC-08: `.aai/system/CANON.yaml` SHALL declare each withdrawn claim with
  its id, its superseding `hitl_decision` timestamp and `ref_id`, its pattern
  set and its corpus globs; `node .aai/scripts/canon.mjs claims` SHALL refuse
  with `claim-record-unresolvable` when a declared record is not in
  `docs/ai/decisions.jsonl`, and SHALL exit 0 against the live tree once
  Spec-AC-11's corrections are in.
  Verification: fixture claim naming a non-existent timestamp refuses by that
  token; live run exits 0.

- Spec-AC-09: The declared corpus for the tripwire claim SHALL include the
  REPOSITORY ROOT, and a planted un-annotated assertion of the withdrawn claim
  in `CHANGELOG.md` SHALL be reported as `claim-live-assertion` with its
  `file:line` and a non-zero exit.
  Verification: plant the sentence in a COPY of the tree, run `claims`, assert
  the token, the path `CHANGELOG.md` and the line number; remove it and assert
  exit 0. (Closes `fu-sweep-scope-excludes-repo-root`.)

- Spec-AC-10: The declared pattern set SHALL match the withdrawn claim in both
  present and future tense and in passive voice, so that "are deleted by a
  separate change", "is deleted by a separate change" and "will be removed" are
  each reported.
  Verification: three planted variants in a copied tree, each reported with its
  own line; a control sentence about deletion that does not assert the
  withdrawn claim is NOT reported. (Closes `fu-sweep-regex-misses-present-tense`.)

- Spec-AC-11: `node .aai/scripts/canon.mjs claims --report` SHALL PRINT the
  generated enumeration of every document carrying a declared correction
  annotation for a claim, grouped by doc type, and
  `docs/specs/SPEC-0148-spec-the-tripwire-is-permanent-not-transitional.md`
  SHALL carry a dated additive block stating the true set — 3 specs
  (SPEC-0138, SPEC-0144, SPEC-0145) and 4 intakes (CHANGE-0151, CHANGE-0152,
  CHANGE-0156, CHANGE-0157) — whose counts equal the generated report's.
  Verification: run `claims --report`; assert its per-type counts are 3 and 4;
  assert the block exists in SPEC-0148 and that its two numbers equal the
  report's, read from the report rather than hard-coded in the test.
  (Closes `fu-spec-d6-enumeration-stale`.)

- Spec-AC-12: `node .aai/scripts/canon.mjs check --section validation_waiver`
  SHALL RENDER the waiver grammar line from `validation-waiver.mjs`'s exported
  `WAIVER_SENTINEL`, `WAIVER_VERSION` and key order, assert it appears verbatim
  in that file's own header grammar line, and assert every
  `AAI-VALIDATION-WAIVER v<N>` literal under `.aai/**` and `tests/skills/**`
  carries an N the manifest declares (current, or a declared legacy version
  with its reason); a stale literal SHALL refuse with `waiver-grammar-drift`
  naming each `file:line` and the expected version.
  Verification: live tree exits 0 with the declared v2 current and v1 legacy;
  a fixture with `WAIVER_VERSION = 3` refuses and names the header line plus
  every stale literal.

- Spec-AC-13: `.aai/VALIDATION.prompt.md`'s round-cap rule SHALL carry STANDING
  DECISION (a) of 2026-09-12 — one additional finding-bearing round, without
  asking, when the hazard was introduced by the feature under delivery, a
  second such extension being a STOP that asks — citing that decision; and
  `node .aai/scripts/canon.mjs check --section decision_citations` SHALL assert
  that EVERY owner-decision citation in `.aai/*.prompt.md` resolves to a
  `hitl_decision` in `docs/ai/decisions.jsonl` with matching `ref_id`, matching
  date and `owner_signoff: true`, refusing with `citation-unresolvable`
  otherwise.
  Verification: live tree exits 0 and the check prints the number of citations
  it resolved; a fixture whose cited date is changed by one day refuses and
  names the prompt line. (Closes `review-round-cap-in-validation-canon`.)

- Spec-AC-14: Every new `.aai/**` file SHALL be classified in
  `.aai/system/PROFILES.yaml` (`tests/skills/test-aai-layer-profiles.sh`
  green), the prompt-corpus growth SHALL carry a new
  `JUSTIFIED_ADDITIONS` entry in `tests/skills/lib/prompt-diet-ledger.sh` with
  its measured byte delta, the TEST-012 checkpoint SHALL be bumped to match,
  and the new suite SHALL have a `tests/skills/suite-map.yaml` row.
  Verification: `bash tests/skills/test-aai-layer-profiles.sh` exit 0;
  `bash tests/skills/test-aai-prompt-diet.sh` exit 0; a grep of the suite-map
  for the new suite's globs.

- Spec-AC-15: `node .aai/scripts/canon.mjs check --all` SHALL exit 0 against
  the LIVE tree, and `node .aai/scripts/canon.mjs build --role <R>` SHALL exit
  0 for every role the manifest declares.
  Verification: run both against the real repository, not a fixture, and record
  stdout. A gate proved only on fixtures has never met the corpus it governs.

## Acceptance Criteria Status

| Spec-AC    | Description                                                          | Status  | Evidence | Review-By | Notes |
|------------|----------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | The payload is assembled in the declared order, contract first       | done    | docs/ai/tdd/spec-canon-is-a-build-artifact/green-TEST-674.log, docs/ai/tdd/spec-canon-is-a-build-artifact/green-TEST-675.log | —         | run 1 |
| Spec-AC-02 | A missing canon section fails closed and is named                    | done    | docs/ai/tdd/spec-canon-is-a-build-artifact/green-TEST-676.log | —         | run 1 |
| Spec-AC-03 | The declared hazard count is asserted against the payload            | done    | docs/ai/tdd/spec-canon-is-a-build-artifact/green-TEST-677.log | —         | run 1 |
| Spec-AC-04 | No canon rule is stated twice, and exceptions are declared           | done    | docs/ai/tdd/spec-canon-is-a-build-artifact/green-TEST-678.log, docs/ai/tdd/spec-canon-is-a-build-artifact/green-TEST-679.log | —         | run 1 |
| Spec-AC-05 | The payload byte size is measured against a declared ceiling         | done    | docs/ai/tdd/spec-canon-is-a-build-artifact/green-TEST-680.log, docs/ai/tdd/spec-canon-is-a-build-artifact/green-TEST-681.log | —         | run 1 |
| Spec-AC-06 | The telemetry hash is the hash of what was assembled                 | done    | docs/ai/tdd/spec-canon-is-a-build-artifact/green-TEST-682.log, docs/ai/tdd/spec-canon-is-a-build-artifact/green-TEST-683.log | —         | run 2 |
| Spec-AC-07 | The orchestration prompt's own command is executed by a test         | done    | docs/ai/tdd/spec-canon-is-a-build-artifact/green-TEST-684.log | —         | run 2 |
| Spec-AC-08 | A withdrawn claim is declared with its superseding record            | done    | docs/ai/tdd/spec-canon-is-a-build-artifact/green-TEST-685.log, docs/ai/tdd/spec-canon-is-a-build-artifact/green-TEST-686.log | —         | run 2 |
| Spec-AC-09 | The claim corpus reaches the repository root                         | done    | docs/ai/tdd/spec-canon-is-a-build-artifact/green-TEST-687.log | —         | run 2 |
| Spec-AC-10 | The pattern set covers tense and voice                               | done    | docs/ai/tdd/spec-canon-is-a-build-artifact/green-TEST-688.log, docs/ai/tdd/spec-canon-is-a-build-artifact/green-TEST-689.log | —         | run 2 |
| Spec-AC-11 | The enumeration of corrected documents is generated, not hand-counted| planned | —        | —         | —     |
| Spec-AC-12 | The waiver grammar is rendered from the code and its literals pinned | planned | —        | —         | —     |
| Spec-AC-13 | The round-cap canon is current and every citation resolves           | planned | —        | —         | —     |
| Spec-AC-14 | New canon files are classified and the corpus growth is ledgered     | planned | —        | —         | —     |
| Spec-AC-15 | The checks are green against the live tree, not only fixtures        | planned | —        | —         | —     |

## Implementation plan

Components affected:
- NEW `.aai/scripts/canon.mjs` — subcommands `build`, `check`, `claims`.
  Node stdlib only. `runMain` + realpath main guard, via
  `lib/cli-pipe-guard.mjs`, matching `check-dispatch-text.mjs`.
- NEW `.aai/system/CANON.yaml` — the declaration (D2). Line-based, two-space
  indentation, in the same dialect `PROFILES.yaml` uses.
- NEW `tests/skills/test-aai-canon.sh` — the suite, named `test-aai-*` so
  `discover_tests()` finds it (the `fu-ps1-quality-outside-sweep-glob` trap),
  plus its `suite-map.yaml` row.
- `.aai/ORCHESTRATION.prompt.md` step 2 — the one runnable build command
  (42 of 45 lines used; the addition must fit or an existing line must shrink).
- `.aai/ORCHESTRATION_PARALLEL.prompt.md:142-143` — the prose ordering
  sentence becomes a pointer to the builder.
- `.aai/VALIDATION.prompt.md:185-188` — standing decision (a).
- `.aai/SUBAGENT_PROTOCOL.md` — the `INPUT` row names the builder.
- `docs/specs/SPEC-0148-...md` — the dated additive block (D6).
- `.aai/system/PROFILES.yaml`, `tests/skills/lib/prompt-diet-ledger.sh`,
  `tests/skills/test-aai-prompt-diet.sh` (TEST-012 pin) — companion
  obligations.

Data flows: `CANON.yaml` -> `canon.mjs build` -> payload on stdout -> the
orchestrator's dispatch -> the role. `canon.mjs build --print-hash` ->
`prompt-hash.mjs` -> `state.mjs append-run` telemetry.

Edge cases: a role with no declared prompt file; a manifest with a duplicate
section id; a claim pattern that matches inside its own declaration (the
manifest itself must be in `historical:`); a `--print-hash` run in a tree with
no `LEARNED.md` (`prompt-hash.mjs` substitutes the ABSENT marker and must keep
doing so); CRLF sources.

Sequencing: Spec-AC-01..07 first (they are the capability and the riskiest),
then 08..11, then 12..13, then the companion obligations, then Spec-AC-15 last
because it is the only one that can only be true once everything else is.

## Test Plan

Ids continue the live band from TEST-674 (highest real id in the corpus at
planning is TEST-673, SPEC-0185; the synthetic TEST-900 and TEST-9xxx bands in
SPEC-0181 are excluded). Every row names its own suite and selector; the
mutation evidence for each is
`docs/ai/tdd/spec-canon-is-a-build-artifact/mutation-<TEST-id>.txt`, produced
by `node .aai/scripts/mutation-run.mjs`. `--patch` is used rather than `--sed`
for every mutation whose target string occurs more than once in its file.

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Mutation | Status |
|----------|------------|------|----------------------|-------------|----------|--------|
| TEST-674 | Spec-AC-01 | integration | tests/skills/test-aai-canon.sh | test_674_build_order_live — build the Validation payload from the live manifest and assert the extracted section-id sequence equals the manifest's declared sequence, contract id first, scope id last. | patch: in canon.mjs, replace the declared-order iteration with Object.keys of the loaded section map so emission follows load order rather than the declared order; the sequence assertion must redden. | green |
| TEST-675 | Spec-AC-01 | integration | tests/skills/test-aai-canon.sh | test_675_order_follows_manifest_not_code — build against a fixture manifest whose first two sections are swapped and assert the PAYLOAD sequence swapped, proving the assertion reads the payload rather than the declaration. | patch: make the emitter hard-code the contract as section 1 regardless of the manifest; the swapped fixture then emits the unswapped order and the test reddens. | green |
| TEST-676 | Spec-AC-02 | integration | tests/skills/test-aai-canon.sh | test_676_absent_section_fails_closed — fixture manifest pointing at an absent contract path; assert non-zero exit, `canon-section-absent` with the section id and path on stderr, and EMPTY stdout. | patch: change the absent-source branch to emit an empty string for the section and continue; exit becomes 0 with a payload written and all three assertions redden. | green |
| TEST-677 | Spec-AC-03 | integration | tests/skills/test-aai-canon.sh | test_677_hazard_count_asserted — live build exits 0 at the declared 5; a fixture contract carrying a sixth `- HAZ-` rule refuses with `canon-count-mismatch` printing declared=5 and found=6. | patch: replace the count comparison with a no-op that always reports a match; the fixture arm reddens. | green |
| TEST-678 | Spec-AC-04 | integration | tests/skills/test-aai-canon.sh | test_678_duplicate_rule_refused — a fixture contract repeating one HAZ line verbatim refuses with `canon-duplicate-rule` naming the normalized text and both line numbers. | patch: restrict the duplicate scan to cross-file comparison only, skipping pairs from the same source file; the intra-file fixture then passes and the test reddens (this is the exact shape of `fu-contract-ledger-rule-stated-twice`). | green |
| TEST-679 | Spec-AC-04 | integration | tests/skills/test-aai-canon.sh | test_679_declared_exception_admitted — the same fixture with that text listed under `uniqueness_exceptions` exits 0 AND prints the exception with its declared reason, so an exception is never silent. | patch: drop the reason from the printed exception line; the assertion on the reason text reddens. | green |
| TEST-680 | Spec-AC-05 | integration | tests/skills/test-aai-canon.sh | test_680_over_budget_refused — a fixture ceiling one byte below the measured payload size refuses with `canon-over-budget` printing measured and ceiling. | patch: change the comparison to greater-than-or-equal-to twice the ceiling; the one-byte fixture passes and the test reddens. | green |
| TEST-681 | Spec-AC-05 | integration | tests/skills/test-aai-canon.sh | test_681_size_is_the_real_size — the size the build prints equals `wc -c` of the captured payload, so the printed number is asserted rather than decorative (the `fu-allowlist-count-is-prose-not-asserted` lesson). | patch: make the printed size the sum of the source files' sizes instead of the emitted payload's; the framing bytes differ and the equality reddens. | green |
| TEST-682 | Spec-AC-06 | integration | tests/skills/test-aai-canon.sh | test_682_hash_matches_prompt_hash — in a fixture tree, `build --print-hash` equals `computeEffectivePromptHash` for the same role prompt. | patch: reorder the hash inputs in canon.mjs so LEARNED precedes the contract; the digests diverge and the equality reddens. | green |
| TEST-683 | Spec-AC-06 | integration | tests/skills/test-aai-canon.sh | test_683_hash_moves_with_the_contract — a one-byte change to the fixture contract changes both digests to the same new value. | patch: make canon.mjs hash the role prompt alone; the digest then does not move when only the contract changes and the test reddens. | green |
| TEST-684 | Spec-AC-07 | integration | tests/skills/test-aai-canon.sh | test_684_prompt_command_runs — extract the `node .aai/scripts/canon.mjs build` line from `.aai/ORCHESTRATION.prompt.md` with a pinned pattern, EXECUTE the extracted string, assert exit 0 and a contract-first payload; assert the file is at most 45 lines. | patch: in ORCHESTRATION.prompt.md, change the extracted command's `--role` flag to `--for`; the executed command exits on a usage error and the test reddens. | green |
| TEST-685 | Spec-AC-08 | integration | tests/skills/test-aai-canon.sh | test_685_claim_record_must_resolve — a fixture claim naming a `hitl_decision` timestamp absent from the ledger refuses with `claim-record-unresolvable` naming the claim id. | patch: make the resolver treat a zero-match ledger scan as satisfied; the fixture passes and the test reddens. | green |
| TEST-686 | Spec-AC-08 | integration | tests/skills/test-aai-canon.sh | test_686_live_claims_clean — `claims` over the LIVE tree exits 0 and reports the number of files scanned as non-zero, so an empty scan can never look like a clean one. | patch: restrict the corpus walk to a directory that does not exist; scanned becomes 0 and the non-zero assertion reddens. | green |
| TEST-687 | Spec-AC-09 | integration | tests/skills/test-aai-canon.sh | test_687_root_changelog_in_corpus — plant the withdrawn sentence, un-annotated, in `CHANGELOG.md` inside a COPIED tree; assert `claim-live-assertion` with path `CHANGELOG.md` and its line number and a non-zero exit; remove it and assert exit 0. | patch: restore the original narrow corpus by dropping the repository-root glob from the declared globs in CANON.yaml; the planted line goes unseen and the test reddens. | green |
| TEST-688 | Spec-AC-10 | integration | tests/skills/test-aai-canon.sh | test_688_present_tense_matched — planted "are deleted by a separate change" and "is deleted by a separate change" are each reported with their own line. | patch: remove the present-tense alternative from the declared pattern set, leaving only future-tense wording; both planted lines go unseen and the test reddens. | green |
| TEST-689 | Spec-AC-10 | integration | tests/skills/test-aai-canon.sh | test_689_negative_control — a planted sentence about deleting a temporary file, which does not assert the withdrawn claim, is NOT reported, so the pattern set is not a bare substring sweep. | patch: widen the declared pattern to the bare word `deleted`; the control line is reported and the test reddens. | green |
| TEST-690 | Spec-AC-11 | integration | tests/skills/test-aai-canon.sh | test_690_enumeration_is_generated — `claims --report` prints per-doc-type counts for the tripwire claim and they are 3 specs and 4 intakes, read from the report. | patch: make the report count only files whose annotation block is the FIRST match in the file; SPEC-0138 and CHANGE-0152 drop out, the counts become 2 and 3, and the test reddens. | pending |
| TEST-691 | Spec-AC-11 | integration | tests/skills/test-aai-canon.sh | test_691_spec0148_block_matches_report — SPEC-0148 carries the dated additive block, and the two numbers in it equal the numbers `claims --report` prints, compared value-to-value rather than against literals in the test. | patch: in SPEC-0148's new block, change the spec count from 3 to 2; the comparison against the generated report reddens. | pending |
| TEST-692 | Spec-AC-12 | integration | tests/skills/test-aai-canon.sh | test_692_grammar_rendered_from_code — the grammar line rendered from `WAIVER_SENTINEL`, `WAIVER_VERSION` and the declared key order appears verbatim in `validation-waiver.mjs`'s own header grammar line. | patch: drop `ref=` from the renderer's key order; the rendered line no longer matches the header and the test reddens. | pending |
| TEST-693 | Spec-AC-12 | integration | tests/skills/test-aai-canon.sh | test_693_version_bump_names_every_stale_literal — in a fixture copy with `WAIVER_VERSION = 3`, the check refuses with `waiver-grammar-drift` and names the header line plus every stale `v2` literal under the declared globs; the live tree exits 0 with v2 current and v1 declared legacy. | patch: limit the literal scan to `.aai/**`, dropping `tests/skills/**`; the fixture arm no longer names the suite literals and the test reddens. | pending |
| TEST-694 | Spec-AC-13 | integration | tests/skills/test-aai-canon.sh | test_694_round_cap_amendment_present — `.aai/VALIDATION.prompt.md` states standing decision (a) with its 2026-09-12 citation, and `check --section decision_citations` resolves that citation to an `owner_signoff: true` record and exits 0. | patch: in canon.mjs, stop comparing `owner_signoff` and accept any matching `ref_id`; the arm that asserts an unsigned record is refused reddens. | pending |
| TEST-695 | Spec-AC-13 | integration | tests/skills/test-aai-canon.sh | test_695_citation_must_resolve — a fixture prompt whose cited decision date is one day off refuses with `citation-unresolvable` naming the prompt file and line, and the check prints the number of citations it resolved. | patch: make the date comparison compare only the year; the one-day-off fixture resolves and the test reddens. | pending |
| TEST-696 | Spec-AC-14 | integration | tests/skills/test-aai-layer-profiles.sh | test_696_new_canon_files_classified — `.aai/scripts/canon.mjs` and `.aai/system/CANON.yaml` each appear in exactly one PROFILES list and the suite's live-tree union check is green. | patch: remove the `canon.mjs` row from PROFILES.yaml; the union check reddens naming the unclassified file. | pending |
| TEST-697 | Spec-AC-14 | integration | tests/skills/test-aai-prompt-diet.sh | test_697_corpus_growth_ledgered — the measured prompt-corpus delta has a matching `JUSTIFIED_ADDITIONS` entry and the TEST-012 checkpoint equals the new prefix total. | patch: decrement the bumped TEST-012 checkpoint by one byte; the prefix arithmetic reddens. | pending |
| TEST-698 | Spec-AC-15 | integration | tests/skills/test-aai-canon.sh | test_698_live_check_all — `canon.mjs check --all` exits 0 against the REAL repository and prints a non-zero count of sections, claims and citations checked. | patch: make `--all` return early after the first section; the counts drop and the non-zero assertions on the later categories redden. | pending |
| TEST-699 | Spec-AC-15 | integration | tests/skills/test-aai-canon.sh | test_699_live_build_every_role — `canon.mjs build --role <R>` exits 0 for every role the live manifest declares, and the declared role count matches the number of built payloads. | patch: drop one role from the live manifest's declared roles; the count comparison reddens. | pending |

## Seams

- S1 — the DECLARATION and the PAYLOAD. `CANON.yaml` is produced by hand and
  consumed by `canon.mjs build`; a check that reads only the declaration tests
  the declaration. Crossed by TEST-675, which swaps the manifest and asserts
  the PAYLOAD moved, and by TEST-681, which compares the printed size to `wc -c`
  of the emitted bytes.
- S2 — the PAYLOAD and the TELEMETRY. `canon.mjs` assembles what a role
  receives; `prompt-hash.mjs` computes the digest `state.mjs append-run`
  records. Two independent orderings of the same three files would make the
  telemetry describe a stack nobody ran. Crossed by TEST-682 and TEST-683,
  which call BOTH implementations on one tree rather than mocking either.
- S3 — the PROMPT and the SCRIPT. The orchestrator is a model reading
  `.aai/ORCHESTRATION.prompt.md`; the builder is a CLI. A prompt naming a flag
  the CLI does not have fails at dispatch time, in production, silently.
  Crossed by TEST-684, which extracts the command from the prompt and runs it.
- S4 — the CLAIMS CHECK and the RELEASE CUT. An unreleased `CHANGELOG.md`
  entry freezes into a permanent dated section at the next
  `.aai/scripts/aai-release.sh` cut, which is why the root is in the corpus.
  Crossed by TEST-687, which plants into the real `CHANGELOG.md` of a copied
  tree rather than into a synthetic file.
- S5 — the WAIVER GRAMMAR's code source and its prose copies.
  `validation-waiver.mjs` exports the constants; `generate-factory-report.mjs`
  imports the parser; the header comment and 20+ suite literals restate the
  shape. Crossed by TEST-693, which bumps the version in a fixture copy and
  asserts every surface is named.
- S6 — new `.aai/**` files and the DISTRIBUTION layer. `PROFILES.yaml`'s two
  lists must union to the live tree exactly, and `aai-sync.sh --profile core`
  reads them. Crossed by TEST-696 against the live tree.
- S7 — prompt-corpus bytes and the DIET LEDGER. Crossed by TEST-697.

## Residual risks

- R1 — A BUILDER CANNOT FORCE A MODEL TO USE IT. `canon.mjs build` produces the
  payload; the orchestrator is an LLM that must actually paste it. Spec-AC-07
  asserts the command in the dispatch text runs and is correct; it cannot
  assert the model used the output. The after-the-fact backstop is Spec-AC-06:
  the effective-prompt-hash recorded with every run is now the hash of the
  assembled canon sections, so a dispatch that skipped the builder is
  detectable in telemetry rather than invisible. This is the same honesty
  `.aai/SUBAGENT_PROTOCOL.md` states for `AAI_ROLE`: a guardrail against the
  accidental omission, not a security boundary. NO ACCEPTANCE CRITERION IN THIS
  SPEC CLAIMS OTHERWISE.
- R2 — UNIQUENESS DETECTION OVER NATURAL LANGUAGE CAN FALSE-POSITIVE. Mitigated
  by scoping the scan to declared rule-line shapes rather than to prose
  sentences, and by `uniqueness_exceptions` entries that must each carry a
  reason the check PRINTS (TEST-679). Implementation must measure the live
  corpus before choosing the line shape, and report what it measured.
- R3 — THE MUTATION GATE THIS RIDE'S OWN EVIDENCE DEPENDS ON CANNOT BE
  RE-DERIVED FROM THE REPOSITORY. `.gitignore:35` excludes `docs/ai/tdd/**`,
  `mutation-gate.mjs` appears in no `.github/workflows` file, and on a checkout
  without that tree it returns the named degrade class `evidence tree absent`
  at EXIT 0 — a gate that passes because it has nothing to look at, which is
  the exact defect class this wave keeps finding. Filed as
  `fu-mutation-gate-absent-tree-passes` (P2) and
  `fu-mutation-evidence-is-gitignored` (P3). THIS SCOPE DOES NOT REPAIR IT:
  the mutation subsystem belongs to the closed `mutation-gate-for-tests`
  capability, and the repair means deciding whether mutation evidence stops
  being gitignored — a policy change that is the owner's, not Planning's.
  Recorded here because this ride's every RED lands in that tree, so the
  limitation bounds this spec's own evidence: a reviewer on a fresh checkout
  can re-run the suites but cannot re-derive the mutation records.
- R4 — THE CLAIMS CHECK GOVERNS ONE DECLARED CLAIM ON DELIVERY. It is a
  mechanism for N claims with one entry populated. That is deliberate (article
  2, YAGNI) and it means the mechanism's value is proven, not its coverage:
  a second withdrawn claim nobody declares is still invisible. The honest
  statement is that retraction is now REPEATABLE, not that the corpus is
  provably free of withdrawn claims.
- R5 — `.aai/ORCHESTRATION.prompt.md` HAS 3 LINES OF HEADROOM (42 of 45). If
  the wiring does not fit, the correct remedy is to shrink an existing line,
  never to raise the ceiling: the cap is itself an asserted count.

## Verification

Commands, in the order Validation should run them:

1. `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-canon.sh`
2. `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-layer-profiles.sh`
3. `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh`
4. `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pr-waiver.sh`
5. `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-hash.sh`
6. `node .aai/scripts/canon.mjs check --all` (live tree, Spec-AC-15)
7. `node .aai/scripts/canon.mjs claims --report` (live tree, Spec-AC-11)
8. `node .aai/scripts/mutation-run.mjs --replay --spec <this spec>`
9. `node .aai/scripts/spec-lint.mjs --path <this spec>`
10. `node .aai/scripts/mutation-gate.mjs --spec <this spec>`
11. One full sweep with `AAI_TEST_TIMEOUT=3000` before close.

Evidence artifacts: `docs/ai/tdd/spec-canon-is-a-build-artifact/red-TEST-<id>.log`
and `green-TEST-<id>.log` per row, `mutation-TEST-<id>.txt` per row, the
captured live payloads and the `check --all` / `claims --report` stdout.

PASS criteria: all TEST-674..TEST-699 green, every Spec-AC in a terminal
status with non-empty Evidence, `mutation-gate.mjs` reporting GATE PASS.

## Evidence contract

- ref_id: `canon-is-a-build-artifact`
- Spec-AC and TEST-xxx links: as mapped in the Test Plan table above
- Command or review scope: the branch diff against main `3edb9368`
- Exit code or review verdict: recorded per command in the evidence log
- Evidence path: `docs/ai/tdd/spec-canon-is-a-build-artifact/`
- Commit SHA or diff range: recorded at hand-off

### Evidence by strategy

Strategy is `tdd`, so this spec demands a STORED RED artifact per AC-gating
test plus the full verification matrix, and a recorded mutation per Test Plan
row (`mutation_gate: v1`). See R3 for the bound on how far that evidence
travels.

## Registry items closed by this scope

Re-derived at planning from `node .aai/scripts/follow-ups.mjs list`
(118 open, 396 closed, 514 total) and from a direct scan of
`docs/ai/decisions.jsonl` for every id named by DEBT-0005 and DEBT-0007, rather
than taken from the intake's list.

REOPENED AND THEN FIXED BY THIS SCOPE — each was closed as `dropped` with
"sweep 7" as the stated reason, and this is sweep 7:

- `fu-contract-prefix-order-unenforced` (P2) — Spec-AC-01, Spec-AC-06,
  Spec-AC-07, TEST-674, TEST-675, TEST-682, TEST-684
- `fu-sweep-scope-excludes-repo-root` (P2) — Spec-AC-09, TEST-687
- `fu-sweep-regex-misses-present-tense` (P2) — Spec-AC-10, TEST-688, TEST-689

FIXED BY THIS SCOPE, open at planning:

- `fu-spec-d6-enumeration-stale` (P3) — Spec-AC-11, TEST-690, TEST-691

NOT A REGISTRY ITEM, closed as a wave-2 backlog entry:

- `review-round-cap-in-validation-canon` — Spec-AC-13, TEST-694, TEST-695

ALREADY CLOSED BEFORE THIS SCOPE — named so no reader re-derives the set, and
so the cut above is checkable: `fu-allowlist-count-is-prose-not-asserted`
(done, TEST-421), `fu-empty-path-cd-stays-in-shipping-repo` (done, TEST-427),
`fu-contract-ledger-rule-stated-twice` (done, `3d60f1fc`),
`fu-metrics-flush-advises-git-restore` (done), `fu-usage-marker-omission-unfixable`
(done), `fu-tripwire-suite-comment-transitional` (done, TEST-438),
`fu-isolation-suite-presumes-deletion` (done, TEST-438),
`fu-overview-shows-closed-ride-inflight` (done).

NOT CLOSED BY THIS SCOPE, with the reason: `fu-mutation-gate-absent-tree-passes`
(P2) and `fu-mutation-evidence-is-gitignored` (P3) — see R3. They belong to the
closed `mutation-gate-for-tests` capability and their repair is an owner policy
decision about whether mutation evidence stays gitignored. This ride names
them rather than silently inheriting them.

## Documents this scope closes

- `docs/issues/CHANGE-0191-canon-is-a-build-artifact.md` — the capability half.
- `docs/issues/CHANGE-0167-operator-waiver-unblocks-pr.md` — the PAIRED
  MAINTENANCE half per `docs/ai/roadmap.yaml:42-44`. Delivered in PR #303
  (`c40dfbd8`) and false-open since; Spec-AC-12 delivers the guard it owed.
- `docs/issues/DEBT-0005-hazard-canon-delivery-and-duplication.md` — last
  member closed by Spec-AC-01..07.
- `docs/issues/DEBT-0007-withdrawn-claim-sweeps-are-not-verifiable.md` — last
  members closed by Spec-AC-08..11.
- `docs/ai/roadmap.yaml` pair 11 flips to `status: done`, completing wave 3.
