---
id: spec-codex-usage-missing-from-run-budgets
type: spec
number: 258
status: done
mutation_gate: v1
frozen_sha256: af8a48a8fbe57915c735d5bcee995b60424d31a4799fbbdeaffe0fc9dd873145
ceremony_level: 2
links:
  requirement: codex-usage-missing-from-run-budgets
  rfc: null
  pr: []
  commits: []
---

# Codex usage reaches run accounting and the run-budget gate

SPEC-FROZEN: true

## Links

- Intake: docs/issues/ISSUE-0106-codex-usage-missing-from-run-budgets.md
- Technology contract: docs/TECHNOLOGY.md
- Existing parser (reused for the CODEX_HOME root only): .aai/scripts/live-parsers/codex.mjs
- Existing consumers: .aai/scripts/state.mjs (append-run, log-tick), .aai/scripts/metrics-flush.mjs, .aai/scripts/unattended-gate.mjs, .aai/SKILL_LOOP.prompt.md step 2f, .aai/SUBAGENT_PROTOCOL.md "Harness-reported usage capture"

## Implementation strategy

- Strategy: hybrid
- Rationale: TDD (stored RED per AC-gating test) for the rollout reader, interval and cumulative arithmetic, identity binding, attribution and the budget verdict, because every one of those is a numeric claim that a wrong boundary silently inflates or zeroes. Direct implementation plus pinned greps for the prose wiring in SKILL_LOOP and SUBAGENT_PROTOCOL, the PROFILES and suite-map rows and the prompt-diet ledger true-up.

## Isolation and review

- Worktree recommendation: not_needed (recorded owner decision)
- Worktree rationale: the owner directed this ride inline in the main checkout on `main` so another agent can resume from the same tree. Planning would otherwise have said `recommended` (two new core scripts plus prompt edits). Planning does not re-open a recorded owner choice.
- User decision: inline
- Base ref: main at f8614f67
- Inline review scope: `.aai/scripts/lib/codex-rollout.mjs`, `.aai/scripts/codex-usage.mjs`, `.aai/scripts/live-parsers/codex.mjs`, `.aai/SKILL_LOOP.prompt.md`, `.aai/SUBAGENT_PROTOCOL.md`, `.aai/system/PROFILES.yaml`, `tests/skills/test-aai-codex-usage.sh`, `tests/skills/suite-map.yaml`, `tests/skills/lib/prompt-diet-ledger.sh`, `tests/skills/test-aai-prompt-diet.sh` (TEST-012 pin only), this spec, the intake, CHANGELOG.md, append-only evidence under docs/ai/tdd/.

## Decisions and boundaries

D1. Source of truth is the local Codex rollout log, read-only. Two event kinds are read, in this priority order per thread:
1. `token_usage_record` lines (payload `thread_id`, `session_id`, `turn_id`, `response_id`, `usage`). These are per-response, not cumulative, and carry a dedupe key. This is the primary basis (`basis: response_records`).
2. `event_msg` lines with `payload.type: token_count` (`info.total_token_usage`, cumulative per thread). Used only when the thread's file holds no `token_usage_record` line at all (older CLI versions). This basis is `cumulative_snapshot`.
Measured on this machine (metadata only, 2026-10-28): CLI 0.163 to 0.165 writes both kinds; on one thread with one compaction the final cumulative `total_token_usage.total_tokens` was 247,960 tokens (2.9 percent) below the sum of that thread's response records, which equals the last record's `thread_token_usage.total_tokens`. The cumulative basis can therefore undercount, and is labelled degraded when a compaction lies in the window (D4).

D2. Component semantics, measured: Codex `total_tokens` equals `input_tokens + output_tokens`; `cached_input_tokens` is a subset of input and `reasoning_output_tokens` a subset of output. The observation reports `input_tokens`, `output_tokens`, `total_tokens` exactly as summed from the source, and reports the two subsets only as `cached_input_tokens_subset` and `reasoning_output_tokens_subset`. They are never added to a total, never passed as `--cache-read` (whose Claude meaning is disjoint from input), and a record whose `total_tokens` differs from its own input plus output marks the observation degraded with reason `inconsistent_total` while keeping the observed values.

D3. Interval. An observation covers the half-open window [from, to) on the line's top-level `timestamp`. File order is irrelevant: a record written late but stamped inside the window counts, a record stamped at or after `to` does not, wherever it sits in the file. `to` defaults to the current clock. Re-running the same observation later returns the same numbers for a closed window (deterministic, no state kept between runs).

D4. Cumulative basis arithmetic (fallback only): delta = the last cumulative snapshot stamped before `to` minus the last snapshot stamped before `from` (zero when none precedes `from`). `info: null` events are skipped; an identical repeated snapshot contributes nothing. A snapshot whose `total_tokens` is lower than its predecessor is a counter reset: the delta becomes the sum of the per-segment deltas, the observation is degraded with reason `counter_reset`, and no component is ever negative. A `compacted` line or a `response_item` of type `compaction` stamped inside the window adds degraded reason `cumulative_may_omit_compaction`.

D5. Missing is not zero. A counted record without a numeric value for a component makes that component `null` (not 0) and adds degraded reason `missing_field:<name>`; `total_tokens` is then taken from the records only if every counted record has it, else `null`. A malformed line other than the last one adds `malformed_line`. A truncated last line (a write in progress) is skipped and reported as `partial_tail: true` without degrading. Status `unavailable` (exit 4, `usage: null`) for: CODEX_HOME rollout directories absent or unreadable (`source_unreadable`), no thread id given or resolvable (`thread_identity_unresolved`), thread id found in no rollout file (`thread_not_found`), or the target thread has no usage event of either kind (`no_usage_events`).

D6. Identity. Thread lookup is by thread id across `<CODEX_HOME>/sessions/**/*.jsonl` and `<CODEX_HOME>/archived_sessions/*.jsonl` (CODEX_HOME defaults to `~/.codex`), never by cwd and never by date directory. Measured: the incident's parent thread and its role subagents live in `archived_sessions/`, which the live-status parser does not scan; matching by cwd or by date would have missed them. A file's own identity is its FIRST `session_meta` line (`id`, `session_id`, `parent_thread_id`, `timestamp`, `cwd`, `source`); a later `session_meta` in the same file is forked history (measured: a child file carries its parent's meta as its second meta line) and never rebinds. A record is counted for a thread only when its `thread_id` equals that thread's own id. A response id is counted once across all files, so a thread present in both directories is never double counted. The thread id is taken from `--thread <id>`; `--thread auto` reads the environment variable `CODEX_THREAD_ID` and degrades to `thread_identity_unresolved` when it is absent. Whether the Codex host exports that variable was NOT verified by Planning; the opt-in smoke (Spec-AC-12) records it.

D7. Descendants and no double counting. `--descendants` adds every thread whose first-meta `parent_thread_id` chain reaches the target, within the same root `session_id`, each thread once. Each thread contributes only its own records, so a parent total with descendants equals the sum of the threads observed alone. Guardian (approval-review) subagents are descendants like any other and count toward the run.

D8. Role attribution, closed rule (`attribute` subcommand). Given the orchestrator thread P and a role window [A, B): if exactly one direct child of P has a first-meta timestamp inside [A, B), the role's usage is that child plus its descendants, attribution `thread`. Otherwise (zero or two or more such children, or the role ran inline in P) the usage is P plus all descendants inside [A, B), attribution `interval`, which by construction also contains orchestration work in that window. A session total is never split across roles. The orchestrator's own usage outside role windows is covered by the run budget (D10) and the per-tick record (D9), not by a per-role run.

D9. Wiring without new STATE fields. `state.mjs` and `metrics-flush.mjs` are NOT edited (state.mjs is an L3 protected path; this scope stays at ceremony level 2). `observe` and `attribute` print the exact argument lists for the existing commands:
- `append_run_flags`: `--harness codex --tokens-in <input> --tokens-out <output> --tokens-total <total> --note "<provenance>"`, where provenance is the space-separated tokens `usage_total_tokens=<total>`, `usage_source=codex_rollout`, `codex_thread=<id>`, `usage_interval=<from>/<to>`, `usage_attribution=<thread or interval or run>`, `usage_basis_detail=<response_records or cumulative_snapshot or mixed>`, plus `usage_degraded=<reason,...>` when degraded. A null component omits only its own flag.
- On `unavailable`: no token flags; the note is `usage_capture=none usage_source=codex_rollout usage_unavailable=<reason>` (the existing honest-gap sentinel from lib/usage-note.mjs).
- `log_tick_flags`: `--tokens-in <input> --tokens-out <output>` only. Never `--cache-read`, never `--cost`.
The note survives the flush (metrics-flush copies `note` into METRICS), so source, identity, window and attribution persist without a schema change.

D10. Budget decision (`budget` subcommand): `budget --thread <root> --since <run start ISO> --max-run-tokens <N>` observes the root thread plus all descendants over [since, now) and prints one JSON verdict with `enforcement` (`active`, `degraded` or `unavailable`), `cumulative_total_tokens`, `limit`, `verdict` (`within`, `exhausted` or `unknown`). Exit 0 within, 3 exhausted (cumulative at or above the limit), 4 unavailable, 2 usage error (including N not a positive integer). On unavailable the human line reads `RUN BUDGET: token budget NOT enforced (<reason>)` and never the word `within`. Degraded still decides on the observed numbers and names its reasons. Post-freeze amendment (PR #512 review, disclosed, owner sign-off not obtained): with `--descendants`, a descendant thread in the tree that has no usage events makes the observation `unavailable` with reason `descendant_unavailable` (fields `descendant`, `descendant_reason`, `lower_bound_total_tokens` = the readable threads total), because missing is not zero (D5). `budget` then exits 4 NOT enforced, except when the lower bound alone is at or above N: exit 3 `exhausted`, enforcement `degraded`. D5 four reasons are the target thread own; `invalid_interval` and `total_tokens_missing` are likewise disclosed here. The root thread with no usage events is still tolerated as before. The Codex observation is the single source for a Codex run's budget: tick-line usage is not added on top (it would double count the same responses).

D11. Fallback policy when enforcement is unavailable (SKILL_LOOP step 2f): attended loop, print the NOT enforced line every tick and continue, bounded only by `max_ticks` and the stagnation guard; unattended ride (`unattended` set), stop with the existing `run-budget` trigger (unattended-gate class cost, park), because an unattended ride may only start with an armed budget and an unreadable source means the budget is not armed. Claude and other harnesses keep today's step 2f tally unchanged.

D12. Privacy. The reader parses only lines whose `type` is `session_meta`, `token_usage_record`, `event_msg` (token_count only), `compacted` or `response_item` (only to detect `payload.type === 'compaction'`). From `session_meta` it keeps only `id`, `session_id`, `parent_thread_id`, `timestamp`, `cwd`, `source`. No output contains message text, instructions, tool payloads or the raw line. Nothing is written by any subcommand; no log content is copied into the repository.

D13. Capability discovery (`probe`): reports `rollout_logs` (`available` with the directories found, or `unavailable` with the reason), `thread_identity` (`resolved` or `unresolved`, with its source `flag` or `env`), and `app_server_token_events: not_integrated`. The App Server `thread/tokenUsage/updated` notification is documented upstream but not consumed by this scope, and the probe must never report it as available.

D14. Reuse. `live-parsers/codex.mjs` keeps its behavior; its `roots()` resolves the CODEX_HOME base through the new lib's exported `codexHome(env)` so both readers agree on where Codex lives. Its other known gaps (later-meta rebinding, no `archived_sessions/` scan) are out of scope and become a suggested follow-up.

D15. Out of scope: the App Server event integration, metrics-flush cost semantics for subscription accounts (flush keeps today's list-price estimate labelled by `cost_basis`; this adapter never passes a cost), quota percentages (`rate_limits` are not read), model routing, a review-round cap redesign, and the release executor.

## Acceptance Criteria Mapping

- Intake Expected 1 (authoritative capture, no estimation): Spec-AC-01, Spec-AC-02, Spec-AC-10.
- Intake Expected 2 (identity, parent-child, cwd changes, no double counting): Spec-AC-04, Spec-AC-05.
- Intake Expected 3 (persist through run and tick accounting with provenance): Spec-AC-06.
- Intake Expected 4 (cumulative, duplicates, resets, compaction, delayed, partial; subsets): Spec-AC-01, Spec-AC-02, Spec-AC-03.
- Intake Expected 5 (budget gate during the run; explicit unavailable state): Spec-AC-07, Spec-AC-08.
- Intake Expected 6 (preserve Claude capture; tokens, cost and quota distinct): Spec-AC-06, Spec-AC-11.
- Intake Verification smoke: Spec-AC-12.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN `codex-usage.mjs observe --thread <id> --from A --to B --json` runs over a fixture thread with token_usage_record lines the system SHALL report input, output and total equal to the sum of the thread's own records stamped in the half-open window A to B, counting each response_id once across all files (a conflicting duplicate degrades with `conflicting_duplicate`), counting a late-written in-window record and excluding an earlier-written record stamped at or after B, and SHALL report cached and reasoning tokens only as the two `_subset` fields with total equal to input plus output | done | docs/ai/reports/validation-codex-usage-r3/full-sweep.log + docs/ai/reports/validation-codex-usage-r3/mutation-and-gates.log | — | D1 D2 D3 |
| Spec-AC-02 | WHEN the thread has token_count events and no token_usage_record the system SHALL report basis cumulative_snapshot with delta equal to the last snapshot before B minus the last snapshot before A, skip `info: null`, add nothing for repeated identical snapshots, sum segments with degraded reason `counter_reset` on a decrease, add `cumulative_may_omit_compaction` for a compaction in the window, and never emit a negative component | done | docs/ai/reports/validation-codex-usage-r3/full-sweep.log + docs/ai/reports/validation-codex-usage-r3/mutation-and-gates.log | — | D4 |
| Spec-AC-03 | WHEN a counted record lacks a numeric component the system SHALL report that component as null with degraded reason `missing_field:<name>` and never 0; a truncated last line SHALL be skipped with `partial_tail: true`; a malformed middle line SHALL add `malformed_line`; and an unreadable CODEX_HOME, an unresolved thread id, an unknown thread or a thread without usage events SHALL each exit 4 with status unavailable, usage null and the named reason | done | docs/ai/reports/validation-codex-usage-r3/full-sweep.log + docs/ai/reports/validation-codex-usage-r3/mutation-and-gates.log | — | D5 |
| Spec-AC-04 | WHEN the target thread's rollout sits in `archived_sessions/` and its cwd differs from the child's cwd the system SHALL still find and bind it by thread id; a file's second session_meta SHALL NOT rebind its identity; a record whose thread_id is another thread SHALL NOT be counted | done | docs/ai/reports/validation-codex-usage-r3/full-sweep.log + docs/ai/reports/validation-codex-usage-r3/mutation-and-gates.log | — | D6 |
| Spec-AC-05 | WHEN `--descendants` is given for a parent with a thread_spawn child and a guardian grandchild the reported total SHALL equal the sum of the three threads observed alone, with the child counted once even when its file exists under both `sessions/` and `archived_sessions/` | done | docs/ai/reports/validation-codex-usage-r3/full-sweep.log + docs/ai/reports/validation-codex-usage-r3/mutation-and-gates.log | — | D7 |
| Spec-AC-06 | WHEN the `append_run_flags` printed by observe are passed verbatim to the real `state.mjs append-run` on a scratch STATE and flushed by the real `metrics-flush.mjs` the STATE run SHALL carry usage_basis field before the flush (metrics-flush does not project it) and the METRICS run SHALL carry tokens_in, tokens_out and tokens_total equal to the observation, harness codex and a note holding `usage_total_tokens=<total>`, `usage_source=codex_rollout`, `codex_thread=<id>`, `usage_interval=<A>/<B>` and `usage_attribution=<a>`; for an unavailable observation the note SHALL hold `usage_capture=none` and no token field SHALL be set; WHEN the printed `log_tick_flags` are passed to the real `state.mjs log-tick` the tick line SHALL carry input_tokens and output_tokens equal to the observation and no cache_read_tokens or est_cost_usd key | done | docs/ai/reports/validation-codex-usage-r3/full-sweep.log + docs/ai/reports/validation-codex-usage-r3/mutation-and-gates.log | — | D9 seam |
| Spec-AC-07 | WHEN `codex-usage.mjs budget --thread R --since S --max-run-tokens N` runs over fixtures the system SHALL exit 3 with verdict exhausted when the root plus descendants total since S is at or above N, exit 0 with verdict within below N, exit 2 for a non-positive N, and exit 4 with enforcement unavailable, verdict unknown and a stdout line containing `NOT enforced` and not `within` when the source is unreadable; the exhausted path fed to the real `unattended-gate.mjs classify --trigger run-budget` SHALL park | done | docs/ai/reports/validation-codex-usage-r3/full-sweep.log + docs/ai/reports/validation-codex-usage-r3/mutation-and-gates.log | — | D10 D11 seam |
| Spec-AC-08 | WHEN `codex-usage.mjs attribute --parent P --from A --to B` runs the system SHALL return attribution thread with exactly the one direct child spawned in the window plus its descendants, and attribution interval over P plus descendants in the window when zero or two such children exist | done | docs/ai/reports/validation-codex-usage-r3/full-sweep.log + docs/ai/reports/validation-codex-usage-r3/mutation-and-gates.log | — | D8 |
| Spec-AC-09 | WHEN observe, attribute, budget or probe run over a fixture whose message, base_instructions and tool payload lines carry a sentinel string the combined stdout and stderr SHALL NOT contain the sentinel, the fixture tree and the repository status SHALL be unchanged, and the commands SHALL read the fixture through CODEX_HOME with HOME pointed at an empty directory | done | docs/ai/reports/validation-codex-usage-r3/full-sweep.log + docs/ai/reports/validation-codex-usage-r3/mutation-and-gates.log | — | D12 |
| Spec-AC-10 | `codex-usage.mjs probe --json` SHALL report rollout_logs available or unavailable with a reason, thread_identity resolved or unresolved with its source, and app_server_token_events not_integrated in every case | done | docs/ai/reports/validation-codex-usage-r3/full-sweep.log + docs/ai/reports/validation-codex-usage-r3/mutation-and-gates.log | — | D13 |
| Spec-AC-11 | SKILL_LOOP step 2f SHALL name `codex-usage.mjs budget`, its exit 3 and exit 4 branches and the D11 attended and unattended fallback; SUBAGENT_PROTOCOL "Harness-reported usage capture" SHALL carry a Codex bullet naming observe, attribute, the D8 rule, no `--cache-read` and no cost; PROFILES core SHALL list both new files; suite-map SHALL map them to aai-codex-usage; live-parsers/codex.mjs SHALL import `codexHome`; the prompt-diet ledger entry and TEST-012 pin SHALL match the measured growth; and test-aai-token-capture.sh, test-aai-state.sh, test-aai-metrics.sh, test-aai-live-status.sh, test-aai-prompt-diet.sh, test-aai-layer-profiles.sh and test-aai-hygiene-pack.sh SHALL exit 0 with state.mjs, metrics-flush.mjs and lib/usage-note.mjs unchanged against the base | done | docs/ai/reports/validation-codex-usage-r3/full-sweep.log + docs/ai/reports/validation-codex-usage-r4/suites.log | — | D9 D14 regression |
| Spec-AC-12 | WHEN `AAI_CODEX_SMOKE=1` and the real CODEX_HOME is readable the opt-in suite arm SHALL pick the newest real thread with at least one token_usage_record, run observe over that thread's whole lifetime and find total_tokens equal to that thread's last record `thread_token_usage.total_tokens` computed independently, and SHALL write a metadata-only report (ids, timestamps, numbers, probe result including whether CODEX_THREAD_ID is set) under docs/ai/reports/ | done | docs/ai/reports/validation-codex-usage-r3/smoke.log | — | intake smoke |

## Implementation plan

Components:
- `.aai/scripts/lib/codex-rollout.mjs` (new, core, Node stdlib only, at most 420 lines): `codexHome(env)`, rollout discovery over `sessions/` and `archived_sessions/`, a streaming line reader applying the D12 filter, first-meta identity, the D1 to D7 arithmetic, `observe()`, `attribute()`, `budget()` returning plain objects.
- `.aai/scripts/codex-usage.mjs` (new, core, at most 260 lines): subcommands `observe`, `attribute`, `budget`, `probe`; `--json` or one human line; exit codes 0, 2, 3, 4 per D5 and D10; builds `append_run_flags` and `log_tick_flags` per D9.
- `.aai/scripts/live-parsers/codex.mjs`: `roots()` uses `codexHome(env)`; nothing else changes.
- `.aai/SKILL_LOOP.prompt.md` step 2f: one added paragraph for the Codex path (D10, D11), at most 700 bytes. Step 4/6 capture prose is not duplicated; it points at SUBAGENT_PROTOCOL.
- `.aai/SUBAGENT_PROTOCOL.md` "Harness-reported usage capture": one Codex bullet (D8, D9). Not in the prompt-diet glob.
- `.aai/system/PROFILES.yaml`: both new files under `core:` (SKILL_LOOP, a core prompt, invokes them).
- `tests/skills/suite-map.yaml`: new row `aai-codex-usage` with the two new files and `.aai/scripts/live-parsers/codex.mjs`.
- `tests/skills/lib/prompt-diet-ledger.sh` and the TEST-012 pin in `tests/skills/test-aai-prompt-diet.sh`: one JUSTIFIED_ADDITIONS entry at the measured SKILL_LOOP growth.
- `tests/skills/test-aai-codex-usage.sh` (new): builds every fixture in a mktemp CODEX_HOME at run time; no committed log fixtures.

Data flow: rollout files, then lib reader, then observation object, then CLI JSON with flag lists, then the orchestrator passes the lists to `state.mjs append-run` and `log-tick` unchanged, and the flush carries the note into METRICS. Budget: SKILL_LOOP step 2f calls `codex-usage.mjs budget` before the next dispatch; exit 3 parks through the existing run-budget stop.

Seams crossed (each has a test that produces on one side and asserts on the other):
- S1 observe output into real append-run and real metrics-flush (TEST-3111).
- S2 observe output into real log-tick (TEST-3112).
- S3 budget exit 3 into real unattended-gate classify run-budget (TEST-3114).
- S4 CODEX_HOME resolution shared with the live-status parser (TEST-3119 plus test-aai-live-status.sh).
- S5 Claude capture path untouched (TEST-3120).
Residual seam no automated test crosses: whether a real Codex orchestrator actually runs step 2f and passes the printed flags. That is prompt compliance, observed only in a real Codex ride; the opt-in smoke proves the source and arithmetic, not the agent's obedience.

Edge cases covered by fixtures: duplicate response ids (same and conflicting usage), a thread file in both directories, out-of-order lines, a record stamped exactly at A and exactly at B, `info: null`, identical snapshots, a counter decrease, a compaction inside and outside the window, a missing `output_tokens`, a truncated last line, a malformed middle line, a second forked session_meta, a foreign thread_id record, a parent and child with different cwd, a guardian grandchild, a thread with no usage events.

### Mutation anchors

The Test Plan mutation cells name these code forms; Implementation writes them as named. A cell whose form the code cannot keep is re-anchored with a `spec-amend` restamp that keeps the same comparison disabled.

- `lib/codex-rollout.mjs`: `const inWindow = ts >= fromMs && ts < toMs;`, `if (seenResponses.has(rec.response_id)) continue;`, `usage.input_tokens = input;`, `usage.total_tokens = total;`, `if (cur.total_tokens < prev.total_tokens) {`, `reasons.push('cumulative_may_omit_compaction');`, `if (!Number.isFinite(n)) return null;`, `return unavailable('thread_not_found');`, `if (ownMeta === null) ownMeta = obj.payload;`, `if (rec.thread_id !== ownId) continue;`, `const ROLLOUT_DIRS = ['sessions', 'archived_sessions'];`, `queue.push(child);`, `const binding = spawned.length === 1 ? 'thread' : 'interval';`, `const META_KEYS = ['id', 'session_id', 'parent_thread_id', 'timestamp', 'cwd', 'source'];`.
- `codex-usage.mjs`: `flags.push('--tokens-total', String(usage.total_tokens));`, `const LOG_TICK_KEYS = ['--tokens-in', '--tokens-out'];`, `const exhausted = cumulative >= limit;`, the literal `token budget NOT enforced`, `app_server_token_events: 'not_integrated'`.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3101 | Spec-AC-01 | unit | tests/skills/test-aai-codex-usage.sh | test_3101_record_window_sums: records at A, inside, late-written inside, and earlier-written at B; observe sums exactly the in-window records of the own thread | `sed:s/const inWindow = ts >= fromMs && ts < toMs;/const inWindow = ts >= fromMs && ts <= toMs;/` on .aai/scripts/lib/codex-rollout.mjs | green |
| TEST-3102 | Spec-AC-01 | unit | tests/skills/test-aai-codex-usage.sh | test_3102_response_id_dedupe: one response id repeated in the file and in a copy under archived_sessions counts once; a repeat with different usage adds degraded conflicting_duplicate | `sed:s/if \(seenResponses.has\(rec.response_id\)\) continue;/void 0;/` on .aai/scripts/lib/codex-rollout.mjs | green |
| TEST-3103 | Spec-AC-01 | unit | tests/skills/test-aai-codex-usage.sh | test_3103_subset_semantics: with cached and reasoning tokens present, input, output and total equal the source sums, the two subsets appear only as _subset fields, total equals input plus output; a record whose total differs adds inconsistent_total | `sed:s/usage.input_tokens = input;/usage.input_tokens = input + cached;/` on .aai/scripts/lib/codex-rollout.mjs | green |
| TEST-3104 | Spec-AC-02 | unit | tests/skills/test-aai-codex-usage.sh | test_3104_cumulative_delta_and_reset: token_count only; baseline before A, info null, identical repeats and a decrease give the segment sum with counter_reset and no negative component | `sed:s/if \(cur.total_tokens < prev.total_tokens\) {/if (false) {/` on .aai/scripts/lib/codex-rollout.mjs | green |
| TEST-3105 | Spec-AC-02 | unit | tests/skills/test-aai-codex-usage.sh | test_3105_cumulative_compaction_flag: a compaction inside the window adds cumulative_may_omit_compaction; one outside the window does not | `sed:s/reasons.push\('cumulative_may_omit_compaction'\);/void 0;/` on .aai/scripts/lib/codex-rollout.mjs | green |
| TEST-3106 | Spec-AC-03 | unit | tests/skills/test-aai-codex-usage.sh | test_3106_missing_partial_malformed: a record without output_tokens gives output null and missing_field:output_tokens; a truncated last line gives partial_tail true and status ok; a malformed middle line adds malformed_line | `sed:s/if \(!Number.isFinite\(n\)\) return null;/if (!Number.isFinite(n)) return 0;/` on .aai/scripts/lib/codex-rollout.mjs | green |
| TEST-3107 | Spec-AC-03 | integration | tests/skills/test-aai-codex-usage.sh | test_3107_unavailable_reasons: unreadable CODEX_HOME, --thread auto without CODEX_THREAD_ID, unknown id, and a thread with no usage events each exit 4 with usage null and the named reason | `sed:s/return unavailable\('thread_not_found'\);/return { status: 'ok', usage: { total_tokens: 0 } };/` on .aai/scripts/lib/codex-rollout.mjs | green |
| TEST-3108 | Spec-AC-04 | unit | tests/skills/test-aai-codex-usage.sh | test_3108_first_meta_identity: a child file whose second session_meta is the parent's keeps the child identity; a record carrying another thread_id is not counted | `sed:s/if \(ownMeta === null\) ownMeta = obj.payload;/ownMeta = obj.payload;/` on .aai/scripts/lib/codex-rollout.mjs | green |
| TEST-3109 | Spec-AC-04 | integration | tests/skills/test-aai-codex-usage.sh | test_3109_archived_and_cwd_change: the parent only under archived_sessions with cwd repo and the child under sessions with cwd worktree are both found by id | `sed:s/const ROLLOUT_DIRS = \['sessions', 'archived_sessions'\];/const ROLLOUT_DIRS = ['sessions'];/` on .aai/scripts/lib/codex-rollout.mjs | green |
| TEST-3110 | Spec-AC-05 | integration | tests/skills/test-aai-codex-usage.sh | test_3110_descendants_no_double_count: parent plus thread_spawn child plus guardian grandchild with --descendants equals the sum of the three observed alone; the child copy in both directories counts once | `sed:s/queue.push\(child\);/void child;/` on .aai/scripts/lib/codex-rollout.mjs | green |
| TEST-3111 | Spec-AC-06 | integration | tests/skills/test-aai-codex-usage.sh | test_3111_append_run_flush_seam: scratch repo copy; observe flags into real state.mjs append-run, then real metrics-flush; the STATE run carries usage_basis field before the flush, then the METRICS run carries the tokens, harness codex and every provenance token; an unavailable observation yields usage_capture=none and no token field | `sed:s/flags.push\('--tokens-total', String\(usage.total_tokens\)\);/void 0;/` on .aai/scripts/codex-usage.mjs | green |
| TEST-3112 | Spec-AC-06 | integration | tests/skills/test-aai-codex-usage.sh | test_3112_log_tick_seam: observe log_tick_flags into real state.mjs log-tick; the tick line has input_tokens and output_tokens equal to the observation and no cache_read_tokens or est_cost_usd | `sed:s/const LOG_TICK_KEYS = \['--tokens-in', '--tokens-out'\];/const LOG_TICK_KEYS = ['--tokens-in', '--tokens-out', '--cache-read'];/` on .aai/scripts/codex-usage.mjs | green |
| TEST-3113 | Spec-AC-07 | unit | tests/skills/test-aai-codex-usage.sh | test_3113_budget_verdicts: total equal to N exits 3 exhausted, N minus one below exits 0 within, N of 0 exits 2, unreadable source exits 4 with NOT enforced and no within | `sed:s/const exhausted = cumulative >= limit;/const exhausted = cumulative > limit;/` on .aai/scripts/codex-usage.mjs | green |
| TEST-3114 | Spec-AC-07 | integration | tests/skills/test-aai-codex-usage.sh | test_3114_budget_parks_via_unattended_gate: on the exhausted fixture budget exits 3, then the real unattended-gate.mjs classify --trigger run-budget with a scratch ledger returns park; on the unavailable fixture the stdout line names NOT enforced | `sed:s/token budget NOT enforced/token budget enforced/` on .aai/scripts/codex-usage.mjs | green |
| TEST-3115 | Spec-AC-08 | unit | tests/skills/test-aai-codex-usage.sh | test_3115_attribution_rule: one child spawned in the window gives attribution thread with that child plus descendants; zero and two children each give attribution interval over the parent plus descendants | `sed:s/const binding = spawned.length === 1 \? 'thread' : 'interval';/const binding = 'thread';/` on .aai/scripts/lib/codex-rollout.mjs | green |
| TEST-3116 | Spec-AC-09 | integration | tests/skills/test-aai-codex-usage.sh | test_3116_privacy_read_only: sentinel in message, base_instructions and tool payload lines never reaches any output of the four subcommands; fixture listing with sizes and mtimes and git status --porcelain are identical before and after; HOME is an empty dir | `sed:s/return e && e.CODEX_HOME \? path.resolve\(e.CODEX_HOME\) : path.join\(home, '.codex'\);/return path.join(home, '.codex');/` on .aai/scripts/lib/codex-rollout.mjs | green |
| TEST-3117 | Spec-AC-10 | unit | tests/skills/test-aai-codex-usage.sh | test_3117_probe_capabilities: available fixture, missing CODEX_HOME and env-resolved thread each report the right fields, and app_server_token_events is not_integrated in all three | `sed:s/app_server_token_events: 'not_integrated'/app_server_token_events: 'available'/` on .aai/scripts/codex-usage.mjs | green |
| TEST-3118 | Spec-AC-11 | contract | tests/skills/test-aai-codex-usage.sh | test_3118_prose_wiring_pins: SKILL_LOOP step 2f names codex-usage.mjs budget, exit 3, exit 4, NOT enforced and the unattended run-budget park; SUBAGENT_PROTOCOL carries the Codex bullet naming observe, attribute, no --cache-read and no cost | `sed:s/codex-usage\.mjs budget/codex-usage.mjs budgt/` on .aai/SKILL_LOOP.prompt.md | green |
| TEST-3119 | Spec-AC-11 | contract | tests/skills/test-aai-codex-usage.sh | test_3119_registration_pins: PROFILES core lists both files, suite-map row aai-codex-usage selects them via select-suites.mjs, live-parsers/codex.mjs imports codexHome from the lib | `sed:s/  - \.aai\/scripts\/codex-usage\.mjs/  - .aai\/scripts\/codex-usagex.mjs/` on .aai/system/PROFILES.yaml | green |
| TEST-3120 | Spec-AC-11 | regression | tests/skills/test-aai-token-capture.sh | Claude capture preserved: test-aai-token-capture.sh, test-aai-state.sh, test-aai-metrics.sh, test-aai-live-status.sh, test-aai-prompt-diet.sh, test-aai-layer-profiles.sh and test-aai-hygiene-pack.sh exit 0 through aai-run-tests.sh, and git diff --quiet main on state.mjs, metrics-flush.mjs and lib/usage-note.mjs exits 0 | `sed:s/tokens_in: \${tokensIn \?\? 'null'}/tokens_in: null/` on .aai/scripts/state.mjs | green |
| TEST-3121 | Spec-AC-12 | smoke | tests/skills/test-aai-codex-usage.sh | test_3121_real_smoke_opt_in: skipped with a SKIP line unless AAI_CODEX_SMOKE=1; picks the newest real thread with records, compares observe total over its lifetime with the last record thread_token_usage total read by an independent node one-liner, writes the metadata-only report | `sed:s/usage.total_tokens = total;/usage.total_tokens = total + 1;/` on .aai/scripts/lib/codex-rollout.mjs | green |

RED observations (stored under `docs/ai/tdd/codex-usage-missing-from-run-budgets/red/`): TEST-3101 to TEST-3117 fail on the pre-change tree because `codex-usage.mjs` and `lib/codex-rollout.mjs` do not exist (command not found, exit not 0, 3 or 4 as asserted). TEST-3118 fails because SKILL_LOOP step 2f names no Codex source. TEST-3119 fails because PROFILES and suite-map lack the rows. TEST-3120 is a regression row: it is green before and after, and its RED proof is the mutation record, not a pre-change failure. TEST-3121 is opt-in; its RED proof is the mutation record run with `AAI_CODEX_SMOKE=1` on this machine, where the source was measured accessible.

## Verification

- Suite: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-codex-usage.sh` exits 0.
- Single rows: `env -u AAI_ROLE bash tests/skills/test-aai-codex-usage.sh --test TEST-31xx`.
- Smoke: `AAI_CODEX_SMOKE=1 env -u AAI_ROLE bash tests/skills/test-aai-codex-usage.sh --test TEST-3121` exits 0 and names the report path.
- Neighbours through the wrapper, each exit 0: test-aai-token-capture.sh, test-aai-state.sh, test-aai-metrics.sh, test-aai-live-status.sh, test-aai-prompt-diet.sh, test-aai-layer-profiles.sh, test-aai-hygiene-pack.sh, test-aai-unattended.sh, test-aai-suite-select.sh.
- Selection: `git diff --name-only main | node .aai/scripts/select-suites.mjs --files-from -`; every selected suite exits 0; one full sweep before close (`AAI_TEST_TIMEOUT=3000`).
- Registration: `node .aai/scripts/check-test-registration.mjs tests/skills` exits 0.
- Mutation records: `node .aai/scripts/mutation-run.mjs --spec <this spec> --test-id <id> --suite <suite> --selector <function> --target <file> --sed '<expr>'` per row; `node .aai/scripts/mutation-gate.mjs --spec <this spec>` exits 0.
- Spec lint: `node .aai/scripts/spec-lint.mjs --path <this spec>` reports no error.
- PASS criteria: every TEST-31xx green, every Spec-AC terminal, state.mjs, metrics-flush.mjs and lib/usage-note.mjs byte-identical to the base.

## Evidence contract

Per artifact: ref_id `codex-usage-missing-from-run-budgets`, the Spec-AC and TEST ids, the command, its exit code, the evidence path under `docs/ai/tdd/codex-usage-missing-from-run-budgets/` or `docs/ai/reports/`, and the commit or diff range against main at f8614f67. The smoke report holds ids, timestamps and numbers only.

### Evidence by strategy

| Strategy | Evidence this spec may demand |
|---|---|
| tdd / hybrid | stored RED artifact per AC-gating test (docs/ai/tdd/) plus the full verification matrix |
| loop | per-TEST-xxx green runs; RED-proof observed, storage optional |
| direct | targeted regression tests green (exit codes) plus the scoped diff |
| untested | the recorded strategy rationale plus the scoped diff |

This spec is `hybrid`: stored RED for TEST-3101 to TEST-3119, mutation records for every row.

## Companion obligations

- Prompt corpus growth (`.aai/SKILL_LOOP.prompt.md`, inside TEST-010's glob): one JUSTIFIED_ADDITIONS entry in `tests/skills/lib/prompt-diet-ledger.sh` at the measured byte growth (cap 700 B) and the matching TEST-012 pin move; covered by TEST-3120 (test-aai-prompt-diet.sh). `.aai/SUBAGENT_PROTOCOL.md` is outside the glob.
- New `.aai/**` files: both classified under `core:` in `.aai/system/PROFILES.yaml`; covered by TEST-3119 and test-aai-layer-profiles.sh.
- ORCHESTRATION.prompt.md is not edited (40-line cap untouched).

## Registry items closed by this scope

none (follow-ups.mjs list scanned 2026-10-28 for codex, usage, budget, token and harness; no open item covers this subject).

Suggested follow-ups (not filed by Planning):
- suggested: `fu-live-codex-parser-forked-meta` — live-parsers/codex.mjs rebinds sessionId on a later forked session_meta and does not scan archived_sessions/, so the dashboard misattributes or misses role subagents.
- suggested: `fu-codex-subscription-cost-label` — metrics-flush prices codex_rollout runs at API list price; label it as a list-price equivalent, not a charge.
- suggested: `fu-codex-app-server-token-events` — consume thread/tokenUsage/updated when a host integration exposes it.

## Notes

- Assumptions recorded instead of questions (autopilot): the thread id comes from `--thread` or `CODEX_THREAD_ID` (unverified host variable, D6); the unattended park on unavailable enforcement (D11) is the bounded fallback the intake asks for.
- Residual risks: prompt compliance of a real Codex orchestrator with step 2f (no automated test crosses it); the cumulative fallback can undercount around compaction (measured 2.9 percent on one thread) and is labelled degraded; Codex log schema can change between CLI versions, and the reader reports missing fields as null rather than guessing.
- Measured facts in this spec come from metadata-only probes of the local CODEX_HOME on 2026-10-28 (field names, counts and totals; no message content read or copied).
