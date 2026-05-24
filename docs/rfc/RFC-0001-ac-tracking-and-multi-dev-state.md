---
id: RFC-0001
type: rfc
status: implementing
links:
  spec: null
  pr: []
  commits:
    - aaae190
---

# RFC-0001 — AC-level Tracking and Multi-Dev STATE

## Context

Two coupled pain points have surfaced in real AAI usage:

1. **Doc-status invisibility at the AC level.** The current document tree (`docs/{rfc,issues,specs,requirements,releases}/`) provides structure but no way to tell what is done, what is in progress, what is deferred, and where deferred items live. The only existing status mechanism is `SPEC-FROZEN: false` in `SPEC_TEMPLATE.md` plus per-`TEST-xxx` lifecycle (`pending → red → green`). `ISSUE_TEMPLATE.md` and `RFC_TEMPLATE.md` have no status fields at all. AI agents frequently perform partial implementations and the unimplemented acceptance criteria silently vanish — there is no enforced gate that flags this. Deferred items get postponed without a target, a due date, or a backlink, and later become impossible to find.

2. **`STATE.yaml` does not survive multi-developer use.** `docs/ai/STATE.yaml` is a deeply-nested mutable YAML committed to git, with a singular `current_focus` field. Invariant INV-03 (`current_focus.type == none → active_work_items empty`) couples runtime focus to active work, so two developers working in parallel produce conflicting `current_focus` states with no automatic merge resolution. The same applies to `LOOP_TICKS.jsonl` which is also committed. For a 4–10 developer team this is the dominant friction point.

Drivers:
- AI agents must not be allowed to silently drop acceptance criteria
- Deferred items must remain findable and must resurface for review automatically
- Multi-developer git workflows must not require constant manual merge resolution of runtime state
- Changes must be backwards-compatible — existing target projects with `aai-update` must keep working without forced migration

## Proposal

**Recommended option: "Lean with teeth" — minimal frontmatter + per-AC table extension + validation gate + auto-detected legacy fallback + STATE relocated to local-only.**

Five layers:

### 1. Minimal frontmatter on all doc types

Required for new docs in `docs/{issues,rfc,specs,requirements,releases}/`:

```yaml
---
id: SPEC-0042              # stable, never reused
type: spec                 # issue|rfc|spec|release|requirement
status: implementing       # draft|implementing|done|deferred|rejected|superseded
links:                     # optional
  rfc: RFC-0042
  pr: 123
---
```

Only three required fields. `owner`, `created_at`, etc. can be derived from `git log` and added later only when needed.

### 2. Per-AC table extension in `SPEC_TEMPLATE.md`

Extend the existing Spec-AC table with `Status`, `Evidence`, `Review-By`, and `Notes` columns:

```markdown
| Spec-AC    | Description       | Status      | Evidence  | Review-By  | Notes                  |
|------------|-------------------|-------------|-----------|------------|------------------------|
| Spec-AC-01 | Frontmatter       | done        | a1b2c3d   | —          | —                      |
| Spec-AC-07 | Auto-migration    | deferred    | —         | 2026-08-01 | → RFC-0051, scope v2   |
| Spec-AC-08 | Perf optimization | blocked     | —         | 2026-06-15 | waiting on DB review   |
```

Status values: `planned | implementing | done | deferred | blocked | rejected`.

The existing per-`TEST-xxx` table (`pending/red/green`) is unchanged — tracking tests is orthogonal to tracking AC delivery.

### 3. Validation gate with three rules (the teeth)

Update `.aai/VALIDATION.prompt.md` to enforce, at PASS claim time:

- **Rule 1 — no silent partials:** any Spec-AC in `planned` or `implementing` status blocks PASS.
- **Rule 2 — no unsubstantiated done:** any Spec-AC with status `done` and empty Evidence blocks PASS.
- **Rule 3 — overdue review is a global interrupt:** the gate scans every spec across the repo; any Spec-AC with status `deferred` or `blocked` whose `Review-By` is in the past blocks any PASS anywhere in the repo until the entry is re-decided.

Anti-cheat: `Review-By` must be at least 14 days in the future or the gate rejects the deferral.

**Backwards-compatibility hook:** the gate auto-detects new vs. legacy specs by the presence of the `Review-By` column header. Legacy specs are skipped entirely — they continue to behave exactly as today. This is critical: it removes any forced migration moment for existing target projects.

### 4. One auto-generated `docs/INDEX.md` (~80 LOC script)

New `.aai/scripts/generate-docs-index.mjs` walks `docs/{issues,rfc,specs,requirements,releases}/**/*.md`, parses frontmatter and the per-AC table, and produces an idempotent INDEX with sections: Overdue reviews, Active, Done, Deferred (cross-spec aggregated), Blocked (cross-spec aggregated), Broken references, Legacy.

A broken-reference check verifies that every `→ <DOC-ID>` reference in a Notes column points to an existing document. The check does not judge target status — only existence.

The script tolerates legacy docs (no frontmatter, no Spec-AC table) and logs a warning rather than failing.

### 5. STATE relocated to local-only, EVENTS.jsonl for shared audit

- `docs/ai/STATE.yaml` → `.gitignore` (per-dev local runtime)
- `docs/ai/LOOP_TICKS.jsonl` → `.gitignore` (per-dev local runtime)
- `docs/ai/METRICS.jsonl` stays committed (already append-only, merge-safe)
- New `docs/ai/EVENTS.jsonl` committed, append-only, JSONL with exactly four event types: `ac_status`, `ac_evidence`, `defer_extended`, `doc_lifecycle`. Schema versioned (`v: 1`).

EVENTS provides cross-developer visibility and audit history of AC transitions without reintroducing the YAML merge problem and without requiring per-actor STATE directories or replay logic. Runtime events (`phase_change`, `lock_change`, etc.) stay in local `LOOP_TICKS.jsonl`.

Rationale: addresses the dominant pain (silent partials, lost deferrals, STATE merge conflicts) with mechanism rather than discipline. Review-By dates turn deferral into a tickler that automatically resurfaces — there is no way for a deferred item to be silently forgotten. Local STATE plus shared EVENTS gives audit and cross-dev visibility without architectural complexity.

## Alternatives Considered

### Option A: Heavy plan — full frontmatter, per-actor STATE dirs, EVENTS.jsonl with 10+ event types, replay logic

- **Pros:** complete architectural solution, full event sourcing, dashboard integration, per-actor cross-dev visibility at runtime.
- **Cons:** ~17 files changed, requires per-actor directory namespacing, replay logic to reconstruct STATE, dual-write migration phase, full doc frontmatter schema, dashboard extension. Significant engineering investment for problems that may not materialize (e.g., per-actor runtime visibility) and that this proposal solves via simpler mechanisms (EVENTS log for audit instead of per-actor STATE for visibility).
- **Rejected because:** the marginal value over the recommended option is small relative to the cost. The recommended option leaves all the heavier pieces as additive future work, not a breaking refactor.

### Option B: Minimal lean — doc-level `status:` field only, validation gate, STATE to `.gitignore`

- **Pros:** ~8 lines changed total, no scripts, no generators, no schema.
- **Cons:** does not address per-AC granularity (the actual reported pain). Doc-level `status: implementing` does not surface that one specific AC was silently deferred. Has two fatal gaps documented earlier:
  - **Dead deposit:** gate enforces terminal status, but nothing forces a return to a `deferred` item. Under pressure, agents will set `deferred` to make PASS succeed and the item rots.
  - **Dead links:** `deferred → RFC-0051` where RFC-0051 never exists, with no detection.
- **Rejected because:** it fails on the specific case the user identified — AC-level deferral that gets lost.

### Option C: GitHub Issues / Projects as source of truth

- **Pros:** no new infrastructure; status, milestones, PR linking are native; familiar to teams.
- **Cons:** binds AAI to GitHub; creates two systems (markdown spec + GitHub issue) that drift; cannot enforce gates at AAI validation time without GitHub API integration; loses offline / multi-host portability.
- **Rejected because:** AAI is designed to be host-agnostic and operate from local markdown alone.

### Option D: Status from directory or filename convention

- **Pros:** zero parsing logic; `git mv` for status changes; trivially grep-able.
- **Cons:** does not address per-AC granularity; conventions drift; no mechanism for Review-By tickler; no broken-reference check.
- **Rejected because:** same fundamental limitation as Option B at the doc level.

## Consequences

### Technical impact

- New required schema in `.aai/templates/{SPEC,ISSUE,RFC}_TEMPLATE.md` (frontmatter + per-AC columns in SPEC).
- New validation rules in `.aai/VALIDATION.prompt.md` with explicit legacy bypass.
- Two new helper scripts: `.aai/scripts/generate-docs-index.mjs`, `.aai/scripts/append-event.mjs`.
- Two new migration helpers: `.aai/scripts/migrate-state-to-local.{sh,ps1}` and optional `.aai/scripts/migrate-spec-template.{sh,ps1}`.
- New shared append-only file `docs/ai/EVENTS.jsonl`.
- `.gitignore` additions for `docs/ai/STATE.yaml` and `docs/ai/LOOP_TICKS.jsonl`.
- Updates to `aai-sync.{sh,ps1}` to inject the new `.gitignore` rules automatically, and to preserve `EVENTS.jsonl` as runtime data.
- `aai-doctor` skill gains diagnostics for legacy `STATE.yaml` in git tree and legacy specs without frontmatter.

### Operational impact

- Validation behavior changes only for specs that adopt the new per-AC table — legacy specs continue exactly as today. No forced migration moment.
- Deferred items become impossible to silently forget: when `Review-By` passes, all subsequent PASS attempts across the repo are blocked until the item is re-decided. This is intentional and is the proposal's primary value.
- Multi-developer projects can keep STATE local without losing cross-developer visibility into AC transitions — EVENTS.jsonl provides the audit trail.
- New docs use the new templates immediately after sync; old docs are migrated opportunistically (per touch) or via the optional batch migration script.

### Migration / compatibility notes

Three-phase rollout, no big-bang day:

1. **Canonical repo** ships the templates, validation gate, and scripts via `aai-sync`. ~3 days of focused work, three independent PRs (templates+gate, INDEX generator, EVENTS append helper).
2. **Per-project rollout** is `/aai-update` in each target project (pulls new layer automatically), then one-time `bash .aai/scripts/migrate-state-to-local.sh` to untrack `STATE.yaml` and `LOOP_TICKS.jsonl` from git. Roughly 10 minutes per project.
3. **Per-spec migration** is opportunistic — gate auto-detects legacy and skips it. Optional batch migration script prepares structure but does not invent semantics (does not guess `deferred` status or `Review-By` dates).

Rollback is straightforward at every layer: `git revert` PRs in canonical, restore `STATE.yaml` tracking with three lines, remove `Review-By` column from a single spec to disable its gate. No data loss in any rollback path.

## Risks

- **R1 — False deferrals as escape hatch.** Agents under pressure may mark ACs `deferred` with a far-future `Review-By` purely to make PASS succeed. Mitigation: anti-cheat enforces `Review-By` ≥ +14 days minimum; INDEX aggregates all deferrals across the repo so they are visible; monthly grep of overdue/upcoming reviews is a cheap process-level audit. Long-term: a `deferred_count` ceiling per spec could be added if abuse materializes.
- **R2 — Broken-reference check false negatives.** The check is regex-based (matches `→ <DOC-ID>` patterns). Free-form Notes that reference docs differently will not be caught. Mitigation: document the convention; accept some false negatives as the cost of zero schema overhead.
- **R3 — EVENTS.jsonl merge edge cases.** Two developers committing simultaneously may produce conflict markers in append-only JSONL. Mitigation: standard JSONL append discipline (same as METRICS.jsonl today); manual resolution is trivial (accept both lines); pre-commit auto-resolver can be added later if frequency warrants.
- **R4 — Sync overrides project-customized VALIDATION.prompt.md.** `aai-sync` will overwrite a project's locally edited `.aai/VALIDATION.prompt.md`. Mitigation: document in changelog; long-term, adopt the project-overrides pattern already used for `copilot-instructions.md`.
- **R5 — Legacy specs never get migrated and the dual-mode validation lives forever.** Mitigation: acceptable. Dual-mode is a few lines of code; legacy specs that no one touches do not need to be migrated. Eventually old specs become archived.
- **R6 — `Review-By` clock skew or timezone confusion.** Mitigation: ISO-8601 dates only (`YYYY-MM-DD`), compared at UTC midnight; gate error message includes both the stored date and today's date.

## Open Questions

1. **Should `Review-By` accept quarter granularity (`2026-Q3`) in addition to ISO dates?** Cleaner for "review next quarter" intent but adds parsing complexity. Initial recommendation: ISO dates only; revisit if real usage shows demand.
2. **Should `aai-doctor` actively suggest migration of legacy specs, or only report counts?** Initial recommendation: report counts only; let project owners decide pace.
3. **Should the broken-reference check resolve `Review-By` against the target doc's lifecycle?** For example, if `deferred → RFC-0051` and RFC-0051 is `status: rejected`, surface a warning? Initial recommendation: not in first version; the check stays existence-only.
4. **Should EVENTS.jsonl include `actor` derived from git or from a configurable AAI identity?** Initial recommendation: `git config user.email` slug; configurable later only if conflicts arise.
5. **Should there be a global config file (`.aai/config/gate.yaml`) for tuning anti-cheat windows, gate enable/disable, etc.?** Initial recommendation: not yet; hard-code defaults; revisit after one quarter of usage.

## Approvals

- Required approvers: AAI canonical repo maintainer.
- Optional reviewers: developers from any target project planning to adopt the changes; one reviewer who has been affected by the multi-dev STATE merge pain.

## Notes

- Full implementation plan (sequencing, file paths, verification steps, migration scripts) is maintained in the author's plan file at `/Users/ales/.claude/plans/potrebuji-predelat-ukladani-glistening-giraffe.md`. That plan is the operational counterpart to this proposal; if this RFC is accepted, the relevant sections will be promoted into a frozen spec under `docs/specs/`.
- This RFC was originally authored in the legacy template format (no frontmatter). After PR 1 of the proposal landed in commit `aaae190`, frontmatter was added in PR 2 — providing the first dogfooding case for the proposed migration path. Status is `implementing` while PR 2 (INDEX generator) and PR 3 (EVENTS audit log) land. It will move to `done` once all three PRs are merged and a validation PASS is recorded against the new template specs.
- Use plain Markdown headings and body text. Do not add emoji or decorative icons unless there is a strong domain-specific reason.
