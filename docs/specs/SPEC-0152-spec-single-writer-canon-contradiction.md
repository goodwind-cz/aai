---
id: spec-single-writer-canon-contradiction
type: spec
number: 152
status: done
ceremony_level: 2
links:
  requirement: single-writer-canon-contradiction
  rfc: null
  pr:
    - 287
  commits:
    - 205239a
---

# Spec — being dispatched decides who writes STATE, and the serial dispatch arms the guard

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0165-single-writer-canon-contradiction.md
- Decision records: none new (design decisions recorded in this spec)
- Technology contract: docs/TECHNOLOGY.md

## Problem in one paragraph

Two canon surfaces forbid what four others direct. `.aai/SUBAGENT_CONTRACT.md`
and `.aai/SUBAGENT_PROTOCOL.md` state the single-writer rule (a dispatched
subagent MUST NOT write `docs/ai/STATE.yaml`), and `state.mjs` enforces it at
the CLI chokepoint through R-GUARD S1 (SPEC-0113): every STATE mutator exits 3
under `AAI_ROLE=subagent`. Meanwhile PLANNING step 12, IMPLEMENTATION step 10,
VALIDATION step 9 and REMEDIATION steps 4 and 5 tell the role to run those
mutators itself, with no mention of the return-the-commands alternative — and
`.aai/ORCHESTRATION.prompt.md`, the serial dispatcher, never relays the ENV row
that arms the marker. So on the serial pipeline the guard is structurally
unarmed, the prose contradicts itself, and two roles lost time to it in one
ride (registry `fu-subagent-state-write-contradiction`, P2). This scope decides
the one truth, aligns the seven surfaces to it, and pins the alignment.

## The decision (D1)

**Option (a) wins: the sole-writer rule holds everywhere. The serial pipeline
gets NO carve.** The rule is restated once, precisely, so it stops reading as a
pipeline rule at all:

> Being DISPATCHED decides who writes STATE — not which pipeline dispatched you.
> A dispatched subagent (serial or parallel) returns its `state.mjs` commands in
> its result block; the orchestrator executes them at merge. An agent that is
> the SOLE agent for the ride (no dispatch, `AAI_ROLE` unset) IS the single
> writer and runs them itself.

Rationale. Four independent facts already decide this, and choosing (b) would
have to overturn all four. (1) R-GUARD S1 lives in `state.mjs`, a
`protected_paths_l3` file this scope may not edit; it refuses every STATE
mutation under the marker unconditionally, with no pipeline discriminator to
carve on. Option (b) would therefore have to either edit a protected file or
ship prose that promises a carve the code refuses — moving the contradiction
rather than removing it. (2) `.aai/SUBAGENT_PROTOCOL.md`'s call contract already
binds EVERY subagent call, not parallel ones: its ENV row says "the subagent
MUST run with `AAI_ROLE=subagent` exported". The serial orchestration prompt is
simply not relaying a contract it is already subject to — a wiring hole, not a
competing rule. (3) `.aai/ORCHESTRATION_PARALLEL.prompt.md` and the merge
protocol already implement (a) end to end, so (a) needs one wiring line and four
pointers, while (b) needs a new named exception in three documents plus a
retraction of the chokepoint-enforcement claim. (4) The live proof: the Planning
dispatch that produced this document ran under (a) — the dispatch carried the
arming line, this role returned its state commands instead of executing them,
and the orchestrator executed them at merge. (a) is not a hypothesis here; it is
the observed working configuration.

What (a) explicitly does NOT claim: that role prompts never run `state.mjs`.
`.aai/SKILL_LOOP.prompt.md`'s no-subagent fallback ("execute steps 3-4
sequentially in the current session by reading and following canonical
prompts") is a real, supported lane where the role IS the sole agent and MUST
run the commands — and `.aai/SUBAGENT_PROTOCOL.md`'s review rule 2 already
carries the same sole-agent clause for `set-code-review`. A rule phrased as
"roles never write STATE" would break that lane and would be a third, new
falsehood. Keying on the dispatch, not on the role and not on the pipeline, is
the only phrasing that is true of every lane this repo actually runs.

## Design decisions

- D2 (one normative home, outside the diet corpus). The full duty — return the
  commands, what the orchestrator does with them, the sole-agent carve, the
  rationalization rows — lives in `.aai/SUBAGENT_CONTRACT.md`'s single-writer
  section. That file is the per-dispatch payload every subagent already
  receives, and it is outside the `.aai/*.prompt.md` diet glob, so normative
  text costs no corpus bytes. The four role prompts get a one-line pointer and
  nothing else; the prohibition is never restated where it could drift.
- D3 (the return channel is a result-block extension key). The subagent returns
  its commands under a top-level `state_update_commands:` list in the result
  block. `.aai/scripts/check-role-output.mjs` consumes an unrecognized top-level
  key and its nested lines and ignores it by design ("extra extension field ...
  validate required core only", check-role-output.mjs ~line 460), so the key
  cannot invalidate a block and the checker needs no edit. This is the one
  cross-component seam in the scope and it gets its own executable test.
- D4 (the orchestrator side is a merge-protocol duty, not a habit). The intake's
  named risk is that roles stop running `state.mjs` while nobody starts, and
  phases silently stop advancing. Mitigation: `.aai/SUBAGENT_PROTOCOL.md`'s
  merge protocol step 3 gains `state_update_commands` as an explicit merge
  input, and `.aai/ORCHESTRATION.prompt.md` step 2 names running them next to
  the `append-run` it already names. Both ends are pinned.
- D5 (arm placement). The pin arms go into `tests/skills/test-aai-r-guard.sh`,
  which already exists for exactly this wiring seam (TEST-RG-PIN-01..03 pin the
  parallel dispatch's arming line and the live marker-refuses-state.mjs seam).
  No new suite file, so no `tests/skills/suite-map.yaml` NEW row and no
  `.aai/system/PROFILES.yaml` entry. Its EXISTING suite-map globs, however, do
  not list the six files this scope newly pins, which would leave the arms
  unselectable by CI test-impact selection on the very edits they guard — the
  globs are extended in scope (Spec-AC-06).
- D6 (protected surfaces untouched). `state.mjs`, `lib/state-engine.mjs`,
  `lib/state-core.mjs`, `allocate-doc-number.mjs`, `pre-commit-checks.*`,
  `.aai/workflow/WORKFLOW.md` and `docs/CONSTITUTION.md` are not edited. R-GUARD
  S1 is already correct; the defect was never in the engine.

## Implementation strategy
- Strategy: tdd
- Rationale: the intake requires the pin bite-proved in both directions
  ("shown red against the pre-fix text, green after"), and here the RED
  observation is free and exact — the four new arms are written first and run
  against the untouched prose, where every one of them fails today (zero
  occurrences of `AAI_ROLE` in `.aai/ORCHESTRATION.prompt.md`, zero of
  `state_update_commands` anywhere in the repo). Writing the arms first is what
  proves the arms can fail at all; the stored RED artifacts under `docs/ai/tdd/`
  are the durable form of the intake's own acceptance criterion, and a `direct`
  strategy may not demand them.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: seven prose files plus one test file on a dedicated
  branch (`docs/single-writer-canon`), no build, no schema, no engine edit. Any
  hostile-mutation bite proof runs in a disposable detached worktree cut from
  the base ref, never in the shipping tree (HAZ-RESTORE).
- User decision: undecided
- Base ref: main
- Worktree branch/path: docs/single-writer-canon (existing branch, inline)
- Inline review scope: .aai/SUBAGENT_CONTRACT.md, .aai/SUBAGENT_PROTOCOL.md,
  .aai/ORCHESTRATION.prompt.md, .aai/PLANNING.prompt.md,
  .aai/IMPLEMENTATION.prompt.md, .aai/VALIDATION.prompt.md,
  .aai/REMEDIATION.prompt.md, tests/skills/test-aai-r-guard.sh,
  tests/skills/suite-map.yaml, docs/specs/SPEC-0152-spec-single-writer-canon-contradiction.md,
  docs/issues/CHANGE-0165-single-writer-canon-contradiction.md, and
  tests/skills/lib/prompt-diet-ledger.sh plus tests/skills/test-aai-prompt-diet.sh
  only as the measured ledger true-up requires.

## Acceptance Criteria Mapping

- Maps to: AC-002
- Spec-AC-01: WHEN the serial dispatcher relays a dispatch, `.aai/ORCHESTRATION.prompt.md`
  SHALL direct exporting `AAI_ROLE=subagent` into the spawned role's
  environment, SHALL direct keeping it unset for the orchestrator's own writes,
  and SHALL name running the role's returned `state_update_commands`; the file
  SHALL stay at or below 45 lines (TEST-011 thin-wrapper ceiling).
- Verification: `bash tests/skills/test-aai-r-guard.sh` exits 0 with
  `TEST-RG-PIN-04` PASS; `wc -l < .aai/ORCHESTRATION.prompt.md` is 45 or less.
  Evidence: suite log plus the recorded line count.

- Maps to: AC-001, AC-002
- Spec-AC-02: Each of `.aai/PLANNING.prompt.md`, `.aai/IMPLEMENTATION.prompt.md`,
  `.aai/VALIDATION.prompt.md` and `.aai/REMEDIATION.prompt.md` SHALL carry, at
  its state-update step, one clause naming both `state_update_commands` and
  `.aai/SUBAGENT_CONTRACT.md`, so no surface directs a dispatched subagent to
  run a STATE mutator unconditionally; the `node .aai/scripts/state.mjs` primary
  path and the `state.mjs is absent` fallback marker SHALL survive verbatim in
  all four (test-aai-state.sh TEST-014).
- Verification: `bash tests/skills/test-aai-r-guard.sh` exits 0 with
  `TEST-RG-PIN-05` PASS; `bash tests/skills/test-aai-state.sh` exits 0.

- Maps to: AC-001
- Spec-AC-03: `.aai/SUBAGENT_CONTRACT.md` SHALL carry the single normative
  statement of D1 — dispatch decides, the returned-commands duty, the
  sole-agent carve, and a rationalization row for the serial-pipeline excuse —
  and `.aai/SUBAGENT_PROTOCOL.md` SHALL name `state_update_commands` as a merge
  input in its merge protocol and SHALL state that the ENV row binds serial and
  parallel dispatches alike.
- Verification: `bash tests/skills/test-aai-r-guard.sh` exits 0 with
  `TEST-RG-PIN-06` PASS. The existing TEST-RG-PIN-01 honesty assertion
  ("not a security boundary") SHALL still pass unchanged.

- Maps to: AC-002
- Spec-AC-04 (SEAM): WHEN a result block carrying a `state_update_commands:`
  list is checked, `node .aai/scripts/check-role-output.mjs` SHALL exit 0, and a
  block missing a required core field SHALL still exit 1 with a
  `ROLE-OUTPUT-VIOLATION:` line. The declared return channel is therefore proven
  compatible with the deterministic checker that gates every merge, with no edit
  to that checker.
- Verification: `bash tests/skills/test-aai-r-guard.sh` exits 0 with
  `TEST-RG-PIN-07` PASS (both arms, in one run, against fixtures in a scratch
  temp dir).

- Maps to: AC-003
- Spec-AC-05: Each new arm SHALL be observed FAILING against the pre-fix text
  before the prose edits land, and passing after, with the RED output stored
  under `docs/ai/tdd/`; and each arm SHALL be re-proved to bite by a hostile
  mutation of the fixed text in a disposable detached worktree, with an
  unmutated control run recorded in the same evidence.
- Verification: a stored `docs/ai/tdd/red-*` log per arm naming the failing
  assertion, a stored green log, and the mutation transcript naming the mutated
  string and the suite exit code for each of the four arms plus the control.

- Maps to: AC-003
- Spec-AC-06: `tests/skills/suite-map.yaml`'s `aai-r-guard` globs SHALL list
  every file the suite now pins — `.aai/SUBAGENT_CONTRACT.md`,
  `.aai/ORCHESTRATION.prompt.md`, `.aai/PLANNING.prompt.md`,
  `.aai/IMPLEMENTATION.prompt.md`, `.aai/VALIDATION.prompt.md`,
  `.aai/REMEDIATION.prompt.md` — so a later edit to any pinned surface selects
  this suite in CI test-impact selection.
- Verification: `node .aai/scripts/select-suites.mjs --files-from <file listing
  the six paths>` names `aai-r-guard` in its output for each of the six;
  `bash tests/skills/test-aai-hygiene-pack.sh` exits 0 (suite-map row coverage).

- Maps to: AC-004
- Spec-AC-07: The `.aai/*.prompt.md` corpus delta SHALL be measured under
  `/bin/bash -c 'cat .aai/*.prompt.md | wc -c'` before and after the edits and
  SHALL NOT exceed 700 bytes; when the delta is positive a single
  `JUSTIFIED_ADDITIONS` entry equal to the MEASURED delta SHALL be appended to
  `tests/skills/lib/prompt-diet-ledger.sh` and the `want_growth` pin in
  `tests/skills/test-aai-prompt-diet.sh` TEST-012 SHALL be raised by the same
  amount; no padding, no recomputation.
- Verification: `bash tests/skills/test-aai-prompt-diet.sh` exits 0 (TEST-010
  headroom within 0..2048 and TEST-012 pin equal to the independent re-sum);
  the before and after byte counts recorded in the implementation evidence, and
  `after - before` equal to the appended ledger entry's leading field.

- Maps to: AC-005
- Spec-AC-08: No `protected_paths_l3` file SHALL appear in this scope's diff,
  and the registry item `fu-subagent-state-write-contradiction` SHALL be closed
  with `resolved_by` naming this change, at the close ceremony and not before.
- Verification: `git diff main --name-only` intersected with the eight
  `protected_paths_l3` entries is empty; after the close,
  `node .aai/scripts/follow-ups.mjs list --json` shows the item closed with a
  `resolved_by` value naming this change.

## Constitution deviations

None. Article 6 (single-writer state) is the article this scope makes true on a
pipeline where it currently is not; Article 5 (additive first) is honored — no
step is renumbered, no result-block required field is added or changed, and the
new `state_update_commands` key is an ignored extension for every existing
consumer.

## Acceptance Criteria Status

Tracks per-Spec-AC delivery state. Separate from per-test lifecycle below.

| Spec-AC    | Description                    | Status      | Evidence       | Review-By   | Notes                          |
|------------|--------------------------------|-------------|----------------|-------------|--------------------------------|
| Spec-AC-01 | serial ORCHESTRATION arms AAI_ROLE=subagent, keeps it unset for own writes, names running state_update_commands, stays at 45 lines or less | done | val r1 check AC-01 met: r-guard exit 0, PIN-04 PASS, ORCHESTRATION 42 of 45 lines; exit-4 lane completed in remediation 9f96799 (review r2 verified reference resolves). docs/ai/validation/validation-20260824T162044Z-single-writer-canon-contradiction-round2.md | validation:2026-08-24 | review r2 re-read the file whole |
| Spec-AC-02 | four role prompts carry the dispatched-subagent clause naming state_update_commands and SUBAGENT_CONTRACT; state.mjs primary path and fallback marker survive | done | val r2: carve in all four prompts plus SKILL_TDD (:66 governs all four set-tdd-cycle sites); REMEDIATION widened to steps 4-6 in 9f96799 after review r1 P1-1; prefix-free sweep in review r2 found zero uncovered directives across 19 files. docs/ai/reviews/review-20260824T172907Z-single-writer-canon-contradiction-round2.md | validation:2026-08-24 | per-file sweep rebuilt from scratch |
| Spec-AC-03 | SUBAGENT_CONTRACT holds the one normative statement; SUBAGENT_PROTOCOL names the merge input and the serial-plus-parallel ENV scope | done | val r2 whitespace-insensitive diff: zero word-level content loss at 83 then 84 of 84 lines; PROTOCOL ENV row binds serial plus parallel, merge step names state_update_commands. docs/ai/validation/validation-20260824T162044Z-single-writer-canon-contradiction-round2.md | validation:2026-08-24 | contract at cap, zero slack (P3-N2 accepted residual) |
| Spec-AC-04 | SEAM: check-role-output accepts a block carrying state_update_commands (exit 0) and still refuses a block missing a required field (exit 1) (correction 2026-08-24: acceptance holds ONLY for correctly indented nested lines; a flush-left list is refused with E-MALFORMED-LINE — the unconditional reading was disproved by review r2 probe B) | done | review r2 ran four fixtures against the real checker: template verbatim exit 0, 3-space and colon-bearing payload exit 0, flush-left YAML list exit 1 E-MALFORMED-LINE — acceptance holds ONLY for correctly indented nested lines (third PIN-07 arm pins the refusal). docs/ai/reviews/review-20260824T172907Z-single-writer-canon-contradiction-round2.md | validation:2026-08-24 | qualified: not unconditional exit 0 as this row once implied |
| Spec-AC-05 | every new arm observed RED on pre-fix text and green after, plus a hostile-mutation bite with an unmutated control | done | PIN-04/05/06 observed RED on pre-fix text (docs/ai/tdd/red-20260824T151347Z-r-guard.log) and green after; PIN-07 is a compatibility seam, green pre-fix BY DESIGN — never RED; its bite proved by mutating check-role-output.mjs:432 in a disposable worktree (arm fires, control green). docs/ai/reviews/review-20260824T172907Z-single-writer-canon-contradiction-round2.md | validation:2026-08-24 | honest deviation: 3 of 4 arms RED-observed, seam arm mutation-proved instead |
| Spec-AC-06 | suite-map aai-r-guard globs list all six newly pinned files so CI selects the suite on an edit to any of them | done | val r2 and review r2: select-suites names aai-r-guard for all pinned paths incl. SKILL_TDD.prompt.md (7 of 7 after remediation r2). docs/ai/reviews/review-20260824T172907Z-single-writer-canon-contradiction-round2.md | validation:2026-08-24 | — |
| Spec-AC-07 | in-corpus delta measured, at most 700 bytes, ledgered at the measured amount with the TEST-012 pin bumped by the same amount | done | BUDGET EXCEEDED, recorded not waved: measured 874 B across THREE ledger entries (657 plus 206 plus 11) vs this row s 700 B single-entry budget; overage is the validation-demanded F2 fix plus review P2-1 on surfaces the frozen spec never declared. Every byte measured under /bin/bash, ledgered 1:1 at zero headroom, TEST-012 pin 1410 to 2284, re-sum verified independently three times. docs/ai/reviews/review-20260824T172907Z-single-writer-canon-contradiction-round2.md | validation:2026-08-24 | review r2 P3-N3: flip must cite 874/3, never a plain done citing 657 |
| Spec-AC-08 | no protected_paths_l3 file in the diff; fu-subagent-state-write-contradiction closed with resolved_by at the close | done | diff intersect protected_paths_l3 empty (val r1 and r2); fu-subagent-state-write-contradiction closed QUALIFIED with resolved_by CHANGE-0165 in this branch (lands on merge), successor fu-uncarved-dispatch-lanes filed. docs/ai/decisions.jsonl | validation:2026-08-24 | qualified closure per val r2 F7 and review r2 P3-N4 |

## Implementation plan

Components and per-surface edits, in the order they should land.

1. `tests/skills/test-aai-r-guard.sh` (FIRST — RED before any prose edit).
   Add four arms to the existing flat run list and to the file's PASS summary
   line, following the file's existing style (scratch fixtures only, bash 3.2,
   `log_fail` sets `FAILED=1` and never exits):
   - `test_pin_orchestration_serial` (TEST-RG-PIN-04) — `.aai/ORCHESTRATION.prompt.md`
     contains `AAI_ROLE=subagent`, an unset instruction for the orchestrator's
     own writes, and `state_update_commands`; and its `wc -l` is 45 or less.
   - `test_pin_role_prompts` (TEST-RG-PIN-05) — for each of the four role
     prompts: contains `state_update_commands` AND `.aai/SUBAGENT_CONTRACT.md`,
     and still contains `node .aai/scripts/state.mjs` and `state.mjs is absent`.
   - `test_pin_contract_and_protocol` (TEST-RG-PIN-06) — `.aai/SUBAGENT_CONTRACT.md`
     contains `state_update_commands` and a sole-agent clause;
     `.aai/SUBAGENT_PROTOCOL.md` contains `state_update_commands` and names the
     serial dispatch surface `.aai/ORCHESTRATION.prompt.md`.
   - `test_seam_extension_key_accepted` (TEST-RG-PIN-07) — write two fixture
     result blocks into `$TEST_DIR`: one valid block plus a
     `state_update_commands:` list (expect `check-role-output.mjs` exit 0), one
     with `started_utc` removed (expect exit 1 and a `ROLE-OUTPUT-VIOLATION:`
     line). Degrade-and-skip if `check-role-output.mjs` is absent.
   Run the suite here: all four MUST fail. Store the output under
   `docs/ai/tdd/red-<ts>-r-guard.log`.
2. `.aai/SUBAGENT_CONTRACT.md` (outside the diet corpus — normative text lives
   here). Extend the "Single-writer rule" section with the D1 statement, the
   returned-commands duty (verbatim, fully substituted commands, one per list
   item, in execution order, under `state_update_commands:`), the note that
   `check-role-output.mjs` ignores extension keys, and the sole-agent carve.
   Add one rationalization row: the serial-pipeline / my-role-prompt-told-me
   excuse against the reality that being dispatched decides it.
3. `.aai/SUBAGENT_PROTOCOL.md` (outside the corpus). ENV row: state that it
   binds EVERY dispatch, serial (`.aai/ORCHESTRATION.prompt.md`) and parallel
   alike. Merge protocol step 3: add `state_update_commands` as an explicit
   merge input the orchestrator executes in the order returned. Do not restate
   the subagent-facing duty — point at the contract (the existing
   PROTOCOL-is-orchestrator-side, CONTRACT-is-payload split, pinned by
   hygiene-pack TEST-082).
4. `.aai/ORCHESTRATION.prompt.md` (in corpus, thin-wrapper ceiling 45, at 40
   today). In step 2, replace the enumerated dispatch fields with a reference to
   the call contract INCLUDING its ENV row (shorter than the list it replaces),
   add the keep-it-unset clause, and add running the returned
   `state_update_commands` next to the existing `append-run`. Budget: +2 lines
   (42 of 45), roughly +110 bytes.
5. The four role prompts (in corpus). ONE line each at the state-update step —
   PLANNING step 12, IMPLEMENTATION step 10, VALIDATION step 9, REMEDIATION
   covering steps 4 and 5 together — of the shape "dispatched (AAI_ROLE=subagent):
   return these under `state_update_commands:` in your result block instead of
   running them, see .aai/SUBAGENT_CONTRACT.md; sole agent: run them". Roughly
   +130 bytes each. Nothing else in those steps changes.
6. `tests/skills/suite-map.yaml`: extend the `aai-r-guard` globs with the six
   newly pinned files (D5).
7. Measure the corpus delta, append the ledger entry at the measured amount and
   bump the TEST-012 `want_growth` pin by the same amount (Spec-AC-07). Then run
   the full sweep.

Data flows. The only new flow is the command list: role prompt (instruction) ->
subagent result block (`state_update_commands:`) -> `check-role-output.mjs`
(ignores it, block still valid) -> orchestrator merge protocol step 3 (executes
in order) -> `state.mjs` with the marker unset (writes land). Every hop is
covered by a Spec-AC.

Edge cases.
- Sole-agent lane (`.aai/SKILL_LOOP.prompt.md` "FALLBACK (no subagent support)"):
  the clause is conditional, so this lane keeps running the commands itself.
  This is why the rule keys on the dispatch, never on the role.
- A dispatched role with NO state change to report omits the key entirely; the
  block stays valid (the key is optional by construction).
- An older vendored layer without `check-role-output.mjs`: unchanged
  degrade-and-report path; the extension key is inert prose there.
- REMEDIATION has two state-touching steps (4 reset-block, 5 set-phase and
  set-human-input); one clause covers both, so the corpus pays for one line.
- `.aai/ORCHESTRATION_PARALLEL.prompt.md` is deliberately NOT edited: it already
  states (a) and its arming line is pinned by TEST-RG-PIN-02. Touching it would
  spend corpus bytes to say what it already says.

## Test Plan

| Test ID  | Spec-AC    | Type       | File path (expected)       | Description                  | Status  |
|----------|------------|------------|----------------------------|------------------------------|---------|
| TEST-001 | Spec-AC-01 | int | tests/skills/test-aai-r-guard.sh | TEST-RG-PIN-04: serial ORCHESTRATION carries the arming line, the unset clause, state_update_commands, and is 45 lines or less | pending |
| TEST-002 | Spec-AC-02 | int | tests/skills/test-aai-r-guard.sh | TEST-RG-PIN-05: all four role prompts carry the dispatched clause and keep the state.mjs primary path plus fallback marker | pending |
| TEST-003 | Spec-AC-02 | int | tests/skills/test-aai-state.sh | TEST-014 still green: nine prompts keep state.mjs primary path and the state.mjs is absent marker after the edits | pending |
| TEST-004 | Spec-AC-03 | int | tests/skills/test-aai-r-guard.sh | TEST-RG-PIN-06: SUBAGENT_CONTRACT holds the normative duty and sole-agent carve; SUBAGENT_PROTOCOL names the merge input and the serial surface | pending |
| TEST-005 | Spec-AC-04 | int | tests/skills/test-aai-r-guard.sh | TEST-RG-PIN-07 SEAM: check-role-output exits 0 on a block with state_update_commands and exits 1 on a block missing started_utc | pending |
| TEST-006 | Spec-AC-05 | int | docs/ai/tdd/ | stored RED log per arm against the pre-fix text, stored green log after, plus a hostile-mutation bite per arm with an unmutated control | pending |
| TEST-007 | Spec-AC-06 | int | tests/skills/test-aai-hygiene-pack.sh | suite-map row coverage green, and select-suites names aai-r-guard for each of the six newly pinned paths | pending |
| TEST-008 | Spec-AC-07 | int | tests/skills/test-aai-prompt-diet.sh | TEST-010 headroom within 0..2048 and TEST-012 pin equals the independent re-sum after the ledger true-up | pending |
| TEST-009 | Spec-AC-08 | int | tests/skills/test-framework.sh | full sweep green, and the diff contains no protected_paths_l3 file | pending |

## Verification
- `bash tests/skills/test-aai-r-guard.sh` (RED first, then green; plus mutated
  clones for TEST-006)
- `bash tests/skills/test-aai-state.sh`
- `bash tests/skills/test-aai-prompt-diet.sh`
- `bash tests/skills/test-aai-hygiene-pack.sh`
- `node .aai/scripts/check-test-registration.mjs`
- `node .aai/scripts/select-suites.mjs --files-from <changed paths>`; run what
  it returns
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh` for
  the full sweep
- `git diff main --name-only` checked against `protected_paths_l3`
- PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status, the
  table flipped at the close step immediately before `close-work-item.mjs`
  (SPEC-0151 AC-FLIP DEFERRAL).

## Evidence contract
- ref_id: single-writer-canon-contradiction
- Spec-AC and TEST-xxx links: as mapped above; every arm names its TEST-RG-PIN
  id in its log line so an evidence path resolves to an assertion.
- Commands and exit codes: the Verification list above, each recorded with its
  exit code.
- Evidence paths: `docs/ai/tdd/red-<ts>-r-guard.log`,
  `docs/ai/tdd/green-<ts>-r-guard.log`, the mutation transcript, the recorded
  before and after corpus byte counts, and the full-sweep log under
  `tests/skills/results/`.
- Commit SHA or diff range: the branch diff against `main` at review time.

### Evidence by strategy

Strategy is `tdd`, so this spec demands the stored RED artifact per AC-gating
arm (Spec-AC-05) plus the full verification matrix above.

## Registry items closed by this scope

`fu-subagent-state-write-contradiction` (P2, ref deslop-scope-and-unrequested-engine)
— closed at the close ceremony with `resolved_by` naming this change.

## Notes

- Consulted `node .aai/scripts/follow-ups.mjs list` at freeze (97 open). Two
  neighbours reproduced live on this ride's first dispatch tick and are
  deliberately NOT closed or narrowed here:
  `fu-dispatch-targets-closed-scope` (rule 6 dispatched Planning onto the
  already-closed CHANGE-0164 scope) and `fu-setfocus-keeps-stale-spec-path`
  (the stale `spec_path` that made it look plausible). Their root cause is in
  `orchestration-dispatch.mjs` rule matching and in `set-focus`'s field
  handling — the latter inside `protected_paths_l3` — so folding them in would
  both widen the intake and require a protected edit. This scope changes who
  runs a state command, not which scope the dispatcher picks.
- Precedent found at freeze, and it strengthens D1 and D2: `.aai/ROLE_COMMON.md`'s
  METRICS block already carries this exact shape — "Subagent-mode carve-out (D5):
  dispatched as a subagent -> do NOT self-append; return the result block ...
  direct execution -> self-append below". All four role prompts already point at
  that block instead of restating it. So the conditional-on-dispatch phrasing is
  not new canon, and the one-line-pointer mechanism this scope uses for the state
  step is already proven in the same four files for the metrics step. The defect
  is simply that the state-update steps never got the same treatment.
- `fu-report-ids-exceed-registry-cap` is a live hazard for the close: keep any
  new follow-up id at 40 characters or fewer.
- The intake's runtime risk (roles stop writing, orchestrator never starts)
  cannot be proven by a prose pin. It is mitigated by D4 pinning BOTH ends and
  is recorded here as the scope's residual risk: a regression would surface as
  a phase that stops advancing on the next serial ride, not as a red suite.
