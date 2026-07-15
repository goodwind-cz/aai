---
id: spec-mechanize-deterministic-ticks
type: spec
number: 19
status: implementing
links:
  change: CHANGE-0009
  research: RES-0001
  rfc: null
  pr: []
  commits: []
---

# SPEC — Mechanize Deterministic Ticks (orchestration dispatch, metrics flush, metrics report as scripts)

SPEC-FROZEN: true

## Links
- Change: CHANGE-0009 (docs/issues/CHANGE-0009-mechanize-deterministic-ticks.md)
- Research: RES-0001 finding F2 / recommendation P1.4
  (docs/specs/RES-0001-aai-competitive-gap-and-model-efficiency.md)
- Promoted follow-up: SPEC-0018 review disposition W2 (three drift-prone
  parsers of docs-audit.yaml — consolidated here, D6)
- Pattern precedent: `.aai/scripts/orchestration-mode.mjs` (RFC-0005 /
  SPEC-0005) — pure decision core, fail-closed, exportable for unit tests
- Transactional machinery precedent: `.aai/scripts/state.mjs`
  (CHANGE-0006 / SPEC-0012)
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec frozen for implementation, work not yet started (this doc)
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: as per template

## Problem (evidence-verified 2026-07-15)
1. `.aai/ORCHESTRATION.prompt.md` (181 lines) makes a premium-model agent
   evaluate a 14-rule first-match decision table over structured STATE enums —
   work `orchestration-mode.mjs` already proved is a script's job.
2. `.aai/METRICS_FLUSH.prompt.md` (113 lines) is deterministic arithmetic +
   guarded cleanup. A recent MANUAL flush made two real mistakes this spec
   must mechanically prevent:
   - a whole-file YAML re-serialization dropped STATE.yaml's commented schema
     header (broke the orchestration-mode suite's real-repo assertions);
   - datetime objects leaked into the ledger entry and broke JSON
     serialization.
3. `.aai/METRICS_REPORT.prompt.md` forbids narrative in its own rules — it is
   "jq in a trench coat" and its output is not reproducible across runs today.
4. W2 (SPEC-0018): `docs-audit.yaml` is parsed by three independent
   implementations (`state.mjs readIndependencePolicy`,
   `pre-commit-checks.sh` grep, the shell grep embedded in
   `install-pre-commit-hook.ps1`) plus an undocumented file-presence coupling
   in `docs-audit.mjs` (`lib/docs-audit-core.mjs CONFIG_PATH`) — drift-prone.
5. Queued fixture defect: `tests/skills/test-aai-docs-audit.sh` line ~3353
   (`test_change0012_regression`) hardcodes
   `docs/specs/SPEC-DRAFT-slug-refs-across-tooling.md`, a repo file DELETED at
   CHANGE-0012 number allocation (renamed to SPEC-0016). The suite aborts on
   a file that was destined to disappear by design.

## Design decisions

### D1 — `orchestration-dispatch.mjs`: pure decision core + read-only STATE snapshot builder
New `.aai/scripts/orchestration-dispatch.mjs`, same architecture as
`orchestration-mode.mjs`:

- A PURE, exported `decide(snapshot)` function implements the ORCHESTRATION
  14-rule first-match table (including SPEC-0012 G3 post-remediation reset
  routing and the rule-14 metrics-flush arm). No clock, no filesystem, no
  writes — table-driven unit-testable.
- A CLI layer builds the `snapshot` by READING (never writing) the repo:
  STATE.yaml via the shared line engine (D5), plus mechanical probes —
  `docs/TECHNOLOGY.md` present, `.aai/workflow/WORKFLOW.md` present, focus
  spec file present + `SPEC-FROZEN: true` marker + frontmatter status,
  `docs/ai/METRICS.jsonl` ref presence (rule-14 "already flushed" check),
  `.aai/system/LOCKS.md` presence.
- The script NEVER mutates STATE. Auto-init/auto-repair stays with the LLM
  wrapper (via `check-state.mjs --repair`); the script flags those states as
  LLM edges (D3). This keeps the dispatch tick side-effect-free and testable.
- Flags: `--state <path>` (default docs/ai/STATE.yaml), `--root <dir>`
  (default cwd; all probes resolve under it), `--human` (append a
  human-readable dispatch block to stderr), `--rules` (print the rule table
  derived from the SAME rule objects — single source, zero drift).
- Plain node, zero dependencies — the Codex/Gemini path runs it identically.

### D2 — Mechanical proxies per rule; judgment stays with roles or LLM edges
The prompt's judgment-flavored clauses get explicit mechanical proxies;
anything not mechanically decidable is flagged, never guessed:

| Rule | Mechanical proxy | Non-mechanical residue |
|------|------------------|------------------------|
| 1 | `project_status == paused` → no_action | — |
| 2 | `human_input.required == true` → no_action | — |
| 3 | `docs/TECHNOLOGY.md` absent → Technology extraction | "outdated" stays a Planning/role concern |
| 4 | `.aai/workflow/WORKFLOW.md` absent → Bootstrap | deeper "roles not normalized" → needs_llm |
| 5+6 | focus item `spec_path` null, spec file missing, frontmatter status not draft/implementing, or `SPEC-FROZEN: true` marker absent → Planning | "AC unmeasurable" is the Planning role's own judgment |
| 7 | `implementation_strategy.selected` missing or `undecided` → Planning | — |
| 8 | `worktree.recommendation` in {recommended, required} AND `user_decision == undecided` → Worktree gate | — |
| 9 | phase in {planning done, preparation} for the focus ref → 9a/9b/9c by `implementation_strategy.selected` (tdd / hybrid / loop) | hybrid TEST-xxx ordering inside the spec → the dispatched role reads the spec; dispatch names the role only |
| 10 | `last_validation.status == fail` → Remediation | — |
| 11 | `last_validation.status == not_run` AND focus phase in {implementation, validation, remediation, code_review} → Validation | "not run recently" for a stale pass → needs_llm (reason `validation_staleness_unknown`) |
| 12 | `code_review.status == fail` → Remediation | — |
| 13 | validation pass AND `code_review.required == true` AND status not in {pass, waived} → Code Review | "review outdated relative to diff" → needs_llm (reason `review_staleness_unknown`) |
| 14 | validation pass AND ref absent from METRICS.jsonl → Metrics flush dispatch; ref present → no_action | — |

Post-remediation reset routing (SPEC-0012 G3) is emergent from the proxies
exactly as documented: reset-to-`not_run` blocks make rules 10/12 not match
and fall through to 11/13; a recorded `pass` with only code_review reset
routes to 13, never re-fires 11. The G3 "missing reset" forensic case
(`fail` + evidence a remediation already completed) is NOT mechanically
provable → needs_llm (reason `possible_missing_remediation_reset`).

Validator independence (CHANGE-0010): when the decided role is Validation,
the dispatch block includes `validator_independence` naming the last
implementer model read from `metrics.work_items[ref].agent_runs` (same scan
as `state.mjs lastImplementerModel`) so the wrapper picks a different model.

### D3 — Dispatch output contract: JSON on stdout, closed exit codes
stdout carries EXACTLY ONE JSON object (machine-readable; the wrapper relays
it). `--human` adds the ORCHESTRATION "DISPATCH FORMAT" text block on stderr
— stdout stays parseable either way.

```
{
  "verdict": "dispatch" | "no_action" | "needs_llm",
  "rule": "1".."14" | "9a"|"9b"|"9c" | null,
  "role": "Planning" | ... | "Metrics Flush" | null,
  "ref_id": "<focus ref or null>",
  "system_prompt": "<prompt path when the rule names one, else null>",
  "inputs": [ "<paths the role needs>" ],
  "expected_outputs": [ ... ],
  "stop_condition": "<one line>",
  "suggested_tier": "mechanical" | "standard" | "premium" | null,
  "validator_independence": { "implementer_model": "<id|null>",
                              "must_differ": true } | null,
  "reasons": [ "<named, machine-greppable reason strings>" ],
  "state_summary": { "<the snapshot fields the decision read>" }
}
```

Exit codes (closed contract):
- 0 — dispatch emitted (verdict `dispatch`)
- 3 — no action required (verdict `no_action`: paused, human gate, flushed)
- 4 — LLM must take over (verdict `needs_llm`): missing/invalid/unrepaired
  STATE (missing file, duplicate top-level keys, unknown enum value, missing
  required block), auto-init/repair needed, or a flagged judgment edge. The
  JSON still prints with named `reasons` — this is AC-002's fail-closed
  degrade-and-report: non-zero + named reason, prompt path takes over.
- 2 — usage error (unknown flag, unreadable --state path argument shape)
- 1 — internal error (unexpected exception; nothing was written — the script
  never writes)

Tier suggestion mapping (from ORCHESTRATION MODEL SELECTION): Planning /
Code Review → premium; Implementation / TDD / Remediation / Validation →
standard; Technology extraction / Bootstrap / Worktree gate / Metrics flush
→ mechanical.

### D4 — Flush is a standalone `metrics-flush.mjs`, NOT a `state.mjs` subcommand
Justification (the CHANGE left this open):
- `state.mjs` is a closed-contract SINGLE-FILE mutator: every subcommand
  edits one STATE.yaml block and the exit-code contract (0/1/2) is documented
  around that. Flush is a MULTI-FILE transaction (METRICS.jsonl append +
  STATE whole-block removals + EVENTS.jsonl best-effort + ephemeral file
  deletion + PRICING/LOOP_TICKS reads) with its own partial-failure states —
  bolting it on would muddy both contracts.
- METRICS_FLUSH.prompt.md itself documents that WHOLE-BLOCK REMOVALS are
  "outside the transactional CLI's mutation surface". That exclusion is
  deliberate (guard ownership); a separate script can own them with the same
  engine without widening state.mjs's surface.
- `state.mjs` calls `main()` unconditionally at module top level — it is not
  importable. Therefore D5.

### D5 — Extract the line engine to `lib/state-engine.mjs`; NEVER re-serialize STATE
The block/line engine currently private to state.mjs (`findBlock`,
`ensureBlock`, `editBlock`, `fieldSpan`, `setField`, `readScalar`,
`nullFieldIfPresent`, `indentOf`, `scalarLine`, `textFieldLines`,
`listFieldLines`, `yq`/`needsQuoting`, `unquoteScalar`, `loadState`,
`writeState` (atomic tmp + concurrency recheck + rename), `bumpUpdatedAt`,
`nowIso`) moves to `.aai/scripts/lib/state-engine.mjs`; `state.mjs` imports
it back (behavior byte-identical — the existing 41-test state suite guards
the refactor). `metrics-flush.mjs` imports the same engine.

Flush STATE cleanup is SURGICAL LINE EDITS ONLY — remove the flushed
`metrics.work_items.<ref>` entry lines, remove done `active_work_items`
items, remove the `metrics:` block when it empties — never `yaml.dump` of
the whole file. The commented schema header and all untouched lines survive
byte-identical by construction (mechanically closes manual-flush mistake #1).
The ledger entry is built exclusively from strings/numbers/nulls read off
lines — no Date objects are ever placed in the entry (closes mistake #2);
a unit guard asserts `JSON.parse(JSON.stringify(entry))` deep-equals entry.

### D6 — `metrics-flush.mjs` semantics: METRICS_FLUSH.prompt.md, verbatim, transactional
Implements the documented algorithm 1:1:
- Criteria: validation PASS/CANCELLED; review pass/waived when required;
  ≥1 agent_run; ref not already in METRICS.jsonl.
- Human review time: sum `review_duration_seconds` of LOOP_TICKS
  `human_resume` lines, minutes rounded up; a non-null STATE `reviews` value
  wins (human override).
- Cost: model_id resolved via PRICING.yaml `lookup_rules` IN ORDER
  (strip-bracket-suffix → model_aliases → exact → longest-prefix → unknown;
  CHANGE-0010 D5); cost only when both tokens present; null tokens → null
  cost + one VISIBLE WARNING line per run (never aggregated).
- Timing fidelity: started/ended present + ISO-parseable, duration equals
  delta ±1s, not >300s future — else duration_seconds null, never estimated.
- ORDERING (mandatory): build + validate everything in memory FIRST (the
  mutated STATE must pass check-state invariants pre-commit), then append the
  ledger line(s), then commit STATE via atomic tmp+rename with the
  concurrency recheck, then events (best-effort), then ephemeral cleanup.
  Ledger-before-reset is preserved; a crash between ledger append and STATE
  commit leaves STATE original (AC-003 "original preserved on failure").
- IDEMPOTENT RESUME: a ref already IN the ledger but still present in
  STATE `metrics.work_items` is detected as an interrupted flush → cleanup-
  only pass (no second append, no duplicate ledger line).
- Full reset (5d) via the engine's field edits when NO active work remains;
  partial-flush reset (5d2, SPEC-0013 H5) resets verdict blocks + nulls the
  leaked fields exactly as documented (flush-provenance notes, never
  reset-block's remediation marker).
- Ephemeral cleanup (6a-d) only on full reset; the protected set
  (METRICS.jsonl, decisions.jsonl, STATE.yaml, published/) is a hard
  constant.
- Events (7): `doc_lifecycle` + `work_item_closed` via append-event.mjs,
  best-effort.
- After the STATE commit the script runs check-state.mjs (subprocess) and
  reports its verdict; a red check-state after commit is exit 1 with the
  pre-flush STATE content saved to `<state>.pre-flush-<ts>` for recovery.
- Flags: `--state/--metrics/--ticks/--pricing/--events <path>` (fixture
  injection), `--ref <id>` (restrict), `--dry-run` (print the full plan JSON,
  write nothing), `--now <ISO>` (test-only clock pin; env
  `AAI_FLUSH_NOW` equivalent).
- Exit codes: 0 flushed (or nothing to flush — report says which), 1
  integrity refusal / post-commit check failure (original preserved or
  recovery file named), 2 usage.
- `.aai/METRICS_FLUSH.prompt.md` reduces to a wrapper: run the script, relay
  its report, handle exit 1 by surfacing the named reason (LLM never
  re-implements the arithmetic).

### D7 — `metrics-report.mjs`: byte-deterministic aggregation
- Reads METRICS.jsonl (+ PRICING.yaml for null-cost fill on known tokens,
  same `lookup_rules` resolver as flush — shared function, D8), writes the
  exact METRICS_REPORT.prompt.md markdown (Per Work Item / Totals / Per Model
  Breakdown) to stdout. No file writes, no clock, no locale: fixed
  `toFixed(2)` USD, leverage `x.x`x with one decimal, ledger order for rows,
  per-model table sorted lexicographically by model_id, `~` prefix on
  partial costs, "No metrics recorded yet." on an empty/comment-only ledger.
  Identical input bytes → identical output bytes (AC-004 golden-testable).
- Flags: `--metrics/--pricing <path>`. Exit 0 incl. empty ledger; 2 usage;
  1 unreadable/corrupt ledger line (named line number).
- `.aai/METRICS_REPORT.prompt.md` reduces to a wrapper.

### D8 — Config reader consolidation (SPEC-0018 W2): YES — one shared JS reader
New `.aai/scripts/lib/guard-config.mjs`: `readGuardConfig(dir)` → column-0
line scan of `<dir>/docs-audit.yaml` returning
`{ present, independence, close_gate, doc_number_guard, raw }` with the
documented fail-open defaults and the invalid-value stderr WARNING semantics
currently in `state.mjs readIndependencePolicy`. Consumers:
- `state.mjs` (replaces its private `readIndependencePolicy`)
- `metrics-flush.mjs` / `orchestration-dispatch.mjs` (any guard dial reads)
- `docs-audit.mjs` mode detection documents the coupling by importing the
  same `present` probe (CONFIG_PATH stays in docs-audit-core.mjs; the core
  re-exports through the shared reader).
The SHELL greps in `pre-commit-checks.sh` / `install-pre-commit-hook.ps1`
stay as deliberate thin greps (hooks must not grow importable-module
plumbing) but each gains a comment naming `lib/guard-config.mjs` as
canonical, and a CONFORMANCE TEST feeds the same fixture configs to the
reader and the grep patterns and asserts they agree (drift now fails a test
instead of diverging silently).

### D9 — Prompts become thin wrappers (≤40 lines each, AC-005)
- `.aai/ORCHESTRATION.prompt.md`: run
  `node .aai/scripts/orchestration-dispatch.mjs --human`; on exit 0 relay/
  execute the dispatch (spawn per SUBAGENT_PROTOCOL, honoring
  `suggested_tier` + `validator_independence`); on exit 3 report no-action
  and stop; on exit 4 read `reasons` and handle ONLY the flagged edges
  (auto-init/repair via `check-state.mjs --repair` then re-run the script
  ONCE; staleness judgments; missing-reset forensics per STATE_FALLBACK.md);
  update STATE via state.mjs before stopping, exactly as today. DEGRADE
  path: if the script file is absent (older vendored layer), report
  DEGRADED and fall back to `.aai/workflow/WORKFLOW.md` + STATE manually —
  the rule table's single source is the script (`--rules` prints it);
  the prompt no longer contains the table (CHANGE-0009 constraint).
- `.aai/METRICS_FLUSH.prompt.md`: run `node .aai/scripts/metrics-flush.mjs`,
  relay report + WARNING lines, handle exit 1 reasons; degrade-and-report if
  absent (do NOT hand-flush; surface human_input instead — hand-flushing is
  the documented failure mode this spec exists to kill).
- `.aai/METRICS_REPORT.prompt.md`: run `node .aai/scripts/metrics-report.mjs`
  and print its stdout verbatim; degrade-and-report if absent.
- Measurable: `wc -l` ≤ 40 for each of the three files; each names its
  script path and its degrade instruction.

### D10 — Fixture fix: docs-audit suite constructs its own DRAFT
`tests/skills/test-aai-docs-audit.sh test_change0012_regression` stops
referencing the deleted repo file: the "live DRAFT spec is scanned
non-vacuously" stanza writes its OWN `SPEC-DRAFT-<slug>.md` fixture inside
the isolated repo (`write_c12_doc`), runs
`docs-audit.mjs --check --strict --no-event --path docs/specs/SPEC-DRAFT-<slug>.md`
there, and keeps asserting `Scanned: 1 docs`. The real-repo full-audit
stanza (no --path) stays. The regression intent (DRAFT docs join the scan
set, `--path <DRAFT>` non-vacuous) is preserved without depending on any
repo file destined to be renamed at allocation.

## Implementation strategy
- Strategy: tdd
- Rationale: every deliverable is a pure deterministic function or a closed
  CLI contract with a natural RED today — the dispatch script does not
  exist (14 fixture STATEs fail), flush golden files fail, the report is
  not byte-stable, wrappers exceed 40 lines, and the docs-audit suite
  currently aborts on the deleted DRAFT path. RED proof is cheap and
  non-tautological; the engine extraction (D5) is guarded by the existing
  green state suite (refactor leg).

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: single active stream (no parallel race), additive new
  scripts + new test suites; the one risky touch — extracting the line
  engine out of state.mjs, the loop's live write path — is fully guarded by
  the existing 41-test state suite, and prompt edits are reversible text.
  Isolation is useful (live write path) but not safety-critical: optional,
  not recommended. Operator decides at preparation.
- User decision: undecided
- Base ref: main
- Inline review scope (if inline): .aai/scripts/orchestration-dispatch.mjs,
  .aai/scripts/metrics-flush.mjs, .aai/scripts/metrics-report.mjs,
  .aai/scripts/lib/state-engine.mjs, .aai/scripts/lib/guard-config.mjs,
  .aai/scripts/state.mjs, .aai/scripts/docs-audit.mjs (present-probe import
  only), .aai/ORCHESTRATION.prompt.md, .aai/METRICS_FLUSH.prompt.md,
  .aai/METRICS_REPORT.prompt.md, tests/skills/

## Acceptance Criteria Mapping
- Maps to CHANGE-0009 AC-001 → Spec-AC-01 (dispatch table), Spec-AC-02
  (reset routing)
- Maps to CHANGE-0009 AC-002 → Spec-AC-03 (fail-closed degrade)
- Maps to CHANGE-0009 AC-003 → Spec-AC-04..06 (flush correctness,
  transactionality, header preservation)
- Maps to CHANGE-0009 AC-004 → Spec-AC-07 (report determinism)
- Maps to CHANGE-0009 AC-005 → Spec-AC-08 (wrappers + suites green)
- Maps to SPEC-0018 W2 promotion → Spec-AC-09 (config consolidation)
- Maps to queued fixture defect → Spec-AC-10 (suite self-containment)

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | `orchestration-dispatch.mjs decide()` reproduces all 14 rules first-match over fixture snapshots; CLI emits the D3 JSON + exit code for fixture STATE files | done | tests/skills/test-aai-orchestration-dispatch.sh TEST-001/002/005 green (docs/ai/tdd/green-20260715T204758Z-change0009-all-suites.log) | — | — |
| Spec-AC-02 | Post-remediation reset routing (SPEC-0012 G3): 3 fixture cases route 10→11 fresh Validation, 12→13 fresh Code Review, pass+review-reset→13 (11 must NOT re-fire) | done | TEST-003 reset-routing fixtures green (same log) | — | — |
| Spec-AC-03 | Unknown/invalid/missing STATE and judgment edges degrade fail-closed: exit 4, named reasons in JSON, zero writes; wrapper path documented to take over | done | TEST-004 exit-4 + named reasons + zero writes green (same log) | — | — |
| Spec-AC-04 | Flush entry correctness: criteria gates, PRICING lookup_rules cost (incl. `[1m]` strip, alias, longest-prefix, unknown), timing fidelity ±1s, per-run null-token WARNING lines, ledger schema match | done | tests/skills/test-aai-metrics.sh TEST-006..009 green (same log) | — | — |
| Spec-AC-05 | Flush transactionality: ledger-before-reset ordering; in-memory pre-validation; original STATE preserved on injected failure; idempotent cleanup-only resume; check-state green after flush; partial-flush H5 + full-reset + ephemeral cleanup per prompt | done | TEST-011/012/013 green: H5 partial reset, full reset + cleanup, crash resume (same log) | — | — |
| Spec-AC-06 | Flush edits are line-surgical: STATE commented schema header + untouched lines byte-identical after flush; no whole-file YAML serialization anywhere; no Date objects in ledger entries | done | TEST-010 green + mutation RED vs yaml.dump-style rewrite (docs/ai/tdd/red-20260715T202712Z-change0009-test010-yamldump-mutation.log) | — | — |
| Spec-AC-07 | `metrics-report.mjs` output byte-identical across repeated runs on a fixed ledger fixture (golden file), incl. partial-cost `~`, per-model table, empty-ledger message | done | TEST-014 report golden byte-identical twice (same green log) | — | — |
| Spec-AC-08 | ORCHESTRATION / METRICS_FLUSH / METRICS_REPORT prompts each ≤40 lines (`wc -l`), name their script + degrade instruction; ALL existing suites green | done | TEST-015 wrappers 40/31/15 lines + TEST-016 sweep all suites green (same green log) | — | — |
| Spec-AC-09 | `lib/guard-config.mjs` is the single JS parser of docs-audit.yaml (state.mjs migrated, behavior-identical incl. invalid-value WARNING); conformance test proves shell greps agree on fixtures | done | TEST-017 test_052 + TEST-018 conformance green (same green log) | — | — |
| Spec-AC-10 | test-aai-docs-audit.sh constructs its own DRAFT fixture; suite passes with no dependence on repo DRAFT files | done | TEST-019 docs-audit suite full run 92 PASS exit 0 (same green log) | — | — |

Status values: planned | implementing | done | deferred | blocked | rejected
(gate behavior per template: any planned/implementing AC blocks PASS; done
requires non-empty Evidence; deferred/blocked require future Review-By).

## Implementation plan
- Components:
  1. `.aai/scripts/lib/state-engine.mjs` — engine extraction (D5);
     `state.mjs` re-imports (no behavior change).
  2. `.aai/scripts/lib/guard-config.mjs` — shared docs-audit.yaml reader
     (D8); migrate `state.mjs`; docs-audit core re-export.
  3. `.aai/scripts/orchestration-dispatch.mjs` — pure `decide()` export +
     snapshot builder + CLI (D1-D3).
  4. `.aai/scripts/metrics-flush.mjs` (D6).
  5. `.aai/scripts/metrics-report.mjs` (D7).
  6. Prompt wrappers (D9).
  7. Fixture fix in tests/skills/test-aai-docs-audit.sh (D10).
  8. New suites: tests/skills/test-aai-orchestration-dispatch.sh,
     tests/skills/test-aai-metrics.sh (flush + report; golden fixtures under
     the suite's own scratch/fixture heredocs — no repo-file dependence).
- Data flows: STATE.yaml --(line engine, read-only)--> snapshot --(pure
  decide)--> dispatch JSON; STATE.yaml + LOOP_TICKS + PRICING --(flush)-->
  METRICS.jsonl append + surgical STATE cleanup + EVENTS; METRICS.jsonl +
  PRICING --(report)--> stdout markdown.
- Edge cases: interrupted flush resume; concurrent STATE writer during flush
  commit (engine recheck → exit 1, ledger line already durable → resume);
  bracketed model ids; comment/blank ledger lines; multi-item partial flush
  where focus ref is flushed but others remain (H5); dispatch on a repo with
  no scripts (wrapper degrade path); YAML-keyword slug refs never regexed
  (exact-string entry match, as in lastImplementerModel).

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Status |
|----------|------------|------|----------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | unit | tests/skills/test-aai-orchestration-dispatch.sh | Table-driven: 14 fixture snapshots (one per rule, first-match order asserted by layering multiple matches) → expected verdict/rule/role/tier from exported `decide()` | green |
| TEST-002 | Spec-AC-01 | int  | tests/skills/test-aai-orchestration-dispatch.sh | CLI on fixture STATE files in an iso repo: D3 JSON shape on stdout, exit 0/3 per fixture, `--human` stderr block, `--rules` prints table | green |
| TEST-003 | Spec-AC-02 | int  | tests/skills/test-aai-orchestration-dispatch.sh | 3 reset-routing fixtures: post-remediation not_run→rule 11 Validation; review-reset→rule 13; pass+review-reset must dispatch 13 and NOT re-fire 11 | green |
| TEST-004 | Spec-AC-03 | int  | tests/skills/test-aai-orchestration-dispatch.sh | Missing STATE, duplicate top-level key, unknown enum, judgment edges (staleness, missing-reset forensics) → exit 4 + named reason; STATE/file mtimes untouched (no writes) | green |
| TEST-005 | Spec-AC-01 | int  | tests/skills/test-aai-orchestration-dispatch.sh | Rule 14 arm: PASS + ref absent from ledger → Metrics Flush dispatch; ref present → no_action exit 3; Validation dispatch carries validator_independence with implementer model | green |
| TEST-006 | Spec-AC-04 | int  | tests/skills/test-aai-metrics.sh | Flush happy-path golden: fixture STATE+TICKS+PRICING → exact ledger JSON line (cost via strip-`[1m]`, alias, longest-prefix, unknown→null fixtures) | green |
| TEST-007 | Spec-AC-04 | int  | tests/skills/test-aai-metrics.sh | Timing fidelity: unparseable/missing timestamps, delta≠duration beyond ±1s, >300s-future stamps → duration_seconds null, never estimated | green |
| TEST-008 | Spec-AC-04 | int  | tests/skills/test-aai-metrics.sh | Criteria negatives: FAIL verdict, review required+not_run, zero agent_runs, already-in-ledger(+absent from STATE) → skipped, each with a named reason in the report | green |
| TEST-009 | Spec-AC-04 | int  | tests/skills/test-aai-metrics.sh | Null-token runs: one VISIBLE WARNING line per run, never aggregated; cost_usd stays null; totals cost null when any run null | green |
| TEST-010 | Spec-AC-06 | int  | tests/skills/test-aai-metrics.sh | Header preservation: STATE commented schema header + all untouched blocks byte-identical after flush (diff of masked regions); check-state green; orchestration-mode suite still green on the flushed file shape | green |
| TEST-011 | Spec-AC-05 | int  | tests/skills/test-aai-metrics.sh | Partial-flush H5: flushed focus ref + other active items → verdict blocks reset with flush-provenance notes, leaked fields nulled, other work_items entries untouched | green |
| TEST-012 | Spec-AC-05 | int  | tests/skills/test-aai-metrics.sh | Full reset + ephemeral cleanup: LOOP_TICKS deleted, >30d validation reports pruned, LATEST.md + protected set never deleted; cleanup skipped when work remains | green |
| TEST-013 | Spec-AC-05 | int  | tests/skills/test-aai-metrics.sh | Transactionality: injected crash between ledger append and STATE commit (env hook) → STATE original byte-identical; re-run performs cleanup-only resume, NO duplicate ledger line; --dry-run writes nothing | green |
| TEST-014 | Spec-AC-07 | int  | tests/skills/test-aai-metrics.sh | Report golden: fixed ledger fixture run twice → byte-identical output equal to committed golden; `~` partial marker; per-model lex ordering; empty ledger message exit 0 | green |
| TEST-015 | Spec-AC-08 | unit | tests/skills/test-aai-prompt-diet.sh (extend) | Each of the 3 prompts ≤40 lines and contains its script path + degrade instruction token | green |
| TEST-016 | Spec-AC-08 | e2e  | tests/skills/ (full run via aai-run-tests) | All existing suites green after engine extraction + prompt shrink (state 41/41, docs-audit, orchestration-mode, check-state, pricing, prompt-diet) | green |
| TEST-017 | Spec-AC-09 | unit | tests/skills/test-aai-state.sh (extend) | guard-config reader: absent file / absent key / report-only / enforce / invalid value (stderr WARNING + fail-open) — behavior identical to pre-refactor state.mjs stanzas | green |
| TEST-018 | Spec-AC-09 | unit | tests/skills/test-aai-hygiene-pack.sh (extend) | Conformance: fixture docs-audit.yaml variants → shared reader verdicts agree with pre-commit-checks.sh / install-pre-commit-hook.ps1 grep patterns | green |
| TEST-019 | Spec-AC-10 | int  | tests/skills/test-aai-docs-audit.sh | Regression stanza builds its own SPEC-DRAFT fixture in the iso repo; `--check --strict --no-event --path <DRAFT>` scans 1 doc; grep proves no repo SPEC-DRAFT path remains hardcoded in the suite | green |

Test status values: pending → red → green. Every Spec-AC has ≥1 TEST; IDs
stable after freeze.

## Verification
- `bash tests/skills/test-aai-orchestration-dispatch.sh` (TEST-001..005)
- `bash tests/skills/test-aai-metrics.sh` (TEST-006..014)
- `bash tests/skills/test-aai-prompt-diet.sh`, `wc -l .aai/ORCHESTRATION.prompt.md .aai/METRICS_FLUSH.prompt.md .aai/METRICS_REPORT.prompt.md` (TEST-015)
- `bash .aai/scripts/aai-run-tests.sh` full sweep (TEST-016)
- `bash tests/skills/test-aai-state.sh`, `bash tests/skills/test-aai-hygiene-pack.sh` (TEST-017/018)
- `bash tests/skills/test-aai-docs-audit.sh` (TEST-019)
- End-to-end (CHANGE-0009 Verification): one loop tick on a fixture STATE —
  script dispatch JSON names the same role the prompt-driven path chose for
  the same STATE (recorded as evidence, not an automated assertion).
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
ref_id, Spec-AC + TEST-xxx links, command/review scope, exit code or verdict,
evidence path under docs/ai/tdd/ or docs/ai/reports/, commit SHA or diff
range.

Notes:
This document defines HOW, not WHAT/WHY. It does not define workflow.

## Review warning dispositions (2026-07-15)

- W1 (vacuous self-containment guard in test-aai-docs-audit.sh — relative
  BASH_SOURCE unresolvable after cd; naive fix would self-match the comment):
  REMEDIATED — absolute SUITE_FILE captured pre-cd, readability assert added,
  explanatory comment de-literalized.
- W2 (guard-config split-brain: hooks' greps were indent-tolerant while the
  reader is column-0; glued-comment token diverged; variants untested):
  REMEDIATED — hook greps anchored to column 0 (canonical-reader semantics),
  reader token parse aligned to the grep boundary (glued comment -> invalid ->
  warn + report-only), conformance test extended with indented/glued/quoted/
  CRLF variants.
- W3 (flush resume path deletes a re-opened ref's new metrics without
  appending): PROMOTED — follow-up candidate; not a regression vs the old
  prompt; the resume path requires an interrupted flush AND a same-ref reopen
  to trigger.
- W4 (refMatches flush criterion + full-reset can strand done-but-unflushed
  sibling metrics): PROMOTED with an operational note — the operator flushes
  or archives sibling metrics before the first real script flush; the
  CHANGE-0010/0011 planning runs recorded on main's STATE are handled exactly
  so at this scope's closeout (archive-merge into the ledger, as done for
  RFC-0007). Follow-up: widen the criterion or make full-reset refuse when
  unflushed sibling metrics remain.
