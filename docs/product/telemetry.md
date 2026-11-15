---
id: telemetry
type: product
capability: telemetry
status: current
delivered_by:
  - CHANGE-0058
  - CHANGE-0070
  - CHANGE-0063
  - telemetry-fields-not-prose
  - done-work-item-stays-in-current-focus
  - codex-usage-missing-from-run-budgets
spec: docs/specs/SPEC-0089-spec-token-economics-end-to-end.md
updated: 2026-09-13
---

# Usage & cost telemetry

## What it does

The factory records what each run cost and under which instructions it ran,
surfaces those numbers in reports and the stakeholder overview, and makes
every capture gap loud instead of silent. Three delivered pieces make up
one capability:

- **Loud capture (CHANGE-0058)** — a run that observed real token usage but
  never recorded it no longer looks identical to one where the runtime
  exposed nothing; the flush classifies each run and the tick logger warns
  on a bogus start time or missing harness version.
- **Instruction identity (CHANGE-0070)** — every run can carry a
  content-addressed sha256 of the effective instruction stack (role prompt +
  SUBAGENT_CONTRACT + LEARNED), so "which prompt version produced this run"
  is a query, not a guess.
- **Visible economics (CHANGE-0063)** — the metrics report shows tokens per
  work item and per role, and the overview shows tokens per delivered
  feature with a grand total, grouped by release and auto-regenerated at
  close so the page cannot go stale.
- **Fields, not prose (telemetry-fields-not-prose)** — verdict, harness,
  requested/actual model and a harness-reported token total are now written
  as STRUCTURED fields on `agent_runs[]` (`append-run --verdict / --harness /
  --tokens-total / --requested-model / --actual-model`), not just narrated in
  free-text `note`. Reliability, cost and per-role model counts derive
  FIELD-FIRST at flush time: the `VERDICT: FAIL` note marker is now a
  fallback, used only when no field was recorded, and the ledger names which
  one produced each ride's numbers (`reliability.basis`:
  `field | note | mixed | none`). A run whose field and note DISAGREE always
  resolves from the field and prints one NOTE naming the disagreement. A
  Validation or Code Review run recorded without `--verdict` is REFUSED
  (exit 2, nothing written) — a missing verdict can no longer look identical
  to a passing one. The default flush gate also widened to recognise a
  per-ref verdict field or a corroborated `validation_verdict` ledger event,
  not only the single global `last_validation` block, so an earlier PASS is
  not stranded by a later, unrelated validation round.
- **Codex usage and budgets (codex-usage-missing-from-run-budgets)** — Codex
  role runs used to be recorded with unknown tokens, and a token budget did
  nothing on Codex. The factory now reads Codex's own local session logs
  (usage metadata only, never message content) and turns them into the same
  run records and budget check other harnesses use, with a note saying where
  the numbers came from. When no Codex usage can be read, the budget says
  so (`token budget NOT enforced`) instead of pretending to enforce a limit.

## How to use it

- `node .aai/scripts/metrics-report.mjs` — per-item and per-role token
  rollups; any role whose runs carry more than one distinct prompt hash gets
  a "Prompt versions" section.
- `/aai-overview` (or any successful `close-work-item`) — refreshed
  `docs/ai/overview.html` with per-item tokens + release groups.
- `/aai-flush` — for an undecomposed harness total (field or note), INFO
  states what happened to the cost: a priced model gets an estimate blended
  from the total (`cost_basis total-blended`), an unpriced model stays
  unattributable by design. WARNING marks capture-missing runs — no total
  anywhere (the defect to chase).
- `node .aai/scripts/state.mjs append-run --prompt-hash <12-64 hex>` records
  a run's instruction version (omit it and behaviour is unchanged);
  `log-tick` warns on duration-0 or missing `--harness`.
- `node .aai/scripts/orchestration-dispatch.mjs --human` prints an advisory
  `Prompt hash: <12-hex>` line for the about-to-run role.
- When merging a subagent result, recording
  `--note "usage_total_tokens=<N> (harness total; in/out not exposed)"` is
  mandatory whenever the harness reported a total (else the run counts as
  capture-missing, not undecomposed-note).
- To group overview items under a release, list their refs in the release
  doc frontmatter as `links.members` (exact ref form); unlisted items fall
  back to close-month groups.
- `node .aai/scripts/state.mjs append-run --role Validation --verdict
  pass|fail|none ...` — Validation and Code Review runs REQUIRE `--verdict`
  (refused, nothing written, otherwise); `--harness` defaults to the
  detected harness; `--tokens-total` records a harness-reported total when
  the runtime exposes only one number (no in/out split); `--requested-model`
  / `--actual-model` record a routing decision and what actually ran.
- `node .aai/scripts/metrics-flush.mjs --release <ref> [--reason "<why>"]
  [--dry-run]`: the sanctioned exit for a closed ride that has no flushable
  telemetry (no `metrics.work_items` row, or a row with zero `agent_runs`).
  It appends one `work_item_released` event with `telemetry: absent`, writes
  no METRICS line, releases `current_focus` when it names the ref, and
  resets only the validation and review blocks that name the ref. It refuses,
  before any write and under `--dry-run` too, when there is no committed
  `work_item_closed` event, the close was superseded by a reopen, the work
  item is not done, the row carries runs, or a fail verdict names the ref or
  is not owned by any ref. With `--ref` or `--sweep` it is a usage error.
- A flush is idempotent per run, not per ride. `metrics-flush.mjs` compares
  each run in STATE (role, model id, start and end time, counted as a
  multiset) with the runs already held by that ride's lines in
  `METRICS.jsonl`. If every run is already there, it is an interrupted flush
  and only the STATE cleanup is resumed (`RESUME <ref>`). If a reopened ride
  has new runs, they go through the same flush gates as a first flush and land
  as one new continuation line holding only those runs; earlier ledger lines
  are never rewritten, and the output prints the usual `Flushed:` line plus a
  `continuation: <ref> flush_segment <n>` line. When the gates refuse the new
  runs, nothing is appended and STATE is left untouched: the output prints
  `SKIP <ref>: <k> agent_runs not in METRICS.jsonl kept in STATE`, followed by
  the gate reason, so the runs stay in STATE until a later flush is admitted.
  `--dry-run` lists such a ride under `flush`, not under `resume`.
- `metrics-flush.mjs --ref <ref>` on a ref that is not a flush candidate now
  exits 1 naming the reason (and `--release` where it applies) instead of an
  empty-success `flush: []`.
- `orchestration-dispatch.mjs` rule 4b no longer dispatches a Metrics Flush
  that cannot act. For a closed focus with zero runs it returns `needs_llm`
  and prints the command a human runs: `metrics-flush.mjs --release <ref>`
  (reason `closed_focus_unflushable_no_flushable_metrics`), or
  `state.mjs clear-focus --ref <ref>` when the focus has no
  `active_work_items` entry (reason
  `closed_focus_item_absent_no_flushable_metrics`). A close superseded by a
  reopen never reaches rule 4b.
- Codex: `node .aai/scripts/codex-usage.mjs probe --json` says whether
  Codex usage logs are readable (`$CODEX_HOME`, default `~/.codex`,
  `sessions/` and `archived_sessions/`) and whether the current thread can
  be identified (`CODEX_THREAD_ID`).
- Codex: after a role run, `codex-usage.mjs attribute --parent <orchestrator
  thread> --from <role start> --to <role end> --json` prints
  `append_run_flags` and `log_tick_flags`; pass them to `state.mjs
  append-run` / `log-tick` unchanged. `observe --thread <id> [--from]
  [--to] [--descendants]` reads one known thread.
- Codex: with `max_run_tokens > 0` the loop runs `codex-usage.mjs budget
  --thread auto --since <run start> --max-run-tokens <N>` before each
  dispatch. Exit 0 = under the limit, 3 = exhausted (the loop stops for a
  human), 4 = no readable source: an attended loop prints
  `token budget NOT enforced` and continues, an unattended ride stops.
- `node .aai/scripts/state.mjs set-validation --ref <R> --status <pass|fail>`
  additionally stamps a per-ref `validation: {status, at}` field on that
  ref's metrics entry when one already exists — the provenance the default
  flush gate's `per-ref-field` source reads.

## Data model

- No breaking schema change. `agent_runs[].note` carries the canonical
  `usage_total_tokens=<N>` grammar (single source
  `.aai/scripts/lib/usage-note.mjs`); `agent_runs[].prompt_hash` is an
  optional 12-64 lowercase hex string in STATE.yaml and copied byte-for-byte
  into METRICS.jsonl. Absent fields render exactly as before.
- Additive fields on `agent_runs[]`: `harness` (closed enum, derived — never
  caller-supplied), `tokens_total` (numeric, undecomposed), `verdict`
  (`pass | fail | none`), `requested_model` / `actual_model` — the latter two,
  like `prompt_hash`, present only when the flag was passed and copied
  byte-for-byte from STATE.yaml into METRICS.jsonl (Round-7, PR #378 P1: the
  flush's output projection used to drop both before the STATE cleanup
  erased the only other place they lived). The ledger's
  per-ride `reliability` object carries `basis`; `cost_usd`/`cost_basis` may
  read `total-blended` (with a `cost_bounds_usd` all-input/all-output range)
  when only a token total is known — derived from `PRICING.yaml`'s
  `cost_blend.input_share`, a labelled CONVENTION, never a measurement.
  `metrics.work_items[<ref>].validation` (STATE) and each ledger line's
  `verdict_basis` (`per-ref-field | global-block | event`) name which source
  admitted the ride past the flush gate.
- Continuation lines: a ride flushed again after a reopen gets a second
  summary line with the same `ref_id` and one extra field, `flush_segment`
  (the number of summary lines the ride had before, plus 1, so the first
  continuation is 2). First-flush lines never carry it. Each line's totals,
  cost and reliability cover only the runs on that line; a reader that sums
  agent runs, tokens, duration and cost per ref gets the ride total. Human
  time is the exception: a continuation line can repeat review minutes that
  the earlier line already counted, so do not sum `human_time_minutes` across
  a ride's lines. A line written by hand to recover runs lost
  earlier carries a `reconstructed` key (`source` and `reason`); a normal flush
  never writes it.
- Recovery of archived runs: `metrics-flush.mjs --recover-archives --archive <dir>
  [--archive <dir>...] --state <STATE.yaml> [--metrics <file>] [--dry-run]`
  writes the role runs that only archived copies of STATE still hold (a
  `docs/ai/archive/` handoff or merge-cleanup copy, a report copy, a
  `.git/aai/checkpoints` snapshot) and that never reached the ledger. It
  appends one line per ref, built by the same code as a normal flush, with
  `verdict`, `verdict_basis` and `strategy` null and a `reconstructed` object
  (`source` naming the copies, a fixed `reason` ending in `verdict unknown`,
  and `recovered_utc`). A ref that already has a line gets a continuation line
  with `flush_segment`. A run is identified by its role plus `started_utc`
  within the ref; a run already in the ledger line of its ref is never
  written again, and a run in the live `--state` wins over its archived
  copy, so a later normal flush treats it as held. The ref that is the live
  `current_focus` is skipped, because its flush will write it. The command
  never writes STATE or EVENTS, `--dry-run` prints the plan as JSON, and a
  second run appends nothing. A recovery line is never a PASS: it is not a
  delivery record, not a flushed record, and the PR gate, the dispatcher and
  the docs audit do not count it as one. Git history cannot recover a
  deleted STATE, because STATE is gitignored and never committed; only the
  archive copies can.
- The archive steps write what they archive. When `merge-cleanup.mjs`
  (`/aai-merge`) archives a merged ride worktree's STATE (step
  `archive-runtime`), it runs the same recovery over that archived copy with
  `--include-focus` (the ride has ended, so its own focus ref is not skipped)
  against the worktree's `docs/ai/METRICS.jsonl`, with `--held-in` naming
  the main checkout's ledger and the base branch's ledger it is about to
  sync to. Runs already in any of them are left alone, so a resumed cleanup or
  a run another merged PR already flushed is not written twice; the others are appended there as a recovery line and moved
  to the main checkout's ledger with the ride's other appended ledger lines,
  where they stay uncommitted until a later change commits them. `plan`
  names the runs it would write and writes nothing. If the worktree is not at
  the merged head or has no ledger, or the check fails, the step is kept
  (`ledger_runs_unchecked`) and prints the exact command to run from the main
  checkout; the archive copy holds the runs meanwhile. The manual worktree
  cleanup in `SKILL_WORKTREE` runs that command right after its `cp` (pull a
  merged branch's main first, or its flushed runs are written twice):
  `node .aai/scripts/metrics-flush.mjs --recover-archives --include-focus --state <copy> --archive <copy>`.
- Readers fold a ride's lines into one ride: the factory report, the metrics
  report (Per Work Item, Totals, Per-Strategy Reliability) and the golden-flow
  token median group all summary lines of a `ref_id` through
  `foldRideSegments` in `.aai/scripts/lib/metrics-flush-record.mjs`; the
  dashboard's work-item count counts distinct `ref_id` values directly.
  The folded ride has the runs in ledger order, summed agent time, tokens and
  cost (null when any segment's cost is null), the largest human time of any
  segment (never the sum), summed reliability counts, the latest date and
  verdict and the first title. A ref with one line renders as before, and a
  lone continuation line (its first segment is not in the ledger) is one ride.
  The overview's per-ref effort and token sums already add every line of a
  ref; the run-level tables (per model, per role, prompt versions,
  `--by-effort`) count runs and need no folding.
- PR gate: `validation-waiver.mjs` counts one passing archive line per
  `flush_segment` (an absent field counts as 1). Two same-day pass lines for
  the archived ride with different segments are accepted; two with the same
  segment still refuse as `archive_ledger_ambiguous`.
- Codex runs carry no new fields: `codex-usage.mjs` emits the existing
  `--tokens-in/--tokens-out/--tokens-total/--harness codex` flags, and the
  provenance (source, thread, time window, attribution `thread`, `interval`
  or `run`, degraded reasons) rides in the run note. Codex's total is input
  plus output; cached input and reasoning are subsets and are never added
  again. No dollar cost is derived from Codex token counts.

## Interfaces and contracts

- `metrics-flush.mjs` — three-way per-run classification
  (decomposed | undecomposed-note | capture-missing) as INFO/WARNING; flush
  exit code unchanged (warn, never block). Carries `prompt_hash` through
  additively.
- `state.mjs log-tick` / `append-run --prompt-hash` — stderr WARNING on
  duration-0 / missing harness; `--prompt-hash` validated (bad value exits 2,
  writes nothing).
- `metrics-report.mjs` / overview — TOKENS ONLY for undecomposed totals,
  never a fabricated USD figure; overview regeneration at close is
  best-effort (a generator failure never changes the close exit code).
- `orchestration-dispatch.mjs` — `prompt_hash` (full 64-char hex) on the
  dispatch-verdict stdout JSON; absent on `no_action` / `needs_llm` verdicts.
- `.aai/scripts/codex-usage.mjs` (`observe | attribute | budget | probe`)
  over `.aai/scripts/lib/codex-rollout.mjs` — prefers Codex's per-response
  usage records (deduplicated by response id), falls back to differences of
  cumulative snapshots; a missing value is reported null with a degraded
  reason (`missing_field:<name>`, `malformed_line`, `partial_tail`), never 0.
  Budget exit codes 0 / 2 (usage) / 3 (exhausted) / 4 (not enforced).
- `.aai/scripts/lib/prompt-hash.mjs` — `computeEffectivePromptHash` /
  `componentHashes`; Node stdlib only, missing input = `ABSENT`, never
  throws.

## Limits and non-goals

- Cost in USD stays unattributable for undecomposed totals by design; no
  token estimation or in/out splitting — runtimes that expose nothing stay
  honest-null.
- Observability only: nothing enforces a prompt-hash match, and there is no
  backfill for runs recorded before the feature landed.
- Release-member matching is by exact ref form; a mismatched id form falls
  back to the close-month group.
- Ledger lines flushed before and after telemetry-fields-not-prose are
  COST-INCOMPARABLE without partitioning on `cost_basis`/`verdict_basis`
  first: a legacy note-marker-only line still carries `cost_usd: null`,
  while a later line may carry a blended estimate. Any report that sums or
  averages `cost_usd`/`total_cost_usd` across that boundary without
  partitioning treats priced and unpriced rides as the same unit.
- 24 pre-existing "stranded" work items (a merged validation PASS with no
  durable per-ref field, no matching global block, and no
  `validation_verdict` ledger event) remain unflushable by design — nothing
  durable says they passed; the honest exits are `--retire` or a fresh
  verdict, never a fabricated one.
- A closed focus with no `active_work_items` entry but recorded runs still
  dispatches a Metrics Flush that cannot act
  (`fu-4b-item-absent-with-runs-wedge`); `--sweep` still treats a close
  superseded by a reopen as closed (`fu-sweep-ignores-reopen`).

- Codex: the current thread is only known when Codex exports
  `CODEX_THREAD_ID` (or `--thread` is passed); otherwise budget reports
  `NOT enforced`. App Server `thread/tokenUsage/updated` events are not
  integrated. Roles started as separate `codex exec` processes fall outside
  the parent's budget tree. Parallel roles with overlapping windows can each
  count a sibling's usage (`interval` attribution). Follow-ups:
  `fu-codex-usage-noresp-copy-sum`, `fu-codex-usage-root-thread-label`,
  `fu-codex-attr-parallel-overlap`, `fu-codex-usage-meta-index-once`.

## Links

- Requests: docs/issues/CHANGE-0058-token-capture-canary.md,
  docs/issues/CHANGE-0070-prompt-hash-telemetry.md,
  docs/issues/CHANGE-0063-token-economics-end-to-end.md,
  docs/issues/CHANGE-0183-telemetry-fields-not-prose.md,
  docs/issues/ISSUE-0098-done-work-item-stays-in-current-focus.md,
  docs/issues/ISSUE-0106-codex-usage-missing-from-run-budgets.md
- Specs: docs/specs/SPEC-0085-spec-token-capture-canary.md,
  docs/specs/SPEC-0096-spec-prompt-hash-telemetry.md,
  docs/specs/SPEC-0089-spec-token-economics-end-to-end.md,
  docs/specs/SPEC-0178-spec-telemetry-fields-not-prose.md,
  docs/specs/SPEC-0224-spec-done-work-item-stays-in-current-focus.md,
  docs/specs/SPEC-0258-spec-codex-usage-missing-from-run-budgets.md
