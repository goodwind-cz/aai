---
id: spec-factory-round-cap
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: 0d8843d41adfc6652526d7afea5b8f4410f6d10a7f3506c59f1ebcedb50a3af7
ceremony_level: 3
links:
  requirement: factory-round-cap
  rfc: null
  pr: []
  commits: []
---

# A ride's re-check loop stops at its counted round cap and pays the full sweep once

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/CHANGE-DRAFT-factory-round-cap.md
- Owner decisions this scope enforces and does not change (docs/ai/decisions.jsonl,
  `hitl_decision`, `owner_signoff: true`): `review-round-cap` (2026-09-05, two
  rounds max), `wave-2-roadmap` STANDING DECISION (a) (one extra round for a
  hazard introduced by the feature, a second is a STOP that asks) and STANDING
  DECISION (b) (a behaviour change after a recorded pass is re-checked with
  `reset-block --force` without asking).
- Canon this scope edits: .aai/VALIDATION.prompt.md c2, .aai/REMEDIATION.prompt.md,
  .aai/SKILL_CODE_REVIEW.prompt.md, .aai/SKILL_VERIFY.prompt.md,
  .aai/ORCHESTRATION.prompt.md (step 3, one existing line), .aai/AGENTS.md
  operator contract rule 3.
- Evidence read at Planning: the six validation and three review reports of ride 8
  `install-path-parity-harness` (PR #546) and the two validation and one review
  reports of `update-ps1-git-stderr` (PR #547). They are in the orchestrating
  session's scratchpad, not in the repository. The archives
  docs/ai/archive/merge-cleanup/pr-546 and pr-547 hold the rides' STATE and
  EVENTS. The ride 8 commits 8238f289, a7817f48, 8ce8bf2e, 3cfbdf2d, 07813eb9
  and cd5d99c5 are in the local object store.
- Technology contract: docs/TECHNOLOGY.md (Node stdlib, bash suites through the
  canonical wrapper).

Registry items closed by this scope: none. `node .aai/scripts/follow-ups.mjs list`
holds no open item on round caps, re-check counting or sweep reuse.

## Implementation strategy

- Strategy: tdd
- Rationale: Every rule here is a deterministic refusal or a count, and each one
  can be seen failing on the unchanged tree. The prose rules are pinned by grep
  tests that are red before the edit. The owner asked for TDD in runs of about
  three Spec-ACs on Node-first rides. Suggested runs: (1) Spec-AC-01..03,
  (2) Spec-AC-04..06, (3) Spec-AC-07..09, (4) Spec-AC-10..12.

## Isolation and review

- Worktree recommendation: required (ceremony L3)
- Worktree rationale: state.mjs is a protected L3 surface. The main checkout is
  shared and holds uncommitted telemetry.
- User decision: worktree (owner-directed in the session brief of 2026-11-12,
  recorded in STATE)
- Base ref: origin/main at d937b4af (v2026.11.11)
- Worktree branch/path: change/factory-round-cap at
  /Users/ales/Projects/aai-worktrees/factory-round-cap
- Review required: true (L3: mandatory, most capable tier)
- Review scope: diff range origin/main...HEAD over .aai/scripts/round-budget.mjs;
  .aai/scripts/state.mjs; .aai/scripts/orchestration-dispatch.mjs;
  .aai/scripts/append-event.mjs; .aai/scripts/check-role-output.mjs;
  .aai/VALIDATION.prompt.md; .aai/REMEDIATION.prompt.md;
  .aai/SKILL_CODE_REVIEW.prompt.md; .aai/SKILL_VERIFY.prompt.md;
  .aai/ORCHESTRATION.prompt.md; .aai/AGENTS.md; .aai/SUBAGENT_CONTRACT.md;
  .aai/system/PROFILES.yaml; tests/skills/test-aai-round-budget.sh;
  tests/fixtures/round-history/install-path-parity-harness.json;
  tests/skills/suite-map.yaml; tests/skills/suite-weights.tsv;
  tests/skills/lib/prompt-diet-ledger.sh; tests/skills/test-aai-prompt-diet.sh;
  tests/skills/test-aai-pr-preflight.sh; tests/skills/test-aai-legacy-migrations.sh;
  tests/skills/test-aai-retired-loop-runner.sh; any existing suite whose fixture
  must change (named in the hand-off); CHANGELOG.md; docs/product/factory-round-cap.md
  (written at /aai-ship step 4);
  the intake and this spec; the append-only ledger lines the ride writes.

## Ceremony

Ceremony level 3. The scope edits `.aai/scripts/state.mjs`, which
`protected_paths_l3` in docs/ai/docs-audit.yaml lists. That brings the L3 rules
from .aai/workflow/WORKFLOW.md: a recorded worktree decision (done), mandatory
review on the most capable tier, no delta re-check rounds (every re-check is a
full one), and an operator checkpoint before merge. The owner merges on his own
word in any case. The state.mjs gate is not optional. Ride 8 left no
`check_dispatched` or `check_verdict` EVENTS lines and no METRICS agent runs, so
the dispatcher never saw its rounds. The one path that ride and every hand-run
ride use is `state.mjs reset-block`, so that is where the counter and the cap must
live. `.aai/workflow/WORKFLOW.md` is not edited: it says nothing about round counts
or sweep scope, so nothing in it contradicts the rules below.

## Measurements behind the decisions

Ride 8 `install-path-parity-harness`, from its reports (verdict, blocking count,
sweep):

| Round | Head | Verdict | Driver | Full sweep |
|---|---|---|---|---|
| V1 | 8238f289 | PASS | first validation | yes, 56 min, green |
| R1 | 8238f289 | FAIL | 1 BLOCKING (Pester line 72), 6 NON-BLOCKING | no |
| V2 | a7817f48 | FAIL | B1 flaky Windows allowlist row (hazard introduced by the feature) | no (intermediate) |
| V3 | 8ce8bf2e | FAIL | B1 own suite over its step bound under sweep load (introduced by the feature) | yes, red |
| V4 | 3cfbdf2d | PASS | 4 NON-BLOCKING | yes, 54 min, green |
| R2 | 3cfbdf2d | FAIL | AC-03 text against the code, test names; 6 NON-BLOCKING | no |
| V5 | 07813eb9 | PASS | NON-BLOCKING folds | no |
| R3 | 07813eb9 | PASS | 4 NON-BLOCKING | no |
| V6 | cd5d99c5 | PASS | forced re-validation after a NON-BLOCKING fold | no |

The owner counts 7 remediation rounds. The reports give 9 check rounds (6
validation, 3 review), 4 FAIL verdicts, 1 forced re-check after a PASS, and 3
full sweeps of about 55 min each. The delta 8238f289..8ce8bf2e touched only
`.github/workflows/ps1-quality.yml`, tests, the spec and the ledgers. The deltas
8ce8bf2e..3cfbdf2d and 3cfbdf2d..07813eb9 touched only tests, the spec and the
ledger. Ride `update-ps1-git-stderr` (PR #547) ran 2 validation rounds and 1
review round, and its r1 FAIL was its full-sweep round.

## Decisions

### D-COUNT. One round counter, kept in EVENTS

- A round is one `state.mjs reset-block` call that changes a block, either
  `fail` to `not_run` or (with `--force`) `pass`/`waived` to `not_run`. An
  idempotent no-op reset of an already `not_run` block is not a round.
- Each such call appends one EVENTS line
  `{"event":"round_reset","ref":<focus ref>,"payload":{"block":<last_validation|code_review>,"from":<fail|pass|waived>,"forced":<bool>}}`.
  It goes to the `EVENTS.jsonl` in the same directory as the STATE file the call
  wrote (`--state` honoured, so suites never touch the real ledger). It is
  written through the same validated writer append-event.mjs uses.
- A stale pass after a remediation is re-checked by dispatch rule 11s, which
  needs no reset and costs no round. A forced reset is a round.
- `roundsUsed(events, ref)` is the count of `round_reset` lines for the ref.
  `roundCap(events, ref)` is `ROUND_CAP_BASE` (2) plus the number of
  `round_extension` lines for the ref.
- Both functions live in one new module, `.aai/scripts/round-budget.mjs`. It
  exports them and its CLI. state.mjs, orchestration-dispatch.mjs,
  append-event.mjs and check-role-output.mjs import it, and none of them keeps
  its own copy.

### D-CAP. Where the cap binds

- `state.mjs reset-block`: when `roundsUsed >= roundCap` for the focus ref
  before the call, it refuses with exit 5 (`ROUND_CAP_EXIT`). It writes neither
  STATE nor EVENTS. It prints one line starting with `REFUSED review-round-cap:`
  that names `<used>/<cap>` and the ref, then the three-option menu from
  D-MENU. A no-op reset is never refused.
- `orchestration-dispatch.mjs` rules 10 and 12: when the rule would dispatch
  Remediation and `roundsUsed >= roundCap`, it does not dispatch. It returns
  exit 3 (no_action), rule `10` or `12`, reasons `review_round_cap` (plus
  `standing_a_available` when the ref has no `standing-a` extension), and
  exactly one `state_update_commands` entry:
  `node .aai/scripts/state.mjs set-human-input --required true --reason "review-round-cap: <used>/<cap> rounds used for <ref>" --question "<D-MENU text>"`.
  Below the cap, the output is byte-identical to today's for the same snapshot.
- `.aai/ORCHESTRATION.prompt.md` step 3 (one existing line is extended, and the
  file stays within its 45-line ceiling): on `review_round_cap`, when
  `standing_a_available` is present and the FAIL report names a hazard
  introduced by the feature, record
  `node .aai/scripts/append-event.mjs --event round_extension --ref <ref> --authority standing-a --reason "<hazard>"`
  and re-run step 1 once. Otherwise, run the returned `state_update_commands`
  and STOP.
- Unattended rides: SKILL_LOOP's existing `review-round-cap` trigger token and
  `unattended-gate.mjs classify` (scope, park) are reused unchanged. The reason
  string starts with `review-round-cap:` so the loop reads the token.

### D-EXT. Extensions

- `append-event.mjs --event round_extension --ref <ref> --authority <standing-a|owner> --reason <text>`.
  `--reason` must be non-empty.
- A second `standing-a` extension for the same ref is refused (exit 1, message
  names STANDING DECISION (a)). That is the "second such extension is a STOP
  that asks" half of decision (a).
- `owner` extensions are not limited. Each one is a visible ledger line, the same
  way `ride-select.mjs gate --override` is logged and never silent.

### D-MENU. The owner menu text

One line, options in this order: `(1) split the ride: close what is green, file
the rest as a new intake (recommended) (2) one more round: append-event
round_extension --authority owner (3) park the ride`.

### D-BAR. The blocking bar

- A role result block (`subagent_result`) with role `Validation` or
  `Code Review` and status `FAIL` must carry at least one `blockers` entry that
  matches
  `BLOCKING <id>: <text> backed-by: check <path> exit <n>` with `n` an integer
  other than 0, or `BLOCKING <id>: <text> backed-by: repro <path>`. `<path>` must
  name an existing file, relative to the repo root.
- Without such an entry, check-role-output.mjs rejects the block with
  `E-FAIL-UNBACKED` (exit 1). Status `BLOCKED` and every other role are
  unaffected.
- The grammar is added to .aai/SUBAGENT_CONTRACT.md's `blockers` line.
- NON-BLOCKING findings never produce a FAIL. Canon routes them to follow-ups
  (`follow-ups.mjs add`) by default. Fixing one inside the ride after a recorded
  pass needs a forced reset, which is a counted round (D-COUNT). The canon says
  so in REMEDIATION and SKILL_CODE_REVIEW, where the H6 disposition duty is
  kept.

### D-SWEEP. The full sweep runs once

- The sweep command is the canonical-wrapper run of
  `tests/skills/test-framework.sh`.
- After that sweep, the Validation role records
  `node .aai/scripts/append-event.mjs --event full_sweep --ref <ref> --head <40-hex HEAD> --rc <exit code> --run-id <framework run id>`.
  append-event refuses a missing or malformed `--head`, a non-integer `--rc` or
  an empty `--run-id`.
- `node .aai/scripts/round-budget.mjs sweep-plan --ref <ref> [--root <dir>]`
  prints exactly one line and exits 0:
  - `SWEEP not-applicable reason=no-sweep-command` when
    `tests/skills/test-framework.sh` is absent (every downstream project).
  - `SWEEP not-applicable reason=lightweight-lane` when the focus spec
    declares ceremony 0 or 1.
  - `SWEEP full reason=no-sweep` when the ref has no `full_sweep` line.
  - `SWEEP full reason=red-sweep run=<id>` when the newest `full_sweep` line
    has `rc` other than 0.
  - `SWEEP full reason=not-ancestor sha=<S>` when that head is not an ancestor
    of HEAD.
  - `SWEEP full reason=code-delta path=<first path>` when any path in the
    delta is outside the reuse classes.
  - `SWEEP reuse sha=<S> run=<id>` otherwise.
- The delta is `git diff --name-only --no-renames <S>` against the working tree,
  plus untracked, non-ignored files.
- The reuse classes are `REUSE_GLOBS`: `tests/**`, `docs/**`, `**/*.md`,
  `.github/**`, `CHANGELOG.md`, and suite-map.yaml's `carry_forward_globs` and
  `inert_globs`. Workflow files are included because the local sweep does not run
  them; the selected suites that read them run in every round, and the PR's CI
  runs the workflows.
- `.aai/**/*.md` canon prompts count as text. Their pins are tests that the
  selected suites run.
- Every round runs the SELECTED plus CORE suites named by
  `select-suites.mjs --files-from <ride diff>` first. A round with a red
  selected or CORE suite is a FAIL and pays no sweep. After a green selected
  run, the validator runs `sweep-plan`. `full` means the sweep is run once and
  recorded. `reuse` means the sweep is cited by run id.
- check-role-output.mjs rejects a `Validation` `PASS` block with `E-SWEEP-OWED`
  when `sweep-plan` for its ref answers `full` at the time of the check. A
  `reuse` or `not-applicable` answer passes; for `not-applicable` the check
  prints a NOTE line naming the reason.
- A FAIL round never needs a sweep. So the ride pays the sweep exactly once when
  nothing outside the reuse classes changes after it, and once more for each
  later code delta or red sweep.

### D-CANON. Prose, one rule each

- VALIDATION c2 is rewritten to point at the rules above: the round counter and
  cap, the standing (a) extension command, the blocking bar, and the sweep-plan
  sequence.
- c2 keeps both owner-decision citations (`review-round-cap`, `wave-2-roadmap`)
  that TEST-694 in test-aai-canon.sh resolves.
- REMEDIATION step 2 adds the default follow-up route for NON-BLOCKING findings
  and says that a fix after a pass is a counted round. Step 4 adds the exit 5
  refusal: stop, do not retry, return the menu.
- SKILL_CODE_REVIEW: a BLOCKING finding carries `backed-by:`, and an unbacked
  concern is NON-BLOCKING.
- SKILL_VERIFY:
  - The reuse exception's last sentence becomes "The ride's one full sweep
    (round-budget.mjs sweep-plan), CI, main, nightly and release always
    execute."
  - The rationalization row "I ran part of the suite, the rest can't be
    affected" gets the counter "Run the selected plus CORE suites this round
    names; the full sweep follows sweep-plan. Blast radius is the selector's
    call, never a guess."
- AGENTS.md rule 3 gains one sentence: the cap is counted by
  `round-budget.mjs status` and enforced by dispatch and `reset-block`.
- No prompt keeps a sentence that demands a full sweep in an intermediate round
  or a re-run of the whole suite.

### D-STATUS. Forward measurement

`node .aai/scripts/round-budget.mjs status --ref <ref> [--json]` prints
`rounds: <used>/<cap> extensions: <n> resets: validation=<v> code_review=<c> forced=<f> sweeps: <count> green=<g> last_sweep=<sha|none>`
and exits 0. It reads only EVENTS. Every ride from this one on can be compared
by rounds and sweep count without METRICS.

### D-REPLAY. Proof of the gain

tests/fixtures/round-history/install-path-parity-harness.json records ride 8's
nine rounds from the table above: role, verdict, whether the FAIL report named a
hazard introduced by the feature, and the changed-path list of each head-to-head
delta, copied from `git diff --name-only` of the commits named above. The
fixture embeds the path lists because the ride's commits are not reachable from
origin and so not present in CI clones.

The replay test builds a scratch git repository. It applies each delta as file
touches and drives the real CLIs in order: `state.mjs set-validation` /
`set-code-review`, `reset-block`, `append-event round_extension` when the round
qualifies under (a), `orchestration-dispatch.mjs`, and `round-budget.mjs
sweep-plan`. It prints one line:
`REPLAY ride=install-path-parity-harness recorded_check_rounds=9 recorded_resets=5 recorded_sweeps=3 replay_resets=<n> replay_stop=<round id> replay_sweeps=<m>`.
It asserts `replay_resets` 3 (R1, V2, and V3 under the one standing-a
extension), `replay_stop` R2 (the fourth FAIL meets the cap of 3), the forced
V6 reset refused, and `replay_sweeps` 1 (V1; the V3 and V4 deltas are reuse
classes).

The gain is reported in the PR and the product doc as recorded against replay:
5 resets and 3 sweeps (about 165 min) against 3 automatic resets, an owner menu
at R2, and 1 sweep (about 55 min).

### D-WIRE. Pins and wiring, named up front

- `.aai/system/PROFILES.yaml` core: add `.aai/scripts/round-budget.mjs`.
- tests/skills/suite-map.yaml: a new suite `aai-round-budget` whose globs are
  round-budget.mjs, state.mjs, orchestration-dispatch.mjs, append-event.mjs,
  check-role-output.mjs, VALIDATION, REMEDIATION, SKILL_CODE_REVIEW,
  SKILL_VERIFY, ORCHESTRATION and tests/fixtures/round-history/**. Add the
  module to the globs of `aai-state`, `aai-orchestration-dispatch` and
  `aai-role-output`. Add a weight row in tests/skills/suite-weights.tsv
  measured from the suite's own run.
- Prompt diet: one `JUSTIFIED_ADDITIONS` entry named `factory-round-cap` in
  tests/skills/lib/prompt-diet-ledger.sh, equal to the measured corpus delta of
  the six edited prompt files. A negative delta is entered as a RECLAIMED
  entry. TEST-010 headroom stays 0/2048.
- The TEST-012 `want_growth` pin in tests/skills/test-aai-prompt-diet.sh is
  bumped by the same amount.
- The companion pins follow:
  - test-aai-pr-preflight.sh TEST-008 needs one more `+<n>/* factory-round-cap
    ledger credit */` term in its `want_growth` formula.
  - test-aai-legacy-migrations.sh TEST-3398 and
    test-aai-retired-loop-runner.sh TEST-3410 re-sum later ledger entries by
    themselves. Re-run them to confirm, and edit them only if they redden.
- Existing pins that must stay green and are re-run, not edited unless they
  redden:
  - test-aai-canon.sh TEST-684 (ORCHESTRATION 45-line ceiling) and TEST-694
    (c2 citations).
  - test-aai-hygiene-pack.sh (ORCHESTRATION 45 lines).
  - test-aai-r-guard.sh TEST-RG-PIN-04.
  - test-aai-role-output.sh. Its FAIL fixtures carry `blockers: []` and assert
    other codes; they must still exit 1 with their named code.
  - test-aai-state.sh, test-aai-orchestration-dispatch.sh, test-aai-recheck.sh,
    test-aai-debug-gate.sh and test-aai-metrics.sh, which call `reset-block`.
    Their fixture STATE files sit in temporary directories, so `round_reset`
    lines land beside them and never in the real ledger.
  - test-aai-unattended.sh (`review-round-cap` park).
- The full list of suites to run each round is the selector's output for the
  ride diff plus CORE. Because round-budget.mjs is a new script under
  `.aai/scripts/`, expect the selector to print FULL_RUN for some deltas.

## Acceptance Criteria Mapping

- Maps to: intake AC-001 to Spec-AC-04 and Spec-AC-05; intake AC-002 to
  Spec-AC-02 and Spec-AC-03; intake AC-003 to Spec-AC-06; intake AC-004 to
  Spec-AC-07 and Spec-AC-08; intake AC-005 to Spec-AC-09; intake AC-006 to
  Spec-AC-10; the scope's wiring and consumer-visible duties to Spec-AC-11 and
  Spec-AC-12; the counter itself to Spec-AC-01.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN round-budget.mjs status runs over an EVENTS file the system SHALL print rounds used as the count of round_reset lines of the ref and the cap as 2 plus its round_extension lines, ignoring other refs and malformed lines with a NOTE | planned | — | — | D-COUNT, D-STATUS |
| Spec-AC-02 | WHEN state.mjs reset-block changes a block the system SHALL append one round_reset line beside the STATE file, and WHEN rounds used already meet the cap it SHALL exit 5 with a REFUSED review-round-cap line and the three-option menu, writing neither STATE nor EVENTS; a no-op reset SHALL append nothing and never refuse | planned | — | — | D-COUNT, D-CAP |
| Spec-AC-03 | WHEN append-event records a round_extension the system SHALL require an authority of standing-a or owner and a non-empty reason, SHALL refuse a second standing-a extension for the same ref, and reset-block SHALL then accept the reset the cap refused | planned | — | — | D-EXT |
| Spec-AC-04 | WHEN dispatch rule 10 or 12 would send Remediation with rounds used at the cap the system SHALL exit 3 with reason review_round_cap, add standing_a_available while no standing-a extension exists, and return exactly one set-human-input command whose reason starts review-round-cap; below the cap the output SHALL be unchanged | planned | — | — | D-CAP |
| Spec-AC-05 | WHEN the dispatch stop is relayed the human-input reason SHALL classify as review-round-cap park in unattended-gate, and ORCHESTRATION step 3 SHALL name review_round_cap, the standing-a command and its re-run once, within the 45-line ceiling | planned | — | — | Seam dispatch to loop to unattended gate |
| Spec-AC-06 | WHEN check-role-output reads a Validation or Code Review FAIL block whose blockers hold no BLOCKING entry backed by check with a nonzero exit or by repro, each naming an existing file, the system SHALL reject it with E-FAIL-UNBACKED; a backed entry SHALL pass and other roles and BLOCKED SHALL be unaffected | planned | — | — | D-BAR |
| Spec-AC-07 | WHEN round-budget.mjs sweep-plan runs the system SHALL print exactly one SWEEP line, with not-applicable for an absent test-framework.sh or a lightweight lane, full for no sweep, a red sweep, a non-ancestor head or a path outside the reuse classes, and reuse otherwise; append-event SHALL refuse a full_sweep line with a bad head, rc or run id | planned | — | — | D-SWEEP |
| Spec-AC-08 | WHEN check-role-output reads a Validation PASS block while sweep-plan answers full the system SHALL reject it with E-SWEEP-OWED, SHALL accept it on reuse, and SHALL accept it with a NOTE line on not-applicable | planned | — | — | D-SWEEP |
| Spec-AC-09 | WHEN the ride 8 round history is replayed through the real CLIs in a scratch repository the system SHALL print the REPLAY line with replay_resets 3, replay_stop R2, the forced V6 reset refused and replay_sweeps 1 against recorded 5 resets and 3 sweeps | planned | — | — | D-REPLAY, the measured gain |
| Spec-AC-10 | The canon prompts SHALL each name the counted cap, the backed blocking bar, the follow-up default for NON-BLOCKING findings and the sweep-plan sequence as D-CANON lists, SHALL keep both owner-decision citations in VALIDATION c2, and SHALL keep no sentence that demands an intermediate full sweep or a whole-suite re-run | planned | — | — | D-CANON |
| Spec-AC-11 | The new module SHALL be classified core in PROFILES, mapped by suite-map to the new suite and the three existing ones, and the prompt-diet ledger entry, the TEST-012 pin and the companion pins SHALL agree with the measured corpus delta at headroom 0 | planned | — | — | D-WIRE |
| Spec-AC-12 | CHANGELOG.md SHALL gain exactly one per-entry unreleased heading for this change below the kept bare scaffold, naming the cap, the blocking bar, the sweep plan and the measured gain | planned | — | — | Consumer-visible; canon prompts ship downstream; the product doc is /aai-ship step 4, not an AC |

## Implementation plan

1. round-budget.mjs (new, Node stdlib only):
   - Exports `ROUND_CAP_BASE = 2`, `ROUND_CAP_EXIT = 5`, `REUSE_GLOBS`,
     `roundsUsed`, `roundCap`, `sweepPlan` and `readEvents`.
   - `roundCap` returns `ROUND_CAP_BASE + extensions`.
   - Refusal and gate sites in the importers use the guard spellings
     `if (gate.refused)` (state.mjs), `if (cap.reached)`
     (orchestration-dispatch.mjs), `if (standingAUsed)` and
     `if (!fullSweepOk)` (append-event.mjs), and `if (failUnbacked)` and
     `if (sweepOwed)` (check-role-output.mjs).
   - state.mjs calls `appendRoundReset(` once, after the STATE write succeeds.
     A failed EVENTS append prints a WARNING and keeps exit 0. The reset
     already happened, and the next dispatch would then under-count, which is
     disclosed here as residual risk R3.
   - The sweep-plan red check reads `last.rc !== 0`.
   - These spellings are what the Test Plan mutations target. If one has to
     change, it is a mutation-class amendment.
2. state.mjs: in `cmdResetBlock`, after the no-op return and before any edit,
   compute the gate from EVENTS beside the STATE path. On a refusal, print and
   `process.exit(ROUND_CAP_EXIT)`.
3. append-event.mjs: add the three event types with their validation.
4. orchestration-dispatch.mjs:
   - Count `round_reset` and `round_extension` for the focus ref in the
     existing EVENTS scan.
   - Rules 10 and 12 check `cap.reached` before `dispatchFor('Remediation'`.
   - The `--rules` text for 10 and 12 names the cap.
5. check-role-output.mjs: add `E-FAIL-UNBACKED` and `E-SWEEP-OWED` as numbered
   postconditions in the header list. `E-SWEEP-OWED` calls `sweepPlan` with the
   repo root that the existing Validation PASS snapshot check already uses.
6. Prompts per D-CANON. ORCHESTRATION gets one extended line.
   SUBAGENT_CONTRACT gets the `blockers` grammar.
7. Fixture and suite:
   - tests/fixtures/round-history/install-path-parity-harness.json.
   - tests/skills/test-aai-round-budget.sh, holding TEST-3600 to TEST-3611 as
     functions in the house style, under `set -euo pipefail`, with
     `env -u AAI_ROLE` for nested suite calls.
   - Wiring per D-WIRE.
8. CHANGELOG entry and prompt-diet true-up last; measure the corpus delta after
   the final prompt edit. The product doc docs/product/factory-round-cap.md is
   written by /aai-ship step 4 after LOOP COMPLETE, not inside the loop, so it
   does not stale a recorded verdict.

Edge cases:
- An EVENTS file that is absent counts 0 rounds.
- A STATE with no focus ref makes reset-block skip the gate and the event, with
  a NOTE.
- A dirty tree at sweep time: the record is keyed on HEAD, so a dirty code path
  reads as a code delta (conservative). The validator commits before the sweep.
- A FAIL whose only blocker is a BLOCKED-style human question uses status
  BLOCKED, not FAIL.
- Delta re-check rounds (RECHECK_DELTA) are unaffected. At L0 to L2 they still
  count one round per reset.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3600 | Spec-AC-01 | unit | tests/skills/test-aai-round-budget.sh | status over a fixture EVENTS with two refs, two resets and one extension for the ref and one malformed line prints rounds 2/3, extensions 1 and a NOTE | target `.aai/scripts/round-budget.mjs`; `sed:s/ROUND_CAP_BASE + extensions/ROUND_CAP_BASE/` drops extensions from the cap and the case must fail | pending |
| TEST-3601 | Spec-AC-02 | integration | tests/skills/test-aai-round-budget.sh | reset-block on a fail block in a temp STATE appends one round_reset beside it with from fail and forced false; a second no-op reset appends nothing | target `.aai/scripts/state.mjs`; `sed:s/appendRoundReset(/void (/` drops the append and the case must fail | pending |
| TEST-3602 | Spec-AC-02 | integration | tests/skills/test-aai-round-budget.sh | with two round_reset lines for the ref a third reset-block exits 5, prints REFUSED review-round-cap 2/2 and the three options, and leaves STATE and EVENTS byte-identical | target `.aai/scripts/state.mjs`; `sed:s/if (gate.refused)/if (false)/` disables the gate and the case must fail | pending |
| TEST-3603 | Spec-AC-03 | integration | tests/skills/test-aai-round-budget.sh | append-event round_extension standing-a succeeds once and the refused reset then passes; a second standing-a for the ref exits 1 naming STANDING DECISION (a); an owner extension with an empty reason exits 1 | target `.aai/scripts/append-event.mjs`; `sed:s/if (standingAUsed)/if (false)/` allows a second standing-a and the case must fail | pending |
| TEST-3604 | Spec-AC-04 | integration | tests/skills/test-aai-round-budget.sh | dispatch over a fixture repo with validation fail and two resets exits 3 with review_round_cap and standing_a_available and one set-human-input command; with one reset it dispatches Remediation byte-identical to a no-EVENTS baseline; same for rule 12 | target `.aai/scripts/orchestration-dispatch.mjs`; `sed:s/if (cap.reached)/if (false)/` dispatches Remediation past the cap and the case must fail | pending |
| TEST-3605 | Spec-AC-05 | integration | tests/skills/test-aai-round-budget.sh | the reason from the TEST-3604 command, run through state.mjs set-human-input, classifies as park via unattended-gate classify --trigger review-round-cap; ORCHESTRATION names review_round_cap and round_extension --authority standing-a and stays at or under 45 lines | target `.aai/ORCHESTRATION.prompt.md`; `sed:s/review_round_cap/review_round_capX/g` removes the relay instruction and the case must fail | pending |
| TEST-3606 | Spec-AC-06 | unit | tests/skills/test-aai-round-budget.sh | check-role-output on Validation FAIL and Code Review FAIL blocks with blockers [] and with an unbacked BLOCKING line exits 1 with E-FAIL-UNBACKED; with a backed check line naming an existing log and exit 1, and with a backed repro line, exits 0; an Implementation FAIL and a Validation BLOCKED are unaffected | target `.aai/scripts/check-role-output.mjs`; `sed:s/if (failUnbacked)/if (false)/` accepts an unbacked FAIL and the case must fail | pending |
| TEST-3607 | Spec-AC-07 | integration | tests/skills/test-aai-round-budget.sh | sweep-plan in scratch repos prints not-applicable without test-framework.sh, not-applicable for a ceremony 1 spec, full no-sweep, full not-ancestor, full code-delta naming a .aai/scripts path, reuse for a delta of tests, docs, a workflow file and a ledger line | target `.aai/scripts/round-budget.mjs`; `sed:s/'tests\/\*\*'/'tests-x\/\*\*'/` drops tests from the reuse classes and the case must fail | pending |
| TEST-3608 | Spec-AC-07 | integration | tests/skills/test-aai-round-budget.sh | the newest full_sweep with rc 1 makes sweep-plan print full red-sweep even for a test-only delta; append-event refuses full_sweep with a short head, a non-integer rc or an empty run id | target `.aai/scripts/round-budget.mjs`; `sed:s/last.rc !== 0/false/` reuses a red sweep and the case must fail | pending |
| TEST-3609 | Spec-AC-07 | unit | tests/skills/test-aai-round-budget.sh | append-event full_sweep validation alone: each malformed field exits 1 and writes no line | target `.aai/scripts/append-event.mjs`; `sed:s/if (!fullSweepOk)/if (false)/` accepts a malformed record and the case must fail | pending |
| TEST-3610 | Spec-AC-08 | integration | tests/skills/test-aai-round-budget.sh | check-role-output on a Validation PASS block in a scratch repo with no full_sweep exits 1 with E-SWEEP-OWED; after a green full_sweep at HEAD it exits 0; in a repo without test-framework.sh it exits 0 and prints a NOTE | target `.aai/scripts/check-role-output.mjs`; `sed:s/if (sweepOwed)/if (false)/` accepts an owed sweep and the case must fail | pending |
| TEST-3611 | Spec-AC-09 | integration | tests/skills/test-aai-round-budget.sh | replays tests/fixtures/round-history/install-path-parity-harness.json through state.mjs, append-event, orchestration-dispatch and round-budget in a scratch repo and asserts the REPLAY line values from D-REPLAY | target `.aai/scripts/round-budget.mjs`; `sed:s/ROUND_CAP_BASE = 2/ROUND_CAP_BASE = 9/` moves the stop past R2 and the case must fail | pending |
| TEST-3612 | Spec-AC-10 | unit | tests/skills/test-aai-round-budget.sh | greps the six prompts for the D-CANON phrases: round-budget.mjs sweep-plan and status, round_extension, backed-by, follow-ups.mjs add, both owner-decision ids in c2; asserts the old SKILL_VERIFY counter text and any intermediate full-sweep demand are absent | target `.aai/VALIDATION.prompt.md`; `sed:s/round-budget.mjs sweep-plan/select-suites.mjs sweep-plan/g` drops the sweep-plan rule and the case must fail | pending |
| TEST-3613 | Spec-AC-11 | unit | tests/skills/test-aai-round-budget.sh | PROFILES core lists round-budget.mjs; select-suites --files-from with the module selects aai-round-budget, aai-state, aai-orchestration-dispatch and aai-role-output; suite-weights has a row | target `.aai/system/PROFILES.yaml`; `sed:s/scripts\/round-budget.mjs/scripts\/round-budget-x.mjs/` unclassifies the module and the case must fail | pending |
| TEST-3614 | Spec-AC-11 | integration | tests/skills/test-aai-prompt-diet.sh | existing TEST-010 headroom 0/2048 and TEST-012 growth sum equal to the ledger with the factory-round-cap entry; pr-preflight TEST-008, legacy-migrations TEST-3398 and retired-loop-runner TEST-3410 green | target `tests/skills/lib/prompt-diet-ledger.sh`; `sed:s/ factory-round-cap / factory-round-capX /` hides the entry from the companion pins and the case must fail | pending |
| TEST-3615 | Spec-AC-12 | integration | tests/skills/test-aai-release.sh | existing TEST-022 asserts exactly one bare unreleased scaffold and the release parser accepts the new per-entry heading | target `CHANGELOG.md`; `sed:s/^## \[unreleased\]$/## [unreleased] — broken/` consumes the bare scaffold and the case must fail (the SPEC-0285 TEST-3586 form) | pending |

Seams crossed:
- state.mjs reset-block → EVENTS `round_reset` → orchestration-dispatch rule
  10/12 → set-human-input → unattended-gate classify. TEST-3604, TEST-3605 and
  TEST-3611 produce on one side with the real CLI and assert on the other.
- Validation role → append-event `full_sweep` → round-budget sweep-plan →
  check-role-output `E-SWEEP-OWED`. TEST-3608, TEST-3610 and TEST-3611 cross it
  with real CLIs.
- Review and validation reports → `blockers` grammar → check-role-output
  `E-FAIL-UNBACKED`. TEST-3606 crosses the result-block side. No automated test
  reads a real reviewer's prose; the grammar's adoption rests on the prompt
  edits (R2).
- Canon prompts ship downstream through aai-sync: the not-applicable branch
  (TEST-3607, TEST-3610) is the downstream face.

## Verification

All local runs use `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh <cmd>`.

1. RED before each GREEN, per TDD run. Store in
   `docs/ai/tdd/factory-round-cap/red-<run>.log` and `green-<run>.log`.
2. `bash tests/skills/test-aai-round-budget.sh` exits 0.
3. Run the selected suites for the ride diff plus CORE. At least these exit 0:
   aai-state, aai-orchestration-dispatch, aai-role-output, aai-canon,
   aai-prompt-diet, aai-pr-preflight, aai-legacy-migrations,
   aai-retired-loop-runner, aai-hygiene-pack, aai-r-guard, aai-unattended,
   aai-recheck, aai-debug-gate, aai-metrics, aai-release, aai-suite-select.
4. Mutation records for TEST-3600 to TEST-3615 under
   `docs/ai/tdd/spec-factory-round-cap/`.
5. Run one full sweep with `AAI_TEST_TIMEOUT=3600`, recorded with this ride's
   own `append-event --event full_sweep`. That is the first use of the rule it
   ships. Later rounds follow `round-budget.mjs sweep-plan`.
6. `node .aai/scripts/round-budget.mjs status --ref factory-round-cap` is
   reported in the PR body as this ride's own rounds and sweeps.
7. PASS criteria: every TEST row green, every Spec-AC done with evidence, the
   REPLAY line as asserted, and CI green on the PR head.

## Evidence contract

Each artifact records the ref_id factory-round-cap, its Spec-AC and TEST links,
the command, the exit code and the evidence path, plus the commit SHA once one
exists. Store RED and GREEN logs under docs/ai/tdd/factory-round-cap/ and
mutation records under docs/ai/tdd/spec-factory-round-cap/.

### Evidence by strategy

tdd: a stored RED artifact per AC-gating test plus the verification matrix
above.

## Residual risks

- R1. A load-only failure of a ride's own suite is no longer re-checked by a
  second sweep after a test-only delta. Ride 8 V3 found exactly that. CI and
  the next ride's sweep remain the net.
- R2. The blocking bar checks the result block, not the report prose. A
  reviewer can cite a weak reproduction file. The bar raises the cost of a FAIL
  without proving that the reproduction is sound.
- R3. If the EVENTS append fails after a reset that succeeded, the round goes
  uncounted. The failure prints a WARNING, and it never undoes the reset.
- R4. An agent can append an `owner` extension without the owner. The line is
  visible in EVENTS and reported by `status`, like a ride-gate override. It is
  not an identity proof.
- R5. A hand-run ride that never calls reset-block (for example by editing STATE
  by hand, which canon forbids) is not counted.
- R6. Classing `.github/**` as reusable relies on the selected suites and the
  PR's CI to cover workflow edits.
