---
id: spec-tdd-red-evidence-classification
type: spec
number: 44
status: done
ceremony_level: 2
links:
  change: tdd-red-evidence-classification
  rfc: null
  pr:
    - 96
  commits:
    - a8a3bf2
---

# SPEC — RED Evidence Classification: Machine-Distinguish product_red from infra_fail

SPEC-FROZEN: true

## Links
- Change: tdd-red-evidence-classification
  (docs/issues/CHANGE-0033-tdd-red-evidence-classification.md)
- Related discipline (not reopened): SPEC-0013 H7 fixture-diversity checklist
  and the "would this suite stay green with only the happy path" RED-proof
  extension in `.aai/SKILL_TDD.prompt.md` — this spec is the sibling gate for
  RED evidence KIND (product assertion vs infrastructure noise).
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec frozen for implementation, work not yet started (SPEC-FROZEN: true)
- implementing: work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: standard meanings per template

## Ceremony level
`ceremony_level: 2` — full pipeline. Honestly considered L1 per the dispatch
invitation and rejected: the scope is NOT single-surface — it touches two
prompt-diet corpus prompts (`.aai/SKILL_TDD.prompt.md`,
`.aai/VALIDATION.prompt.md`), adds one NEW executable gate script, and one NEW
bash test suite; it also changes what counts as valid TDD evidence for every
future cycle (workflow-behavior change, not a small fix). It touches NO
`protected_paths_l3` entry — `.aai/scripts/state.mjs` is explicitly
verify-only (zero diff; see D3) — so L3 is not forced.

## Problem statement (verified facts)
1. `.aai/SKILL_TDD.prompt.md` Phase 1 requires "Failure is for the right
   reason (not syntax error)" (RED Phase Checklist) but the prescribed
   evidence format — a raw log at `docs/ai/tdd/red-[timestamp].log` plus
   `state.mjs set-tdd-cycle --status RED --red <path>` — carries NO
   structured field distinguishing a product assertion failure from an
   infrastructure failure. Both exit non-zero; both satisfy the letter of
   "RED observed".
2. The risk is real in this repo's own history: existing RED logs contain
   both shapes — `docs/ai/tdd/ceremony-lane-red.log` test_012 fails with
   `TypeError: Cannot read properties of undefined` (runner-level exception,
   though there a legitimate missing-feature signal) while other sections
   fail via `AssertionError` with expected/actual. Nothing machine-checks
   which shape a log is.
3. `state.mjs set-tdd-cycle` (state.mjs:621-680) has no classification flag —
   and `state.mjs` is a `protected_paths_l3` surface, so recording the
   classification in STATE would force L3 ceremony for no functional gain.
4. `.aai/VALIDATION.prompt.md` step 5g (RED-proof check) confirms a test "has
   been observed FAILING" but has no tool to check the failure KIND.
5. Both prompts are in the prompt-diet corpus (`tests/skills/
   test-aai-prompt-diet.sh` PROMPT_FILES) whose byte floor TEST-010 is
   already failing (DEBT-0002) — verbose text must live outside the corpus.

## Design decisions
- D1 (where the classification lives): in the RED log file itself as exactly
  one machine-readable header line, grammar:
  `RED_CLASS: product_red` or `RED_CLASS: infra_fail`
  (match rule: line matching `^RED_CLASS:[ \t]*(product_red|infra_fail)[ \t]*$`;
  exactly one such line per log file). The log is already the durable,
  git-diffable evidence artifact and STATE already points to it
  (`tdd_cycle.evidence.red`), so machine consumers reach the classification
  through the recorded path. Plain-file portability per Constitution art. 3.
- D2 (no silent default — intake AC-001): a log with NO `RED_CLASS` line, a
  duplicate/conflicting line, or an unrecognized value is UNCLASSIFIED and is
  never accepted as `product_red`. Rejection is the default; acceptance
  requires the explicit `product_red` token.
- D3 (protected paths untouched): `.aai/scripts/state.mjs` gets ZERO diff.
  No `--red-class` flag is added; `set-tdd-cycle` calls are byte-for-byte
  unchanged. This intentionally narrows the intake's "log and/or STATE"
  option to log-only, avoiding forced L3 ceremony (recorded refinement).
- D4 (the gate is an executable check, not prose): new script
  `.aai/scripts/tdd-evidence-check.mjs` (Node stdlib only, plain `node`
  invocation, no dependencies). CLI: `node .aai/scripts/tdd-evidence-check.mjs
  --red <log-path>`. Exit contract:
  - 0 = `product_red` — accepted as RED-proof
  - 1 = `infra_fail` — REJECTED; fix the infrastructure and re-capture
  - 2 = unclassified/invalid (missing line, >1 RED_CLASS line, unknown value)
    — REJECTED, per D2
  - 3 = usage error / unreadable path (fail fast with context, art. 4)
  One log file = one classification; a multi-section log is classified as a
  whole (if any section is infra noise, the author fixes or splits before
  claiming RED).
- D5 (classification rule — intake AC-002, language-agnostic): classify
  `product_red` ONLY when the log shows the test's OWN assertion/expectation
  output was reached — the expected-vs-actual or failure message the test
  itself emits (e.g. `AssertionError` with expected/actual, a suite's
  `FAIL: TEST-xxx <described reason>` line). Classify `infra_fail` when the
  run died BEFORE any test assertion executed — runner/module-loader
  exception (import/module-resolution error, syntax error in the test file,
  missing fixture/file, command not found), timeout, or crash with no
  assertion output. Expressed as "assertion output reached", never a
  specific runner's exception format (works for bash suites, vitest, pytest,
  cargo, etc.). Author-asserted in v1; reviewer/Validation spot-checks the
  raw log against this rule (same spot-check model as today's "right
  reason" checklist item). Auto-derivation heuristics are OUT of scope.
- D6 (author-side gate): SKILL_TDD Phase 1 requires writing the `RED_CLASS`
  header into the captured log and running the check; a non-zero check
  result BLOCKS advancing to GREEN (extends the existing "Cannot proceed to
  GREEN until RED evidence exists" hard block: the evidence must be
  product_red-classified).
- D7 (validation-side gate): VALIDATION step 5g additionally runs the check
  against the current scope's recorded RED evidence
  (`tdd_cycle.evidence.red` and/or the red logs cited by the spec's AC
  table). `infra_fail` or unclassified NEWLY captured evidence does not
  count as RED-proof (same consequence ladder as today's 5g: residual risk,
  or FAIL for security/data-integrity/bug-fix ACs).
- D8 (forward-looking only — intake AC-004): legacy logs (captured before
  this change lands) are NOT retroactively reclassified or failed. The gate
  applies to the current scope's newly captured evidence; VALIDATION carries
  an explicit legacy carve-out: a pre-change log with no `RED_CLASS` line
  falls back to today's by-eye "right reason" spot-check. Closed/done work
  items are never re-gated. No repo-wide sweep over docs/ai/tdd/ is added
  anywhere.
- D9 (byte discipline, DEBT-0002): the verbose contract (grammar, exit
  codes, classification rule with examples) lives in the SCRIPT's header
  comment and usage text (non-corpus file). Corpus edits are lean:
  `.aai/SKILL_TDD.prompt.md` ≤ ~10 added lines, `.aai/VALIDATION.prompt.md`
  ≤ ~4 added lines. TEST-010's pre-existing byte-floor gap worsens by only
  this small delta (recorded in validation notes, same handling as
  SPEC-0043 R3).

## Implementation strategy
- Strategy: tdd
- Rationale: the gate script is NEW behavior whose whole purpose is evidence
  integrity (data-integrity class per PLANNING step 7 — exactly where a
  rubber-stamped criterion does the most damage), and the misclassification
  matrix (missing/duplicate/unknown/valid) deserves per-test RED-GREEN
  discipline. Dogfood bonus: this scope's own RED logs adopt the `RED_CLASS`
  header voluntarily, exercising the format before the gate exists.

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: additive scope — one new script, one new test suite,
  lean edits to two prompts; no protected paths, no migrations, no
  cross-cutting refactor. Operator has already recorded
  `user_decision: inline` for this scope ("operator-approved: inline on
  feat/tdd-red-evidence-classification" in STATE); Planning does not
  override that recorded decision.
- User decision: inline (pre-recorded by operator)
- Base ref: main
- Inline review scope: see Code review scope below.
- Code review required: true (workflow-canon + executable gate + test changes)
- Code review scope (explicit paths):
  `.aai/scripts/tdd-evidence-check.mjs`, `.aai/SKILL_TDD.prompt.md`,
  `.aai/VALIDATION.prompt.md`, `tests/skills/test-aai-tdd-evidence.sh`,
  `docs/specs/SPEC-0044-spec-tdd-red-evidence-classification.md`,
  `docs/issues/CHANGE-0033-tdd-red-evidence-classification.md`,
  `docs/INDEX.md`

## Acceptance Criteria Mapping
- Maps to: CHANGE-0033 AC-001
  - Spec-AC-01: RED evidence carries a machine-readable classification:
    exactly one `RED_CLASS: product_red|infra_fail` line per log (D1), and
    `.aai/scripts/tdd-evidence-check.mjs` implements the exit contract
    0/1/2/3 (D4) with NO path that accepts a missing, duplicated, or
    unknown-valued classification (D2 — exit 2, never 0).
  - Verification: TEST-001 (synthetic fixture matrix over the script).
- Maps to: CHANGE-0033 AC-002
  - Spec-AC-02: `.aai/SKILL_TDD.prompt.md` Phase 1 states the concrete,
    language-agnostic distinguishing rule ("test's own assertion output
    reached" vs "runner/import/timeout/syntax failure before any assertion
    output" — D5), the `RED_CLASS` grammar, the check invocation, and a RED
    Phase Checklist item for classification; verbose contract lives in the
    script header, corpus addition stays lean (D9).
  - Verification: TEST-003 (canon grep contract, REDs on unedited canon).
- Maps to: CHANGE-0033 AC-003
  - Spec-AC-03: the gate has teeth on realistic evidence: a fixture log with
    a genuine broken-import/runner-crash body classified `infra_fail` exits
    1 (cycle must NOT advance to GREEN on it — hard-block wording in
    SKILL_TDD, D6), and a fixture log with a genuine assertion-failure body
    classified `product_red` exits 0 (accepted).
  - Verification: TEST-002 (integration fixture pair crossing Seam 1);
    TEST-003 asserts the hard-block wording.
- Maps to: CHANGE-0033 AC-003 (gate consumed by Validation) + AC-004
  - Spec-AC-04: `.aai/VALIDATION.prompt.md` step 5g instructs running
    `tdd-evidence-check.mjs` against the current scope's recorded RED
    evidence; `infra_fail`/unclassified NEW evidence is rejected as
    RED-proof (D7); an explicit legacy carve-out exempts pre-change logs
    without a `RED_CLASS` line from mechanical rejection (D8).
  - Verification: TEST-004 (canon grep contract, REDs on unedited canon).
- Maps to: CHANGE-0033 AC-004
  - Spec-AC-05: the change is additive — a legacy repo log (no `RED_CLASS`
    line) yields exit 2 from the script when explicitly invoked, but no
    repo-wide gate consumes legacy logs; `tests/skills/test-aai-tdd.sh`
    still exits 0; `.aai/scripts/state.mjs` has ZERO diff (D3);
    `node .aai/scripts/docs-audit.mjs --check --strict --no-event` exits 0.
  - Verification: TEST-005 (regression + zero-diff + legacy-log probe).

## Constitution deviations

None.

(Checked at freeze: art. 1 evidence gates strengthened, not weakened; art. 2
one field + one small script, no speculative auto-detection; art. 3 plain
git-diffable log lines and a stdlib-only script; art. 4 exit 3 usage errors
fail fast with context; art. 5 additive at every boundary — legacy logs stay
valid, set-tdd-cycle unchanged; art. 6 state.mjs untouched, single writer
preserved; art. 7 not applicable to this scope.)

## Acceptance Criteria Status

| Spec-AC    | Description                                              | Status  | Evidence | Review-By | Notes |
|------------|----------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | RED_CLASS grammar + check script exit contract, no default-accept | done | TEST-001 GREEN, docs/ai/tdd/green-20260717T141023Z-tdd-red-evidence-classification-test001-005.log | — | — |
| Spec-AC-02 | SKILL_TDD Phase 1 concrete classification rule (lean)    | done | TEST-003 GREEN, same log; `.aai/SKILL_TDD.prompt.md` Phase 1 | — | — |
| Spec-AC-03 | infra_fail fixture rejected / product_red fixture accepted | done | TEST-002 GREEN, same log | — | — |
| Spec-AC-04 | VALIDATION 5g consumes the check; legacy carve-out       | done | TEST-004 GREEN, same log; `.aai/VALIDATION.prompt.md` step 5g | — | — |
| Spec-AC-05 | Additive: no retroactive invalidation; state.mjs zero-diff | done | TEST-005 GREEN, same log; `git diff --stat -- .aai/scripts/state.mjs` empty; docs-audit --check --strict --no-event exit 0 | — | — |

## Implementation plan
Edit points (all additive; corpus edits lean per D9):
1. `.aai/scripts/tdd-evidence-check.mjs` — NEW (~100 lines, Node stdlib
   only): parse `--red <path>`; scan for `^RED_CLASS:[ \t]*(\S+)[ \t]*$`
   lines; enforce exactly-one + enum; exit 0/1/2/3 per D4; print a one-line
   human verdict naming the log path and classification; header comment +
   usage text carry the full D5 classification rule (the verbose canon).
2. `.aai/SKILL_TDD.prompt.md` Phase 1 — amend step 4 (Capture RED Evidence):
   write the `RED_CLASS:` header line per the D5 rule, then run
   `node .aai/scripts/tdd-evidence-check.mjs --red <log>`; non-zero blocks
   GREEN (fix infra, re-capture). Amend RED Phase Checklist: extend the
   "right reason" item with the classification + check-exit-0 requirement.
   Amend the Phase 1 BLOCK line: RED evidence must be product_red-classified.
3. `.aai/VALIDATION.prompt.md` step 5g — append: run the check against the
   scope's recorded RED log(s); infra_fail/unclassified NEW evidence is not
   RED-proof; legacy logs without `RED_CLASS` (pre-change) keep today's
   by-eye spot-check (D8).
4. `tests/skills/test-aai-tdd-evidence.sh` — NEW bash-3.2-compatible suite
   (pattern: tests/skills/test-aai-token-capture.sh; run through
   `.aai/scripts/aai-run-tests.sh`): fixture matrix (TEST-001), realistic
   accept/reject pair (TEST-002), canon grep contracts (TEST-003/004),
   regression + legacy probe (TEST-005).
Edge cases: duplicate RED_CLASS lines with IDENTICAL values → still exit 2
(exactly-one rule keeps the parser trivial and unambiguous); CRLF line
endings → tolerate trailing `\r` (normalize before match); empty log file →
exit 2 (unclassified); path outside docs/ai/tdd/ → allowed (the check is
path-agnostic; placement discipline stays with SKILL_TDD).

## Seam analysis
- Seam 1: the grammar SKILL_TDD tells authors to write ↔ the parser
  tdd-evidence-check.mjs accepts. Crossed end-to-end by TEST-002 (fixture
  logs written exactly per the canon grammar, checked by the real script)
  and pinned textually by TEST-003 (canon names the literal `RED_CLASS:`
  token and both enum values the script implements).
- Seam 2: `tdd_cycle.evidence.red` path recorded in STATE ↔ Validation
  running the check on that recorded path. The producing side is unchanged
  (set-tdd-cycle byte-identical, D3); the consuming instruction is pinned by
  TEST-004. Behavioral adherence by LLM role agents cannot be mechanically
  forced — recorded as residual risk R1 (same class as SPEC-0043 R1).
- Seam 3: prompt-diet corpus byte floor ↔ corpus additions in the two
  prompts. Not automatable as a new pass (TEST-010 already fails
  pre-existing, DEBT-0002); handled as recorded delta in validation notes
  (R2).

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                    | Description                                                                                                    | Status  |
|----------|------------|-------------|-----------------------------------------|----------------------------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-tdd-evidence.sh   | Check-script contract matrix: product_red→0, infra_fail→1, missing/duplicate/unknown RED_CLASS→2, unreadable path/usage→3; no input shape reaches exit 0 without the literal `product_red` token | green |
| TEST-002 | Spec-AC-03 | integration | tests/skills/test-aai-tdd-evidence.sh   | Realistic accept/reject split (Seam 1): broken-import runner-crash log + `RED_CLASS: infra_fail` → exit 1 (rejected); assertion-failure log (expected-vs-actual reached) + `RED_CLASS: product_red` → exit 0 (accepted) | green |
| TEST-003 | Spec-AC-02 | unit        | tests/skills/test-aai-tdd-evidence.sh   | Canon contract: SKILL_TDD Phase 1 carries the `RED_CLASS:` grammar (both values), the D5 assertion-output-reached rule, the check invocation, a classification checklist item, and the product_red-only GREEN hard block — REDs on unedited canon | green |
| TEST-004 | Spec-AC-04 | unit        | tests/skills/test-aai-tdd-evidence.sh   | Canon contract: VALIDATION step 5g names tdd-evidence-check.mjs, rejects infra_fail/unclassified NEW evidence as RED-proof, and carries the legacy (pre-change, no-RED_CLASS) carve-out — REDs on unedited canon | green |
| TEST-005 | Spec-AC-05 | integration | tests/skills/test-aai-tdd-evidence.sh   | Additive regression: legacy repo log (e.g. docs/ai/tdd/dispatch-retarget-red.log) → exit 2 when explicitly probed, and no repo-wide sweep exists; `bash tests/skills/test-aai-tdd.sh` exit 0; `git diff` empty on .aai/scripts/state.mjs; docs-audit --check --strict --no-event exit 0 | green |

RED-proof: TEST-001/002 MUST be observed failing before the script exists
(invocation fails / wrong exits); TEST-003/004 MUST be observed failing
against unedited canon (they grep for text that does not yet exist).
TEST-005 is a baseline-green regression guard BY DESIGN (recorded RED-waiver:
it pins pre-existing behavior — legacy-log probe exit 2 REDs naturally until
the script lands, so the waiver covers only the re-run/zero-diff arms; the
anti-tautology obligation for the change itself is carried by TEST-001..004).
Dogfood: the RED logs captured for THIS scope carry `RED_CLASS: product_red`
headers themselves.

## Verification
- `bash tests/skills/test-aai-tdd-evidence.sh` → exit 0 (TEST-001..005), run
  via `.aai/scripts/aai-run-tests.sh` per LEARNED wrapper rule.
- `bash tests/skills/test-aai-tdd.sh` → exit 0 (regression).
- `grep -n "RED Phase Checklist" -A 15 .aai/SKILL_TDD.prompt.md` shows the
  amended checklist including the classification step (intake Verification).
- `git diff --stat -- .aai/scripts/state.mjs` → empty (protected surface
  verify-only, D3).
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` → exit 0.
- Manual dry run (intake Verification): scratch test file with a broken
  import captured as RED evidence → check exits 1 under `RED_CLASS:
  infra_fail` (and 2 if unlabeled); same file fixed to fail on its intended
  assertion → check exits 0 under `RED_CLASS: product_red`.
- Known pre-existing failures (NOT gates for this scope, verified on clean
  main per LEARNED 2026-07-15/17): `test-aai-worktree.sh` scratch-git
  fixture; `test-aai-prompt-diet.sh` TEST-010 byte floor (this change adds a
  small number of corpus bytes under D9 — re-record the TEST-010 delta in
  validation notes); `test-aai-ceremony-levels.sh` test_010_seam_survival
  (transitively re-runs prompt-diet).

## Residual risks
- R1: Prompt-protocol adherence by LLM agents is not mechanically enforced —
  the canon-contract tests pin the TEXT of the SKILL_TDD/VALIDATION duties,
  not agent behavior (same accepted class as SPEC-0043 R1).
- R2: Prompt-diet TEST-010 net-reduction number worsens by the small corpus
  delta (already failing pre-existing, DEBT-0002; D9 minimizes it).
- R3: The classification is author-asserted in v1 — a careless/incorrect
  self-classification (e.g. labeling a crash `product_red`) passes the
  mechanical check; mitigation is the D5 rule being concrete enough for
  reviewer/Validation spot-check against the raw log (intake accepts this
  explicitly; heuristic auto-detection is a possible follow-up, not scoped).

## Evidence contract
For each implementation, validation, TDD, and code review artifact record:
ref_id `tdd-red-evidence-classification`, Spec-AC + TEST-xxx links, command
or review scope, exit code or verdict, evidence path, commit SHA/diff range.
