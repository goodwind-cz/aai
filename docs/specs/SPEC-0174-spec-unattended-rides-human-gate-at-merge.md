---
id: spec-unattended-rides-human-gate-at-merge
type: spec
number: 174
status: done
ceremony_level: 3
links:
  requirement: docs/rfc/RFC-0014-unattended-rides-human-gate-at-merge.md
  rfc: docs/rfc/RFC-0014-unattended-rides-human-gate-at-merge.md
  pr:
    - 365
  commits:
    - d9638a845d199653f59f0a9850e6124a3eeb712e
---

# Spec — the human gate moves to the merge, and an opted-in unattended ride answers its own quality questions

SPEC-FROZEN: true

## Links
- Requirement / decision authority: `docs/rfc/RFC-0014-unattended-rides-human-gate-at-merge.md` (status `accepted`; owner decisions D1 and D2 of 2026-09-07, recorded in `docs/ai/decisions.jsonl` as two `planning_decision` lines with `actor: owner`)
- Reused, not reimplemented: `.aai/SKILL_INTERROGATE.prompt.md` (the resolution ladder), `.aai/scripts/hitl-channel.mjs` (async question channel, SPEC-0111), `.aai/scripts/ride-select.mjs` (`gate` and `next`), `.aai/SKILL_HITL.prompt.md` STEP 4c (the trigger to target-command mapping), `docs/ai/decisions.jsonl` (the one decision ledger)
- Precedent for the engine shape: `.aai/scripts/ride-select.mjs` and `.aai/scripts/orchestration-mode.mjs` — deterministic, fail-closed CLIs a prompt calls and branches on
- Technology contract: `docs/TECHNOLOGY.md` (Node stdlib only, zero dependencies, bash 3.2 suites, POSIX plus PowerShell mirrors)

Registry items closed by this scope: none. `node .aai/scripts/follow-ups.mjs list` at base `8d967f47` reports 150 open items; no open item has this scope's subject (searched for hitl, ship, unattend, autonom, budget, merge, gate, decision). Items whose subject this scope TOUCHES and why each stays open: `fu-orchestrator-does-not-watch-ci` (P2) becomes more visible because an unattended night now opens pull requests nobody watches, but CI watching is a separate surface and the merge gate is where a human reads CI status — recorded as a residual risk below, not closed here; `fu-overview-shows-closed-ride-inflight` (P2) is aggravated by ride chaining (STATE has no terminal phase and no clear-focus) and belongs to the STATE engine, an L3 protected path this scope deliberately does not touch; `fu-metrics-verdict-has-no-staleness` (P2) is about the metrics ledger's verdict, untouched here.

## Blocker owed to the owner before the implementation ride starts

`node .aai/scripts/ride-select.mjs gate --ref unattended-rides-human-gate-at-merge --intake docs/rfc/RFC-0014-unattended-rides-human-gate-at-merge.md` exits 1: `REFUSED — unattended-rides-human-gate-at-merge is not on the roadmap`. Both `/aai-ship` step 1a and the `SKILL_LOOP` loop-start gate call it, so the implementation ride cannot start until the owner either adds the pair to `docs/ai/roadmap.yaml` or passes `--override "<reason>"` (logged to EVENTS, never silent). Roadmap content is explicitly an owner decision; Planning does not make it. This blocks the ride, not the freeze.

## What is already true, and what is missing

- The ship checkpoint stops BEFORE any pull request exists (`.aai/SKILL_SHIP.prompt.md` step 5: "STOP and wait. This is a genuine human gate — never assume consent."), and `.aai/SKILL_PR.prompt.md`'s precondition list plus `.aai/AGENTS.md`'s commit gating policy both name that confirmation as the authority to commit and push.
- `.aai/AGENTS.md` Operator contract rule 1 ALREADY says internal rides go to a green, review-passed PR without a question. Canon therefore already contradicts itself on internal rides; D2 resolves the contradiction in rule 1's direction and generalises it.
- Async HITL (SPEC-0111) needs a linked issue or pull request to post to. With the gate before the PR, a scope with no pre-existing issue has no channel.
- `SKILL_LOOP` stop condition (b) exits on `human_input.required == true`. Stop condition (c) exits when the work items are done — so today an unattended night yields AT MOST ONE pull request even if every question resolved itself. "Several finished pull requests by morning" is unreachable without ride chaining.
- The run budget guards (`max_run_tokens`, `max_run_cost_usd`) both default to `0`, which means UNLIMITED. An unattended night under today's defaults has no cost ceiling at all.
- `/aai-interrogate` is the resolution ladder D1 needs and it already records to `docs/ai/decisions.jsonl`, but it runs only at spec freeze and only while a human is in-session.
- Role self-assessment is unreliable (RFC-0014 D1 evidence: a validator reported a run duration the harness contradicted; a remediator corrected the reviewer's own dispatch count). Nothing here may depend on a role grading its own question.

## Design decisions

- **D1 — the auto-versus-park boundary is a deterministic table keyed on the HITL trigger id, not a judgement a role makes about its own question.** The trigger set is already closed and already stamped mechanically: `.aai/ORCHESTRATION_HITL.prompt.md` writes `[HITL-<n>]` into `blocking_reason`, and `.aai/SKILL_HITL.prompt.md` STEP 4c already resolves behaviour from that token. RFC-0014 D1's subject classes map onto it one to one:

  | Trigger | Subject class | Unattended | Resolution when auto |
  |---|---|---|---|
  | HITL-1 product intent ambiguity | scope | park | — |
  | HITL-2 technology contract conflict | scope | park | — |
  | HITL-3 security or privacy risk ambiguity | irreversibility | park | — |
  | HITL-4 irreversible migration semantics | irreversibility | park | — |
  | HITL-5 unspecified numeric threshold | quality | auto | interrogate ladder: `inferred: <path>` else `recommended-default` |
  | HITL-6 validation blocked by missing creds or infra | cost | park | — |
  | HITL-7 worktree recommendation unanswered | quality | auto, except `required` or ceremony 3 | `inline` for not_needed and optional, `worktree` for recommended |
  | HITL-8 inline review scope dirty or ambiguous | quality | auto | scope derived from the spec and STATE, recorded as `inferred: <path>` |
  | HITL-9 code review BLOCKING findings | quality | auto | always `fail`, routing to Remediation; never `waived` |
  | stagnation escalation | guard | park | — |
  | run-budget escalation | cost | park | — |
  | review-round-cap escalation | scope | park | — |
  | anything else, absent or unparseable | unknown | park | — |

  HITL-5's row is consistent with `.aai/PLANNING.prompt.md`, which already forbids a clarification marker on performance budgets precisely because canon decides them. HITL-9's row is the RES-0002 evidence made mechanical: two Code Review FAILs remediated with no human input. HITL-7's row reproduces `.aai/SKILL_SHIP.prompt.md` autopilot default 2 exactly rather than inventing a second worktree policy.

- **D2 — a waiver is never an autonomous outcome.** The engine has no code path that emits `waived`, for any trigger, under any flag or environment variable. Auto-resolving HITL-9 to `fail` costs a remediation round; auto-resolving it to `waived` would silently downgrade rigor, which `.aai/INTAKE_COMMON.md` forbids and which no owner decision authorises.

- **D3 — you cannot get a decision out of the gate without an audit line.** `classify` appends exactly one line to `docs/ai/decisions.jsonl` before it prints its verdict, for parks as well as auto-resolutions, and exits non-zero WITHOUT a verdict when the append fails. Recording is not a step a prompt can forget. The line reuses the existing ledger and the interrogate field set (`v`, `ts`, `actor`, `type`, `ref_id`, `question`, `answer`, `source`) with one new `type` value, `unattended_decision`, plus `trigger`, `class` and `decision`. No second ledger, no new file.

- **D4 — what bounds a night: a mandatory run budget, the unchanged existing guards, and a pull-request cap.** `max_ticks` stays 20 and `stagnation_limit` stays 3, and unattended may only LOWER them, never raise them. Unattended additionally REFUSES TO START without a declared run budget, because the default of unlimited is the one guard that is not actually armed today. `max_prs` (default 3, hard cap 5) bounds the chaining of D5 and therefore bounds the morning review. No wall-clock window: a session-resident loop can only check a deadline between ticks, which is what `max_ticks` already measures, and a token budget is the honest cost control. Rejected, recorded here so it is not re-proposed silently.

- **D5 — several pull requests means chaining rides, and a chained ride is one a human already wrote.** Under unattended, stop condition (c) does not exit; it asks `node .aai/scripts/ride-select.mjs next`, and adopts the proposed ride ONLY when its intake document already exists on disk and `ride-select.mjs gate` admits it. A proposal with no intake document on disk stops the run and says so. An unattended ride therefore never authors an intake document — creating one is a scope decision, and scope parks (D1). This answers RFC-0014's second open question in the direction the owner's original request pointed.

- **D6 — the morning surface is a rendered view of the existing ledger, not a new artifact.** `summary --since <ISO>` reads `docs/ai/decisions.jsonl` and prints the run's auto-resolutions and parks grouped by outcome; it writes nothing. The pull requests are named by the `gh pr list` command rather than re-derived into a local file, because GitHub already holds that list and a local copy would be the second ledger this scope is forbidden to invent. The richer rendered digest is already a reserved wave-2 roadmap capability (`cloud-morning-digest` in `docs/ai/roadmap.yaml`) and belongs to that ride.

- **D7 — unattended is a caller argument, never STATE.** `unattended=true`, `max_prs` and the budget are passed the way `checkpoint_mode` already is. Nothing is persisted, so a session that dies overnight resumes INTERACTIVE: the failure mode of losing the opt-in is more rigor, never less. This also keeps `.aai/scripts/state.mjs` — an L3 protected path — untouched.

- **D8 — D2 of the RFC is visible, not ambient.** The gate move is stated in `.aai/AGENTS.md`'s commit gating policy, in `.aai/SKILL_PR.prompt.md`'s preconditions, in the `/aai-ship` skill description carried into all four harness trees, in `docs/USER_GUIDE.md` and in `CHANGELOG.md`. A behaviour change to every ride that lives only inside one prompt file is ambient by construction.

## Constitution deviations

Article 5 (additive first). Moving the ship checkpoint from before the pull request to the merge is a BREAKING change at a public prompt boundary: `.aai/SKILL_SHIP.prompt.md` steps 5 to 7 change meaning for every ride, not only unattended ones, and `.aai/AGENTS.md`'s commit gating policy — vendored into every downstream project by `/aai-update` — changes with it. It is justified because the RFC's owner decision D2 makes it explicitly, the change is documented in five operator-visible surfaces (D8) and in `CHANGELOG.md`, and the consent it moves is not removed: Article 7 (operator-only merge) is untouched and is the surface the gate moves ONTO. Articles 1, 2, 3, 4, 6 and 7: no deviation.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN `node .aai/scripts/unattended-gate.mjs classify --trigger <t> --ref <ref> --question <q> --json` runs, the system SHALL exit 0 with `decision` `auto` for exactly `HITL-5`, `HITL-8`, `HITL-9`, and for `HITL-7` unless `--worktree-recommendation required` or `--ceremony 3` is passed; and SHALL exit 3 with `decision` `park` for `HITL-1`, `HITL-2`, `HITL-3`, `HITL-4`, `HITL-6`, `stagnation`, `run-budget`, `review-round-cap`, and for any absent, empty, unrecognised or malformed trigger; every result SHALL carry a `class` drawn from the closed set quality, scope, cost, irreversibility, guard, unknown, matching the D1 table row for row | done | TEST-001, TEST-002; aai-unattended PASS 2026-09-09T17:02:36Z | — | D1; the boundary is read from the mechanically stamped trigger token, never from a role's self-assessment |
| Spec-AC-02 | The system SHALL never emit `waived` as a resolution for any trigger, under any flag, argument or environment variable; `HITL-9` SHALL resolve to `fail` in every auto case; and `HITL-7` SHALL resolve to `inline` for `not_needed` and `optional` and to `worktree` for `recommended`, which are the same outcomes `.aai/SKILL_SHIP.prompt.md` autopilot default 2 already records and are members of `.aai/SKILL_HITL.prompt.md` STEP 4c's accepted enum for that trigger | done | TEST-003, TEST-004; aai-unattended PASS 2026-09-09T17:02:36Z | — | D2; the second clause is a seam assertion against two other files, not a restatement |
| Spec-AC-03 | Every `classify` invocation SHALL append exactly one line to `docs/ai/decisions.jsonl` (overridable with `--ledger <path>`) carrying `v`, `ts`, `actor` `unattended`, `type` `unattended_decision`, `ref_id`, `trigger`, `class`, `decision`, `question`, `answer` and `source`, BEFORE printing its verdict; every earlier byte of the ledger SHALL remain a byte-exact prefix; and WHEN the append cannot be performed the system SHALL exit non-zero and print NO verdict, so no autonomous decision can exist without its audit line | done | TEST-005, TEST-006, TEST-007; aai-unattended PASS 2026-09-09T17:02:36Z | — | D3; reuses the interrogate field set and the one ledger, adds one `type` value |
| Spec-AC-04 | WHEN `node .aai/scripts/unattended-gate.mjs preflight` runs, the system SHALL exit 3 naming the failing bound when both `--max-run-tokens` and `--max-run-cost-usd` are absent or zero, when `--max-ticks` exceeds 20, when `--stagnation-limit` exceeds 3, when `--max-prs` is below 1 or above 5, or when `--intake` is absent or names a path that does not exist; and SHALL otherwise exit 0 printing the effective bounds `max_ticks`, `stagnation_limit`, `max_run_tokens`, `max_run_cost_usd` and `max_prs` | done | TEST-008, TEST-009; aai-unattended PASS 2026-09-09T17:02:36Z | — | D4; unattended may lower a guard, never raise one |
| Spec-AC-05 | An unattended ride SHALL never author an intake document: `preflight` SHALL require `--intake` to name an existing file, `.aai/SKILL_SHIP.prompt.md`'s unattended branch SHALL refuse a free-text need and name the path form instead, and the chaining of Spec-AC-07 SHALL adopt a ride proposed by `ride-select.mjs next` ONLY when that ride's intake document exists on disk AND `ride-select.mjs gate` admits it, stopping the run with a named reason otherwise | done | TEST-010, TEST-011; aai-unattended PASS 2026-09-09T17:02:36Z | — | D5; answers RFC-0014 open question 2 |
| Spec-AC-06 | `.aai/SKILL_SHIP.prompt.md` SHALL open the pull request on validation PASS with the review gate satisfied without asking, and SHALL present the checkpoint AFTER the pull request exists, naming its URL and that merging stays operator-only; the literal strings `Ship? [y] open PR` and `never assume consent` SHALL be absent from that file; `.aai/SKILL_PR.prompt.md`'s precondition list and `.aai/AGENTS.md`'s commit gating policy SHALL name validation PASS plus the satisfied review gate as the authority to commit and push and SHALL place the human confirmation at the merge; and `docs/CONSTITUTION.md` Article 7 SHALL remain byte-identical | done | TEST-012, TEST-017; aai-unattended PASS + aai-golden-flow suite exit 0 2026-09-09T17:03:16Z | — | D2 of the RFC, applied to EVERY ride; the Article 7 clause is the proof the gate moved rather than vanished |
| Spec-AC-07 | `.aai/SKILL_LOOP.prompt.md` stop condition (b) SHALL keep its current exit path as the DEFAULT and take the unattended branch only when the caller passed `unattended=true`; on a `park` verdict it SHALL print the existing HITL block, whose `HITL OUTPUT FORMAT` section stays byte-identical, and EXIT; on an `auto` verdict it SHALL apply the resolution through the typed setter that `classify` returns in `target_command`, which SHALL equal the `.aai/SKILL_HITL.prompt.md` STEP 4c declared command for that trigger; and stop condition (c) under unattended SHALL chain per Spec-AC-05 until `max_prs` pull requests have been opened, then exit | done | TEST-013, TEST-014; aai-unattended PASS 2026-09-09T17:02:36Z | — | D1 and D5 wiring; `target_command` is the seam assertion against STEP 4c |
| Spec-AC-08 | WHEN `node .aai/scripts/unattended-gate.mjs summary --since <ISO8601> --ledger <path>` runs, the system SHALL print every `unattended_decision` line at or after `--since` grouped into auto-resolved and parked, each with `ref_id`, `trigger`, `class`, `question`, `answer` and `source`, SHALL name the `gh pr list` command for the pull requests rather than deriving them, and SHALL create no file and modify no file anywhere in the repository | done | TEST-015; aai-unattended PASS 2026-09-09T17:02:36Z | — | D6; answers RFC-0014 open question 3 without a second ledger |
| Spec-AC-09 | Companion obligations (closed list): `.aai/system/PROFILES.yaml` carries a classification entry for `.aai/scripts/unattended-gate.mjs`; `tests/skills/suite-map.yaml` carries an `aai-unattended` row naming the script and the prompts; `tests/skills/lib/prompt-diet-ledger.sh` carries one `JUSTIFIED_ADDITIONS` entry equal to the MEASURED byte growth of the in-glob prompt edits with a matching `TEST-012` checkpoint bump; and the `/aai-ship` description in `.claude/skills/aai-ship/SKILL.md`, its three synced harness copies, `SKILLS.md`, `docs/USER_GUIDE.md` and the regenerated `docs/SKILL_CATALOG.html` plus `docs/skill-catalog-data.json` no longer claim the checkpoint opens the pull request | done | TEST-016; aai-prompt-diet suite exit 0 2026-09-09T17:02:38Z; sync-harness-skills --check 0 | — | D8; both companion checks of `.aai/PLANNING.prompt.md` apply — new `.aai/**` file AND prompt-corpus growth |

## Seams

| Seam | Producer | Consumer | Test that crosses it |
|---|---|---|---|
| the shared decision ledger | `unattended-gate.mjs classify` appends a new `type` value | `follow-ups.mjs list --json` and `generate-factory-report.mjs` both read `docs/ai/decisions.jsonl` | TEST-007 runs both readers over a ledger seeded with `unattended_decision` lines and asserts their counts and exit codes are unchanged |
| the worktree enum, encoded in three places | `classify` HITL-7 resolution | `.aai/SKILL_HITL.prompt.md` STEP 4c normalisation table and `.aai/SKILL_SHIP.prompt.md` autopilot default 2 | TEST-004 asserts every value `classify` can emit is an accepted enum in STEP 4c and matches the default-2 mapping |
| the auto-resolution to the STATE write | `classify` `target_command` | the loop runs it as sole agent through `state.mjs` typed setters | TEST-014 asserts `target_command` is byte-equal to the STEP 4c declared command for each auto trigger, and empty for every park |
| the moved gate and the close ceremony | `SKILL_SHIP` opens the pull request with no prior confirmation | `SKILL_PR` branch hygiene, close ceremony, `nothing-left-behind.mjs` | TEST-017 runs `golden-flow.mjs` end to end and asserts exit 0 with all four gate counters zero |
| chaining and the roadmap gate | the unattended branch of stop condition (c) | `ride-select.mjs gate` and `next` | TEST-010 drives chaining in a fixture where `next` proposes a ride with no intake document and asserts the run stops with a named reason |

Residual risk, no automated test: an unattended night now opens pull requests whose CI nobody watches until morning (`fu-orchestrator-does-not-watch-ci`). The merge gate is where a human reads CI status, so a red pull request cannot merge itself; the cost is a wasted night, not a bad merge. Second residual: automation complacency — a morning stack of pull requests invites shallower review than a single question would have received. RFC-0014 names this as an accepted cost; no technical mitigation is proposed.

## Implementation plan

- **New** `.aai/scripts/unattended-gate.mjs` — Node stdlib only, three subcommands (`classify`, `preflight`, `summary`), the D1 table as a single frozen literal, exit codes 0 admit or auto, 3 refuse or park, 2 usage. Fail-closed on every unknown input.
- **Edit** `.aai/SKILL_SHIP.prompt.md` — steps 5 to 7 reorder (open the pull request, then the merge checkpoint); an unattended opt-in that calls `preflight` first and refuses a free-text need.
- **Edit** `.aai/SKILL_LOOP.prompt.md` — stop condition (b) gains the unattended branch with the exit path as default; stop condition (c) gains the chaining branch; loop parameters gain `unattended` and `max_prs`.
- **Edit** `.aai/SKILL_PR.prompt.md` precondition list and `.aai/AGENTS.md` commit gating policy — the authority to commit and push becomes validation PASS plus the satisfied review gate; the human confirmation moves to the merge.
- **Edit** `.aai/system/PROFILES.yaml`, `tests/skills/suite-map.yaml`, `tests/skills/lib/prompt-diet-ledger.sh`, `tests/skills/test-aai-prompt-diet.sh` (TEST-012 pin).
- **Edit** `.claude/skills/aai-ship/SKILL.md`, then `node .aai/scripts/sync-harness-skills.mjs --write`, then `node .aai/scripts/generate-docs-hub.mjs`; `SKILLS.md`; `docs/USER_GUIDE.md`; `CHANGELOG.md` (`## [unreleased] — <title>` heading, per the release rollup's required shape).
- **New** `tests/skills/test-aai-unattended.sh` (bash 3.2, run through `bash .aai/scripts/aai-run-tests.sh`).
- Edge cases: an unattended run whose session dies loses the opt-in and resumes interactive (D7, fail-safe); a `classify` call with a ledger path inside a read-only directory exits non-zero with no verdict (D3); `ride-select.mjs next` returning nothing ends the run cleanly with the summary; `--max-prs` reached mid-ride finishes the ride in flight and then stops rather than abandoning it.
- Out of scope and named: the rendered morning digest (`cloud-morning-digest`, roadmap wave 2); watching CI after a pull request opens; a PowerShell mirror of the new script (no `.ps1` mirror exists for `ride-select.mjs` or `hitl-channel.mjs` either — consistency, recorded as a residual).

## Test Plan

| Test ID  | Spec-AC | Type | File path (expected) | Description | Status |
|----------|---------|------|----------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-unattended.sh | all thirteen D1 rows driven through `classify`, asserting `decision` and exit code per row | green |
| TEST-002 | Spec-AC-01 | integration | tests/skills/test-aai-unattended.sh | absent, empty, lowercase, whitespace and invented triggers all park with `class` `unknown` and exit 3 | green |
| TEST-003 | Spec-AC-02 | integration | tests/skills/test-aai-unattended.sh | `HITL-9` resolves `fail` across a flag and environment fuzz; the literal `waived` is unreachable in every output | green |
| TEST-004 | Spec-AC-02 | integration | tests/skills/test-aai-unattended.sh | seam: every HITL-7 value `classify` emits is an accepted enum in SKILL_HITL STEP 4c and matches SKILL_SHIP default 2 | green |
| TEST-005 | Spec-AC-03 | integration | tests/skills/test-aai-unattended.sh | one ledger line per call with the full field set; the pre-call bytes stay a byte-exact prefix | green |
| TEST-006 | Spec-AC-03 | integration | tests/skills/test-aai-unattended.sh | an unwritable ledger makes `classify` exit non-zero and print no verdict | green |
| TEST-007 | Spec-AC-03 | integration | tests/skills/test-aai-unattended.sh | seam: `follow-ups.mjs list --json` and `generate-factory-report.mjs` over a ledger carrying `unattended_decision` lines return unchanged counts and exit codes | green |
| TEST-008 | Spec-AC-04 | integration | tests/skills/test-aai-unattended.sh | five `preflight` refusal arms, each turning exit 0 into exit 3 alone, each naming its bound | green |
| TEST-009 | Spec-AC-04 | integration | tests/skills/test-aai-unattended.sh | `preflight` admit path prints all five effective bounds and exits 0 | green |
| TEST-010 | Spec-AC-05 | integration | tests/skills/test-aai-unattended.sh | seam: chaining adopts a ride only when its intake exists and the gate admits; a doc-less proposal stops the run with a named reason | green |
| TEST-011 | Spec-AC-05 | unit | tests/skills/test-aai-unattended.sh | SKILL_SHIP's unattended branch names the intake-path form and refuses a free-text need | green |
| TEST-012 | Spec-AC-06 | unit | tests/skills/test-aai-unattended.sh | the two forbidden literals are absent from SKILL_SHIP, the merge checkpoint text is present, SKILL_PR and AGENTS carry the moved authority, CONSTITUTION Article 7 is byte-identical | green |
| TEST-013 | Spec-AC-07 | unit | tests/skills/test-aai-unattended.sh | SKILL_LOOP keeps the default exit path, gains the unattended branch, and its HITL OUTPUT FORMAT block is byte-identical to the base commit | green |
| TEST-014 | Spec-AC-07 | integration | tests/skills/test-aai-unattended.sh | seam: `target_command` is byte-equal to the STEP 4c declared command for each auto trigger and empty for every park | green |
| TEST-015 | Spec-AC-08 | integration | tests/skills/test-aai-unattended.sh | `summary` groups auto and parked from a fixture ledger, names `gh pr list`, and a before-and-after tree hash proves no file was created or modified | green |
| TEST-016 | Spec-AC-09 | integration | tests/skills/test-aai-prompt-diet.sh | the suite's own TEST-012 pin equals the ledger re-sum after the bump, and TEST-010 headroom stays inside the cap | green |
| TEST-017 | Spec-AC-06 | integration | tests/skills/test-aai-golden-flow.sh | seam: the deterministic golden flow still exits 0 with all four gate counters zero after the gate move | green |

Every Spec-AC has at least one TEST row. TEST-016 targets the prompt-diet suite's own arm named TEST-012; the two numbering schemes are unrelated.

## Verification

- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-unattended.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-golden-flow.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-layer-profiles.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-hygiene-pack.sh`
- `node .aai/scripts/sync-harness-skills.mjs --check` exits 0
- `node .aai/scripts/docs-audit.mjs --check --strict` CLEAN
- one full sweep `AAI_TEST_TIMEOUT=3000 bash tests/skills/test-framework.sh` before the close ceremony
- PASS criteria: every TEST row green AND every Spec-AC in a terminal status with non-empty Evidence.

## Evidence contract

Strategy `tdd`, so each AC-gating test owes a STORED RED artifact under `docs/ai/tdd/` observed failing on the pre-change tree, plus the green run, plus the full verification matrix above. Record per artifact: `ref_id`, Spec-AC and TEST links, the command, the exit code, the evidence path, and the commit SHA or diff range.

RED observations planned, and where each is recorded:
- TEST-001 to TEST-015 fail with "no such file" against `.aai/scripts/unattended-gate.mjs` before the engine exists — that is absence, not a bite. The bite each row owes is recorded separately: after the engine exists, each row is re-observed RED against a deliberately wrong table entry, a suppressed ledger append, a raised guard bound, or the pre-change prompt text, and the log is stored as `docs/ai/tdd/red-TEST-0NN-<stamp>.log`.
- TEST-016 is observed RED by leaving the `TEST-012` pin unbumped after the prompt edit.
- TEST-017 is observed RED by pointing the golden flow at the pre-change `SKILL_SHIP`.

## Implementation strategy
- Strategy: tdd
- Rationale: recorded by the user in the RFC's `## Notes` (`Implementation mode (user choice): tdd`) — behavioural, multi-surface, and it touches both a deliberate human gate and autonomous decision-making on the owner's behalf, where a regression is expensive and hard to see. Planning keeps the user's choice.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: the dispatch mandates the MAIN checkout deliberately. `generate-overview.mjs` derives project identity from `path.basename(process.cwd())`, so a feature worktree bakes the worktree's name into committed overview artifacts (`fu-overview-pages-bake-worktree-name`, open). The main checkout's directory is named `aai`, which sidesteps the defect. Ceremony level 3 still requires an explicit recorded `user_decision`; Implementation Preparation records `inline`.
- User decision: undecided
- Base ref: main
- Worktree branch/path: branch `feat/unattended-rides-human-gate-at-merge` in the main checkout
- Inline review scope: `.aai/scripts/unattended-gate.mjs`, `.aai/SKILL_SHIP.prompt.md`, `.aai/SKILL_LOOP.prompt.md`, `.aai/SKILL_PR.prompt.md`, `.aai/AGENTS.md`, `.aai/system/PROFILES.yaml`, `tests/skills/test-aai-unattended.sh`, `tests/skills/suite-map.yaml`, `tests/skills/lib/prompt-diet-ledger.sh`, `tests/skills/test-aai-prompt-diet.sh`, `.claude/skills/aai-ship/SKILL.md`, `SKILLS.md`, `docs/USER_GUIDE.md`, `CHANGELOG.md`, `docs/specs/SPEC-0174-spec-unattended-rides-human-gate-at-merge.md`

Ceremony level 3 rationale: the scope moves the factory's consent gate for EVERY ride and grants an agent autonomous decision-making on the owner's behalf. No `protected_paths_l3` entry is touched (the state engine, the allocator, the guards and the workflow canon are all deliberately out of scope, per D7), so level 3 is declared UPWARD by judgement, not forced. It buys mandatory review on the most capable tier and an operator checkpoint before merge — which is exactly the gate D2 creates, so the two are self-consistent.
