# Changelog

All notable changes to AAI are documented in this file. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). AAI does not yet
follow semantic versioning — entries are grouped by date or release event.

For target projects: run `/aai-update` to pull the latest layer. After
updating, run `/aai-doctor` to surface any migration actions specific to
your project (for example, the STATE-to-local migration introduced in
RFC-0001).

## [unreleased] — loop hardening: stagnation guard, version + cost telemetry, L1 triage

Loop-engineering hardening informed by the Ralph Wiggum / loop-engineering
prior art (Huntley, Osmani, Anthropic "Building Effective Agents"). The AAI
loop already covered the core best practices (filesystem-as-memory, hard stop
conditions, maker≠checker, evidence-gated PASS); these close the remaining gaps:

- **Stagnation guard** (`SKILL_LOOP.prompt.md`, `system/AUTONOMOUS_LOOP.md`,
  `scripts/autonomous-loop.{sh,ps1}`): new `stagnation_limit` (default 3, also a
  `--stagnation-limit` / `-StagnationLimit` flag on the runners). When
  `focus_ref_id` and `validation_status` stay unchanged for that many
  consecutive ticks, the loop escalates to HITL (recording a `human_pause`)
  instead of spinning the remaining tick budget. Computed from existing
  `LOOP_TICKS.jsonl` fields — no new state.
- **Version drift telemetry**: each tick line now records `harness_version`
  (captured once at loop start, in both the in-session loop and the
  `autonomous-loop.{sh,ps1}` runners) so a behavior regression can be correlated
  with a harness upgrade. The runners also emit a per-tick `stagnation_count`.
- **Cost observability + caching discipline**: tick lines may carry optional,
  best-effort `input_tokens` / `output_tokens` / `cache_read_tokens` /
  `est_cost_usd` (only when the runtime exposes real usage — never fabricated).
  A new CACHING DISCIPLINE note codifies keeping the loop session-resident (not
  cron-per-tick) and a stable cacheable prefix, to stay inside the ~5 min cache
  TTL.
- **L1 triage** (`.aai/scripts/triage.{sh,ps1}`): cheapest rung of autonomy —
  a read-only health snapshot (docs drift via `docs-audit --quick`, state
  presence, working-tree, last tick). Writes nothing, safe to `/schedule`;
  `--check` exits 1 on real docs drift for use as a CI/daily alarm.

## [unreleased] — chore: gitignore TDD evidence logs

`docs/ai/tdd/**` (red/green/refactor test-output logs) is now gitignored
with a `.gitkeep` placeholder — same policy as `docs/ai/reports/**`:
per-dev runtime evidence, pruned by METRICS_FLUSH after 7 days; durable
evidence lives in AC Status tables and EVENTS.jsonl.
`migrate-state-to-local.{sh,ps1}` additionally untracks any already
committed TDD logs and injects the ignore patterns in downstream projects.
Same treatment for `docs/ai/loop/` — ad-hoc per-tick scratch some loop
runs create; canonical loop state lives in STATE.yaml/LOOP_TICKS.jsonl
(local) and EVENTS.jsonl/METRICS.jsonl (committed). The migrate scripts'
gitignore checks are now CR-tolerant (CRLF downstream gitignores).

## [unreleased] — CHANGE-0003: docs-audit verify mode

Adds the third skill mode
([CHANGE-0003](docs/issues/CHANGE-0003-docs-audit-verify-mode.md)):
semantic docs-vs-code reconciliation. The audit checks claims against
traces (commits, events); `verify` checks them against the code itself.

### Added
- `/aai-docs-audit verify <DOC-ID>`: the agent reads each acceptance
  criterion, probes the codebase (search, read, run existing tests —
  never writes code), and proposes per-AC verdicts (`implemented` with
  path:line or test evidence / `not-implemented` / `cannot-determine`).
  Operator approves per item; approved updates write the AC Status table
  and emit `ac_status`/`ac_evidence`/`doc_lifecycle` events, after which
  the standard gate and drift audit guard the doc. Expensive by design:
  one doc (or named small batch) per invocation.
- Guard test pinning that the skill prompt documents all three modes
  (audit / remediate / verify).
- USER_GUIDE: "three modes, three questions" overview and verify step in
  the retro-cleanup workflow.

## [unreleased] — CHANGE-0002: docs-audit engine improvements, round 2

Triage and fixes for six further deficiencies from the downstream second
remediation pass
([CHANGE-0002](docs/issues/CHANGE-0002-docs-audit-engine-improvements-2.md)).
All six accepted (D11 partly already worked; verifying it exposed and
fixed a real prefix-match bug).

### Added
- Review-By accepts `<actor> <method>` composition: Claude model ids
  (`claude-sonnet-4-6`, ...) or `human`/`operator`(`:<name>`) plus a
  method from the label set, extended methods (`PlaywrightSuites`,
  `Validation`, `TDD-snapshot-scripts`; extensible via
  `review_by_methods` config), or `method:date`. Bare actor without a
  method stays invalid (D10).
- `PARENT-ID/<sub-item>` EVENTS refs documented (SKILL_LOOP,
  append-event header); engine evidence lookup now boundary-safe —
  `CHANGE-0045` events no longer count for `CHANGE-004` (D11).
- `plan_scan_mode` config (default `lenient`): `docs/plans/**` files
  without frontmatter inventory as operator plan files instead of
  orphans; `strict` restores the old behavior (D12).
- Index generator auto-demotes schema violations in legacy-classified
  docs (first commit before `legacy_until_date`) to the Skipped section,
  tagged `[legacy — auto-skipped]`; non-legacy violations still fail (D13).
- Suggested ID lists every ID shape in multi-ID filenames
  (`PRD-022 (primary) + PRD-024 + PRD-025`; `PRD-022 (primary) +
  TEST-021`) (D14).
- `category_prefixes` config (default `PHASE`, `MILESTONE`, `EPIC`):
  category-scoped filenames get unique slug IDs plus a Scope shown in
  `--list` (`DECISION-PHASE-0-scope` / scope `PHASE-0`) (D15).

### Fixed
- `firstCommitDate` no longer uses `git log --follow`, whose rename
  detection mis-attributed a file's add commit to an unrelated commit
  adding similar content — legacy/new classification could be wrong for
  similar-looking docs (found by the D13 fixture).

## [unreleased] — CHANGE-0001: docs-audit engine improvements

Triage and fixes for nine deficiencies reported from the first real
downstream remediation run
([CHANGE-0001](docs/issues/CHANGE-0001-docs-audit-engine-improvements.md)).
All changes are relaxations or additive, default-off validators —
no breaking change for existing projects.

### Added
- Compound doc IDs (`SPEC-CHANGE-027`, `DECISION-RFC-002`,
  `SPEC-PROC-10`, `DECISION-SPEC-FE-13`, `SPEC-PRD-022`, ...) are now
  scanned: shared `DOC_ID_RE` allows letter segments between prefix and
  a 1-5 digit tail; the `→ DOC-ID` broken-ref matcher loosened
  identically (D1).
- Legacy `SPEC-FROZEN: true` body markers (bare, `**bold-key:**`,
  `**bold**: `, emoji-prefixed) make a `status: draft` doc effectively
  frozen — no more false probable-stale-open on frozen-in-body specs (D2).
- `amendment_note` / `amended_by` / `superseded_by` frontmatter fields
  recognized and surfaced in the digest Annotations section; enum
  unchanged (D3, option a).
- Review-By accepts skill literals (`TDD`, `Loop`, `code-review`,
  `manual`, `deferred`) and `label:YYYY-MM-DD` combos in both the audit
  and the INDEX generator; only dated forms feed overdue checks (D4).
- Drift digest gains a per-doc Triage commands block (`git log --grep`,
  `head -50 <path>`) (D5).
- Digest "Pending commit" notice lists scanned docs with uncommitted
  changes; regression test pins that verdicts always reflect the working
  tree, so adding frontmatter clears an orphan without committing (D6).
- `DOC_TYPE_ENUM` validation: unknown `type:` warns by default,
  `--strict-types` promotes it to a hard failure (D7).
- Orphan table gains a Suggested ID column inferred from the filename (D8).
- `generate-docs-index.mjs --continue-on-error`: renders a partial INDEX
  plus a "Skipped (schema violations)" section instead of hard-aborting;
  default CI behavior unchanged (D9).

## [unreleased] — RFC-0002: docs hygiene and drift audit

Implements [RFC-0002](docs/rfc/RFC-0002-docs-hygiene-and-drift-audit.md)
([SPEC-0001](docs/specs/SPEC-0001-docs-hygiene-and-drift-audit.md)) in
response to a downstream triage brief documenting four drift classes:
orphan docs, false-done, stale-open, bulk frontmatter drift. The audit
REPORTS; the operator DECIDES — nothing is auto-fixed.

### Added
- `.aai/scripts/docs-audit.mjs`: classifies every prefixed doc under
  `docs/` (orphan / superseded / drifted / tracked-done / obsolete /
  tracked-open) and derives drift verdicts (`probable-false-done`,
  `probable-partial`, `probable-stale-open`) from frontmatter, AC tables,
  EVENTS.jsonl, and git evidence. Flags: `--check` (CI gate via exit
  code), `--quick` (counts only, no git probes), `--path`, `--strict`
  (enforce without config; intake post-save gate), `--no-event`.
- `.aai/scripts/lib/docs-model.mjs` + `lib/docs-audit-core.mjs`: shared
  doc-model parsers (extracted from the INDEX generator) and audit core.
- Optional committed config `docs/ai/docs-audit.yaml`
  (`legacy_until_date`, `stale_after_days`, `scan_exclude`,
  `backlog_globs`). Absent config means report-only — first runs never
  hard-fail legacy backlogs.
- `/aai-docs-audit` skill (`.aai/SKILL_DOCS_AUDIT.prompt.md` +
  `.claude/skills/aai-docs-audit/SKILL.md`) with an operator-approved
  interactive remediation mode for retroactive backfill.
- `docs/INDEX.md` sections: `Orphans (need triage)` and `Drift report`.
- `docs_audit` event type in `append-event.mjs` (counts payload), emitted
  best-effort by every non-quick engine run.
- `.aai/templates/DOCS_AUDIT_TEST_TEMPLATE.md`: portable CI gate wrappers
  (plain CI step, vitest, pytest).
- `tests/skills/test-aai-docs-audit.sh`: fixture-per-drift-class suite.

### Changed
- `SKILL_INTAKE.prompt.md` + all eight `INTAKE_*.prompt.md`: post-save
  template-compliance check (`--check --strict --path <artifact>`); an
  artifact cannot be reported saved while non-compliant.
- `SKILL_LOOP.prompt.md`: cheap `--quick` docs hygiene check once per
  tick, surfaced in the tick summary (never blocks).
- `VALIDATION.prompt.md`: step 8b done-transition assertion — a spec
  cannot move to `done` without a fully terminal, evidenced AC table.
- `SKILL_DOCTOR.prompt.md`: new CAT-11 Docs Hygiene category.
- `generate-docs-index.mjs`: now consumes the shared parser lib.

## [unreleased] — RFC-0001: AC-level tracking and multi-dev STATE

Implements [RFC-0001](docs/rfc/RFC-0001-ac-tracking-and-multi-dev-state.md)
in three sequential PRs. Designed for zero breaking change in target
projects: the validation gate auto-detects opt-in by spec column, legacy
specs continue to behave exactly as before, and the STATE relocation
requires an explicit per-project migration step.

### Added
- Minimal frontmatter (`id`, `type`, `status`, `links`) on document
  templates: ISSUE, RFC, SPEC, REQUIREMENT, RELEASE, CHANGE, TECHDEBT,
  RESEARCH. Status enum: `draft | implementing | done | deferred | rejected | superseded`.
- SPEC_TEMPLATE: new "Acceptance Criteria Status" table with columns
  `Spec-AC | Description | Status | Evidence | Review-By | Notes`.
  Separate from the existing per-`TEST-xxx` lifecycle table.
- VALIDATION.prompt.md: AC STATUS GATE section with four rules
  (no silent partials, no unsubstantiated done, overdue Review-By blocks
  any PASS in the repo, anti-cheat minimum +14 days on Review-By).
- `.aai/scripts/generate-docs-index.mjs`: generates `docs/INDEX.md` with
  sections for Overdue / Active / Done / Drafts / Deferred / Blocked /
  Broken references / Rejected / Legacy. Tolerant to legacy docs. Marker
  discipline prevents overwriting hand-maintained INDEX.md.
- `.aai/scripts/append-event.mjs`: helper that appends a single audit
  event to `docs/ai/EVENTS.jsonl`. Event types: `ac_status`,
  `ac_evidence`, `defer_extended`, `doc_lifecycle`. Auto-fills `v`,
  `ts`, `actor`.
- `.aai/scripts/migrate-state-to-local.{sh,ps1}`: target-project
  migration helper. Untracks STATE.yaml + LOOP_TICKS.jsonl, adds
  gitignore entries, creates EVENTS.jsonl. Idempotent, dry-run flag,
  refuses dirty working tree, never auto-commits.
- `docs/ai/EVENTS.jsonl`: new shared append-only audit log.
- `.aai/scripts/install-pre-commit-hook.{sh,ps1}`: opt-in helper that
  installs a `.git/hooks/pre-commit` to auto-regenerate `docs/INDEX.md`
  when `docs/` changes.
- `SKILL_DOCTOR.prompt.md`: new CAT-10 health check for STATE migration
  consistency (gitignored vs tracked, missing EVENTS.jsonl).
- `aai-sync.{sh,ps1}`: auto-injects STATE.yaml and LOOP_TICKS.jsonl
  gitignore entries into the target `.gitignore` on every sync.

### Changed
- `docs/ai/STATE.yaml` and `docs/ai/LOOP_TICKS.jsonl` are now per-developer
  local (gitignored). Previously committed to git, this caused
  multi-developer merge conflicts. Cross-developer visibility moves to
  `docs/ai/EVENTS.jsonl` (committed, append-only).
- `SKILL_LOOP.prompt.md`, `VALIDATION.prompt.md`, `METRICS_FLUSH.prompt.md`:
  emit `ac_status`, `ac_evidence`, and `doc_lifecycle` events to
  `docs/ai/EVENTS.jsonl` via `append-event.mjs`. Emissions are best-effort;
  failure does not abort the primary operation.
- README.md: documented per-dev STATE policy, EVENTS.jsonl, and migration
  pointer; updated sync exclusion list to include `docs/rfc/`.
- `aai-sync.{sh,ps1}`: `docs/rfc/**` added to the documented project-owned
  exclusion list (implementation already never synced it).

### Migration (per target project)
1. `/aai-update` — pulls the new layer; gitignore entries auto-added.
2. `bash .aai/scripts/migrate-state-to-local.sh --dry-run` — preview.
3. `bash .aai/scripts/migrate-state-to-local.sh` — untrack STATE files.
4. Commit the resulting `.gitignore` change and the new `EVENTS.jsonl`.
5. `/aai-doctor` — verify migration completed cleanly.
6. (Optional) `bash .aai/scripts/install-pre-commit-hook.sh` to auto-regen
   `docs/INDEX.md` on every commit touching `docs/`.

Existing specs continue to validate exactly as before. The new AC STATUS
GATE activates only when a spec opts in by including a `Review-By` column
in its Acceptance Criteria Status table.

### Removed
- Nothing was removed. RFC-0001 is purely additive on the canonical layer.
- `docs/ai/STATE.yaml` and `docs/ai/LOOP_TICKS.jsonl` were untracked from
  the canonical repo (`git rm --cached`); the files remain on disk and
  continue to function as per-developer runtime state.

---

## Prior history

Earlier changes are recorded in `git log`. This CHANGELOG starts with
RFC-0001 — earlier features were tracked only in commit messages.
