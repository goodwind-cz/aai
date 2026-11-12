---
id: spec-round-cap-hardening
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: 542e084a44ed62dbb6bc81c5bf08417166a5f9b0202ffe024481a2907e6b2119
ceremony_level: 3
links:
  requirement: round-cap-hardening
  rfc: null
  pr: []
  commits: []
---

# The round cap fails closed on an unreadable ledger and counts one remediation as one round

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/ISSUE-DRAFT-round-cap-hardening.md
- Prior scope (closed, not edited): docs/specs/SPEC-0286-spec-factory-round-cap.md.
  This spec keeps its D-COUNT, D-CAP, D-EXT, D-SWEEP and D-STATUS rules and
  changes only what the decisions below name. It narrows SPEC-0286 residual risk
  R3 and leaves R7 and R8 as they are.
- Owner decisions enforced and not changed (docs/ai/decisions.jsonl):
  `review-round-cap` (two rounds max), `wave-2-roadmap` STANDING DECISION (a)
  (one standing-a extension per ride).
- Technology contract: docs/TECHNOLOGY.md (Node stdlib, bash suites through the
  canonical wrapper).

Registry items closed by this scope: `fu-round-budget-events-fail-closed`,
`fu-round-cap-dual-reset`, `fu-round-menu-full-command` (all ref
`factory-round-cap`, from `node .aai/scripts/follow-ups.mjs list`).

## Implementation strategy

- Strategy: tdd
- Rationale: every change is a refusal, a count or a fixed text that can be seen
  failing on the unchanged tree (the EISDIR and EACCES probes in the intake were
  run against origin/main b65ca681). Owner-preferred TDD runs of about three
  Spec-ACs: (1) Spec-AC-01..03, (2) Spec-AC-04..06, (3) Spec-AC-07..10.

## Isolation and review

- Worktree recommendation: required (ceremony L3)
- Worktree rationale: state.mjs is a protected L3 surface; the main checkout is
  shared, holds uncommitted telemetry, and a release is being cut from another
  worktree.
- User decision: worktree (owner-directed in the session brief of 2026-11-12)
- Base ref: origin/main at b65ca681 (rebase onto the v2026.11.12 release commit
  when it lands)
- Worktree branch/path: fix/round-cap-hardening at
  /Users/ales/Projects/aai-worktrees/round-cap-hardening
- Review required: true (L3: mandatory, most capable tier)
- Review scope: diff range origin/main...HEAD over .aai/scripts/round-budget.mjs;
  .aai/scripts/state.mjs; .aai/scripts/orchestration-dispatch.mjs;
  .aai/scripts/append-event.mjs; .aai/scripts/check-role-output.mjs;
  .aai/REMEDIATION.prompt.md; .aai/ORCHESTRATION.prompt.md;
  tests/skills/test-aai-round-budget.sh; tests/skills/lib/prompt-diet-ledger.sh;
  tests/skills/test-aai-prompt-diet.sh; tests/skills/test-aai-pr-preflight.sh;
  any existing suite whose fixture must change (named in the hand-off);
  CHANGELOG.md; the intake and this spec; the append-only ledger lines the ride
  writes.

## Ceremony

Ceremony level 3. The joint reset (D-JOINT) changes `state.mjs reset-block`,
and `.aai/scripts/state.mjs` is in `protected_paths_l3` of
docs/ai/docs-audit.yaml. No correct fix of the half-reset avoids state.mjs: the
gate cannot know that a second reset belongs to the same remediation unless the
call says so, and `resetGate(eventsPath, ref)` receives no block name. L3 brings
a recorded worktree decision (done), mandatory review on the most capable tier,
full re-check rounds only, and an operator final-diff checkpoint before merge.
The owner merges on his own word.

The round cap applies to this ride: 2 rounds, a FAIL needs a backed BLOCKING
entry, and the full sweep is paid once per `round-budget.mjs sweep-plan`.

## Decisions

### D-READ. A ledger that exists but cannot be read fails closed

- `readEvents(eventsPath)` returns no events only for ENOENT (absent file, as
  today). Any other read error (EACCES, EISDIR, EIO, ENOTDIR, ...) is thrown
  with its `code`. The guard spelling is
  `if (err.code === 'ENOENT') return out;` followed by a rethrow.
- `resetGate` catches it and returns `refused: true` with the message
  `REFUSED review-round-cap: cannot read <path> (<CODE>); the round count for <ref> is unknown. Repair the file, then retry.`
  It carries no owner menu, because one more round cannot be granted against a
  ledger nobody can read. `state.mjs reset-block` prints it and exits 5
  (`ROUND_CAP_EXIT`), writing neither STATE nor EVENTS. One exit code keeps one
  stop rule for every caller (D-RELAY).
- `append-event --event round_extension --authority standing-a`: when the read
  throws, it exits 1 with
  `round_extension refused: cannot read <path> (<CODE>); the standing-a limit cannot be checked`
  and appends nothing. The guard spelling is `if (eventsUnreadable)`. An `owner`
  extension does not read the ledger and is unchanged.
- `round-budget.mjs status`: prints `round-budget: cannot read <path> (<CODE>)`
  on stderr, nothing on stdout, and exits 1.
- `round-budget.mjs sweep-plan`: its two not-applicable answers keep their order
  and win first. Otherwise it prints
  `SWEEP full reason=events-unreadable code=<CODE>` and exits 0.
- check-role-output.mjs: a Validation PASS whose EVENTS cannot be read is
  rejected with E-SWEEP-OWED naming `reason=events-unreadable`, not with an
  uncaught exception.
- orchestration-dispatch.mjs already fails closed: it exits 1 with
  `internal error: ... EISDIR` and dispatches nothing. That stays. TEST-3625 pins
  it so a later best-effort wrapper cannot silently turn it into a dispatch.

### D-JOINT. One remediation is one round

- `state.mjs reset-block <block> [<block>]` accepts one or two distinct names
  from `last_validation`, `code_review`. A third name, a repeated name or an
  unknown name is refused before any read of EVENTS, with no write.
- Every named block is checked first: a `not_run` block is a no-op for that
  block; a `pass`/`waived` block without `--force` refuses the whole call; an
  unexpected status refuses the whole call. The guard spelling for a per-block
  refusal is `if (refusedBlock)`. When every named block is a no-op the call
  exits 0 and writes nothing (as today).
- The round gate runs ONCE for the call, after the per-block checks and before
  any edit. A refusal (cap or D-READ) leaves every named block as it was.
- The changed blocks are written in ONE STATE write. Their `round_reset` lines
  are appended in ONE `appendFileSync` call, one line per changed block, in the
  order named. Every line after the first carries `"same_round": true` in its
  payload.
- `roundsUsed(events, ref)` counts `round_reset` lines of the ref whose
  `payload.same_round !== true`. `status` keeps its per-block counts
  (`validation=`, `code_review=`, `forced=`) over all lines. Ledger lines written
  before this change have no `same_round` and count as before.
- `--force` applies to every named block. Each line records its own `from`.
- The single-block form behaves byte-for-byte as today.
- Two separate single-block calls in one remediation still count two rounds; the
  canon names the one-call form (D-RELAY). That residual is R1 below.

### D-RELAY. What callers do with exit 5

- orchestration-dispatch.mjs rules 10 and 12 check the cap BEFORE the
  `last_run_role === 'Remediation'` forensic case. At the cap the answer is
  `review_round_cap` with the owner menu even when the last run was a
  Remediation; below the cap the output is unchanged
  (`possible_missing_remediation_reset` still fires).
- .aai/REMEDIATION.prompt.md step 4 adds the joint form
  `node .aai/scripts/state.mjs reset-block last_validation code_review` for the
  case where both blocks failed (one call, one round), and says that on exit 5
  nothing was reset: stop, do not retry, return its REFUSED line.
- .aai/ORCHESTRATION.prompt.md step 4 `possible_missing_remediation_reset`:
  reset every failed block in one `reset-block` call; on exit 5 reset nothing
  else and re-run the script once (dispatch then answers `review_round_cap`, or
  exits 1 on an unreadable ledger). Existing lines are edited; the file stays at
  or under its 45-line ceiling.

### D-MENU2. The owner menu's option (2) is a runnable command

- `ROUND_MENU` becomes `roundMenu(ref)`. Option (2) reads
  `(2) one more round: node .aai/scripts/append-event.mjs --event round_extension --ref <ref> --authority owner --reason <why>`
  with the real ref substituted and `<why>` left for the owner. Options (1) and
  (3) and the order are unchanged. The text holds no double quote, so the
  dispatch's `set-human-input --question "..."` command stays one shell word.
- Both the reset-block refusal and the dispatch rule 10/12 stop use it.

## Acceptance Criteria Mapping

- Maps to: intake Expected Behavior bullet 1 (fail closed) to Spec-AC-01,
  Spec-AC-02, Spec-AC-03; bullet 2 (one remediation is one round, no half
  reset) to Spec-AC-04, Spec-AC-05; bullet 3 (exit 5 handling, cap before the
  forensic case) to Spec-AC-06, Spec-AC-08; bullet 4 (runnable menu) to
  Spec-AC-07; companion duties to Spec-AC-09, Spec-AC-10.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN state.mjs reset-block runs on a fail block while the EVENTS file beside STATE exists but cannot be read (a directory, or mode 0200 holding resets at the cap) the system SHALL exit 5 with a REFUSED review-round-cap line naming the path and the error code, and SHALL leave STATE and EVENTS byte-identical; an absent EVENTS file SHALL still count 0 rounds | planned | RED docs/ai/tdd/round-cap-hardening/red-1.log; GREEN green-1.log; mutation docs/ai/tdd/spec-round-cap-hardening/mutation-TEST-3620.txt and mutation-TEST-3621.txt | — | D-READ |
| Spec-AC-02 | WHEN append-event records a standing-a round_extension and the EVENTS file cannot be read the system SHALL exit 1 naming the read error and SHALL append nothing | planned | RED docs/ai/tdd/round-cap-hardening/red-1.log; GREEN green-1.log; mutation docs/ai/tdd/spec-round-cap-hardening/mutation-TEST-3622.txt | — | D-READ |
| Spec-AC-03 | WHEN the EVENTS file cannot be read round-budget status SHALL exit 1 with the read error and no rounds line, sweep-plan SHALL print SWEEP full reason=events-unreadable after its not-applicable checks, check-role-output SHALL reject a Validation PASS with E-SWEEP-OWED naming that reason, and orchestration-dispatch SHALL exit nonzero without dispatching Remediation | planned | RED docs/ai/tdd/round-cap-hardening/red-1.log; GREEN green-1.log; mutation docs/ai/tdd/spec-round-cap-hardening/mutation-TEST-3623.txt, mutation-TEST-3624.txt, mutation-TEST-3625.txt | — | D-READ; dispatch is a pin of existing behaviour |
| Spec-AC-04 | WHEN reset-block names both last_validation and code_review, both fail, at 1 of 2 rounds the system SHALL reset both in one STATE write, append two round_reset lines of which the second carries same_round true, and status SHALL then print rounds 2/2 with validation=2 and code_review=1 | planned | RED docs/ai/tdd/round-cap-hardening/red-2.log; GREEN green-2.log; mutation docs/ai/tdd/spec-round-cap-hardening/mutation-TEST-3626.txt | — | D-JOINT |
| Spec-AC-05 | WHEN a two-block reset-block is refused (rounds at the cap, an unreadable ledger, a pass block without force, a repeated or unknown block name) the system SHALL leave both blocks and EVENTS byte-identical; a two-block call with one block already not_run SHALL reset the other with one line and no same_round; the single-block form SHALL be unchanged | planned | RED docs/ai/tdd/round-cap-hardening/red-2.log; GREEN green-2.log; mutation docs/ai/tdd/spec-round-cap-hardening/mutation-TEST-3627.txt | — | D-JOINT, no half reset |
| Spec-AC-06 | WHEN dispatch rule 10 or 12 meets a fail block at the cap and the last recorded run is Remediation the system SHALL exit 3 with review_round_cap and one set-human-input command, and below the cap the same snapshot SHALL still return needs_llm possible_missing_remediation_reset | planned | RED docs/ai/tdd/round-cap-hardening/red-2.log; GREEN green-2.log; mutation docs/ai/tdd/spec-round-cap-hardening/mutation-TEST-3628.txt | — | D-RELAY |
| Spec-AC-07 | WHEN the cap refuses a reset or dispatch stops at the cap the menu option 2 SHALL be the full append-event round_extension command with --event, the ref, --authority owner and --reason, and running that command with the placeholder replaced SHALL let the next reset-block pass | planned | RED docs/ai/tdd/round-cap-hardening/red-3.log; GREEN green-3.log; mutation docs/ai/tdd/spec-round-cap-hardening/mutation-TEST-3629.txt | — | D-MENU2; seam refusal text to owner to append-event to the gate |
| Spec-AC-08 | REMEDIATION step 4 SHALL name the one-call two-block reset and the exit 5 stop with its REFUSED line, and ORCHESTRATION step 4 SHALL name one reset-block call for every failed block and the exit 5 re-run, within the 45-line ceiling | planned | RED docs/ai/tdd/round-cap-hardening/red-3.log; GREEN green-3.log; mutation docs/ai/tdd/spec-round-cap-hardening/mutation-TEST-3630.txt | — | D-RELAY prose |
| Spec-AC-09 | The prompt-diet ledger SHALL hold one round-cap-hardening entry equal to the measured corpus delta of the edited prompts, with the TEST-012 pin and the pr-preflight TEST-008 term bumped by the same amount and TEST-010 headroom 0 | planned | RED docs/ai/tdd/round-cap-hardening/red-3.log; GREEN green-3.log; mutation docs/ai/tdd/spec-round-cap-hardening/mutation-TEST-3631.txt | — | Companion obligation; a negative delta is a RECLAIMED entry |
| Spec-AC-10 | CHANGELOG.md SHALL gain exactly one per-entry unreleased heading for this fix below the kept bare scaffold, naming the fail-closed ledger read, the one-round joint reset and the runnable menu command | planned | RED docs/ai/tdd/round-cap-hardening/red-3.log; GREEN green-3.log; mutation docs/ai/tdd/spec-round-cap-hardening/mutation-TEST-3632.txt | — | Consumer-visible; canon and scripts ship downstream |

## Implementation plan

1. round-budget.mjs:
   - `readEvents` rethrows any error but ENOENT (D-READ spelling).
   - `resetGate` catches it and returns the D-READ refusal.
   - `roundsUsed` skips `same_round` lines.
   - `appendRoundReset(eventsPath, ref, payloads)` takes one or more payloads
     and appends them in one write; a payload after the first gets
     `same_round: true`.
   - `roundMenu(ref)` replaces `ROUND_MENU` (D-MENU2). Importers switch to it.
   - The CLI: `status` exits 1 on a read error; `sweep-plan` passes the error to
     `sweepPlan`, which answers events-unreadable after its not-applicable
     checks.
2. state.mjs `cmdResetBlock`: parse one or two block names, run every per-block
   check, then the gate once, then edit every changed block; `main()` writes
   STATE once and calls `appendRoundReset` once with every changed block's
   payload. The usage hint becomes `reset-block <block> [<block>]` (the
   test-aai-state.sh substring `reset-block <block>` still holds).
3. append-event.mjs: the standing-a read is wrapped; `if (eventsUnreadable)`
   refuses with exit 1.
4. orchestration-dispatch.mjs: in rules 10 and 12 move the cap check above the
   `last_run_role` check; use `roundMenu(ref)` in `roundCapStop`.
5. check-role-output.mjs: wrap the E-SWEEP-OWED read; an unreadable ledger
   becomes E-SWEEP-OWED with the events-unreadable SWEEP line.
6. REMEDIATION step 4 and ORCHESTRATION step 4 per D-RELAY.
7. Tests in tests/skills/test-aai-round-budget.sh (TEST-3620..3632) in the house
   style, under `set -euo pipefail`, `env -u AAI_ROLE` for nested calls. The
   EACCES cases skip with a SKIP line when `id -u` is 0 (root reads a 0200
   file); the EISDIR cases run everywhere.
8. CHANGELOG entry and prompt-diet true-up last; measure the corpus delta after
   the final prompt edit.

Edge cases:
- ENOTDIR (docs/ai is a file) counts as unreadable, not absent.
- A joint call where the first named block is not_run writes one line with no
  `same_round`; the counted line is always the first changed block's.
- A failed EVENTS append after a successful read and STATE write keeps today's
  WARNING and exit 0: the round goes uncounted (R2).
- A STATE with no focus ref skips the gate and the event with the existing NOTE,
  for one or two blocks.
- Dispatch: `roundCapStop` reason string still starts `review-round-cap:`, so
  unattended-gate classify (TEST-3605) is unchanged.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3620 | Spec-AC-01 | integration | tests/skills/test-aai-round-budget.sh | EVENTS.jsonl is a directory beside a temp STATE with a fail block: reset-block exits 5, prints REFUSED review-round-cap with the path and EISDIR, STATE is byte-identical; with EVENTS absent the same reset exits 0 and writes one line | target `.aai/scripts/round-budget.mjs`; `sed:s/if \(err.code === 'ENOENT'\) return out;/return out;/` reads every error as absent and the case must fail | pending |
| TEST-3621 | Spec-AC-01 | integration | tests/skills/test-aai-round-budget.sh | EVENTS mode 0200 holding two resets for the ref: reset-block exits 5 naming EACCES and the file keeps its two lines (restored to 0600 to compare); SKIP line under root | target `.aai/scripts/round-budget.mjs`; `sed:s/if \(err.code === 'ENOENT'\) return out;/return out;/` lets the third reset through and the case must fail | pending |
| TEST-3622 | Spec-AC-02 | integration | tests/skills/test-aai-round-budget.sh | EVENTS mode 0200 holding one standing-a extension: a second standing-a round_extension exits 1 naming the read error and the line count is unchanged; SKIP line under root | target `.aai/scripts/append-event.mjs`; `sed:s/if \(eventsUnreadable\)/if (false)/` appends the second standing-a and the case must fail | pending |
| TEST-3623 | Spec-AC-03 | integration | tests/skills/test-aai-round-budget.sh | with EVENTS a directory: status exits 1 with the read error and no rounds line; sweep-plan in a scratch repo holding test-framework.sh prints SWEEP full reason=events-unreadable code=EISDIR; without test-framework.sh it still prints not-applicable | target `.aai/scripts/round-budget.mjs`; `sed:s/reason: 'events-unreadable'/reason: 'no-sweep'/` restores the wrong reason and the case must fail | pending |
| TEST-3624 | Spec-AC-03 | integration | tests/skills/test-aai-round-budget.sh | check-role-output on a Validation PASS block in a scratch repo holding test-framework.sh and an EVENTS directory exits 1 with E-SWEEP-OWED naming events-unreadable and no stack trace | target `.aai/scripts/check-role-output.mjs`; `sed:s/events-unreadable/no-sweep/` drops the named reason and the case must fail | pending |
| TEST-3625 | Spec-AC-03 | integration | tests/skills/test-aai-round-budget.sh | orchestration-dispatch over a fixture with a validation fail below the cap and an EVENTS directory exits nonzero and its stdout holds no Remediation dispatch | target `.aai/scripts/orchestration-dispatch.mjs`; `sed:s/fs.readFileSync\(eventsPath, 'utf8'\)/''/` reads the ledger as empty, dispatches Remediation and the case must fail | pending |
| TEST-3626 | Spec-AC-04 | integration | tests/skills/test-aai-round-budget.sh | both blocks fail with one round_reset already recorded: reset-block last_validation code_review exits 0, both blocks read not_run, two lines are appended with same_round true on the second, status prints rounds: 2/2 and validation=2 code_review=1 | target `.aai/scripts/round-budget.mjs`; `sed:s/same_round !== true/same_round !== 1/` counts the second line and the case must fail | pending |
| TEST-3627 | Spec-AC-05 | integration | tests/skills/test-aai-round-budget.sh | two-block calls refused at 2/2, on an EVENTS directory, with code_review pass and no force, with a repeated name and with an unknown name each leave STATE and EVENTS byte-identical; last_validation not_run plus code_review fail resets code_review with one line and no same_round | target `.aai/scripts/state.mjs`; `sed:s/if \(refusedBlock\)/if (false)/` lets the pass block through and the case must fail | pending |
| TEST-3628 | Spec-AC-06 | integration | tests/skills/test-aai-round-budget.sh | a fixture whose METRICS records a Remediation run last and whose validation fails: with two resets dispatch exits 3 with review_round_cap and one set-human-input command; with one reset it exits 4 with possible_missing_remediation_reset; same for rule 12 | target `.aai/scripts/orchestration-dispatch.mjs`; `sed:s/if \(cap.reached\) return roundCapStop\('10'/if (false) return roundCapStop('10'/` loses the stop and the case must fail | pending |
| TEST-3629 | Spec-AC-07 | integration | tests/skills/test-aai-round-budget.sh | takes option 2 from a real reset-block refusal and from the dispatch set-human-input command, asserts --event round_extension, the ref, --authority owner and --reason, replaces the placeholder, runs it in the fixture and the next reset-block exits 0 | target `.aai/scripts/round-budget.mjs`; `sed:s/--event round_extension --ref/--ref/` makes the copied command fail and the case must fail | pending |
| TEST-3630 | Spec-AC-08 | unit | tests/skills/test-aai-round-budget.sh | greps REMEDIATION for the two-block reset-block command and the exit 5 REFUSED line rule, and ORCHESTRATION for one reset-block call per failed block and exit 5, and asserts ORCHESTRATION is at most 45 lines | target `.aai/REMEDIATION.prompt.md`; `sed:s/reset-block last_validation code_review/reset-block last_validation/` drops the joint form and the case must fail | pending |
| TEST-3631 | Spec-AC-09 | integration | tests/skills/test-aai-round-budget.sh | runs prompt-diet TEST-010 (headroom 0/2048) and TEST-012, and pr-preflight TEST-008, legacy-migrations TEST-3398 and retired-loop-runner TEST-3410, all green with the round-cap-hardening entry | target `tests/skills/lib/prompt-diet-ledger.sh`; `sed:s/ round-cap-hardening / round-cap-hardeningX /` hides the entry from the companion pins and the case must fail | pending |
| TEST-3632 | Spec-AC-10 | integration | tests/skills/test-aai-round-budget.sh | asserts exactly one bare unreleased scaffold and one per-entry heading naming round-cap hardening, and the release parser accepts it | target `CHANGELOG.md`; `sed:s/## \[unreleased\](?=\n)/## [unreleased] — broken/` consumes the bare scaffold and the case must fail | pending |

Seams crossed:
- state.mjs reset-block (joint) → EVENTS round_reset with same_round →
  round-budget roundsUsed → orchestration-dispatch rule 10/12 and `status`.
  TEST-3626 and TEST-3628 produce with the real CLI and read with the real
  readers.
- reset-block refusal text → owner → append-event round_extension → the next
  reset-block gate. TEST-3629 copies the command out of real output and runs it.
- An unreadable ledger read by five consumers (reset-block, append-event,
  status/sweep-plan, check-role-output, dispatch): TEST-3620..3625 each read
  the same fixture shape through the real CLI.
- Canon prompts ship downstream through aai-sync; no test runs a real
  Remediation agent against the new REMEDIATION text (R3).

## Verification

All local runs use `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh <cmd>`.

1. RED before each GREEN, per TDD run, stored as
   `docs/ai/tdd/round-cap-hardening/red-<run>.log` and `green-<run>.log`.
2. `bash tests/skills/test-aai-round-budget.sh` exits 0 (TEST-3600..3615 stay
   green beside TEST-3620..3632).
3. The selected suites for the ride diff plus CORE exit 0; at least aai-state,
   aai-orchestration-dispatch, aai-role-output, aai-round-budget, aai-canon,
   aai-prompt-diet, aai-pr-preflight, aai-hygiene-pack, aai-unattended,
   aai-recheck, aai-debug-gate, aai-metrics.
4. Mutation records for TEST-3620..3632 under
   `docs/ai/tdd/spec-round-cap-hardening/`.
5. One full sweep with `AAI_TEST_TIMEOUT=3600` at final validation, recorded
   with `append-event --event full_sweep`; later rounds follow `sweep-plan`.
6. `node .aai/scripts/round-budget.mjs status --ref round-cap-hardening` is
   reported in the PR body.
7. PASS criteria: every TEST row green, every Spec-AC done with evidence, CI
   green on the PR head.

## Evidence contract

Each artifact records the ref_id round-cap-hardening, its Spec-AC and TEST
links, the command, the exit code and the evidence path, plus the commit SHA
once one exists. RED and GREEN logs under docs/ai/tdd/round-cap-hardening/,
mutation records under docs/ai/tdd/spec-round-cap-hardening/.

### Evidence by strategy

tdd: a stored RED artifact per AC-gating test plus the verification matrix
above.

## Residual risks

- R1. Two separate single-block `reset-block` calls in one remediation still
  count two rounds and can still half-reset at cap minus one. The canon names
  the one-call form; nothing detects the two-call form, because no verdict event
  separates two remediations in EVENTS.
- R2. SPEC-0286 R3, narrowed: a read error now refuses, but an EVENTS append
  that fails after a successful read and STATE write still leaves the round
  uncounted with a WARNING.
- R3. No test runs a real Remediation or orchestrator agent against the edited
  prose; the relay of exit 5 rests on the prompt text (TEST-3630 pins the text).
- R4. SPEC-0286 R7 (set-validation / set-code-review `--status not_run` clear a
  fail uncounted) and R8 (a `full_sweep` record is not tied to a real run) are
  unchanged and out of scope.
- R5. The EACCES cases skip under root; the EISDIR cases carry the fail-closed
  proof on every runner.
