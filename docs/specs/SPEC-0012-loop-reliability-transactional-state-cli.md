---
id: SPEC-0012
type: spec
status: done
links:
  change: CHANGE-0006
  rfc: null
  requirement: null
  pr: []
  commits: []
---

# SPEC-0012 — Loop reliability: transactional STATE CLI, remediation transition reset, implementer AC-table reconciliation (CHANGE-0006)

SPEC-FROZEN: true

## Links
- Change request (WHAT/WHY): docs/issues/CHANGE-0006-loop-reliability-state-cli.md
- STATE validator being reused/extended: .aai/scripts/check-state.mjs (ISSUE-0004 / SPEC-0010 Group B)
- CLI conventions mirrored: .aai/scripts/append-event.mjs (closed sets, exit 2 on bad input)
- Close gate consumed by G4: .aai/scripts/docs-audit.mjs --gate (SPEC-0011 G1)
- Sibling precedent for isolation/strategy posture: docs/specs/SPEC-0010-docs-index-and-state-tooling-robustness.md, docs/specs/SPEC-0011-docs-audit-closeout-guardrails.md
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec frozen for implementation, work not yet started (this doc)
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: standard meanings per template

## Scope

Close the "runtime state is edited as free text by LLMs" defect class from
CHANGE-0006 (2026-07-04 skills audit + CHANGE-0005 live-run evidence):

- G1 — transactional STATE CLI `.aai/scripts/state.mjs` (load → mutate → atomic
  rewrite → internal duplicate-key check; exit non-zero on invalid enum/shape).
- G2 — migrate the STATE-mutation instructions in nine prompts to `state.mjs`
  calls with an explicit degrade-gracefully fallback for vendored projects.
- G3 — Remediation closes by RESETTING the failed block (`reset-block`) and never
  writes its own validation/review verdict; ORCHESTRATION documents the reset so
  rules 11/13 dispatch a fresh independent Validation / Code Review.
- G4 — IMPLEMENTATION and SKILL_TDD gain a pre-handoff AC-table reconciliation
  step including a `docs-audit.mjs --gate <SPEC-ID>` self-check (exit 0 before
  reporting complete).

WHAT/WHY lives in CHANGE-0006; this doc defines HOW.

Out of scope (per CHANGE-0006): automatic token/cost capture from the harness;
rewriting the ORCHESTRATION decision table beyond the reset note; downstream
vendored-project migration (ships via aai-update); a `state.mjs init`
auto-creation mode (STATE auto-init remains the prompt-guided path in
`.aai/ORCHESTRATION.prompt.md:66-69`; every `state.mjs` command exits 2 when
STATE.yaml is absent).

## Problem summaries (verified against live code, 2026-07-04)

### G1/G2 — every role prompt hand-edits STATE.yaml as free text
Verified hand-edit sites (the intake's approximate lines confirmed):
- `.aai/PLANNING.prompt.md:91-97` (step 11 STATE update), `:128-142` (METRICS
  agent_runs append), `:146-153` (STATE-WRITE SAFETY postscript).
- `.aai/IMPLEMENTATION.prompt.md:96-101` (step 10), `:148-162` (METRICS),
  `:166-173` (safety postscript).
- `.aai/VALIDATION.prompt.md:156-164` (step 9), `:210-224` (METRICS), `:228-235`
  (safety postscript).
- `.aai/REMEDIATION.prompt.md:30-35` (step 5), `:45-59` (METRICS), `:63-70`
  (safety postscript).
- `.aai/SKILL_TDD.prompt.md:123-134` (RED tdd_cycle YAML edit), `:195-206`
  (GREEN), `:259-272` (REFACTOR), `:321-330` (cycle clean), `:475-500`
  (agent_runs append + safety).
- `.aai/ORCHESTRATION.prompt.md:130-142` (metrics auto-init), `:147-155`
  (mandatory STATE update before stopping).
- `.aai/ORCHESTRATION_PARALLEL.prompt.md:101-105` (state update summary),
  `:114-120` (single-writer merge + write).
- `.aai/METRICS_FLUSH.prompt.md:42-55` (step 5 STATE cleanup incl. metrics key
  removal and block resets).
- `.aai/SKILL_LOOP.prompt.md:210-213` (orchestration.mode/k/groups record),
  `:284-301` (step 6 tick-line append to LOOP_TICKS.jsonl), `:148-149`
  (`type: recovery` line), `:158-160` and `:172-174` (human_input writes).
`check-state.mjs` exists precisely because this already corrupted state
(ISSUE-0004 duplicate `metrics:`); in the CHANGE-0005 run a timestamp regex edit
hit the schema comment line (`docs/ai/STATE.yaml:16` `#   updated_at_utc: ...`)
instead of the real top-level `updated_at_utc:` field.

### G3 — FAIL → Remediation has no transition reset (remediation loop / self-validation)
`.aai/ORCHESTRATION.prompt.md:92` (rule 10, `latest validation FAIL →
Remediation`) precedes `:93` (rule 11, dispatch Validation) and nothing resets
`last_validation.status` to `not_run`, so after Remediation the next tick
re-matches rule 10. The only documented escape is
`.aai/REMEDIATION.prompt.md:28-29` step 4 ("Re-run validation...") plus step 5
writing `last_validation` itself — self-validation, violating the independence
rules at `.aai/VALIDATION.prompt.md:13-25` and `.aai/SKILL_LOOP.prompt.md:223-233`.
Same defect for `code_review.status: fail` (rule 12 at `:94` vs rule 13 at
`:95-98`). Observed live: the operator hand-reset the status between CHANGE-0005
ticks 5 and 6.

### G4 — implementer never reconciles the AC table (guaranteed wasted tick)
Neither `.aai/IMPLEMENTATION.prompt.md` (steps 7-10; step 8 only flips Test Plan
rows to `green`) nor `.aai/SKILL_TDD.prompt.md` (Phase 4, `:295-330`) instructs
reconciling the spec's `## Acceptance Criteria Status` table (status + Evidence
per row). The table is first enforced by VALIDATION's AC-STATUS GATE
(`.aai/VALIDATION.prompt.md:47-92`), so a gate-opted spec reaches Validation with
`planned` rows → guaranteed FAIL → one full Remediation + re-Validation cycle
per work item (observed: CHANGE-0005 ticks 4-6, ~15 min + 2 subagent runs).

### Log/metrics lines are hand-authored JSON/YAML
`docs/ai/LOOP_TICKS.jsonl` lines and `metrics.work_items[].agent_runs` entries
are authored as free text by the model (schema at `.aai/SKILL_LOOP.prompt.md:286-298`;
observed real lines carry: `type, tick, role, scope, started_utc, ended_utc,
duration_seconds, exit_code, focus_ref_id_before/after,
validation_status_before/after, orchestration_mode, orchestration_k,
harness_version`, with observed `duration_seconds: null` — the model cannot
subtract timestamps reliably and must not estimate).

## Design decisions (load-bearing — read before implementing)

### D1 — subcommand surface and exit codes (closed sets, mirroring append-event.mjs)
`node .aai/scripts/state.mjs <subcommand> [flags]`. Default STATE path
`docs/ai/STATE.yaml`, overridable with `--state <path>`; default ticks path
`docs/ai/LOOP_TICKS.jsonl`, overridable with `--ticks <path>` (fixture-repo
testing per CHANGE-0006 constraint — tests never touch real runtime files).

The intake's seven required subcommands, plus four ADDITIVE ones without which
the nine prompts cannot drop free-text edits (AC-003 is unattainable without
them — SKILL_TDD edits `tdd_cycle`, PLANNING/ORCHESTRATION edit
strategy/worktree blocks, SKILL_LOOP/ORCHESTRATION edit `human_input`):

1. `set-focus --type <intake_change|intake_issue|intake_prd|intake_hotfix|intake_research|intake_rfc|intake_release|technology_extraction|maintenance|none> --ref <ID> --path <p>`
   (`--type none` permits omitted/null ref+path).
2. `set-phase --ref <ID> --phase <planning|preparation|implementation|validation|code_review|remediation> [--status <planned|in_progress|blocked|done>] [--path <p>] [--spec-path <p>]`
   — upserts the `active_work_items` entry (matches ORCHESTRATION auto-init policy).
3. `set-validation --status <pass|fail|not_run> [--ref <id>] [--evidence <path>]... [--notes <text>]`
   — self-stamps `run_at_utc` from the system clock.
4. `set-code-review [--status <not_run|pass|fail|waived>] [--required <true|false>] [--scope <text>] [--base-ref <r>] [--head-ref <r>] [--report <path>]... [--notes <text>]` (≥1 flag required).
5. `append-run --ref <ID> --role <Planning|Implementation|TDD Implementation|Validation|Code Review|Remediation|Orchestration|Metrics Flush> --model <id> --started <ISO-UTC> [--note <text>] [--tokens-in N] [--tokens-out N] [--tdd-tests N]`
   — `started_utc` is supplied (captured at role start via `date -u`);
   `ended_utc` is SELF-STAMPED from the system clock at invocation;
   `duration_seconds` computed; `tokens_*` default null, `cost_usd` always
   null (auto-capture out of scope); AUTO-INITS a missing
   `metrics.work_items.<ref>` entry (with `human_time_minutes` nulls) and
   converts an inline `agent_runs: []` to block form without duplicating the key.
6. `log-tick --tick N --role <text> --scope <ref> --started <ISO-UTC> [--exit-code N] [--focus-before X] [--focus-after X] [--validation-before X] [--validation-after X] [--mode <single|parallel>] [--k N] [--harness <v>] [--type <tick|recovery>] [--tokens-in N] [--tokens-out N] [--cache-read N] [--cost X] [--lingering-procs N] [--free-memory X]`
   — appends one JSONL line to LOOP_TICKS.jsonl (see D7); does NOT touch STATE.yaml.
7. `reset-block <last_validation|code_review> [--force]` — see D6.
8. (additive) `set-strategy --selected <loop|tdd|hybrid|undecided> [--source <path>] [--rationale <text>]`.
9. (additive) `set-worktree [--recommendation <not_needed|optional|recommended|required>] [--user-decision <undecided|worktree|inline|waived>] [--base-ref <r>] [--branch <b>] [--path <p>] [--inline-scope <text>] [--rationale <text>]` (≥1 flag required).
10. (additive) `set-tdd-cycle --status <IDLE|RED|GREEN|REFACTOR_COMPLETE> [--test-id <TEST-xxx>] [--spec-path <p>] [--test-path <p>] [--red <p>] [--green <p>] [--refactor <p>]`
    (`IDLE` nulls all fields — the SKILL_TDD cycle-clean shape).
11. (additive) `set-human-input --required <true|false> [--question <text>] [--reason <text>]`.

Exit codes (closed contract):
- **0** — success, including idempotent no-ops (e.g. resetting an already-`not_run` block).
- **1** — integrity refusal: the file is ALREADY corrupt (duplicate top-level
  key pre-edit → refuse to compound, point at `check-state.mjs --repair`) or the
  mutated content would fail the duplicate-key check. Original file preserved
  byte-identical.
- **2** — usage/validation error before any write: unknown subcommand, invalid
  enum value, unknown block name, missing required flag, `--ref` not matching
  `^[A-Z]+-\d+$`, malformed/`>300s`-future ISO timestamp, or missing STATE file.
Mirrors `append-event.mjs` (`fail(msg, 2)` at `:49-52`, closed `EVENT_TYPES` at
`:26`) and `check-state.mjs` (exit 1 detection / exit 2 missing file).

Every STATE-mutating subcommand also bumps the REAL top-level `updated_at_utc:`
field (column-0 key match per `check-state.mjs` `TOP_KEY_RE` at `:31` — a `#`
comment line can never match, which mechanically closes the CHANGE-0005
timestamp-regex mishap class). `log-tick` never bumps STATE.

### D2 — no YAML library: structural line-edit engine (comments/key order preserved by construction)
The repo ships no package manifest and no YAML dependency (docs/TECHNOLOGY.md;
`check-state.mjs` is deliberately a pure text scan). `state.mjs` therefore does
NOT parse/re-emit YAML: it locates the target top-level block by column-0 key
(reusing the block-range discipline of `check-state.mjs
metricsBlockRanges`/`TOP_KEY_RE`), edits only the lines inside that block
(scalar line replace, list-item splice, block append), and leaves every other
line byte-identical. Consequences (these are the normalization rules to
document): the commented schema header (`docs/ai/STATE.yaml:1-23`) and all key
order survive verbatim by construction; multi-line text values are written as
`>-` block scalars at the existing 2-space-step indentation; fields the command
does not name are left untouched. A full-file diff after any command touches
only the target block plus the `updated_at_utc` line.

### D3 — atomic write: temp file + rename, pre-rename integrity check, deterministic crash injection
Write path for every STATE mutation: (1) run the duplicate-key scan on the
CURRENT file — if already duplicated, exit 1 (see D1); (2) build the mutated
content in memory; (3) run the duplicate-key scan on the MUTATED content — on
violation exit 1 without writing; (4) write to `<state>.tmp-<pid>` in the SAME
directory; (5) `fs.renameSync(tmp, state)` (atomic on same-filesystem POSIX).
A crash at any point before (5) leaves the target byte-identical; rename is the
sole commit point. For deterministic kill-mid-write tests (racy SIGKILL is
flaky), a test-only fault-injection hook `AAI_STATE_INJECT_CRASH=during-write|
before-rename` makes the process exit uncleanly at the corresponding point;
the hook is inert unless the env var is set. `log-tick` uses plain
`fs.appendFileSync` (single-line JSONL append, same posture as
`append-event.mjs:120`).

### D4 — shared lib extraction: `.aai/scripts/lib/state-core.mjs`
Extract `TOP_KEY_RE`, `topLevelKeyCounts`, `duplicateKeys` (and the
line-normalization helper) from `check-state.mjs:31-50,190-195` into
`.aai/scripts/lib/state-core.mjs`; both `check-state.mjs` and `state.mjs` import
it (no logic fork — the CLI validator and the CLI writer share one definition of
"duplicate top-level key"). `check-state.mjs`'s CLI contract (args, output,
exit codes, `--repair`) is UNCHANGED; the existing
`tests/skills/test-aai-check-state.sh` suite must stay green (regression gate).

### D5 — fallback wording for vendored projects (grep-stable token)
Every migrated prompt block uses this canonical two-path shape (same degrade
pattern as the docs-audit tick check, `.aai/SKILL_LOOP.prompt.md:54`):

    Primary path: node .aai/scripts/state.mjs <subcommand> ...
    FALLBACK — if .aai/scripts/state.mjs is absent (older vendored AAI layer):
    edit docs/ai/STATE.yaml by hand per the legacy block below, then validate:
      node .aai/scripts/check-state.mjs docs/ai/STATE.yaml

The literal token `state.mjs is absent` is the grep-stable fallback marker
(wiring tests assert it per prompt); the legacy inline instructions are RETAINED
under the fallback, never as the primary path (CHANGE-0006 constraint: vendored
older projects must not break mid-migration).

### D6 — reset-block semantics: reset ONLY a block that was `fail`
`reset-block last_validation` sets `last_validation.status: fail → not_run` and
appends a reset marker to its `notes` ("reset by remediation <ISO-UTC>; pending
independent re-validation"); prior `run_at_utc`/`evidence_paths` are left as
audit history. `reset-block code_review` sets `code_review.status: fail →
not_run` (leaving `required` and `report_paths` untouched). Guards, mechanically
encoding the CHANGE-0006 scoping constraint:
- status `fail` → reset, exit 0;
- status `not_run` → idempotent no-op, exit 0 with a notice (no file write);
- status `pass` or `waived` → REFUSED, exit 2 with message, no write, unless
  `--force` (post-PASS WARNING remediation must NOT reset a passing block — the
  remediation prompt instructs resetting only the block(s) that triggered the
  remediation, i.e. that were `fail`).
REMEDIATION's closing step becomes: apply fixes → `reset-block` each block that
was `fail` → append your agent run → STOP. It NEVER runs validation/review in
its own context and NEVER writes `last_validation.status` or
`code_review.status` verdict values. ORCHESTRATION gains a note at rules 10/12:
a completed remediation has reset the failed block to `not_run`, so the next
tick falls through to rule 11 (fresh independent Validation) or rule 13 (fresh
Code Review); with validation `pass` and review reset to `not_run`, rule 11's
"validation not run recently" must not re-fire — `pass` counts as run.

### D7 — log-tick field mapping to the existing LOOP_TICKS.jsonl schema
Emitted line = exactly the observed hand-written schema (superset-compatible):
`type` (default `tick`; `recovery` via `--type`), `tick`, `role`, `scope`,
`started_utc` (from `--started`, ISO-validated, rejected if >300s in the future
— the SKILL_LOOP `:300` rule moves into code), `ended_utc` (SELF-STAMPED from
the system clock), `duration_seconds` (computed integer — no more `null` from a
model that must not do arithmetic), `exit_code` (default 0),
`focus_ref_id_before/after`, `validation_status_before/after` ("after" values
default to the current STATE.yaml values read by the helper; "before" values
supplied by the caller), `orchestration_mode`/`orchestration_k` (default from
STATE's `orchestration` block, else `single`/1), `harness_version` (default
`"unknown"`). Optional fields (`input_tokens`, `output_tokens`,
`cache_read_tokens`, `est_cost_usd`, `lingering_procs`, `free_memory`) are
emitted ONLY when their flag is passed — the helper never fabricates usage
(SKILL_LOOP `:290-293` discipline moves into code). The model supplies only
semantic fields; the clock supplies time.

### D8 — implementer AC-table reconciliation (G4) placement
`.aai/IMPLEMENTATION.prompt.md` gains step 9b (after verification commands,
before the STATE update): reconcile the spec's `## Acceptance Criteria Status`
table — set each Spec-AC covered by this scope to a terminal status with
concrete Evidence (commit SHA, RUN_ID, or log path), or truthfully
`deferred`/`blocked` with future Review-By + Notes; emit `ac_status` events
(best-effort); then run `node .aai/scripts/docs-audit.mjs --gate <SPEC-ID>` and
fix until exit 0 BEFORE reporting complete. `.aai/SKILL_TDD.prompt.md` gains the
equivalent step in Phase 4 (before "Run Standard Validation"). Validation's
AC-STATUS GATE remains the enforcement backstop — the implementer-side call is
a self-check, not a verdict.

### D9 — post-review hardening (review-20260704T093742Z W1–W5)
Fixes applied by post-PASS warning remediation (verdicts untouched; regression
tests TEST-021..025, each proven RED against the pre-fix engine):
- **W1**: `reset-block` treats ANY block-scalar `notes` header (`|-`, `|+`,
  `>+`, `|`, `|2`, ...) uniformly — the reset marker is appended INSIDE the
  scalar at the existing content indentation; prior note lines survive as audit
  history (TEST-021).
- **W2**: a top-level block header carrying an inline value (`metrics: {}`,
  `metrics: null`, ...) is REFUSED exit 1 (refuse-rather-than-corrupt, D2
  posture) instead of splicing nested lines under it; the shared
  `state-core.mjs` gains `inlineChildConflicts()` so `check-state.mjs` and the
  writer's post-mutation scan both detect the child-lines-under-inline-header
  shape (SEAM-1 no longer depends on validator weakness) (TEST-022).
- **W3**: user-supplied plain-scalar values that YAML could misparse (`: `,
  leading `#`/`[`/`{`/quote, trailing `:`, ` #`, leading/trailing space) are
  written single-quoted with `''` escaping; newline-bearing values are rejected
  exit 2; already-safe values stay unquoted (minimal diffs) (TEST-023).
- **W4 — concurrency posture (documented contract)**: the CLI assumes
  SINGLE-WRITER discipline; coordination is prompt-level
  (`.aai/SUBAGENT_PROTOCOL.md` sole-writer rule under parallel dispatch;
  RFC-0004 docs-lock is the heavyweight layer — full locking deliberately out
  of scope). Mechanized guard: the writer re-reads the target immediately
  before the commit rename and REFUSES exit 1 ("concurrent modification
  detected") if the bytes no longer match the load-time snapshot, turning a
  silent lost-update into a loud retry; `AAI_STATE_INJECT_CONCURRENT=
  before-rename` is the deterministic test hook (TEST-024).
- **W5**: strict per-subcommand flag sets — any unrecognized `--flag` exits 2
  naming the flag and the valid set (the LLM-typo class the CLI exists to
  close; `--evidnce` can no longer silently drop evidence) (TEST-025).

## Implementation strategy
- Strategy: hybrid
- Rationale: TDD (RED-GREEN-REFACTOR) for the deterministic, higher-risk engine
  surface — `state.mjs` core (atomic write + crash injection, duplicate-key
  refusal, closed-set enum validation, reset-block guard semantics, log-tick
  schema/timestamp validation, append-run auto-init) and the `state-core.mjs`
  extraction (a shared contract two CLIs depend on). Loop (grep-verified) for
  the mechanical prompt migrations across the nine prompts and the
  ORCHESTRATION reset note (wiring prose, mirroring the TEST-015..017 style of
  SPEC-0005 and TEST-010/013 of SPEC-0011). Matches the sibling SPEC-0010/0011
  hybrid posture.
- RED-proof obligation applies to every AC-gating test regardless of strategy:
  CLI tests are RED before `state.mjs` exists; grep-wiring tests are RED against
  the pre-migration prompts (they reference no `state.mjs` today).

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: the scope touches three or more independent modules
  simultaneously — a new engine script (`state.mjs`), a lib extraction that
  modifies `check-state.mjs`, NINE workflow prompts, and a new test suite — and
  it is PR-bound. It also modifies the loop's own state-mutation path (the
  tooling this repo runs on), so isolation is prudent. NOT `required`: changes
  are additive/behavioral (new CLI, prompt prose, no STATE schema migration,
  fallback keeps old behavior reachable). Matches the SPEC-0010/0011
  `recommended` precedent.
- User decision: undecided (Planning recommends; Implementation Preparation asks
  the user and records the decision — inline-on-dedicated-branch is an
  acceptable override consistent with SPEC-0010/0011 precedent).
- Base ref: main
- Worktree branch/path: TBD if the user chooses worktree
- Inline review scope (if inline is chosen):
  - `.aai/scripts/state.mjs` (new)
  - `.aai/scripts/lib/state-core.mjs` (new, extracted)
  - `.aai/scripts/check-state.mjs` (imports the lib; CLI contract unchanged)
  - `.aai/PLANNING.prompt.md`, `.aai/IMPLEMENTATION.prompt.md`,
    `.aai/VALIDATION.prompt.md`, `.aai/REMEDIATION.prompt.md`,
    `.aai/SKILL_TDD.prompt.md`, `.aai/ORCHESTRATION.prompt.md`,
    `.aai/ORCHESTRATION_PARALLEL.prompt.md`, `.aai/METRICS_FLUSH.prompt.md`,
    `.aai/SKILL_LOOP.prompt.md`
  - `tests/skills/test-aai-state.sh` (new)
  - `docs/specs/SPEC-0012-loop-reliability-transactional-state-cli.md`

## Acceptance Criteria Mapping

### G1 — transactional STATE CLI

- Maps to: CHANGE-0006 AC-001
  - Spec-AC-01: Every STATE-mutating subcommand (`set-focus`, `set-phase`,
    `set-validation`, `set-code-review`, `set-strategy`, `set-worktree`,
    `set-tdd-cycle`, `set-human-input`, `append-run`, `reset-block`) applied to a
    fixture STATE.yaml exits 0, changes ONLY the target block plus the real
    top-level `updated_at_utc` line, and leaves the file such that
    `check-state.mjs` exits 0. RED-proof: pre-fix the script does not exist
    (`node .aai/scripts/state.mjs` fails).
  - Verification: TEST-001, TEST-002, TEST-020.

- Maps to: CHANGE-0006 AC-001 (reject path)
  - Spec-AC-02: Invalid enum values, unknown block names, malformed/ill-shaped
    `--ref`, missing required flags, and a missing STATE file each exit 2 and
    leave the target file byte-identical (no write occurred).
  - Verification: TEST-003, TEST-004.

### G1 — atomicity and corruption guard

- Maps to: CHANGE-0006 AC-002
  - Spec-AC-03: With crash injection at `during-write` and at `before-rename`,
    an interrupted `state.mjs` invocation leaves the target STATE.yaml
    byte-identical (never truncated, never duplicate-keyed); `check-state.mjs`
    still exits 0. RED-proof: a naive in-place-write stub (or absent tmp+rename)
    corrupts/truncates under the same injection.
  - Verification: TEST-005, TEST-006.

- Maps to: CHANGE-0006 AC-002 (integrity refusal + shared definition)
  - Spec-AC-04: A mutation on an ALREADY-corrupt STATE (pre-existing duplicate
    top-level `metrics:`) is REFUSED with exit 1 (message pointing at
    `check-state.mjs --repair`), file untouched; duplicate-key detection is
    shared via `.aai/scripts/lib/state-core.mjs` and the existing
    `tests/skills/test-aai-check-state.sh` suite stays green after the
    extraction.
  - Verification: TEST-007, TEST-008.

### G2 — prompt migration

- Maps to: CHANGE-0006 AC-003
  - Spec-AC-05: All nine prompts (PLANNING, IMPLEMENTATION, VALIDATION,
    REMEDIATION, SKILL_TDD, ORCHESTRATION, ORCHESTRATION_PARALLEL,
    METRICS_FLUSH, SKILL_LOOP) reference `node .aai/scripts/state.mjs` as the
    PRIMARY path of their STATE-mutation instructions and carry the canonical
    fallback marker `state.mjs is absent`; no prompt retains a raw
    `sed`/`node -e` STATE edit as the primary path (grep-verified per prompt).
  - Verification: TEST-014.

### G3 — remediation transition reset

- Maps to: CHANGE-0006 AC-004 (remediation side)
  - Spec-AC-06: REMEDIATION's closing step instructs
    `state.mjs reset-block last_validation` / `reset-block code_review` for each
    block that was `fail`, explicitly FORBIDS writing its own
    validation/review verdict, and no longer instructs "Re-run validation" in
    its own context (grep-verified).
  - Verification: TEST-015.

- Maps to: CHANGE-0006 AC-004 (orchestration side)
  - Spec-AC-07: ORCHESTRATION's decision logic documents the post-remediation
    reset at rules 10/12 (failed block reset to `not_run` → next tick falls
    through to rule 11 / rule 13 for a fresh INDEPENDENT check); fixture-driven:
    a STATE with `last_validation.status: fail` after `reset-block
    last_validation` satisfies rule 11's decision inputs (`not_run`, implementation
    present) and no longer matches rule 10, with `code_review` untouched.
  - Verification: TEST-016.

- Maps to: CHANGE-0006 AC-004 + Constraints (reset scoping)
  - Spec-AC-08: `reset-block` resets only a `fail` block: on `fail` → `not_run`
    exit 0; on `not_run` → idempotent no-op exit 0 (no write); on
    `pass`/`waived` → exit 2 refused without `--force` (post-PASS WARNING
    remediation cannot clobber a passing verdict).
  - Verification: TEST-011.

### G4 — implementer AC-table reconciliation

- Maps to: CHANGE-0006 AC-005
  - Spec-AC-09: IMPLEMENTATION (step 9b) and SKILL_TDD (Phase 4) contain the
    pre-handoff AC-table reconciliation step including the
    `docs-audit.mjs --gate <SPEC-ID>` self-check with "fix until exit 0 before
    reporting complete" (grep-verified in both prompts); and a simulated handoff
    on a fixture spec with an unreconciled table is caught implementer-side by
    the gate call (exit 1, reasons naming the rows), while the reconciled
    fixture passes (exit 0).
  - Verification: TEST-017, TEST-018.

### G1/AC-006 — mechanized logging

- Maps to: CHANGE-0006 AC-006
  - Spec-AC-10: `log-tick` appends LOOP_TICKS.jsonl lines schema-compatible with
    the existing hand-written ones (all required fields per D7; `type: recovery`
    supported; append-only — two invocations yield two lines), with
    `ended_utc`/`duration_seconds` from the system clock, and NO
    token/cost/leak fields unless their flags are passed; a malformed or
    >300s-future `--started` exits 2 with no append.
  - Verification: TEST-012, TEST-013.

- Maps to: CHANGE-0006 AC-006 + AC-001 (agent_runs mechanics)
  - Spec-AC-11: `append-run` appends the agent_runs entry under the SINGLE
    top-level `metrics:` key (never a second one), auto-initializes a missing
    `metrics.work_items.<ref>` entry, converts an inline `agent_runs: []` to
    block form without duplicating the nested key, self-stamps
    `ended_utc`/`duration_seconds` from the system clock, and bumps the REAL
    top-level `updated_at_utc` field while the commented schema header stays
    byte-identical.
  - Verification: TEST-009, TEST-010.

### Coverage and no regression

- Maps to: CHANGE-0006 AC-007
  - Spec-AC-12: New behavior is covered by `tests/skills/test-aai-state.sh`
    (run green via `.aai/scripts/aai-run-tests.sh`); existing suites stay green
    — check-state, docs-audit (known pre-existing `test_index_continue_on_error`
    failure unchanged), test-canon, orchestration-mode, docs-lock, intake; on
    the real repo `docs-audit.mjs --check --strict --no-event` exits 0 CLEAN and
    `generate-docs-index.mjs` stays idempotent.
  - Verification: TEST-019.

## Acceptance Criteria Status

Tracks per-Spec-AC delivery state. Separate from per-test lifecycle below.

| Spec-AC    | Description | Status  | Evidence | Review-By | Notes |
|------------|-------------|---------|----------|-----------|-------|
| Spec-AC-01 | Every STATE-mutating subcommand mutates only its target block + real `updated_at_utc`; `check-state.mjs` exits 0 afterward | done | TEST-001/002/020 green: docs/ai/tdd/green-spec0012-suite-20260704T091433Z.log (suite exit 0); RED: docs/ai/tdd/red-spec0012-suite-20260704T090402Z.log; W3 hardening TEST-023 green (hostile scalars quoted): docs/ai/tdd/green-spec0012-w1-w5-remediation-20260704T095253Z.log, RED: docs/ai/tdd/red-spec0012-w1-w5-remediation-20260704T094801Z.log | — | AC-001; TDD |
| Spec-AC-02 | Invalid enum / unknown block / bad ref shape / missing flag / missing STATE → exit 2, file byte-identical | done | TEST-003/004 green: docs/ai/tdd/green-spec0012-suite-20260704T091433Z.log; W5 hardening TEST-025 green (unknown flags exit 2): docs/ai/tdd/green-spec0012-w1-w5-remediation-20260704T095253Z.log, RED: docs/ai/tdd/red-spec0012-w1-w5-remediation-20260704T094801Z.log | — | AC-001; TDD |
| Spec-AC-03 | Crash injection during-write / before-rename never truncates or duplicate-keys STATE (tmp+rename atomicity) | done | TEST-005/006 green: docs/ai/tdd/green-spec0012-suite-20260704T091433Z.log; RED vs naive in-place-write stub: docs/ai/tdd/red-spec0012-atomicity-stub-20260704T090432Z.log; W4 hardening TEST-024 green (pre-rename concurrent-modification refusal): docs/ai/tdd/green-spec0012-w1-w5-remediation-20260704T095253Z.log, RED: docs/ai/tdd/red-spec0012-w1-w5-remediation-20260704T094801Z.log | — | AC-002; TDD |
| Spec-AC-04 | Mutation on already-corrupt STATE refused exit 1 (no compounding); dup-key logic shared via lib/state-core.mjs; check-state suite green | done | TEST-007/008 green: docs/ai/tdd/green-spec0012-suite-20260704T091433Z.log; test-aai-check-state.sh exit 0 post-extraction (7 PASS); W2 hardening TEST-022 green (inline-header refusal + shared inlineChildConflicts validator, check-state re-run 7 PASS): docs/ai/tdd/green-spec0012-w1-w5-remediation-20260704T095253Z.log, RED: docs/ai/tdd/red-spec0012-w1-w5-remediation-20260704T094801Z.log | — | AC-002; TDD + regression |
| Spec-AC-05 | All nine prompts use state.mjs as primary path with `state.mjs is absent` fallback; no raw sed/node -e primary edit | done | TEST-014 green: docs/ai/tdd/green-spec0012-suite-20260704T091433Z.log; RED vs pre-migration prompts: docs/ai/tdd/red-spec0012-grepwiring-20260704T090413Z.log | — | AC-003; loop (grep) |
| Spec-AC-06 | REMEDIATION closes via reset-block, forbids own verdict, drops self-run validation step | done | TEST-015 green: docs/ai/tdd/green-spec0012-suite-20260704T091433Z.log; RED: docs/ai/tdd/red-spec0012-grepwiring-20260704T090413Z.log | — | AC-004; loop (grep) |
| Spec-AC-07 | ORCHESTRATION documents post-remediation reset routing to rules 11/13; fixture fail→reset→not_run drives rule-11 inputs | done | TEST-016 green (real reset-block on fail fixture + grep): docs/ai/tdd/green-spec0012-suite-20260704T091433Z.log | — | AC-004; SEAM-2 |
| Spec-AC-08 | reset-block scoping: fail→not_run; not_run idempotent exit 0; pass/waived refused exit 2 without --force | done | TEST-011 green: docs/ai/tdd/green-spec0012-suite-20260704T091433Z.log; W1 hardening TEST-021 green (`\|-`/`>+`/`\|` notes preserved on reset): docs/ai/tdd/green-spec0012-w1-w5-remediation-20260704T095253Z.log, RED: docs/ai/tdd/red-spec0012-w1-w5-remediation-20260704T094801Z.log | — | AC-004; TDD |
| Spec-AC-09 | IMPLEMENTATION + SKILL_TDD pre-handoff AC reconciliation incl. --gate self-check; unreconciled handoff caught exit 1 | done | TEST-017/018 green (real gate exit 1 naming rows / exit 0 on reconciled sibling): docs/ai/tdd/green-spec0012-suite-20260704T091433Z.log | — | AC-005; SEAM-3 |
| Spec-AC-10 | log-tick emits schema-compatible LOOP_TICKS lines, real clock stamps, no fabricated cost fields, recovery type, append-only | done | TEST-012/013 green: docs/ai/tdd/green-spec0012-suite-20260704T091433Z.log | — | AC-006; TDD; SEAM-4 |
| Spec-AC-11 | append-run: single metrics key, auto-init entry, inline `[]`→block conversion, self-stamped timing, real updated_at_utc bump | done | TEST-009/010 green: docs/ai/tdd/green-spec0012-suite-20260704T091433Z.log | — | AC-006/001; TDD |
| Spec-AC-12 | New suite green via aai-run-tests.sh; existing suites unchanged; real-repo audit CLEAN; index idempotent | done | TEST-019 green; suite exit 0 via aai-run-tests.sh (docs/ai/tdd/green-spec0012-suite-20260704T091433Z.log); check-state exit 0 (7 PASS); docs-audit suite exit 0 (74 PASS, historical test_index_continue_on_error did not reproduce); docs-lock exit 0 (14 PASS); intake exit 0 (11 checks); test-canon exit 0 (8 pre-existing intentional RED stubs unchanged) | — | AC-007; orchestration-mode suite exits 1 in this worktree on its TEST-016 ("missing docs/ai/STATE.yaml" — gitignored runtime file absent in any fresh worktree); IDENTICAL failure reproduced on a pristine `git archive HEAD` baseline, so it is pre-existing/env-dependent, not a regression of this diff |

Status values: planned | implementing | done | deferred | blocked | rejected.
Gate (per .aai/VALIDATION.prompt.md): any planned/implementing row blocks PASS;
any done row needs non-empty Evidence; deferred/blocked need a future Review-By.

## Implementation plan
- Components/modules affected:
  - `.aai/scripts/lib/state-core.mjs` (NEW): `TOP_KEY_RE`, `topLevelKeyCounts`,
    `duplicateKeys`, line normalization, block-range location — extracted from
    `check-state.mjs:31-50,190-195`.
  - `.aai/scripts/check-state.mjs`: import from the lib; CLI contract, output,
    and exit codes unchanged (regression-gated by test-aai-check-state.sh).
  - `.aai/scripts/state.mjs` (NEW): subcommand dispatch per D1; structural
    line-edit engine per D2; atomic write + `AAI_STATE_INJECT_CRASH` hook per
    D3; `reset-block` guards per D6; `log-tick` per D7; `append-run` auto-init
    per D5/D1. `--state`/`--ticks` path overrides for fixture testing.
  - Nine prompts, replacing each verified hand-edit block (see Problem
    summaries for exact lines) with the D5 two-path shape:
    - PLANNING step 11 + METRICS → `set-focus`/`set-phase`/`set-strategy`/
      `set-worktree`/`set-code-review` + `append-run`.
    - IMPLEMENTATION step 10 + METRICS → `set-phase`/`set-code-review` +
      `append-run`; NEW step 9b (D8 reconciliation).
    - VALIDATION step 9 + METRICS → `set-validation`/`set-phase` + `append-run`.
    - REMEDIATION steps 4-5 + METRICS → fixes, then `reset-block` for each
      block that was `fail` + `append-run`; verdict-prohibition sentence (D6).
    - SKILL_TDD tdd_cycle blocks (RED/GREEN/REFACTOR/clean) → `set-tdd-cycle`;
      agent_runs → `append-run`; Phase 4 reconciliation step (D8).
    - ORCHESTRATION metrics auto-init + closing STATE update → `append-run`
      auto-init note + `set-*` commands; reset-routing note at rules 10/12 (D6).
    - ORCHESTRATION_PARALLEL merged-result write → `set-*` commands
      (orchestrator remains the single writer; subagents still never write).
    - METRICS_FLUSH step 5 cleanup → keep as guarded manual edit (whole-block
      removal is out of the CLI's mutation surface) but require the
      `check-state.mjs` validation after cleanup via the D5 fallback shape;
      tick-derived `reviews` unchanged.
    - SKILL_LOOP step 6 + recovery line → `log-tick` (incl. `--type recovery`);
      stagnation/budget HITL writes → `set-human-input`; orchestration
      mode/k/groups record → keep the optional-block guidance, primary path
      `set-*` where covered, fallback otherwise.
  - `tests/skills/test-aai-state.sh` (NEW): TEST-001..020 (+ TEST-021..025 D9 hardening) on
    `tests/skills/test-framework.sh` conventions; ALL fixtures are
    scratch-created STATE.yaml/LOOP_TICKS.jsonl copies under a temp dir
    (`--state`/`--ticks`) — never the real gitignored runtime files
    (CHANGE-0006 constraint).
- Data flows: role prompts → `state.mjs` → STATE.yaml (atomic) / LOOP_TICKS.jsonl
  (append); `state.mjs` and `check-state.mjs` → `lib/state-core.mjs`;
  implementer prompts → `docs-audit.mjs --gate` (existing SPEC-0011 predicate,
  consumed unchanged).
- Edge cases: inline `agent_runs: []` (auto-init form) on append; missing
  `metrics:`/`work_items:` scaffolding (created without duplicating keys); STATE
  file with CRLF (normalize on read, preserve trailing-newline convention like
  `check-state.mjs:191-195`); `set-focus --type none` nulling ref/path;
  `reset-block` on a STATE with no `last_validation` block (exit 2 unknown
  block instance); `log-tick` before any STATE `orchestration` block exists
  (defaults `single`/1).

## Seam analysis
- SEAM-1 (`state.mjs` writer → `check-state.mjs` validator, shared
  `lib/state-core.mjs`): the writer must never produce what the validator
  rejects. Crossed end-to-end by TEST-001/002 (every real mutation is followed
  by a real `check-state.mjs` run asserting exit 0) and TEST-008 (extraction
  regression on the validator's own suite).
- SEAM-2 (`reset-block` producer → ORCHESTRATION decision inputs, rules 10-13):
  remediation's reset must produce exactly the state shape that routes the next
  tick to rule 11/13. Crossed by TEST-016 (real `reset-block` on a
  fail-state fixture, then assert the rule-10/11 decision inputs) plus grep
  assertions on both prompts. Residual risk (recorded): the decision table
  itself is LLM-interpreted prose, not executable code — a fixture can only
  verify the INPUTS, not the dispatch. Mitigated by the Verification section's
  manual loop smoke (one FAIL→Remediation→re-Validation cycle in a fixture repo
  showing `not_run` between remediation and re-validation, no self-recorded
  PASS).
- SEAM-3 (implementer-side `--gate` self-check → VALIDATION's AC-STATUS GATE
  backstop): both sides consume the same `docs-audit.mjs --gate` predicate.
  Crossed by TEST-018 (real unreconciled fixture spec → real gate exit 1 caught
  at the simulated handoff; reconciled → exit 0), producer/consumer both real.
- SEAM-4 (`log-tick` producer → LOOP_TICKS.jsonl consumers: SKILL_LOOP
  stagnation check reads `focus_ref_id_*`/`validation_status_*` tails,
  METRICS_FLUSH reads timing lines): crossed by TEST-012 asserting the emitted
  line is a field-superset match of the observed hand-written schema (parsed as
  JSON, required fields present with correct types) so existing consumers keep
  working.
- Residual risk (recorded): prompts are vendored downstream; a vendored project
  with NEW prompts but WITHOUT `state.mjs` relies entirely on the D5 fallback
  path. Mitigated by retaining the full legacy instructions under the fallback
  marker (TEST-014 asserts the marker per prompt) and by aai-update shipping
  script + prompts together.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)            | Description | Status  |
|----------|------------|-------------|---------------------------------|-------------|---------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-state.sh | Fixture STATE: `set-focus` + `set-phase` happy path → exit 0; `check-state.mjs` exit 0; commented schema header byte-identical; `updated_at_utc` (real field, not the `:16` comment) bumped. RED: state.mjs absent. | green |
| TEST-002 | Spec-AC-01 | integration | tests/skills/test-aai-state.sh | Table-driven happy path over `set-validation`/`set-code-review`/`set-strategy`/`set-worktree`/`set-tdd-cycle`/`set-human-input` → each exit 0 + `check-state.mjs` exit 0; `set-validation` self-stamps `run_at_utc`. | green |
| TEST-003 | Spec-AC-02 | unit        | tests/skills/test-aai-state.sh | Table-driven invalid enums (e.g. `set-validation --status maybe`, `set-phase --phase testing`, `set-worktree --recommendation always`) → exit 2, fixture byte-identical. | green |
| TEST-004 | Spec-AC-02 | unit        | tests/skills/test-aai-state.sh | Degenerate inputs: unknown block (`reset-block metrics`), bad ref shape (`append-run --ref nope`), missing required flag, missing STATE file → each exit 2, no write/append. | green |
| TEST-005 | Spec-AC-03 | integration | tests/skills/test-aai-state.sh | `AAI_STATE_INJECT_CRASH=before-rename` on a mutating command → process dies non-zero, target STATE byte-identical, `check-state.mjs` exit 0, stray tmp file ignorable. RED: naive in-place write corrupts. | green |
| TEST-006 | Spec-AC-03 | integration | tests/skills/test-aai-state.sh | `AAI_STATE_INJECT_CRASH=during-write` (partial tmp content) → target STATE intact and never truncated/duplicate-keyed; re-run without injection succeeds. | green |
| TEST-007 | Spec-AC-04 | integration | tests/skills/test-aai-state.sh | Fixture STATE with a PRE-EXISTING duplicate top-level `metrics:` → any mutating command refuses exit 1 naming `check-state.mjs --repair`, file untouched (corruption never compounded). | green |
| TEST-008 | Spec-AC-04 | integration | tests/skills/test-aai-state.sh | Regression: after the `lib/state-core.mjs` extraction, `bash tests/skills/test-aai-check-state.sh` passes unchanged (validator CLI contract intact). | green |
| TEST-009 | Spec-AC-11 | integration | tests/skills/test-aai-state.sh | Degenerate: `append-run` into an inline `agent_runs: []` entry → converted to block form with ONE `agent_runs` key (no duplicate nested key), entry fields complete, `check-state.mjs` exit 0. | green |
| TEST-010 | Spec-AC-11 | integration | tests/skills/test-aai-state.sh | `append-run` with NO existing `metrics.work_items.<ref>` → entry auto-initialized (human_time_minutes nulls) under the single `metrics:` key; `ended_utc` self-stamped ≥ `--started`; `duration_seconds` computed integer; `cost_usd: null`. | green |
| TEST-011 | Spec-AC-08 | unit        | tests/skills/test-aai-state.sh | `reset-block` guards: `fail`→`not_run` exit 0 with reset note; already-`not_run` → idempotent exit 0, file unmodified; `pass` → exit 2 refused (no write); `pass` + `--force` → reset. | green |
| TEST-012 | Spec-AC-10 | integration | tests/skills/test-aai-state.sh | `log-tick` → appended line parses as JSON with all observed-schema fields (type/tick/role/scope/started_utc/ended_utc/duration_seconds/exit_code/focus+validation before+after/orchestration_mode/orchestration_k/harness_version); NO token/cost/leak fields when flags absent; `--type recovery` honored; two calls append two lines (never rewrites). | green |
| TEST-013 | Spec-AC-10 | unit        | tests/skills/test-aai-state.sh | `log-tick` timestamp validation: non-ISO `--started` and `--started` >300s in the future → exit 2, nothing appended. | green |
| TEST-014 | Spec-AC-05 | unit        | tests/skills/test-aai-state.sh | Grep-wiring over ALL nine prompts: each references `node .aai/scripts/state.mjs` in its STATE-mutation block AND carries the `state.mjs is absent` fallback marker; no prompt instructs a `sed -i`/`node -e` STATE edit as primary path. RED: pre-migration prompts contain no state.mjs reference. | green |
| TEST-015 | Spec-AC-06 | unit        | tests/skills/test-aai-state.sh | Grep REMEDIATION: contains `reset-block last_validation` + `reset-block code_review` + the verdict-prohibition sentence; does NOT contain the old self-run "Re-run validation" closing step. | green |
| TEST-016 | Spec-AC-07 | integration | tests/skills/test-aai-state.sh | Fixture STATE `last_validation.status: fail` + `code_review.status: pass` → `reset-block last_validation` → `last_validation.status: not_run`, `code_review` untouched (rule-10 input cleared, rule-11 inputs satisfied); grep ORCHESTRATION for the reset-routing note at rules 10/12→11/13. | green |
| TEST-017 | Spec-AC-09 | unit        | tests/skills/test-aai-state.sh | Grep IMPLEMENTATION (step 9b) + SKILL_TDD (Phase 4): both contain the AC-table reconciliation step, the `docs-audit.mjs --gate` self-check, and "exit 0 before reporting complete". | green |
| TEST-018 | Spec-AC-09 | integration | tests/skills/test-aai-state.sh | Simulated handoff fixtures: spec with `planned` rows → `docs-audit.mjs --gate <ID>` exit 1 naming the rows (implementer-side catch BEFORE Validation); fully-reconciled sibling fixture → exit 0 (control both directions). | green |
| TEST-019 | Spec-AC-12 | e2e         | tests/skills/test-aai-state.sh | Suite + regression anchor: `tests/skills/test-aai-state.sh` green via `.aai/scripts/aai-run-tests.sh`; check-state / docs-audit (1 known pre-existing fail unchanged) / test-canon / orchestration-mode / docs-lock / intake suites green; real-repo `docs-audit --check --strict --no-event` exit 0; `generate-docs-index.mjs` idempotent. | green |
| TEST-020 | Spec-AC-01 | integration | tests/skills/test-aai-state.sh | Comment/key-order preservation: full-file diff after each mutating command touches ONLY the target block + `updated_at_utc` line; header comment block (lines 1-23 shape) byte-identical; key order of untouched top-level blocks unchanged. | green |
| TEST-021 | Spec-AC-08 | integration | tests/skills/test-aai-state.sh | Review W1 (D9): `reset-block last_validation` on `notes: \|-` / `>+` / `\|` block-scalar fixtures → prior note lines SURVIVE, marker appended in-scalar at content indent, header style kept, `check-state.mjs` exit 0. RED: pre-fix `\|-` note lines deleted. | green |
| TEST-022 | Spec-AC-04 | integration | tests/skills/test-aai-state.sh | Review W2 (D9): `append-run` under `metrics: {}` / `metrics: {placeholder: 1}` and `set-focus` under `current_focus: {}` → refused exit 1 naming the inline header, file byte-identical; hand-corrupted child-lines-under-inline-header file → `check-state.mjs` exit 1 naming the key; childless inline header stays exit 0. RED: pre-fix invalid YAML written with exit 0, validator blind. | green |
| TEST-023 | Spec-AC-01 | unit        | tests/skills/test-aai-state.sh | Review W3 (D9): colon-bearing `--ref`/`--branch`, leading-quote `--model`, `#`-bearing `--test-id`/`--red` → written single-quoted with `''` escaping; safe values stay unquoted; newline-bearing value → exit 2, no write. RED: pre-fix `ref_id: CHANGE-1: bad` written verbatim exit 0. | green |
| TEST-024 | Spec-AC-03 | integration | tests/skills/test-aai-state.sh | Review W4 (D9): `AAI_STATE_INJECT_CONCURRENT=before-rename` (deterministic second-writer commit between load and rename) → exit 1 "concurrent modification detected", other writer's line survives, stale mutation NOT committed, tmp cleaned, retry succeeds; single-writer posture documented in state.mjs header + this spec. RED: pre-fix last-rename-wins lost update, exit 0. | green |
| TEST-025 | Spec-AC-02 | unit        | tests/skills/test-aai-state.sh | Review W5 (D9): unknown/misspelled flags (`--evidnce`, `--notse`, `--frce`, `--hrness`, cross-subcommand `--evidence` on append-run) → exit 2 naming the flag AND the valid set, zero writes/appends; full valid flag surface (incl. global `--state`/`--ticks`) still accepted. RED: pre-fix silently ignored, exit 0. | green |

Test status values: pending → red → green. Every Spec-AC has ≥1 TEST-xxx. Test
IDs are stable; do not renumber after freeze.

Fixture diversity (LEARNED / RFC-0006 lesson — degenerate cases are first-class):
kill-mid-write atomicity (TEST-005/006), duplicate-key rejection on
already-corrupt input (TEST-007), unknown ref/block shapes (TEST-004), empty
inline `agent_runs: []` (TEST-009), reset of an already-`not_run` block
(idempotence, TEST-011).

TDD vs loop per AC: Spec-AC-01/02/03/04/08/10/11 (CLI core + lib extraction)
are TDD (RED-proof mandatory). Spec-AC-05/06/09 (prompt wiring) and the grep
half of Spec-AC-07 are loop (grep-verified, RED against pre-migration prompts).
Spec-AC-07's fixture half (TEST-016) and Spec-AC-09's gate half (TEST-018)
exercise real producer→consumer seams. Spec-AC-12 is the regression gate.

## Verification
- `bash tests/skills/test-aai-state.sh` via `.aai/scripts/aai-run-tests.sh` —
  TEST-001..025 green, incl. both crash-injection atomicity cases and the
  review-W1..W5 hardening regressions (D9).
- `node .aai/scripts/check-state.mjs <fixture>` exit 0 after every mutating
  subcommand (SEAM-1, embedded in TEST-001/002/009/010).
- Grep-wiring assertions over the nine prompts (TEST-014..017 style mirrors
  SPEC-0005 TEST-015..017 / SPEC-0011 TEST-010/013).
- Existing suites re-run green: test-aai-check-state.sh, test-aai-docs-audit.sh
  (known pre-existing `test_index_continue_on_error` failure unchanged),
  test-aai-test-canon.sh, test-aai-orchestration-mode.sh, test-aai-docs-lock.sh,
  test-aai-intake.sh.
- Real repo: `node .aai/scripts/docs-audit.mjs --check --strict --no-event`
  exit 0 CLEAN; `node .aai/scripts/generate-docs-index.mjs` idempotent (two
  runs byte-identical modulo `Generated:`).
- Manual loop smoke (SEAM-2 residual-risk mitigation): one
  FAIL→Remediation→re-Validation cycle driven in a fixture repo shows
  `last_validation.status: not_run` between remediation and re-validation and
  no self-recorded PASS.
- PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status with
  evidence.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id (CHANGE-0006 / SPEC-0012)
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path
- commit SHA or diff range when available

Notes:
This document defines HOW, not WHAT/WHY (CHANGE-0006 owns WHAT/WHY).
This document does not define workflow.
Use plain Markdown headings and body text. Do not add emoji or decorative icons
unless there is a strong domain-specific reason.
