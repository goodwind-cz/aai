---
id: CHANGE-0006
type: change
status: done
links:
  spec: SPEC-0012
  pr:
    - 34
  commits:
    - 4efbba6
---

# Change Request: Loop reliability — transactional STATE CLI, remediation transition reset, implementer AC-table reconciliation

Frontmatter status values: draft | implementing | done | deferred | rejected | superseded

## Summary
- Replace hand-edited YAML mutations of `docs/ai/STATE.yaml` with a transactional
  helper CLI (`.aai/scripts/state.mjs`), fix the validation/review FAIL →
  Remediation transition so the loop dispatches an independent re-check instead
  of self-validating or looping, and make the Implementation/TDD roles reconcile
  the spec's `## Acceptance Criteria Status` table before handoff to Validation.
- Three defects, one root cause: runtime state is edited as free text by LLMs
  with no transactional primitive. One helper closes the corruption class, gives
  transitions a clean reset primitive, and mechanizes tick/metrics logging.

## Motivation / Business Value
- Sourced from a skill-layer audit (2026-07-04) plus defects observed live in the
  CHANGE-0005 loop run (2026-07-02/03):
  - **STATE corruption risk:** every role prompt hand-edits STATE.yaml
    (PLANNING.prompt.md:132, IMPLEMENTATION.prompt.md:152, VALIDATION.prompt.md:156,
    REMEDIATION.prompt.md:30, SKILL_TDD.prompt.md:123, ORCHESTRATION.prompt.md:147,
    METRICS_FLUSH.prompt.md:42). `check-state.mjs` exists precisely because this
    already corrupted state once (ISSUE-0004 duplicate `metrics:` key). In the
    CHANGE-0005 run a timestamp regex edit hit the schema comment line instead of
    the real `updated_at_utc` field.
  - **Transition bug:** ORCHESTRATION rule 10 (`validation FAIL → Remediation`)
    precedes rule 11 and nothing resets `last_validation` to `not_run`, so after
    Remediation the next tick re-matches rule 10 (remediation loop). The only
    documented escape is REMEDIATION step 4 telling the remediation context to
    re-run validation and write `last_validation` itself — self-validation,
    violating the validator-independence rule (VALIDATION.prompt.md:13-25,
    SKILL_LOOP.prompt.md:223-233). Same defect for `code_review.status: fail`
    (rule 12 vs rule 13). In the CHANGE-0005 run the operator had to reset the
    status by hand between ticks 5 and 6.
  - **Guaranteed wasted tick:** neither IMPLEMENTATION.prompt.md nor
    SKILL_TDD.prompt.md instructs the implementer to reconcile the spec's
    `## Acceptance Criteria Status` table (status + Evidence per row). The table
    is first enforced by VALIDATION's AC-STATUS GATE, so a gate-opted spec
    reaches Validation with `planned` rows → guaranteed FAIL → one full
    Remediation + re-Validation cycle per work item (observed: CHANGE-0005
    ticks 4–6, ≈15 min + 2 subagent runs wasted).
  - **Chronically-null metrics:** LOOP_TICKS.jsonl lines and
    `metrics.work_items[].agent_runs` entries are hand-authored JSON/YAML;
    `cost_usd` is always authored null and `total_cost_usd` degrades to null if
    any run is null (METRICS_FLUSH.prompt.md:38).

## Scope
- In scope:
  - **G1 — `state.mjs` transactional CLI.** New `.aai/scripts/state.mjs` with
    subcommands: `set-focus`, `set-phase`, `set-validation`, `set-code-review`,
    `append-run` (self-stamps `date -u` timestamps), `log-tick` (appends the
    LOOP_TICKS.jsonl line), `reset-block last_validation|code_review`. Each
    command: load → mutate → atomic rewrite → internal duplicate-key check
    (reuse check-state.mjs logic). Exit non-zero on invalid enum/shape.
  - **G2 — prompt migration.** Replace the hand-edit blocks in PLANNING,
    IMPLEMENTATION, VALIDATION, REMEDIATION, SKILL_TDD, ORCHESTRATION,
    ORCHESTRATION_PARALLEL, METRICS_FLUSH and SKILL_LOOP with `state.mjs` calls
    (degrade gracefully to the old instructions if the script is absent —
    vendored older projects).
  - **G3 — transition fix.** Remediation's closing step resets
    `last_validation.status` (and `code_review.status` when it was `fail`) to
    `not_run` via `state.mjs reset-block` and NEVER writes its own PASS;
    ORCHESTRATION decision logic notes the reset so rules 11/13 dispatch a fresh
    independent Validation / Code Review after any remediation.
  - **G4 — implementer AC-table reconciliation.** IMPLEMENTATION and SKILL_TDD
    gain a pre-handoff closeout step: set each covered Spec-AC row terminal with
    concrete Evidence (or truthfully `deferred`/`blocked`), then run
    `docs-audit.mjs --gate <SPEC-ID>` and fix until exit 0 before reporting
    complete. Validation's gate remains the enforcement backstop.
  - Tests for the CLI (atomicity, enum validation, duplicate-key rejection,
    reset semantics, log-tick shape) and grep-wiring tests for the prompt
    migration, in the existing skills test-suite conventions.
- Out of scope:
  - Automatic token/cost capture from the harness (runtime does not expose
    usage to the model; fields stay best-effort).
  - Rewriting the ORCHESTRATION decision table beyond the reset rule.
  - Downstream vendored-project migration (ships via aai-update as usual).

## Affected Area
- New: `.aai/scripts/state.mjs` (+ tests `tests/skills/test-aai-state.sh`).
- Prompts: `.aai/PLANNING.prompt.md`, `.aai/IMPLEMENTATION.prompt.md`,
  `.aai/VALIDATION.prompt.md`, `.aai/REMEDIATION.prompt.md`,
  `.aai/SKILL_TDD.prompt.md`, `.aai/ORCHESTRATION.prompt.md`,
  `.aai/ORCHESTRATION_PARALLEL.prompt.md`, `.aai/METRICS_FLUSH.prompt.md`,
  `.aai/SKILL_LOOP.prompt.md`.
- Reuses: `check-state.mjs` validation logic, `docs-audit.mjs --gate` (SPEC-0011).

## Desired Behavior (To-Be)
- No role prompt instructs a free-text edit of STATE.yaml; every mutation goes
  through `state.mjs`, which cannot produce duplicate top-level keys and always
  bumps `updated_at_utc` on the real field.
- After a Remediation completes, STATE shows `last_validation.status: not_run`
  (and `code_review.status: not_run` when review had failed), so the next
  orchestration tick dispatches an independent re-Validation / re-Review; the
  remediation context never records its own verdict.
- An Implementation/TDD handoff on a gate-opted spec passes
  `docs-audit.mjs --gate <SPEC-ID>` (exit 0) before Validation is dispatched;
  Validation's AC-STATUS GATE stops being the first place the table is seen.
- Tick lines and agent_runs entries are written by the helper with real
  system-clock timestamps; the model supplies only the semantic fields.

## Acceptance Criteria
- AC-001: `state.mjs` subcommands (`set-focus`, `set-phase`, `set-validation`,
  `set-code-review`, `append-run`, `log-tick`, `reset-block`) mutate
  STATE.yaml/LOOP_TICKS.jsonl atomically; after any command `check-state.mjs`
  exits 0; invalid enum values / unknown refs exit non-zero without writing.
- AC-002: an interrupted write (simulated kill mid-rewrite) never leaves a
  truncated or duplicate-key STATE.yaml (atomic temp-file + rename).
- AC-003: every listed prompt's STATE-mutation instruction references
  `state.mjs` (grep-verified), with a documented fallback when the script is
  absent; no prompt retains a raw `sed`/`node -e` STATE edit as the primary path.
- AC-004: REMEDIATION instructs `reset-block` + forbids writing its own
  validation/review verdict; ORCHESTRATION dispatches Validation (rule 11) on
  the tick following a remediation that reset a FAIL (fixture-driven test of the
  decision inputs, or grep-wiring assertions on both prompts).
- AC-005: IMPLEMENTATION and SKILL_TDD contain the pre-handoff AC-table
  reconciliation step incl. `--gate` self-check (grep-verified); a simulated
  handoff with an unreconciled table is caught by the implementer-side gate
  call (exit 1) before Validation.
- AC-006: `log-tick` produces LOOP_TICKS.jsonl lines schema-compatible with the
  existing hand-written ones (all required fields, real timestamps, no
  model-fabricated timing).
- AC-007: new behavior covered by tests in the skills suite; existing suites
  (docs-audit, test-canon, check-state, orchestration-mode, docs-lock, intake)
  stay green.

## Verification
- `bash tests/skills/test-aai-state.sh` (via `.aai/scripts/aai-run-tests.sh`) —
  CLI unit/integration cases green, incl. kill-mid-write atomicity case.
- Grep-wiring assertions over the nine prompts (mirroring TEST-015..017 style
  from SPEC-0005/0011).
- Full existing suites re-run green; `docs-audit.mjs --check --strict` CLEAN;
  `generate-docs-index.mjs` idempotent.
- Manual loop smoke: one FAIL→Remediation→re-Validation cycle driven in a
  fixture repo shows `not_run` between remediation and re-validation and no
  self-recorded PASS.

## Constraints / Risks
- Prompts are vendored downstream; keep the old inline instructions as an
  explicit fallback path ("if state.mjs is absent…") so older vendored projects
  do not break mid-migration (same degrade pattern as docs-audit tooling).
- `state.mjs` must not reorder/reformat unrelated YAML (preserve comments and
  key order where feasible) to keep diffs reviewable; document any normalization.
- LOOP_TICKS.jsonl / STATE.yaml are gitignored per-developer runtime files —
  tests must use fixture repos, never the real repo state.
- The reset rule must not fire when remediation targets a non-validation defect
  (e.g. post-PASS review WARNING remediation) — reset only the block that was
  `fail`.

## Notes
- Sourced from the 2026-07-04 skills audit (defect classes 1, 2, 3, 5) and the
  CHANGE-0005 loop run evidence (manual timestamp-regex mishap; manual
  `last_validation` reset between ticks 5–6; guaranteed AC-table FAIL at tick 4).
- Companion hygiene items (body lint, PR ceremony, warnings policy, fixture
  diversity, trigger wiring) are split into CHANGE-0007.
