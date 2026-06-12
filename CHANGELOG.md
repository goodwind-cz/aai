# Changelog

All notable changes to AAI are documented in this file. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). AAI does not yet
follow semantic versioning — entries are grouped by date or release event.

For target projects: run `/aai-update` to pull the latest layer. After
updating, run `/aai-doctor` to surface any migration actions specific to
your project (for example, the STATE-to-local migration introduced in
RFC-0001).

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
