---
id: RFC-0002
type: rfc
status: done
links:
  rfc: RFC-0001
  spec: SPEC-0001
  pr: []
  commits:
    - 728ea95
---

# RFC-0002 — Docs Hygiene and Drift Audit

## Context

A downstream project (fh-workspace, consuming AAI via `aai-update`) submitted a
triage brief dated 2026-06-12 documenting four classes of documentation drift
observed across 404 prefixed doc IDs over an 8-week period:

1. **Orphan docs** — doc files land in `docs/` without template frontmatter and
   without being wired into any plan. Example: four ISSUE docs added in one
   commit, discovered only by manual grep five months later.
2. **False-Done** — a doc with N acceptance criteria is marked Done in an
   operator backlog while the code ships 1 of N. Invisible because the doc
   skipped the Acceptance Criteria Status table.
3. **Stale-Open** — a doc filed Open whose work was completed incidentally by
   other changes; nobody updated the doc. Open for months after the fact.
4. **Bulk frontmatter drift** — periodic manual sweeps flip dozens of stale
   `status` fields at once; the need for the sweep is itself the symptom.

The brief asks upstream to (1) confirm the primitives it lists, (2) resolve
five decisions D1-D5, (3) produce a design, and (4) stop before implementation
for operator review. This RFC is that design. It builds directly on RFC-0001,
which shipped the tracking primitives; this RFC adds the missing enforcement.

## Primitives Confirmation

Verified against the live upstream codebase on 2026-06-12:

| # | Brief claim | Verdict | Notes |
|---|---|---|---|
| 1 | Templates in `.aai/templates/*.md` mandate frontmatter (`id`, `type`, `status`, `links`) | Confirmed | All 14 templates carry the RFC-0001 frontmatter block. |
| 2 | `SPEC_TEMPLATE.md` has an `## Acceptance Criteria Status` table convention | Confirmed, with correction | Only `SPEC_TEMPLATE.md` has the table (line 63). `CHANGE_TEMPLATE.md` does **not** — the brief's CHANGE-048 example assumes it does. See Open Question 1. |
| 3 | `docs/ai/EVENTS.jsonl` + `.aai/scripts/append-event.mjs` emit `ac_status` and `doc_lifecycle` | Confirmed | Event types are a **closed set** (`ac_status`, `ac_evidence`, `defer_extended`, `doc_lifecycle`). Adding `docs_audit` requires extending `EVENT_TYPES` in the helper. |
| 4 | `SKILL_LOOP.prompt.md` states the events discipline | Confirmed | Lines 16-35; loop emits `ac_status`/`doc_lifecycle`, never `ac_evidence`. |
| 5 | `aai-validation` emits `ac_evidence` when Evidence is populated | Confirmed | `VALIDATION.prompt.md` step 8a. |

Two primitives the brief does not know about, which materially change the
design (the fix is smaller than the brief assumes):

| # | Existing primitive | Coverage |
|---|---|---|
| 6 | `.aai/scripts/generate-docs-index.mjs` (RFC-0001 layer 4) already walks `docs/{issues,rfc,specs,requirements,releases}`, parses frontmatter + AC tables, detects legacy docs, overdue Review-By dates, and broken `→ DOC-ID` references, and renders `docs/INDEX.md` with per-class sections | Covers a large part of brief deliverables 1 (classification) and 3 (dashboard). The audit must extend this script's model, not duplicate it. |
| 7 | `VALIDATION.prompt.md` AC STATUS GATE (RFC-0001 layer 3) already blocks PASS on any non-terminal Spec-AC, any `done` AC without Evidence, and any overdue `Review-By` repo-wide | Covers most of brief deliverable 6 (closeout-time check) for docs that go through validation. The gap is docs that never enter the loop. |

## Decisions (D1-D5)

### D1 — Architecture: (C) both, implemented as an extension of RFC-0001 layer 4

A new skill `aai-docs-audit` is the on-demand operator tool; enforcement is
hard-wired into `aai-intake`, `aai-loop`, `aai-validation`, and `aai-doctor`.
Both halves share one engine: a new `.aai/scripts/docs-audit.mjs` that reuses
the frontmatter/AC-table parsing extracted from `generate-docs-index.mjs` into
a shared module. No logic is duplicated; the skill and the hooks differ only
in invocation mode and verbosity.

Rationale: (A) alone leaves drift invisible between manual runs — exactly how
fh-workspace accumulated five-month-old orphans. (B) alone gives the operator
no first-run triage tool for the existing backlog of drifted docs. The brief's
own recommendation matches.

### D2 — Central view: enrich `docs/INDEX.md` in place

No new tracker file. `docs/INDEX.md` is already the auto-generated single
place to look (marker-protected, idempotent, sectioned). The audit adds two
sections: `Orphans (need triage)` and `Drift report`. This matches the
downstream operator signal ("one place for todo / progress / done") without
introducing a second source of truth. Per-type tracker files are rejected:
they re-create the N-places-to-look problem the operator complained about.

Operator-authored plan files (downstream `BACKLOG-overview.md`, `PLAN-*.md`)
are **read-only inputs**: a configurable glob lets the audit cross-check
"backlog says Done" claims against AC tables, but the audit never writes to
them. Upstream defines no backlog file convention; the glob is empty by
default.

### D3 — CI gate: script exit code, with a portable test wrapper as a template

`docs-audit.mjs --check` exits non-zero on hard failures (new doc without
template frontmatter, schema violations) and zero otherwise. This is the CI
gate. AAI is host-agnostic, so the gate must not require vitest; downstream
projects mount it in whatever runner they have. A ready-to-copy vitest wrapper
(`docs/__tests__/aai-docs-tracker.test.ts` shape, per the brief) ships as a
template in `.aai/templates/`, and the upstream repo gates itself via
`tests/skills/test-aai-docs-audit.sh`.

### D4 — Backwards compatibility: `legacy_until_date` in committed config, not STATE.yaml

The brief proposes the knob in `docs/ai/STATE.yaml`. That conflicts with
RFC-0001 layer 5: STATE.yaml is per-developer local runtime, gitignored in
downstream projects, so a shared policy knob cannot live there. Instead the
audit reads a small committed, project-owned config:

```yaml
# docs/ai/docs-audit.yaml (committed; created by operator or first audit run)
legacy_until_date: 2026-06-12   # docs first committed before this date soft-warn
stale_after_days: 90            # no DOC-ID-referencing commit for this long => stale candidate
scan_exclude: []                # extra path globs to skip
backlog_globs: []               # operator plan files to cross-check (read-only)
```

Legacy detection: a doc whose first-commit date (`git log --diff-filter=A
--format=%cs -- <path>`, last line) is before `legacy_until_date` is
**legacy** — missing frontmatter soft-warns. Docs first committed on/after the
date, and untracked files, are **new** — missing frontmatter hard-fails in
`--check` mode. When the config file is absent, the audit runs in report-only
mode (everything soft-warns) and prints how to enable enforcement, so the
first run never drowns the operator. Shallow clones where the first-commit
date is unknowable fall back to legacy (soft) plus a warning.

### D5 — Submodule scope: per-repo

Each repository carrying its own AAI layer audits its own `docs/`. The
workspace-root audit does not recurse into submodules. Recursion would couple
the audit to a git topology AAI does not otherwise assume, and submodules with
their own AAI flow already get the audit via their own `aai-update`. This
matches the brief's recommendation.

## Proposal

### Scan scope

Default scan: `docs/**/*.md` whose filename matches a prefixed doc ID
(`^[A-Z]+-\d{3,5}-`), excluding `docs/{ai,knowledge,archive,project-sessions,templates}`
and `INDEX.md`. This is broader than the RFC-0001 generator's five fixed
directories on purpose: downstream taxonomies place CHANGE/PRD/DECISION/
TECHDEBT docs in additional folders, and class-1 orphans by definition land in
unplanned locations. The existing generator keeps its five-directory scope for
INDEX rendering; the audit's classification feeds the two new INDEX sections.

### Deliverable 1 — Per-doc classification

Every scanned doc classifies into exactly one of:

| Class | Rule (first match wins, top-down) |
|---|---|
| `orphan` | No parseable frontmatter, or missing `id`/`status`, and the doc is **new** per D4. |
| `superseded` | Frontmatter status `superseded` or `rejected`. |
| `drifted` | Any drift heuristic below fires (deliverable 2). |
| `tracked-done` | Status `done`; AC table (if present) all terminal with evidence. |
| `obsolete` | Status `deferred` with all Review-By dates overdue, or **legacy** doc with no DOC-ID-referencing commit within `stale_after_days`. |
| `tracked-open` | Everything else with valid frontmatter (`draft`/`proposed`/`accepted`/`implementing`/`frozen`). |

Legacy docs missing frontmatter classify as `orphan` too, but are reported in
a separate soft-warn bucket and never fail `--check`.

### Deliverable 2 — Drift report

For each doc, compare frontmatter status, the AC Status table (when present),
`docs/ai/EVENTS.jsonl` entries referencing the doc ID, and a fresh evidence
probe (`git log --grep="<DOC-ID>"`). Verdicts:

- `aligned` — status, AC rows, and evidence agree.
- `probable-false-done` — status `done` (or backlog glob row marked Done) while
  AC rows are non-terminal or lack evidence, or while no commit references the
  doc ID.
- `probable-stale-open` — status `draft`/`implementing` with no doc edit and no
  DOC-ID-referencing commit within `stale_after_days`, especially when EVENTS
  or git show the referenced work completed elsewhere.
- `probable-partial` — status `done` on a doc type whose template mandates an
  AC table, but the table is absent (the CHANGE-048 shape).

All verdicts are heuristic, operator-reviewed, never auto-applied. The audit
**reports**; the operator **decides and edits**. The audit never modifies any
doc, plan file, or backlog row.

### Deliverable 3 — Operator dashboard

Two new sections in `docs/INDEX.md` (same marker, same idempotence):
`Orphans (need triage)` with a count CTA, and `Drift report` with one row per
non-aligned doc (verdict, evidence summary, suggested next step). Plain
markdown, cat-able. Additionally `docs-audit.mjs` prints the same digest to
stdout so the skill can show it in chat without reading the file.

### Deliverable 4 — EVENTS extension

Add `docs_audit` to the closed `EVENT_TYPES` set in `append-event.mjs`.
Payload: `{ total, orphans, drifted, stale, mode }` with `ref` =
`docs-audit/<scope>` (scope = `full` or a subpath). Emitted best-effort at the
end of every audit run (skill, loop tick, or `--check`), so audit history is
itself EVENTS-tracked. Schema stays `v: 1` — additive event type, no breaking
change.

### Deliverable 5 — Intake-time enforcement

`SKILL_INTAKE.prompt.md` (and the `INTAKE_*.prompt.md` entry points) gain a
post-save verification step: after writing the artifact, run
`node .aai/scripts/docs-audit.mjs --check --strict --path <saved-file>`
(`--strict` enforces even when `docs-audit.yaml` is absent — a just-saved
artifact is new by definition, so report-only leniency does not apply). If the saved
doc fails frontmatter validation, the intake must fix it before reporting the
artifact path — the artifact cannot be reported as saved while non-compliant.
This closes class 1's root cause at the only chokepoint AAI controls. Docs
added outside intake (human commits, other tools) are caught by the loop tick
and the CI gate instead.

### Deliverable 6 — Closeout-time check

The existing AC STATUS GATE already blocks false-done at validation time for
specs in the loop. Two additions:

- `VALIDATION.prompt.md`: when a doc's frontmatter transitions to `done`,
  assert the AC table (if mandated by its template) exists and is fully
  terminal with evidence; otherwise FAIL with the specific gap. Emit the
  existing `doc_lifecycle` event on the transition (already specified).
- `SKILL_LOOP.prompt.md`: each tick runs `docs-audit.mjs --quick` (counts
  only, no git probes — cheap) and surfaces non-zero orphan/drift counts in
  the tick summary. The loop does not block on them; it makes them visible.
- `SKILL_DOCTOR.prompt.md`: new category reporting audit counts and whether
  `docs/ai/docs-audit.yaml` exists (suggesting enforcement enablement).

### Assisted remediation mode (operator-approved backfill)

The audit never writes autonomously, but retroactive cleanup of an existing
backlog must not be manual drudgery. The skill therefore includes an
interactive remediation pass, entered only on explicit operator request
(`/aai-docs-audit remediate` or "apply suggestions N, M"):

1. The skill walks the current audit findings one by one. For each item it
   shows the verdict, the evidence, and the **exact proposed edit** (e.g., the
   frontmatter block to insert per the doc type's template, or the AC table
   reconciliation with per-row evidence from `git log` / EVENTS).
2. The operator approves, edits, or skips each item. Batch approval ("apply
   all orphan frontmatter fixes") is allowed; silent approval is not — the
   skill never proceeds past an unanswered item.
3. Every applied change emits its canonical event: frontmatter `status`
   transitions emit `doc_lifecycle`, AC row transitions emit `ac_status`, so
   the backfill itself lands in the EVENTS.jsonl audit history.
4. Proposals must be derivable from evidence. Where evidence is ambiguous
   (e.g., `probable-stale-open` with no commit referencing the doc), the skill
   proposes no status value — it asks. It never invents `done`.
5. Operator-authored plan/backlog files remain out of scope even here: the
   skill may show the suggested backlog row text, but the operator pastes it.
6. After the pass, the skill re-runs the audit and regenerates INDEX so the
   operator sees the residual count immediately.

This is compatible with the hard constraint: the decision stays with the
operator per item; the skill only removes the mechanical typing. There is no
non-interactive `--fix` flag, deliberately — unattended remediation is exactly
the auto-fix this RFC rejects.

### Files changed (implementation inventory, for the follow-up PR)

| Path | Change |
|---|---|
| `.aai/scripts/lib/docs-model.mjs` | New — frontmatter/AC-table parsers extracted from `generate-docs-index.mjs`. |
| `.aai/scripts/docs-audit.mjs` | New — classification, drift heuristics, digest, `--check`, `--quick`, `--path`. |
| `.aai/scripts/generate-docs-index.mjs` | Use shared lib; render two new sections from audit output. |
| `.aai/scripts/append-event.mjs` | Add `docs_audit` event type. |
| `.aai/SKILL_DOCS_AUDIT.prompt.md` | New — skill prompt (Appendix B). |
| `.claude/skills/aai-docs-audit/SKILL.md` | New — thin shim per upstream convention (Appendix A). |
| `.aai/SKILL_INTAKE.prompt.md` + `INTAKE_*.prompt.md` | Post-save `--check --path` verification step. |
| `.aai/SKILL_LOOP.prompt.md` | `--quick` tick summary + `docs_audit` event note. |
| `.aai/VALIDATION.prompt.md` | `done`-transition assertion. |
| `.aai/SKILL_DOCTOR.prompt.md` | New diagnostic category. |
| `.aai/templates/DOCS_AUDIT_TEST_TEMPLATE.md` | New — portable vitest wrapper for downstream CI. |
| `tests/skills/test-aai-docs-audit.sh` | New — fixtures per Appendix C. |
| `.aai/system/DYNAMIC_SKILLS.md`, `.aai/AGENTS.md`, `CHANGELOG` | Documentation. |

## Alternatives Considered

- **(A) New skill only.** Pros: smallest change, zero impact on existing
  flows. Cons: drift accumulates between manual runs; fh-workspace evidence
  shows nobody runs an optional audit until the damage is months old.
  Rejected.
- **(B) Extensions only.** Pros: enforcement is automatic. Cons: no on-demand
  first-run triage tool; the operator cannot scope, re-run, or dry-run the
  audit; loop ticks must stay cheap so they cannot carry the full git-probe
  drift analysis. Rejected.
- **Greenfield audit script ignoring `generate-docs-index.mjs`.** Rejected:
  duplicate parsers guarantee the two views drift apart — the exact disease
  this RFC treats.
- **Auto-fixing drift (flipping statuses, updating backlog rows).** Rejected
  by hard constraint: operator-authored markdown is sacred; heuristics are
  probabilistic and must not write unattended. The assisted remediation mode
  (see Proposal) is the accepted middle ground: per-item operator approval,
  evidence-derived proposals only, every change event-logged.

## Consequences

- Technical: one new engine script + shared parser lib; four prompt files gain
  small steps; one event type added; no schema version bump; no new doc type;
  no changes to STATE.yaml shape.
- Operational: new docs cannot be saved non-compliant via intake; loop ticks
  surface counts; CI can hard-fail orphan introduction; existing legacy docs
  only ever soft-warn until the operator sets `legacy_until_date`.
- Migration: downstream runs `aai-update`, optionally creates
  `docs/ai/docs-audit.yaml`. Expected fh-workspace first run (per the brief,
  with `legacy_until_date: 2026-06-12`): ISSUE-007/8/9/10 hard-fail as
  orphans, CHANGE-048 surfaces `probable-false-done` (via `probable-partial`
  + backlog glob), ~5 TECHDEBT items surface `probable-stale-open`.
- Rollback: revert the PR; `docs/INDEX.md` regenerates without the new
  sections; `docs_audit` events already in EVENTS.jsonl remain valid history.

## Risks

- **Heuristic false positives** burn operator trust. Mitigation: report-only,
  verdicts carry their evidence inline, `aligned` is the default when signals
  conflict, thresholds configurable.
- **Git-history-based legacy detection** breaks on shallow clones. Mitigation:
  unknown age falls back to legacy/soft plus an explicit warning; doctor
  reports the condition.
- **Loop-tick token cost.** Mitigation: `--quick` mode is pure file parsing
  (no git probes, no EVENTS scan); full analysis only in the skill and CI.
- **Scan glob over-matching** in repos with unconventional `docs/` layouts.
  Mitigation: `scan_exclude` config; ID-pattern filename filter keeps prose
  docs out.
- **INDEX churn** in large repos making diffs noisy. Mitigation: sections are
  sorted deterministically; counts change only when reality changes.

## Open Questions

1. Should `CHANGE_TEMPLATE.md` gain the `## Acceptance Criteria Status` table
   now (it is the false-done vector in the case study), or as a separate
   CHANGE per the brief's hard-constraint spirit? Recommendation: separate
   CHANGE, referenced from this RFC, so the audit ships without touching
   template semantics.
2. Default `stale_after_days`: 90 proposed. Downstream evidence (5-month gaps)
   suggests even 120 would have caught everything.
3. Should the loop tick emit a `docs_audit` event every tick, or only when
   counts change? Recommendation: only on change, to keep EVENTS.jsonl
   meaningful.

## Approvals

- Required: AAI canonical repo maintainer (operator review of this RFC).
- Per the downstream brief's instruction, implementation stops here until this
  design clears review. On acceptance: status `proposed → accepted`, the
  appendices below are promoted to their real paths, and the implementation
  lands as a spec under `docs/specs/` following the normal AAI flow.

---

## Appendix A — SKILL_MD_DRAFT (`.claude/skills/aai-docs-audit/SKILL.md`)

```markdown
---
name: aai-docs-audit
description: Use when docs/ may contain orphan, false-done, or stale documents, before a release closeout, or for a periodic docs hygiene review. Reports per-doc classification and drift verdicts; edits docs only in the operator-approved remediation mode.
---

<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific role (Planning, Implementation, Validation, Remediation), skip this skill. This skill is only for top-level use initiated by the user or orchestrator.
</SUBAGENT-STOP>

Read the file `.aai/SKILL_DOCS_AUDIT.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-docs-audit`.

If `.aai/SKILL_DOCS_AUDIT.prompt.md` does not exist, say: "SKILL_DOCS_AUDIT not found — are you in an AAI project? Expected: .aai/SKILL_DOCS_AUDIT.prompt.md"
```

## Appendix B — PROMPT_DRAFT (`.aai/SKILL_DOCS_AUDIT.prompt.md`)

```markdown
# SKILL: Docs Audit (docs hygiene and drift detection)

ROLE
You are the docs auditor. You classify every prefixed doc under docs/ and
report drift between frontmatter status, Acceptance Criteria Status tables,
docs/ai/EVENTS.jsonl, and git evidence. You REPORT; the operator DECIDES.

HARD RULES
- In audit mode, never modify any doc, plan file, backlog file, or INDEX
  section. Verdicts are heuristic.
- In remediation mode, modify a doc only after the operator approved that
  specific item (or an explicit batch) in this conversation. Never edit
  operator-authored plan/backlog files in any mode.
- Respect docs/ai/docs-audit.yaml. If absent, run report-only and say how to
  enable enforcement (create the config with legacy_until_date).
- Audit scope is this repository only. Do not recurse into git submodules.

PROCESS
1) Run: node .aai/scripts/docs-audit.mjs
   (use --path <subpath> if the user scoped the request)
2) If the script is missing, stop: "docs-audit.mjs not found — run /aai-update".
3) Present the digest exactly as structured below.
4) Regenerate the index: node .aai/scripts/generate-docs-index.mjs
5) The engine appends the docs_audit event itself (best-effort) on every
   non-quick run — do not append a duplicate manually.
6) For each orphan and each probable-* verdict, offer the operator the
   specific remediation (e.g., "add frontmatter per ISSUE_TEMPLATE.md",
   "reconcile AC table then flip backlog row") — as suggestions only.

REMEDIATION MODE (only on explicit operator request)
Entered via "/aai-docs-audit remediate" or "apply suggestions <ids>". Then:
R1) Walk approved findings one at a time. For each, show the verdict, the
    evidence, and the exact proposed edit (full frontmatter block from the
    doc type's template; AC row changes with per-row evidence).
R2) Wait for approval, edit, or skip per item. Batch approval is allowed
    when the operator names the batch; never proceed past an unanswered item.
R3) Propose only what the evidence supports. If evidence is ambiguous, ask
    instead of proposing a status. Never propose "done" without evidence.
R4) After each applied change, emit the canonical event (best-effort):
    node .aai/scripts/append-event.mjs --event doc_lifecycle --ref <DOC-ID> \
      --from <old> --to <new>
    (use --event ac_status for AC row transitions)
R5) For operator-authored plan/backlog files, show suggested row text only;
    the operator pastes it themselves.
R6) When done: re-run docs-audit.mjs, regenerate the INDEX, and report the
    residual counts.

OUTPUT FORMAT
## Docs Audit — <date>
- Scanned: N docs | Orphans: N (K legacy soft) | Drifted: N | Stale: N
### Orphans (need triage)
<table: path | first-commit date | legacy/new | missing fields>
### Drift report
<table: doc ID | verdict | evidence summary | suggested next step>
### Verdict
CLEAN | NEEDS-TRIAGE (K items)
```

## Appendix C — FIRST_RUN_FIXTURES (`tests/skills/test-aai-docs-audit.sh` plan)

Fixture repo built in a temp dir by the test (pattern of
`tests/skills/test-aai-bootstrap.sh`), exercising one fixture per drift class:

| Fixture | Contents | Expected |
|---|---|---|
| `docs/issues/ISSUE-101-orphan-new.md` | No frontmatter; committed after `legacy_until_date` | Class `orphan`; `--check` exits 1; listed in INDEX "Orphans (need triage)". |
| `docs/issues/ISSUE-001-orphan-legacy.md` | No frontmatter; committed before `legacy_until_date` | Soft-warn bucket; `--check` exits 0. |
| `docs/specs/SPEC-201-false-done.md` | Frontmatter `status: done`; AC table with 1 of 3 rows done, no evidence on the rest | Verdict `probable-false-done`. |
| `docs/specs/SPEC-202-partial.md` | `status: done`, AC table mandated but absent | Verdict `probable-partial`. |
| `docs/issues/ISSUE-203-stale-open.md` | `status: implementing`; last touch and last DOC-ID commit older than `stale_after_days`; a later commit message references the same scope as done | Verdict `probable-stale-open`. |
| `docs/specs/SPEC-204-aligned.md` | `status: done`; AC table all done with commit evidence; matching `ac_evidence` events in fixture EVENTS.jsonl | Verdict `aligned`; class `tracked-done`. |
| Missing `docs/ai/docs-audit.yaml` | First test phase runs without config | Report-only: `--check` exits 0 even with ISSUE-101 present; output contains enablement hint. |
| EVENTS emission | After full run | Last EVENTS.jsonl line has `event: docs_audit` with counts payload. |
| Idempotence | Second run, no repo changes | INDEX.md byte-identical; no duplicate `docs_audit` event in `--quick` mode. |

Downstream first-run acceptance (manual, fh-workspace): with
`legacy_until_date: 2026-06-12`, the audit must surface ISSUE-007/8/9/10 as
orphans, CHANGE-048 as probable-partial/false-done, and the known TECHDEBT
items as probable-stale-open — matching the brief's "What downstream will do
after upstream ships" section.
