---
id: SPEC-0010
type: spec
status: done
links:
  requirement: null
  issue: [ISSUE-0003, ISSUE-0004, ISSUE-0005]
  rfc: RFC-0001
  pr: []
  commits: []
---

# SPEC-0010 — Docs-index & STATE tooling robustness: idempotent committed index, STATE duplicate-key detection, row-level AC-status granularity (ISSUE-0003 / ISSUE-0004 / ISSUE-0005)

SPEC-FROZEN: true

## Links
- Primary issue (WHAT/WHY): docs/issues/ISSUE-0003-index-autogen-bakes-stale-drift-row.md
- Issue: docs/issues/ISSUE-0004-state-duplicate-metrics-key-silently-shadows-data.md
- Issue: docs/issues/ISSUE-0005-ac-status-qualifier-skips-whole-doc-from-index.md
- AC-tracking authority (per-dev STATE, EVENTS as shared log): docs/rfc/RFC-0001-ac-tracking-and-multi-dev-state.md
- Sibling docs-index integrity / coverage invariant: docs/specs/SPEC-0006-index-deferred-coverage-and-done-close-policy.md
- Sibling parser CRLF tolerance (same modules): docs/specs/SPEC-0007-parsefrontmatter-crlf-tolerance-and-posix-index-paths.md
- Docs hygiene / drift authority: docs/rfc/RFC-0002-docs-hygiene-and-drift-audit.md
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec frozen for implementation, work not yet started (this doc)
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: standard meanings per template

## Scope

One spec resolving three related AAI docs/state tooling-robustness bugs. They are
combined because they share files and are the same "fail loud, don't silently
drop" family: ISSUE-0003 and ISSUE-0005 both touch
`.aai/scripts/generate-docs-index.mjs` (so they cannot be parallelized), ISSUE-0005
and the docs-audit alignment touch `.aai/scripts/lib/docs-model.mjs` +
`.aai/scripts/lib/docs-audit-core.mjs`, and ISSUE-0004 is the STATE-side member of
the same silent-data-loss family. One branch (`fix/docs-tooling-robustness`), one
PR. WHAT/WHY lives in the three issues; this doc defines HOW.

The AC below are organized into three clearly-labeled groups (A = ISSUE-0003,
B = ISSUE-0004, C = ISSUE-0005) plus a shared no-regression AC.

## Problem summaries (verified against live code on this branch)

### Group A — ISSUE-0003: committed docs/INDEX.md is non-idempotent
`generate-docs-index.mjs:365` embeds `section('Drift report', audit.drift, …)`
and `:360` embeds `section('Orphans (need triage)', auditOrphans, …)`; both are
sourced from `runAudit(ROOT)` (`:358`), which probes **git history**
(`lastIdMentionDate`, `ac_evidence` events, `firstCommitDate`,
`lastEditDate`). The `AAI:INDEX-AUTOGEN` pre-commit hook
(`install-pre-commit-hook.sh`) runs the generator and `git add docs/INDEX.md`
*before the commit object exists*. A doc set `status: done` and first-mentioned
in the same commit therefore has no commit/`ac_evidence` referencing it at hook
time → the drift heuristic
(`docs-audit-core.mjs:363` "no commit and no ac_evidence event references this
doc") emits `probable-false-done`, which is baked into the committed
`docs/INDEX.md`. The instant the commit exists, a fresh regen clears the row, so
`git show HEAD:docs/INDEX.md` ≠ a fresh regen (modulo `Generated:`) — non-
idempotent. Observed 4× (PRs #20–#23), each needing a manual "regenerate INDEX in
committed state" follow-up commit.

### Group B — ISSUE-0004: duplicate top-level `metrics:` key in STATE.yaml silently shadows data
STATE.yaml is edited by multiple sessions/agents (by hand / Edit tool, not a
script). A concurrent session that appends a second top-level `metrics:` mapping
instead of merging into the existing one triggers YAML last-key-wins: the first
`metrics:` block's `work_items` (and their `agent_runs`) are silently dropped on
`safe_load`. No tool caught it (found by hand during a flush). There is no node
STATE validator today; `.aai/SKILL_CHECK_STATE.prompt.md` (INV-01..13) has no
duplicate-top-level-key invariant.

### Group C — ISSUE-0005: a non-canonical AC status skips the WHOLE spec from the index
`docs-model.mjs:27` `AC_STATUS_ENUM = {planned, implementing, done, deferred,
blocked, rejected}`. In `generate-docs-index.mjs:122-124` any AC cell whose
lowercased `Status` is not in the enum pushes an "unknown AC status" failure;
`:167-170` then splices the WHOLE doc out of `docs[]` (into "Skipped (schema
violations)" / `docs/INDEX.violations.md`). So one cell like `done (pre-existing)`
drops an entire spec from every real index section. `docs-audit-core.mjs:301`
raises the same violation, so the two engines must stay aligned.

## Design decisions (load-bearing — read before implementing)

### A. ISSUE-0003 — make the committed index a pure function of the docs
**Decision (issue option (a), chosen):** stop embedding the git-history-dependent
`runAudit()`-derived sections in the committed `docs/INDEX.md`. Concretely, remove
the **Drift report** AND **Orphans (need triage)** sections from `docs/INDEX.md`
(both are sourced from `runAudit()` which probes git history and is therefore
non-idempotent at pre-commit time — not just Drift; the Orphans age-class /
first-commit derivation is equally volatile before the commit exists). The
committed index becomes a deterministic function of on-disk frontmatter + AC
tables only. The `Generated:` line remains the sole volatile line (already
excluded from every idempotence check by `grep -v '^Generated:'`).

**Drift/orphan visibility is preserved, not lost** (issue constraint): the drift
and orphan analysis is already produced on demand by
`.aai/scripts/docs-audit.mjs` (`### Drift report`, Orphans in its report — lines
77/119-127), which is unchanged. Additionally, `generate-docs-index.mjs` writes
the relocated sections to a **git-ignored, marker-guarded companion**
`docs/INDEX.audit.md` (so an index-gen user still sees drift/orphans locally
without polluting the committed artifact). The companion is added to `.gitignore`
and is NOT staged by the pre-commit hook.

**Why this over options (b)/(c):** (b) "treat the doc being closed in the staged
commit as evidenced" is fragile — the commit does not exist at hook time and
faking it risks masking genuine false-dones; (c) "hook amend / second pass"
adds a second commit, the exact churn the issue is trying to remove. Option (a)
is the only one that makes `docs/INDEX.md` a pure function of the docs, which is
the durable invariant. Rejected-option rationale recorded here per the dispatch.

**Follow-up noted (not in scope):** a future spec may escalate drift to a
`--strict` gate in `docs-audit.mjs` for CI; this spec only relocates the
report, it does not change drift detection semantics.

### B. ISSUE-0004 — detect+repair the duplicate key; prevent it in writers
Two axes, both delivered:
1. **Safety net (testable core, TDD):** a new node validator
   `.aai/scripts/check-state.mjs` that DETECTS any duplicate **top-level** key in
   `docs/ai/STATE.yaml` (a line matching `^[A-Za-z_][\w-]*:` at column 0, counted
   by name) and exits non-zero (fail loud) naming the duplicated key(s). This is
   a pure text scan — **no YAML library dependency** (the repo has no manifest /
   yaml dep; top-level-key duplication is detectable structurally without a full
   parse, exactly as the issue's Python `collections`-based check does). A
   `--repair` mode merges duplicate `metrics:` blocks into one **without data
   loss**: union `work_items` mappings, and for a `work_items` ref present in both
   blocks, concatenate its `agent_runs` (append, preserving order and count);
   then re-validate to exit 0. Repair is behavior-specified (zero `agent_runs`
   lost), not implementation-bound — Implementation MAY use `python3` (present on
   dev/CI) or an indentation-block extractor for the structural merge, provided
   the no-data-loss AC and the "single top-level `metrics:` key after repair" AC
   hold.
2. **Durable prevention (loop):** wire the detector into
   `.aai/SKILL_CHECK_STATE.prompt.md` as a new invariant [INV-14] (duplicate
   top-level key ⇒ FAIL, REPAIR merges), and add explicit STATE-write guidance to
   the role prompt(s) that append `metrics.work_items.*.agent_runs`: *append into
   the EXISTING `metrics.work_items.<ref>.agent_runs`; NEVER emit a second
   top-level `metrics:` key.* Prevention (writers) + safety net (validator)
   mirrors the docs-audit "fix the source, keep the fail-loud guard" posture.

### C. ISSUE-0005 — row-level granularity (core) + narrow qualifier normalization
**Decision (issue option (2) as core + option (1) added, chosen):**
1. **Row-level, not whole-doc, skip (core):** an unknown AC status flags only
   that ROW; the doc stays in its correct placement section in `docs/INDEX.md`.
   Split the current `failures[]` into doc-level violations (unknown frontmatter
   status — unchanged, still whole-doc) vs **AC-status row-level** violations
   (which no longer add the doc to `failedRels`). Row-level AC-status violations
   are surfaced in their own report surface (an "AC status violations (row-level)"
   list in the companion / `docs/INDEX.violations.md`) while the doc is indexed
   normally. **Detection is not weakened:** under `--strict` a genuinely-invalid
   AC status is STILL fatal (exit 1); only the default degrade-and-report path
   changes — the doc is kept in the index with the row flagged instead of
   vanishing.
2. **Narrow qualifier normalization (added):** a new shared helper
   `normalizeAcStatus(raw)` in `docs-model.mjs` accepts `<canonical> (<qualifier>)`
   where the leading token is a canonical `AC_STATUS_ENUM` member and there is a
   single trailing parenthetical (e.g. `done (pre-existing)`, `blocked
   (external)`) → normalizes to the base canonical status; the qualifier is
   preserved (surfaced in Notes / carried on the parsed row), never silently
   dropped. Such a value is NOT a violation. The rule is deliberately narrow: the
   leading token MUST be a canonical status and there MUST be exactly one trailing
   `(...)`; anything else (`finished`, `done-ish`, `donee`) stays a genuine
   violation. Base status drives placement, progress counts, and drift terminal
   classification.
3. **Generator/audit alignment (constraint):** both `generate-docs-index.mjs`
   (`:121`) and `docs-audit-core.mjs` (`:299-301`, and the `TERMINAL_AC` /
   drift-heuristic reads at `:353-354`) consume the SAME `normalizeAcStatus` so a
   qualified `done (pre-existing)` is treated identically (accepted, terminal
   `done`) in both, and a genuinely-invalid status is reported by both. This
   prevents the two engines drifting on AC-status handling.

### Shared
- **Reuse existing harnesses; do not invent a parallel runner.** Index / AC-status
  tests (Groups A, C) go in `tests/skills/test-aai-docs-audit.sh`, registered in
  `main()` BEFORE `test_index_continue_on_error` (the `set -e` suite's known
  pre-existing last-failing test). STATE-validator tests (Group B) go in a new
  small harness `tests/skills/test-aai-check-state.sh` (there is no existing
  check-state harness), using `tests/skills/test-framework.sh`.
- **RED-proof obligation (all AC-gating tests, any strategy):** every gating test
  must be observed FAILING without the change. The self-evaluation-trap negatives
  (A: index must be *unchanged* on a normal repo; C: a genuine garbage status must
  still be flagged; B: repair must lose *zero* runs) embed a positive control in
  the same fixture so RED is genuine.
- **Do not regress:** SPEC-0006 (whole-doc deferred section, zero-section coverage
  invariant, open-decision guard, idempotence), SPEC-0007 / ISSUE-0001 (CRLF
  tolerance, POSIX paths, legacy-ratio guard), and the existing docs-audit / index
  suites. NOTE: `test_index_sections_and_idempotence` currently asserts
  `## Orphans (need triage)` and `## Drift report` INSIDE `docs/INDEX.md`
  (test lines ~268-269); relocating those sections (Decision A) requires updating
  that assertion to check the companion / `docs-audit.mjs` output instead — this
  is in-scope for Spec-AC-10.

## Implementation strategy
- Strategy: hybrid
- Rationale: TDD (RED-GREEN-REFACTOR) for the deterministic, higher-risk code
  surfaces — the index drift/orphan relocation (RED-proof the baked
  `probable-false-done` row and the git-state-invariance), the AC-status
  `normalizeAcStatus` + row-level granularity (a parser change consumed by two
  engines with self-eval-trap negatives), and the STATE validator detect+repair
  (silent-data-loss risk demands a no-data-loss regression proof). Loop for the
  low-risk glue: the `.gitignore` line, the pre-commit-hook companion note, the
  `SKILL_CHECK_STATE.prompt.md` [INV-14] prose, and the role-prompt STATE-write
  guidance (verified by `grep`). Matches the sibling SPEC-0006/0007 hybrid posture.
- RED-proof obligation applies to every AC-gating test regardless of strategy.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: the scope touches three or more independent modules
  simultaneously — `generate-docs-index.mjs`, `docs-model.mjs`,
  `docs-audit-core.mjs`, a new `check-state.mjs`, the pre-commit hook installer,
  two test harnesses, `.gitignore`, and two prompt files — and it is PR-bound.
  It is also the very tooling that gates this repo (index generation + STATE
  health + the pre-commit path), so isolation is prudent. It is NOT `required`:
  there is no schema migration and the changes are additive/behavioral (relocating
  a section, adding a helper, adding a validator). The sibling SPEC-0006/0007
  docs-index work ran inline on a dedicated branch; the broader three-module reach
  here nudges the recommendation one notch to `recommended`. Work is already on a
  dedicated branch `fix/docs-tooling-robustness` off `main`.
- User decision: undecided (Planning recommends; Implementation Preparation asks
  the user and records the decision — inline-on-dedicated-branch is an acceptable
  override consistent with SPEC-0006/0007 precedent).
- Base ref: main
- Worktree branch/path: branch `fix/docs-tooling-robustness` (worktree path TBD if
  the user chooses worktree)
- Inline review scope (if inline is chosen):
  - `.aai/scripts/generate-docs-index.mjs`
  - `.aai/scripts/lib/docs-model.mjs`
  - `.aai/scripts/lib/docs-audit-core.mjs`
  - `.aai/scripts/check-state.mjs` (new)
  - `.aai/scripts/install-pre-commit-hook.sh` (+ `.ps1` parity)
  - `.aai/SKILL_CHECK_STATE.prompt.md`
  - the role prompt(s) that append `metrics.work_items.*.agent_runs`
  - `.gitignore`
  - `tests/skills/test-aai-docs-audit.sh`
  - `tests/skills/test-aai-check-state.sh` (new)
  - `docs/specs/SPEC-0010-docs-index-and-state-tooling-robustness.md`

## Acceptance Criteria Mapping

### Group A — ISSUE-0003 (committed index idempotence)

- Maps to: ISSUE-0003 Expected Behavior / Verification (idempotence repro)
  - Spec-AC-01: For the repro scenario — a doc set `status: done` AND first-
    mentioned by ID in the SAME commit, with the `AAI:INDEX-AUTOGEN` hook active —
    the committed `docs/INDEX.md` is byte-identical (modulo the `Generated:` line)
    to a fresh `generate-docs-index.mjs` run performed AFTER the commit exists,
    with no manual follow-up "regenerate INDEX" commit. RED-proof: on pre-fix code
    the committed index carries a `Drift report (1) … probable-false-done` row
    that the post-commit fresh regen drops (diff non-empty).
  - Verification: TEST-001.

- Maps to: ISSUE-0003 Constraints (committed index = pure function of docs)
  - Spec-AC-02: `docs/INDEX.md` is a deterministic function of on-disk docs only —
    it embeds NO git-history-dependent (`runAudit()`-derived) section. Concretely:
    with the docs on disk unchanged, mutating git history (e.g. adding a commit
    that references a doc ID, or adding an `ac_evidence` event) does NOT change
    `docs/INDEX.md` (modulo `Generated:`). The generator no longer renders the
    Drift report / Orphans sections into `docs/INDEX.md`.
  - Verification: TEST-002.

- Maps to: ISSUE-0003 Constraints (do not lose drift visibility)
  - Spec-AC-03: Drift/orphan visibility is preserved: `docs-audit.mjs` still
    reports drift verdicts and orphans for a `probable-false-done` fixture
    (unchanged), AND `generate-docs-index.mjs` writes the relocated drift/orphan
    sections to a git-ignored, marker-guarded companion `docs/INDEX.audit.md` that
    is (a) listed in `.gitignore` (`git check-ignore` matches) and (b) NOT staged
    by the `AAI:INDEX-AUTOGEN` pre-commit hook.
  - Verification: TEST-003.

### Group B — ISSUE-0004 (STATE duplicate-metrics-key)

- Maps to: ISSUE-0004 Expected Behavior / Verification (detect, fail loud)
  - Spec-AC-04: `node .aai/scripts/check-state.mjs docs/ai/STATE.yaml` DETECTS a
    duplicate top-level key and exits non-zero, printing a message that names the
    duplicated key(s) (e.g. `metrics`). On a STATE with exactly one of each
    top-level key it exits 0. No YAML library is required (structural top-level-key
    scan). RED-proof: pre-implementation there is no detector — a lenient
    `safe_load` silently keeps only the last `metrics:` block.
  - Verification: TEST-004.

- Maps to: ISSUE-0004 Verification (REPAIR merges, no data loss)
  - Spec-AC-05: `check-state.mjs --repair docs/ai/STATE.yaml` merges duplicate
    `metrics:` blocks into a single top-level `metrics:` key: `work_items` are
    unioned and, for a ref present in both blocks, its `agent_runs` are
    concatenated — ZERO `agent_runs` lost. After repair the file has exactly one
    top-level `metrics:` key and re-validation exits 0. Verified on a fixture where
    block A has `work_items.X.agent_runs=[r1]` and block B has
    `work_items.X.agent_runs=[r2]` + `work_items.Y.agent_runs=[r3]` → result
    `X:[r1,r2], Y:[r3]`, total run count preserved. RED-proof: pre-fix a lenient
    parse of the same fixture yields only block B's `work_items` (r1 lost).
  - Verification: TEST-005.

- Maps to: ISSUE-0004 Expected Behavior (prevention wiring)
  - Spec-AC-06: `.aai/SKILL_CHECK_STATE.prompt.md` documents a new invariant
    [INV-14] (duplicate top-level key ⇒ FAIL; REPAIR merges via
    `check-state.mjs --repair`), and the role prompt(s) that append
    `metrics.work_items.*.agent_runs` carry explicit guidance to append into the
    EXISTING `metrics.work_items` and never emit a second top-level `metrics:`
    key. Verified by `grep` for both the [INV-14] text and the append-into-existing
    guidance.
  - Verification: TEST-006.

### Group C — ISSUE-0005 (row-level AC-status granularity)

- Maps to: ISSUE-0005 Expected Behavior option (2) (row-level, not whole-doc)
  - Spec-AC-07: A spec (`status: done`) whose AC table has ONE genuinely-unknown
    AC status cell (e.g. `Status: bogus-status`) and otherwise valid rows appears
    in its correct `docs/INDEX.md` placement section (the Done section), NOT
    removed from the index; the offending row is flagged in a row-level
    "AC status violations" surface. RED-proof: on pre-fix code the whole doc is
    absent from the Done section and appears only under "Skipped (schema
    violations)".
  - Verification: TEST-007.

- Maps to: ISSUE-0005 Expected Behavior option (1) (qualifier normalization)
  - Spec-AC-08: An AC status of the form `<canonical> (<qualifier>)` whose leading
    token is a canonical `AC_STATUS_ENUM` member (e.g. `done (pre-existing)`,
    `blocked (external)`) is normalized to its base canonical status via
    `normalizeAcStatus`, is NOT reported as a violation, drives placement/progress
    by the base status, and preserves the qualifier (not silently dropped);
    `generate-docs-index.mjs --strict` exits 0 on such a doc. RED-proof: on pre-fix
    code `done (pre-existing)` is an "unknown AC status" → the doc is dropped and
    `--strict` exits 1.
  - Verification: TEST-008.

- Maps to: ISSUE-0005 Constraints (detection preserved; generator/audit aligned)
  - Spec-AC-09: A genuinely-invalid AC status (no canonical leading token, e.g.
    `finished`) is STILL reported as a violation by BOTH `generate-docs-index.mjs`
    and `docs-audit.mjs` (both via the shared `normalizeAcStatus`); under `--strict`
    both exit non-zero on it. The normalization rule is narrow (leading token must
    be a canonical status; single trailing parenthetical) — `donee`, `done-ish`,
    `finished` are not normalized. Positive control (self-eval trap): the same
    fixture's qualified `done (pre-existing)` row is accepted, proving the check is
    not a blanket accept-all.
  - Verification: TEST-009.

### Shared — no regression

- Maps to: all three issues' Verification "no regression" + Constraints
  - Spec-AC-10: `bash tests/skills/test-aai-docs-audit.sh` passes except the known
    pre-existing `test_index_continue_on_error` (with the relocated-section
    assertions updated per Decision A); `bash tests/skills/test-aai-check-state.sh`
    passes; on the real repo `node .aai/scripts/docs-audit.mjs --check --strict
    --no-event` exits 0 CLEAN and `node .aai/scripts/generate-docs-index.mjs` is
    idempotent (two runs byte-identical modulo `Generated:`); SPEC-0006 invariants
    (deferred whole-doc section, zero-section coverage, open-decision guard) and
    the SPEC-0007 CRLF/legacy-ratio suite still pass.
  - Verification: TEST-010.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | ISSUE-0003: committed INDEX byte-idempotent to post-commit fresh regen (close-in-same-commit repro); no follow-up commit | done | TEST-001 PASS 2026-07-01T13:37Z (docs-audit suite); RED log docs/ai/tdd/red-spec0010-groupAC-docsaudit.log; hook-time regen == post-commit fresh regen verified independently | — | Group A; RED = baked probable-false-done drift row |
| Spec-AC-02 | ISSUE-0003: INDEX is pure function of on-disk docs; no runAudit/git-history section embedded; git-state-invariant | done | TEST-002 PASS 2026-07-01T13:37Z; `diff <(grep -v Generated: docs/INDEX.md) <(regen)` empty; no Drift/Orphans headings in INDEX.md confirmed | — | Group A; removes Drift report + Orphans from committed INDEX |
| Spec-AC-03 | ISSUE-0003: drift/orphan visibility preserved (docs-audit unchanged + git-ignored companion docs/INDEX.audit.md not staged by hook) | done | TEST-003 PASS 2026-07-01T13:37Z; git check-ignore exit 0 (.gitignore:45); companion exists locally untracked; hook un-stages via git rm --cached | — | Group A; companion in .gitignore, marker-guarded |
| Spec-AC-04 | ISSUE-0004: check-state.mjs detects duplicate top-level key, exits non-zero naming key; clean STATE exit 0; no YAML dep | done | TEST-004 PASS 2026-07-01T13:38Z (check-state suite); independent fixture confirm: dup-metrics exit 1 names "metrics"; clean exit 0; no YAML import confirmed | — | Group B; TDD detect core |
| Spec-AC-05 | ISSUE-0004: --repair merges duplicate metrics blocks, unions work_items + concatenates agent_runs, ZERO runs lost, re-validate exit 0 | done | TEST-005 PASS 2026-07-01T13:38Z; independent fixture: r1+r2+r3 all present after repair, metrics_keys=1, re-validate exit 0; RED log docs/ai/tdd/red-spec0010-groupB-checkstate.log | — | Group B; no-data-loss regression proof |
| Spec-AC-06 | ISSUE-0004: SKILL_CHECK_STATE [INV-14] + role-prompt append-into-existing guidance present (grep) | done | TEST-006 PASS 2026-07-01T13:38Z; [INV-14] present in SKILL_CHECK_STATE.prompt.md; guidance present in all 5 role prompts (IMPLEMENTATION/PLANNING/REMEDIATION/VALIDATION/SKILL_TDD) | — | Group B; prevention wiring (loop) |
| Spec-AC-07 | ISSUE-0005: one unknown AC cell flags the ROW only; doc stays in correct INDEX section (not whole-doc-skipped) | done | TEST-007 PASS 2026-07-01T13:37Z; RED log confirms pre-fix whole-doc skip; post-fix doc remains in Done section | — | Group C; RED = whole doc in Skipped only |
| Spec-AC-08 | ISSUE-0005: `<canonical> (<qualifier>)` normalized to base status, not a violation, qualifier preserved, --strict exit 0 | done | TEST-008 PASS 2026-07-01T13:37Z; normalizeAcStatus("done (pre-existing)") = {status:"done",qualifier:"pre-existing",canonical:true} verified; RED log confirms pre-fix failure | — | Group C; narrow rule |
| Spec-AC-09 | ISSUE-0005: genuinely-invalid status still flagged by BOTH generator + docs-audit; --strict exit 1; positive control accepted | done | TEST-009 PASS 2026-07-01T13:37Z; both engines import normalizeAcStatus from docs-model.mjs; "finished" flagged by both; "done (pre-existing)" accepted by both | — | Group C; SEAM alignment; detection not weakened |
| Spec-AC-10 | No regression: docs-audit suite (relocated-section asserts updated) + check-state suite green; repo docs-audit CLEAN; index idempotent; SPEC-0006/0007 intact | done | docs-audit: 53 PASS / 1 pre-existing fail (test_index_continue_on_error); check-state: 4/4 PASS; docs-audit --check --strict --no-event exit 0 CLEAN; orchestration-mode/docs-lock/docs-canon/test-canon all green 2026-07-01T13:39Z | — | Shared |

Status values: planned | implementing | done | deferred | blocked | rejected.
Gate (per .aai/VALIDATION.prompt.md): any planned/implementing row blocks PASS;
any done row needs non-empty Evidence; deferred/blocked need a future Review-By.

## Implementation plan
- Components/modules affected:
  - `.aai/scripts/generate-docs-index.mjs`:
    - Remove the `section('Orphans (need triage)', …)` and `section('Drift report',
      …)` calls (`~:360-369`) from the committed `docs/INDEX.md` output. Keep the
      `runAudit()` call only to build the git-ignored companion. Write
      `docs/INDEX.audit.md` (marker-guarded, `# Docs Index Audit — auto-generated,
      DO NOT EDIT`) containing the relocated Orphans + Drift sections; write/remove
      it with the same marker-guard discipline as `writeViolationsReport`.
    - Group C: replace the `AC_STATUS_ENUM.has(s)` check (`:121-124`) with
      `normalizeAcStatus`. If not canonical → push a ROW-LEVEL AC-status violation
      that (default) does NOT add the doc to `failedRels` (doc stays indexed) but
      is surfaced in an "AC status violations (row-level)" list (companion /
      `INDEX.violations.md`); under `--strict` it remains fatal. Use the base
      status everywhere a row status is read (placement, `progressFor`,
      deferred/blocked collection). Keep the unknown-FRONTMATTER-status path
      (`:115-118`) whole-doc as-is.
  - `.aai/scripts/lib/docs-model.mjs`:
    - Add `export function normalizeAcStatus(raw)` → `{ status, qualifier,
      canonical }`: lowercase+trim; if it matches `^(<enum-token>)\s*\((.+)\)$`
      with a canonical leading token → `{status: token, qualifier, canonical:true}`;
      else if the whole value ∈ `AC_STATUS_ENUM` → `{status: value, qualifier:null,
      canonical:true}`; else `{status: value, qualifier:null, canonical:false}`.
      Narrow by construction (single trailing parenthetical, canonical leading
      token).
  - `.aai/scripts/lib/docs-audit-core.mjs`:
    - Route the AC-status read at `:299-301` and the terminal/drift reads
      (`:353-354`, `TERMINAL_AC` checks) through `normalizeAcStatus` so a qualified
      `done (pre-existing)` is terminal `done` and only genuinely-invalid statuses
      are reported (aligned with the generator).
  - `.aai/scripts/check-state.mjs` (new): CLI. Default: scan STATE.yaml for
    duplicate top-level keys (`^[A-Za-z_][\w-]*:` at col 0), print + exit 1 on any
    duplicate. `--repair`: merge duplicate `metrics:` blocks (union `work_items`,
    concatenate `agent_runs`), write back, re-validate. Pure text scan for detect;
    structural merge may shell to `python3` or use an indentation-block extractor
    (behavior-specified, no-data-loss).
  - `.aai/scripts/install-pre-commit-hook.sh` (+ `.ps1` parity): add a comment /
    ensure the hook stages only `docs/INDEX.md` (+ `INDEX.violations.md`) and never
    `docs/INDEX.audit.md` (it is git-ignored; add a `git rm --cached
    --ignore-unmatch docs/INDEX.audit.md` guard mirroring the violations handling
    if desired).
  - `.aai/SKILL_CHECK_STATE.prompt.md`: add [INV-14] (duplicate top-level key ⇒
    FAIL; REPAIR merges via `check-state.mjs --repair`), and add its row to the
    OUTPUT FORMAT invariant list.
  - role prompt(s) appending `metrics.work_items.*.agent_runs` (e.g. the METRICS
    sections of the role prompts): add append-into-existing / never-second-
    `metrics:`-key guidance.
  - `.gitignore`: add `docs/INDEX.audit.md`.
  - `tests/skills/test-aai-docs-audit.sh`: add TEST-001..003 (Group A),
    TEST-007..009 (Group C), and the docs-audit half of TEST-010, registered
    BEFORE `test_index_continue_on_error`; update the relocated-section assertion
    in `test_index_sections_and_idempotence`.
  - `tests/skills/test-aai-check-state.sh` (new): TEST-004..006 + the check-state
    half of TEST-010, using `tests/skills/test-framework.sh`.
- Data flows: index generation reads frontmatter + AC tables (on-disk) → renders
  INDEX; `runAudit()` output is diverted from INDEX to the companion. AC-status
  normalization interposed at the single read point in each engine. STATE
  validator reads STATE.yaml text; `--repair` rewrites it.
- Edge cases:
  - Group A: a repo with genuine drift (a real probable-false-done that persists
    post-commit) — still surfaced by `docs-audit.mjs` + companion; the committed
    INDEX simply no longer carries it. Idempotence holds because both the hook-time
    and post-commit INDEX exclude the volatile section.
  - Group B: a STATE with duplicate `metrics:` where a ref exists in only one block
    (union, no concat needed); a duplicate of a non-`metrics:` top-level key
    (detected+reported, repair scoped to `metrics:` — other duplicates reported but
    not auto-merged, with a clear message).
  - Group C: `done` (bare) unchanged; `done (pre-existing)` normalized; `finished`
    still a violation; a canonical token with an EMPTY parenthetical `done ()` →
    treat as non-canonical (violation) to keep the rule narrow; multiple
    parentheticals `done (a) (b)` → non-canonical.

## Seam analysis
- SEAM-1 (`docs-model.mjs.normalizeAcStatus` → consumed by BOTH
  `generate-docs-index.mjs` AND `docs-audit-core.mjs`): a shared AC-status
  normalizer backing two engines that gate CI, pre-commit, and intake. Risk: the
  two engines diverge on which statuses are accepted/terminal. Crossed end-to-end
  by TEST-009 (a genuinely-invalid status is flagged by BOTH real tools; a
  qualified status is accepted by BOTH) and TEST-008 (qualified status → terminal
  `done` in the generator's placement AND not a docs-audit violation) — real
  generator + real `docs-audit.mjs`, not two mocked unit checks.
- SEAM-2 (`generate-docs-index.mjs` → committed `docs/INDEX.md` + `AAI:INDEX-AUTOGEN`
  pre-commit hook staging): the relocation changes what the hook bakes into the
  committed artifact. Risk: the companion gets staged, or the committed index
  still depends on git state. Crossed by TEST-001 (real hook-time regen vs
  post-commit fresh regen byte-identical) and TEST-003 (companion git-ignored +
  not staged).
- SEAM-3 (`check-state.mjs` validator ↔ STATE.yaml written by multiple role
  prompts/sessions): the validator must catch exactly the multi-session shape that
  produced the bug and repair it without loss. Crossed by TEST-005 (a
  two-`metrics:`-block STATE — the real concurrent-session shape — is detected and
  merged with zero `agent_runs` lost) and TEST-006 (the prompt guidance that
  prevents writers from creating the second key).
- Residual risk (recorded): the `--repair` structural merge of YAML without a
  parser library is inherently format-sensitive; mitigated by (a) scoping
  auto-merge to the known `metrics:` shape, (b) the zero-data-loss AC verified on a
  fixture, and (c) detect-only fail-loud for any other duplicate top-level key
  (reported, not silently mutated). A full YAML-parser-based repair is a noted
  follow-up if broader duplicate shapes appear in the field.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                     | Description | Status |
|----------|------------|-------------|------------------------------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-docs-audit.sh      | Git fixture repo with the `AAI:INDEX-AUTOGEN` hook: set a doc `status: done` + first-mention its ID in one commit; assert `git show HEAD:docs/INDEX.md` == a fresh post-commit regen (both `grep -v '^Generated:'`), no follow-up commit. RED: pre-fix committed index has a `Drift report (1) … probable-false-done` row the fresh regen drops. | green |
| TEST-002 | Spec-AC-02 | integration | tests/skills/test-aai-docs-audit.sh      | Fixture: regen INDEX; mutate git history only (add a commit referencing a doc ID / append an `ac_evidence` event) with docs on disk unchanged; regen again; assert `docs/INDEX.md` byte-identical (modulo `Generated:`) and contains no `## Drift report` / `## Orphans` heading. | green |
| TEST-003 | Spec-AC-03 | integration | tests/skills/test-aai-docs-audit.sh      | Probable-false-done fixture: `docs-audit.mjs` still reports the drift verdict + orphans; `generate-docs-index.mjs` writes `docs/INDEX.audit.md`; assert it is `git check-ignore`-matched and the pre-commit hook does not stage it. | green |
| TEST-004 | Spec-AC-04 | unit        | tests/skills/test-aai-check-state.sh     | STATE fixture with two top-level `metrics:` keys → `check-state.mjs` exit 1, message names `metrics`; single-key STATE → exit 0. No yaml dep. RED: pre-impl no detector / lenient parse silent. | green |
| TEST-005 | Spec-AC-05 | integration | tests/skills/test-aai-check-state.sh     | Dup-`metrics:` fixture (A: X=[r1]; B: X=[r2], Y=[r3]) → `--repair` yields single `metrics:` key, `X:[r1,r2]`, `Y:[r3]`, total run count preserved, re-validate exit 0. RED: pre-fix lenient parse drops block A (r1 lost). | green |
| TEST-006 | Spec-AC-06 | unit        | tests/skills/test-aai-check-state.sh     | `grep` asserts `.aai/SKILL_CHECK_STATE.prompt.md` contains the [INV-14] duplicate-top-level-key invariant AND the role prompt(s) contain the append-into-existing / never-second-`metrics:`-key guidance. | green |
| TEST-007 | Spec-AC-07 | integration | tests/skills/test-aai-docs-audit.sh      | Fixture spec `status: done` with one AC row `Status: bogus-status` + otherwise valid rows → real generator; assert the doc appears in the Done section AND the row is listed as a row-level AC-status violation; NOT absent / only-in-Skipped. RED: pre-fix doc absent from Done, only in Skipped. | green |
| TEST-008 | Spec-AC-08 | integration | tests/skills/test-aai-docs-audit.sh      | Fixture spec with `Status: done (pre-existing)` → no violation, row counts as `done`, doc indexed normally, qualifier preserved; `generate-docs-index.mjs --strict` exit 0. RED: pre-fix unknown AC status → doc dropped, `--strict` exit 1. | green |
| TEST-009 | Spec-AC-09 | integration | tests/skills/test-aai-docs-audit.sh      | Fixture with both `finished` (invalid) and `done (pre-existing)` (qualified) rows → BOTH `generate-docs-index.mjs` and `docs-audit.mjs` flag `finished` and accept `done (pre-existing)`; `--strict` exit 1 (generator) / reported (audit). Positive control = qualified row accepted (proves not accept-all). RED: mutation removing the normalizer flags the qualified row. | green |
| TEST-010 | Spec-AC-10 | integration | tests/skills/test-aai-docs-audit.sh + tests/skills/test-aai-check-state.sh | Regression: docs-audit suite green except known `test_index_continue_on_error` (relocated-section assertion updated); check-state suite green; real-repo `docs-audit --check --strict --no-event` exit 0 CLEAN; `generate-docs-index.mjs` idempotent (two runs byte-identical modulo `Generated:`); SPEC-0006/0007 assertions intact. | green |

Test status values: pending → red → green. Every Spec-AC has ≥1 TEST-xxx. Test
IDs are stable; do not renumber after freeze.

TDD vs loop per AC: Spec-AC-01/02/03 (Group A relocation), Spec-AC-04/05 (Group B
validator detect+repair), Spec-AC-07/08/09 (Group C normalizer + granularity) are
TDD (RED-proof mandatory). Spec-AC-06 (prompt/guidance wiring) is loop
(grep-verified). Spec-AC-10 is a regression gate (loop-run of the suites).

## Verification
- `bash tests/skills/test-aai-docs-audit.sh` — TEST-001..003, 007..009, and the
  docs-audit half of 010 green; pre-existing pass set preserved (only
  `test_index_continue_on_error` known-fails).
- `bash tests/skills/test-aai-check-state.sh` — TEST-004..006 + check-state half of
  010 green.
- `node .aai/scripts/check-state.mjs docs/ai/STATE.yaml` exit 0 on a clean STATE;
  exit 1 naming the key on a duplicate-`metrics:` fixture; `--repair` merges with
  zero `agent_runs` lost.
- `node .aai/scripts/generate-docs-index.mjs` on the real repo: no `## Drift
  report` / `## Orphans` heading in `docs/INDEX.md`; `docs/INDEX.audit.md` written
  and git-ignored; two runs byte-identical modulo `Generated:`.
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` on the real repo
  exits 0 CLEAN and still reports drift/orphans in its own output.
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal with evidence.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id (ISSUE-0003 / ISSUE-0004 / ISSUE-0005 / SPEC-0010)
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path
- commit SHA or diff range when available

Notes:
This document defines HOW, not WHAT/WHY (the three issues own WHAT/WHY).
This document does not define workflow.
Use plain Markdown headings and body text. Do not add emoji or decorative icons
unless there is a strong domain-specific reason.
