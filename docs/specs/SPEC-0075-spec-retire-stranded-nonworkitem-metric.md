---
id: spec-retire-stranded-nonworkitem-metric
type: spec
number: 75
status: done
ceremony_level: 1
links:
  requirement: docs/issues/ISSUE-0029-retire-stranded-nonworkitem-metric.md
  rfc: null
  pr:
    - 138
  commits:
    - 417adfe682b3d9e17e8237998c01c55bc87d0d85
---

# Implementation Spec — retire-stranded-nonworkitem-metric

SPEC-FROZEN: true

Ceremony justification: the scope is confined to one EXISTING non-protected
script (`.aai/scripts/metrics-flush.mjs`) and its EXISTING test suite
(`tests/skills/test-aai-metrics.sh`) — no new `.aai/**` file, no
prompt-corpus edit (`.aai/METRICS_FLUSH.prompt.md` / `.aai/AGENTS.md`
untouched by design — see Constraints), no protected-path touch.
`.aai/scripts/metrics-flush.mjs` is confirmed NOT in `protected_paths_l3`
(docs/ai/docs-audit.yaml): the L3 set is `.aai/scripts/state.mjs`,
`.aai/scripts/lib/state-engine.mjs`, `.aai/scripts/lib/state-core.mjs`,
`.aai/scripts/allocate-doc-number.mjs`, `.aai/scripts/pre-commit-checks.sh`,
`.aai/scripts/pre-commit-checks.ps1`, `.aai/workflow/WORKFLOW.md`,
`docs/CONSTITUTION.md`. Single reviewable, reversible, additive new-flag
change inside one script that already exists and is already classified core
in `.aai/system/PROFILES.yaml` -> Level 1 (same tier as the immediately
preceding metrics-adjacent spec's precedent shape, SPEC-0074).

## Links
- Requirement: docs/issues/ISSUE-0029-retire-stranded-nonworkitem-metric.md
- Decision records: none yet (pre-PR)
- Technology contract: docs/TECHNOLOGY.md

## Problem

`.aai/scripts/metrics-flush.mjs` has exactly two dispositions per
`metrics.work_items` entry: flush (truth-gated) or SKIP. `pr-67-post-merge-
review` (a one-off post-merge Code Review of PR #67, PASS, 686s) is not a
work item and never went through the close ceremony, so it satisfies NEITHER
flushability predicate — default (`last_validation.status == pass` naming
the ref, ~line 615) nor `--sweep` (a committed `work_item_closed` event for
the ref in EVENTS.jsonl, ~lines 245-262) — and SKIPs forever. There is no
sanctioned exit for "this entry is legitimately not a work item," so the
entry sits in STATE indefinitely, printing a misleading SKIP on every run
and training the operator to ignore SKIP as a signal.

## Scope
- In scope: `.aai/scripts/metrics-flush.mjs` (new `--retire <ref> [--reason
  "..."]` mode, its FAIL-CLOSED guard, EVENTS.jsonl audit-append, STATE
  cleanup, `--dry-run` support, header-comment + usage-message
  documentation); `tests/skills/test-aai-metrics.sh` (new test functions
  appended to the existing suite); this spec doc.
- Out of scope: any change to `.aai/METRICS_FLUSH.prompt.md` or
  `.aai/AGENTS.md` (see Constraints); any change to `append-event.mjs`'s
  closed `EVENT_TYPES` set (the retire write path is a direct, in-script
  `fs.appendFileSync` mirroring the script's own existing METRICS.jsonl
  ledger-append idiom — it does not shell out to `append-event.mjs`, so
  that script's closed set is not touched or exercised); actually running
  `--retire pr-67-post-merge-review` against the real repo (that is an
  operator action after this spec's implementation lands — the Test Plan
  proves the mechanism on synthetic fixtures, per the intake's explicit
  instruction not to depend on the real entry); a `--sweep`+`--retire`
  combined-flag contract (undefined/unused combination, not built now).

## Design

Add `--retire <ref>` and `--reason "<text>"` to `parseArgs`' value-flag map
(`opts.retire`, `opts.reason`, both default `null`). When `opts.retire` is
set, `main()` branches into a new `handleRetire()` function immediately
after the existing `vStatus`/`vRef`/`entries` reads (~line 624) and NEVER
reaches the default flush loop — the two code paths are structurally
disjoint, which is what makes "default behavior byte-unchanged" true by
construction rather than by incidental non-interference.

`handleRetire(ref, reason, { entries, vStatus, vRef, eventsPath, statePath,
origLines, trailingNewline, raw, nowIsoStr, opts })`:

1. **Existence guard.** `entries.find(e => e.ref === ref)` (exact match —
   `metrics.work_items` keys are literal, unlike the flexible `refMatches()`
   used for `last_validation.ref_id`). Absent -> `fail('retire refused:
   "<ref>" is not present in metrics.work_items — nothing to retire', 1)`.
   No mutation.
2. **FAIL-CLOSED flushability guard — REUSES the two existing predicates
   verbatim, never a new/looser check:**
   - Default predicate (line ~638): `vStatus === 'pass' &&
     refMatches(vRef, ref)`. True -> `fail('retire refused: "<ref>" would
     flush (last_validation.status is pass and names <ref>) — flush it, do
     not retire (fail-closed truth-gate)', 1)`. No mutation.
   - Sweep predicate (the existing `closedRefs(eventsPath)` function,
     lines 250-262): called UNCONDITIONALLY for retire (regardless of
     whether `--sweep` was also passed) — `closedRefs(eventsPath).has(ref)`.
     True -> `fail('retire refused: "<ref>" would flush (a committed
     work_item_closed event exists for <ref> in EVENTS.jsonl) — flush it,
     do not retire (fail-closed truth-gate)', 1)`. No mutation.
   - Both guards run BEFORE the `--dry-run` branch, so `--dry-run --retire`
     on a flushable ref is STILL refused (same message, same exit code,
     nothing printed as a "plan") — dry-run reports a valid plan, it never
     previews a bypass.
3. **Build the audit record** (only reached once both guards pass): compact
   `discarded_runs` from the entry's own `runs` array (already parsed by
   the existing `parseMetricsEntries`) — `{ role, model_id,
   duration_seconds }` per run, values read verbatim (no re-derivation, no
   `trustedDuration` re-validation — retire preserves what was recorded,
   it does not re-score it). Event shape:
   ```json
   {"v":1,"ts":"<nowIsoStr>","actor":"<git user.email slug|unknown>",
    "event":"metric_retired","ref":"<ref>",
    "payload":{"reason":"<text|null>","discarded_runs":[{"role":...,
    "model_id":...,"duration_seconds":...}, ...]}}
   ```
   `ts` reuses the same `nowMs`/`--now`-pinnable clock the rest of the
   script already uses (determinism/testability parity with the ledger
   entries). `actor` is a small local helper mirroring `append-event.mjs`'s
   own `actorSlug()` (git `user.email`, lowercased, sanitized, falling back
   to `"unknown"` on any failure — no new dependency, `spawnSync` is
   already imported). The same JSON-round-trip safety guard `buildEntry`
   already applies to ledger entries is applied here too (deep-equal after
   `JSON.parse(JSON.stringify(...))`) — refuse rather than append a
   Date-object-tainted record.
4. **`--dry-run`**: print `{"dry_run":true,"retire":"<ref>","reason":...,
   "would_remove_from_state":true,"event":{...}}` and exit 0. Nothing
   written.
5. **Mutate a COPY of `origLines`**: `removeMetricsEntries(lines, [ref])`
   (the EXISTING function, unchanged — it already drops the whole `metrics:`
   block when it empties). Retire does NOT touch `active_work_items`,
   `last_validation`, `code_review`, or `current_focus` — a stranded
   non-work-item entry was never wired into those blocks in the first
   place (unlike a real flush, which resets verdict state for completed
   work). `bumpUpdatedAt(lines, nowIsoStr)` (existing helper) records the
   real mutation timestamp.
6. **In-memory pre-validation** (existing `duplicateKeys`/
   `inlineChildConflicts` guards, same as the default path) — integrity
   refusal, no write, on any structural violation.
7. **Ledger-before-STATE ordering** (mirrors the default flush's existing
   D-invariant): `fs.mkdirSync` + `fs.appendFileSync(eventsPath, ...)`
   FIRST (the audit record is durable before STATE changes at all), THEN
   `writeState(statePath, lines, trailingNewline, raw)` (the existing
   atomic tmp+rename engine call — unchanged).
8. **Post-commit `check-state.mjs`** (existing `spawnSync` call, unchanged
   pattern): non-zero -> pre-flush STATE snapshot saved to
   `<state>.pre-flush-<ts>`, `fail(..., 1)`. Same recovery shape as the
   default path — a partial retire cannot strand STATE any more than a
   partial flush can.
9. Report `Retired: <ref> -> <relative eventsPath> (metric_retired)` and
   `check-state: OK (...)`, exit 0.

Documentation: the top-of-file comment block (Flags:/Exit codes: sections)
and the `parseArgs` unknown-flag error message are extended to name
`--retire`/`--reason` and the new refusal reason under exit code 1.
`.aai/METRICS_FLUSH.prompt.md` is NOT touched (see Constraints).

## Constraints / Risks
- `.aai/scripts/metrics-flush.mjs` is NOT `protected_paths_l3` (confirmed
  above). No protected path is touched.
- The fail-closed guard is the WHOLE point: `--retire` must be impossible to
  use as a truth-gate bypass. Both guard predicates are the EXISTING
  functions/expressions the default and `--sweep` gates already use —
  no new, looser check is invented.
- `.aai/METRICS_FLUSH.prompt.md` is NOT reworded. The existing
  `test_spec0011_closeout_prompts_wired` test
  (`tests/skills/test-aai-docs-audit.sh`) asserts that file does NOT
  contain the literal string `work_item_closed` (SPEC-0054: the prompt must
  not claim flush emits close-lifecycle events) — documenting `--retire`'s
  guard behavior in prose there would risk reintroducing that literal and
  breaking the invariant. `--retire` is documented exclusively in the
  script's own header comment and usage/error text.
- EVENTS.jsonl is append-only. The retire write path is a direct
  `fs.appendFileSync`, mirroring the script's OWN existing ledger-append
  idiom (`fs.mkdirSync` + `fs.appendFileSync` for METRICS.jsonl) — never a
  rewrite, never routed through a whole-file rewrite of any kind.
- Integrity/rollback: reuses the flush's existing ledger-before-STATE
  ordering, in-memory pre-validation, and post-commit check-state +
  recovery-snapshot shape, so a partial `--retire` write cannot strand
  STATE.
- No secret referenced — SECRETS PREFLIGHT skipped (confirmed by the
  intake).

## Companion obligations (PLANNING step 3a)

- Adds bytes to the prompt corpus (`.aai/*.prompt.md`, `.aai/AGENTS.md`)?
  NO — `--retire` is documented only in `metrics-flush.mjs`'s own header
  comment and usage/error text; `.aai/METRICS_FLUSH.prompt.md` is
  deliberately untouched (see Constraints). No prompt-diet ledger true-up
  (no `tests/skills/lib/prompt-diet-ledger.sh` / TEST-012 checkpoint
  change).
- Adds a NEW `.aai/**` file? NO — `.aai/scripts/metrics-flush.mjs` already
  exists and is already listed as `core` in `.aai/system/PROFILES.yaml`
  (confirmed: line 113, `- .aai/scripts/metrics-flush.mjs`, under the core
  block). `tests/skills/test-aai-metrics.sh` already exists and is
  extended, not created. No `.aai/system/PROFILES.yaml` classification
  entry needed.
- Outcome: NEITHER obligation applies. Skipped, per the closed two-entry
  list in `.aai/PLANNING.prompt.md` step 3a.

## Implementation strategy
- Strategy: tdd
- Rationale: this is state-mutation + fail-closed branch logic (a guard
  whose entire purpose is to be un-bypassable) over synthetic STATE/EVENTS
  fixtures — exactly the shape the intake calls out as clean TDD terrain,
  and the same class of risk (decision-order / gate logic on a shared
  transactional script) that SPEC-0070/SPEC-0074 already established `tdd`
  for on this codebase. A test that never observed the guard actually
  refusing something proves nothing about the guard.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: single non-protected script + its existing test file,
  small and fully reversible (a new, structurally-disjoint CLI branch),
  already on a dedicated branch (`fix/retire-stranded-nonworkitem-metric`)
  off `main`. No cross-cutting refactor, no migration, no protected-path
  touch.
- User decision: inline
- Base ref: main
- Worktree branch/path: fix/retire-stranded-nonworkitem-metric (inline)
- Inline review scope: `.aai/scripts/metrics-flush.mjs`,
  `tests/skills/test-aai-metrics.sh`

## Acceptance Criteria Mapping

- Maps to: Verification bullet 1 (FAIL-CLOSED guard: refuses a ref that
  WOULD flush by either predicate; refuses a ref not present)
- Spec-AC-01: `--retire <ref>` where `last_validation.status == pass` AND
  `last_validation.ref_id` names `<ref>` REFUSES with a non-zero exit and
  writes nothing (STATE and EVENTS.jsonl byte-unchanged).
  - Verification: `bash tests/skills/test-aai-metrics.sh test_111_retire_refused_default_flushable` -> exit 0.

- Maps to: Verification bullet 1 (same bullet, the sweep predicate)
- Spec-AC-02: `--retire <ref>` where a committed `work_item_closed` event
  exists for `<ref>` in EVENTS.jsonl (regardless of whether `--sweep` was
  passed) REFUSES with a non-zero exit and writes nothing.
  - Verification: `bash tests/skills/test-aai-metrics.sh test_112_retire_refused_sweep_flushable` -> exit 0.

- Maps to: Verification bullet 1 (refuses a ref not present)
- Spec-AC-03: `--retire <ref>` where `<ref>` is absent from
  `metrics.work_items` REFUSES with a non-zero exit and writes nothing.
  - Verification: `bash tests/skills/test-aai-metrics.sh test_113_retire_refused_not_in_state` -> exit 0.

- Maps to: Verification bullet 2 (running --retire clears a genuinely
  stranded ref)
- Spec-AC-04: `--retire <ref>` where `<ref>` satisfies NEITHER
  flushability predicate removes `<ref>`'s entry from
  `STATE.metrics.work_items` (and the whole `metrics:` block if it was the
  last entry), appends exactly one `metric_retired` event to
  EVENTS.jsonl BEFORE the STATE commit, and exits 0.
  - Verification: `bash tests/skills/test-aai-metrics.sh test_110_retire_stranded_ref` -> exit 0.

- Maps to: Constraints/Risks — "retirement records the discarded run
  summary durably, it does not just delete real telemetry"
- Spec-AC-05: the appended `metric_retired` event's `payload` carries
  `reason` (the `--reason` text, or `null` when omitted) and
  `discarded_runs`, an array with one compact `{role, model_id,
  duration_seconds}` object per discarded `agent_runs` entry, values equal
  to what was recorded in STATE.
  - Verification: `bash tests/skills/test-aai-metrics.sh test_110_retire_stranded_ref` -> exit 0 (payload assertions in the same run).

- Maps to: Verification bullet 1 ("--dry-run reports what it WOULD retire
  without writing; default behavior is byte-unchanged")
- Spec-AC-06: `--dry-run --retire <ref>` prints a JSON plan naming the ref
  and the would-be `metric_retired` event and writes nothing, for BOTH a
  retirable ref (plan printed, exit 0) and a refused ref (same refusal
  message/exit code as the non-dry-run case, no plan printed, nothing
  written) — dry-run never bypasses the guard.
  - Verification: `bash tests/skills/test-aai-metrics.sh test_114_retire_dry_run` -> exit 0.

- Maps to: Verification bullet 1 ("default (no --retire) behavior is
  byte-unchanged") and bullet 4 (full suite green)
- Spec-AC-07: the default (no `--retire`) flush code path is provably
  unaffected — every pre-existing assertion in
  `tests/skills/test-aai-metrics.sh` (TEST-006..023, TEST-101..109) and the
  full skill suite still pass.
  - Verification: `bash tests/skills/test-aai-metrics.sh` -> exit 0 (all
    cases). `bash tests/skills/test-framework.sh` -> exit 0 (full suite;
    named residual flakes only, see Verification section).

- Maps to: Constraints — "do NOT reword `.aai/METRICS_FLUSH.prompt.md`;
  document `--retire` in the script's own `--help`/comments"
- Spec-AC-08: `--retire` and `--reason` are documented in
  `metrics-flush.mjs`'s own top-of-file comment block and its
  unknown-flag usage text; `.aai/METRICS_FLUSH.prompt.md` is unmodified
  (the existing `test_spec0011_closeout_prompts_wired` negative assertion
  — the literal `work_item_closed` stays ABSENT from that file — still
  passes, unmodified).
  - Verification: `bash tests/skills/test-aai-metrics.sh test_116_retire_documented_not_in_prompt` -> exit 0. `bash tests/skills/test-aai-docs-audit.sh` -> exit 0 (regression, unmodified test).

## Constitution deviations

None. Art.1: measurable exit-code + STATE/EVENTS-content AC below, no PASS
claim in planning. Art.2: the smallest change that closes the gap — one new
CLI mode reusing two existing predicates and two existing helper functions
(`removeMetricsEntries`, `writeState`), no new file, no new schema. Art.3:
pure `.mjs` (node stdlib only, `spawnSync` already imported) + the existing
bash-3.2-compatible test suite. Art.4: every refusal path prints an
explicit, reason-naming message to stderr; nothing goes silent. Art.5:
additive-only — the default flush code path is structurally disjoint (a
separate branch reached only when `opts.retire` is set), so every
pre-existing exit code/output for the no-`--retire` path is provably
unchanged (Spec-AC-07). Art.6: STATE.yaml is still written exclusively via
the existing `lib/state-engine.mjs` atomic `writeState()` — no new writer,
no hand-edit. Art.7: no merge-boundary change; this is a maintenance CLI
mode, not a PR/merge action.

## Seam analysis

`docs/ai/EVENTS.jsonl` is a shared append-only log written by
`append-event.mjs`/`close-work-item.mjs` and READ by
`docs-audit.mjs`/`lib/docs-audit-core.mjs` (multiple heuristics) and by
`metrics-flush.mjs`'s own `closedRefs()`. This change adds a NEW event type
(`metric_retired`) to that shared log — a genuine seam (a producer this
change owns, writing into a log several OTHER features consume). Verified
NOT to require a new integration test: every existing consumer matches on
an EXACT, closed event-type string (`e.event === 'work_item_closed'`,
`e.event === 'ac_evidence'`, etc. — confirmed by inspection of
`lib/docs-audit-core.mjs` and `metrics-flush.mjs`'s own `closedRefs()`),
never a closed enumerated whitelist that would reject an unrecognized type.
An unrecognized `metric_retired` line is therefore silently and safely
ignored by every existing reader (Constitution Art.5, additive-first) — no
consumer can regress. The regression net (Spec-AC-07/TEST-009: the full
`tests/skills/test-framework.sh` run, which includes
`tests/skills/test-aai-docs-audit.sh`) is the seam-crossing proof: real
EVENTS.jsonl fixtures containing a `metric_retired` line are exercised by
the existing docs-audit suite's generic EVENTS-parsing paths without any
docs-audit-specific code change. `append-event.mjs`'s own closed
`EVENT_TYPES` validator is NOT a seam here because `--retire`'s write path
never calls that script (direct `fs.appendFileSync`, per Design/
Constraints) — that validator only gates writers that go THROUGH
`append-event.mjs`, which this change deliberately does not do.

## Acceptance Criteria Status

| Spec-AC    | Description                                                        | Status  | Evidence | Review-By | Notes |
|------------|---------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | Refuses a ref last_validation names with PASS                       | done    | TEST-003 green-20260724T121819Z-retire.log | — | test_111 exit 0 |
| Spec-AC-02 | Refuses a ref with a committed work_item_closed event                | done    | TEST-004 green-20260724T121819Z-retire.log | — | test_112 exit 0 |
| Spec-AC-03 | Refuses a ref absent from metrics.work_items                        | done    | TEST-005 green-20260724T121819Z-retire.log | — | test_113 exit 0 |
| Spec-AC-04 | Genuinely-stranded ref: removed from STATE, metric_retired appended  | done    | TEST-001 green-20260724T121819Z-retire.log | — | test_110 exit 0 |
| Spec-AC-05 | metric_retired payload carries reason + discarded_runs summary       | done    | TEST-002 green-20260724T121819Z-retire.log | — | test_110 payload asserts |
| Spec-AC-06 | --dry-run reports without writing; never bypasses the guard          | done    | TEST-006 green-20260724T121819Z-retire.log | — | test_114 exit 0 |
| Spec-AC-07 | Default (no --retire) path byte-unchanged; full suite green          | done    | TEST-007+TEST-009 test-framework.sh 42/42 | — | metrics suite + full suite green |
| Spec-AC-08 | --retire documented in script only; prompt file untouched            | done    | TEST-008 green-20260724T121819Z-retire.log | — | test_116 exit 0 |

## Implementation plan
- Components/modules affected: `.aai/scripts/metrics-flush.mjs`
  (`parseArgs` gains `--retire`/`--reason`; new `handleRetire()` function;
  new local `actorSlug()` helper; top-of-file comment block updated);
  `tests/skills/test-aai-metrics.sh` (new `write_retire_state()` fixture
  builder alongside the existing `write_sweep_state()`/`write_flush_state()`
  pattern; six new `test_11N_*` functions; `main()` extended to call them).
- Data flow: `metrics.work_items[<ref>]` (STATE, read) +
  `last_validation.status`/`.ref_id` (STATE, read) + EVENTS.jsonl
  `work_item_closed` lines (read) -> guard decision -> on success:
  EVENTS.jsonl gains one `metric_retired` line (write, append-only) and
  STATE loses the `metrics.work_items[<ref>]` entry (write, surgical line
  removal via the existing `removeMetricsEntries`). No new inputs beyond
  the two new CLI flags.
- Edge cases: retiring the LAST entry in `metrics.work_items` must drop the
  whole `metrics:` block (already handled by the existing
  `removeMetricsEntries`, exercised here for the first time via a
  single-entry retire fixture — covered by TEST-001/TEST-002); `--reason`
  omitted -> `payload.reason: null`, never an empty string or a fabricated
  default; an entry whose `runs` array is empty -> `discarded_runs: []`
  (not an error — an empty run history is still legitimately retirable
  once it clears the existence + flushability guards); `git config
  user.email` unavailable in a throwaway test fixture (no `.git` in
  `mk_repo`, only `mk_seam_repo` inits one) -> `actor: "unknown"`, matching
  `append-event.mjs`'s own fallback, never a crash; `--retire` combined
  with `--sweep`/`--ref` -> `--retire` takes the branch unconditionally
  before either flag is consulted, so the combination is inert (undefined
  contract, not built, not tested — out of scope per Scope above).

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)               | Description                                                                                                                                                                                                                                                                                   | Status  |
|----------|------------|-------------|-------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-04 | integration | tests/skills/test-aai-metrics.sh    | Synthetic STATE: metrics.work_items entry STRAY-0001 (2 agent_runs), last_validation not naming it (status not_run), EVENTS.jsonl carries no work_item_closed for it. `--retire STRAY-0001 --reason "mis-recorded, not a work item"` removes STRAY-0001 from STATE and appends exactly one metric_retired line, exit 0. RED (pre-fix): --retire is an unrecognized flag -> exit 2, no mutation. GREEN (post-fix): exit 0, entry removed, event appended. Discriminating: 2 -> 0.                                            | green   |
| TEST-002 | Spec-AC-05 | integration | tests/skills/test-aai-metrics.sh    | Same run as TEST-001: the appended event's payload.reason equals the given text and payload.discarded_runs is an array of 2 objects, each {role, model_id, duration_seconds} equal to the fixture's own agent_runs values. RED (pre-fix): no event line exists at all. GREEN (post-fix): payload present and field-exact. Discriminating: absent -> present-and-correct.                                                                                                                                                     | green   |
| TEST-003 | Spec-AC-01 | integration | tests/skills/test-aai-metrics.sh    | Synthetic STATE: last_validation.status pass, ref_id names FLUSHABLE-0001 (also in metrics.work_items, >=1 run). `--retire FLUSHABLE-0001` exits non-zero, STATE and EVENTS.jsonl byte-unchanged, stderr names "would flush" / "last_validation". RED (pre-fix): exit 2 for the WRONG reason (unrecognized flag, no guard exists). GREEN (post-fix): exit 1 for the CORRECT reason (message-content discriminating, not just exit code).                                                                                    | green   |
| TEST-004 | Spec-AC-02 | integration | tests/skills/test-aai-metrics.sh    | Synthetic STATE: metrics.work_items entry CLOSED-0001, last_validation not naming it; EVENTS.jsonl carries a committed work_item_closed event for CLOSED-0001. `--retire CLOSED-0001` exits non-zero, no mutation, stderr names the committed work_item_closed event. RED/GREEN as TEST-003 (message-content discriminating: wrong-reason 2 -> correct-reason 1).                                                                                                                                                             | green   |
| TEST-005 | Spec-AC-03 | integration | tests/skills/test-aai-metrics.sh    | `--retire NOT-A-REF` where NOT-A-REF is absent from metrics.work_items -> exits non-zero, no mutation, stderr says the ref is not present. RED (pre-fix): exit 2, unrecognized-flag message (wrong reason). GREEN (post-fix): exit 1, "not present in metrics.work_items" message. Discriminating on message content.                                                                                                                                                                                                          | green   |
| TEST-006 | Spec-AC-06 | integration | tests/skills/test-aai-metrics.sh    | (a) `--dry-run --retire STRAY-0001` on the TEST-001 fixture -> exit 0, prints a JSON plan naming the ref and the would-be metric_retired event, STATE and EVENTS.jsonl stay byte-unchanged. (b) `--dry-run --retire FLUSHABLE-0001` on the TEST-003 fixture -> STILL refused, same non-zero exit/reason as TEST-003, nothing written, no plan printed. RED (pre-fix, case a): exit 2, no plan. GREEN: exit 0 + printed plan. Discriminating: 2 -> 0 and absent-plan -> present-plan.                                          | green   |
| TEST-007 | Spec-AC-07 | regression  | tests/skills/test-aai-metrics.sh    | Re-run the EXISTING test_006_flush_golden (byte-exact golden ledger line) and the full existing suite (TEST-006..023, TEST-101..109) unmodified — the default (no --retire) path is provably untouched: identical golden bytes, identical exit codes, identical skip/flush reasons. NON-DISCRIMINATING BY DESIGN (pre-fix == post-fix on every existing assertion) — pins that --retire is a structurally separate branch, not a regression risk to the default path; RED-proof obligation does not apply (see Notes below). | green   |
| TEST-008 | Spec-AC-08 | integration | tests/skills/test-aai-metrics.sh    | `--retire`/`--reason` appear in metrics-flush.mjs's own top-of-file comment block AND its unknown-flag usage text (grep the script itself, both locations); .aai/METRICS_FLUSH.prompt.md still does NOT contain the literal work_item_closed (re-verified locally, not just relying on the other suite).                                                                                                                                                                                                                        | green   |
| TEST-009 | Spec-AC-07 | regression  | tests/skills/test-framework.sh      | Full skill-suite regression: `bash tests/skills/test-framework.sh` -> exit 0 across ALL suites (a shared flush script can regress suites beyond test-aai-metrics.sh, e.g. test-aai-docs-audit.sh's EVENTS-parsing paths). Acceptable residuals ONLY: `aai-run-tests` TEST-018 reaper CI-load flake; `aai-test-canon` TEST-006; `aai-ceremony-levels` byte-guard flake when this spec's own files are uncommitted. Any OTHER failing suite blocks.                                                                            | green   |

Notes:
- Every Spec-AC has at least one TEST-xxx entry.
- New bash test functions (appended to `tests/skills/test-aai-metrics.sh`,
  after `test_109_sweep_seam_close_then_sweep`, called from `main()`):
  `test_110_retire_stranded_ref` (TEST-001, TEST-002),
  `test_111_retire_refused_default_flushable` (TEST-003),
  `test_112_retire_refused_sweep_flushable` (TEST-004),
  `test_113_retire_refused_not_in_state` (TEST-005),
  `test_114_retire_dry_run` (TEST-006), `test_116_retire_documented_not_in_prompt`
  (TEST-008). TEST-007 and TEST-009 re-run EXISTING, unmodified tests/
  suites as regression pins — no new function for either.
- RED-proof obligation: TEST-001..006 and TEST-008 are genuinely RED-proof
  — `--retire` does not exist pre-fix, so every one of them was observed
  producing a DIFFERENT result (wrong exit code, wrong/absent message, no
  event, no plan) before the change than after. TEST-007 and TEST-009 are
  explicitly exempted (regression pins on already-passing assertions,
  identical pre/post by design) — recorded honestly rather than claiming a
  fake RED, per the RED-proof rule's own carve-out for non-discriminating
  regression rows (SPEC-0074 precedent).
- Fixtures are synthetic (a temp STATE.yaml built by a new
  `write_retire_state()` helper + a temp EVENTS.jsonl, both scratch
  temp-dir repos per the suite's existing `mk_repo`/`write_sweep_state`
  pattern) — none of TEST-001..008 depends on the real
  `pr-67-post-merge-review` entry.
- Table cell check: no cell in this table contains a literal `|` character
  (SPEC-0072 pipe-table-drop hazard) — ref names use hyphens only
  (`STRAY-0001`, `FLUSHABLE-0001`, `CLOSED-0001`, `NOT-A-REF`), and every
  exit-code/reason description uses `/`, `,`, or `->`, never `|`. Every row
  in this table has exactly 8 pipe-delimited cells matching the header.

## Verification
- `bash tests/skills/test-aai-metrics.sh` -> exit 0 (all cases, existing +
  new).
- `bash tests/skills/test-aai-metrics.sh test_110_retire_stranded_ref` (and
  each new `test_11N_*`/`test_116_*` name individually) -> exit 0, for
  isolated RED capture before the fix and GREEN capture after (the suite's
  existing sourcing convention: `bash tests/skills/test-aai-metrics.sh
  <function-name>` runs one test in isolation).
- `bash tests/skills/test-aai-docs-audit.sh` -> exit 0 (regression,
  unmodified — the SPEC-0054 prompt-file negative-assertion test).
- `bash tests/skills/test-framework.sh` -> exit 0 (full skill suite; the
  ONLY acceptable residuals are the three named CI-load/byte-guard flakes
  in TEST-009 — any other failure blocks).
- `.aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-metrics.sh` ->
  exit 0 (process-group-wrapped run, matches CI invocation).
- Manual spot check: `node .aai/scripts/metrics-flush.mjs --retire
  pr-67-post-merge-review --dry-run` against the REAL repo STATE.yaml
  prints a plan (the real entry currently satisfies neither predicate, so
  it should be retirable) — informational only, not part of the automated
  PASS criteria, and not a claim that the real entry has been retired by
  this spec (that is a separate operator action after merge).
- Post-freeze advisory: `node .aai/scripts/spec-lint.mjs --path
  docs/specs/SPEC-0075-spec-retire-stranded-nonworkitem-metric.md`
  (report-only).
- PASS criteria: all TEST-001..009 green; all Spec-AC-01..08 in a terminal
  (`done`) status with non-empty evidence.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: retire-stranded-nonworkitem-metric (SPEC-000N at merge)
- Spec-AC and TEST-xxx links (Spec-AC-01/TEST-003, Spec-AC-02/TEST-004,
  Spec-AC-03/TEST-005, Spec-AC-04/TEST-001, Spec-AC-05/TEST-002,
  Spec-AC-06/TEST-006, Spec-AC-07/TEST-007+TEST-009, Spec-AC-08/TEST-008)
- command or review scope
- exit code or review verdict
- evidence path (RED/GREEN logs under `docs/ai/tdd/`; review under
  `docs/ai/reviews/`)
- commit SHA or diff range when available
