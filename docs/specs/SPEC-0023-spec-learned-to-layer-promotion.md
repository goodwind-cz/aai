---
id: spec-learned-to-layer-promotion
type: spec
number: 23
status: done
links:
  change: learned-to-layer-promotion
  requirement: null
  rfc: null
  pr:
    - 65
  commits:
    - 833ef7c
---

# SPEC — Promote session lessons into the vendored layer (+ drift-check preflight)

SPEC-FROZEN: true

## Links
- Change (WHAT/WHY): docs/issues/CHANGE-0015-learned-to-layer-promotion.md
- Prompts edited: .aai/SKILL_PR.prompt.md, .aai/INTAKE_COMMON.md,
  .aai/SKILL_LOOP.prompt.md
- Config edited: docs/ai/docs-audit.yaml (doc_number_guard dial)
- Guard engine (unchanged, semantics relied on): .aai/scripts/allocate-doc-number.mjs
  `--guard` + pre-commit host .aai/scripts/pre-commit-checks.sh CHECK 8 + CI mirror
  .github/workflows/docs-numbering.yml
- Test suites extended: tests/skills/test-aai-hygiene-pack.sh,
  tests/skills/test-aai-doc-numbering.sh
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec being written / frozen for implementation
- implementing: spec frozen, work delivered in the worktree, awaiting
  independent validation + merge (this doc)
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: standard meanings per template

## Implementation strategy
- Strategy: loop
- Rationale: the deliverables are prompt-text rules, a one-key config flip, and
  grep-wired test stanzas — no engine code changes. A single focused pass with
  grep-RED evidence per AC (run each new stanza against the pre-edit text,
  prove it FAILS, then edit, prove GREEN) gives the same falsifiability as TDD
  at a fraction of the ceremony. The only behavioral surface (the enforce flip)
  is covered by an end-to-end test that drives the real pre-commit host script.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: edits touch the PR ceremony and pre-commit guard dial —
  the exact machinery the main checkout's own commits run through.
- User decision: worktree (provisioned by the operator)
- Base ref: main
- Worktree branch/path: feat/learned-to-layer at /Users/ales/Projects/aai-feat-learned-layer
- Inline review scope: n/a (worktree chosen)

## Design decisions (resolved — do not reopen during implementation)

### D1 — Merge-conflict + ceremony-hardening rules live at the push/merge boundary
SKILL_PR gains a step 5b (between PUSH+PR and the MERGE BOUNDARY) because that
is where branch-sync conflicts and post-merge cleanup actually execute. The
rules are the 2026-07-15/16 session lessons verbatim: docs/INDEX.md conflicts
are resolved by REGENERATING (never hand-merging) via generate-docs-index.mjs;
CHANGELOG.md conflicts stack BOTH [unreleased] entries; docs/ai/EVENTS.jsonl is
an append-only log (RFC-0001) so conflicts union-merge (keep both lines);
`grep '^<<<<<<<'` must come back empty before any `git add`. Hardening: after
any `git merge`, VERIFY the merge actually happened — a squash-merge base had
moved and `git merge` silently aborted on a dirty tree; the resolution commit
then claimed a merge that never happened. Check `.git/MERGE_HEAD` exists or the
resulting commit has 2 parents before committing conflict resolutions.
Branch/worktree cleanup happens only after `gh pr view` reports state MERGED.

### D2 — Enforce flip is safe for the DRAFT-carrying development flow
`doc_number_guard: enforce` makes pre-commit CHECK 8 and the CI mirror BLOCK on
a DRAFT/duplicate violation. This cannot break in-flight branches that carry
`*-DRAFT-*.md` docs (like the one delivering this spec), because the guard
predicate evaluates the STAGED/MERGED tree, not the raw working directory:
`guardDocFiles()` enumerates via `git ls-files` (CHANGE-0012 FIX 3 /
SPEC-0015 D6, proven by doc-numbering TEST-015), so purely-untracked local
drafts never trip it. During development, DRAFT docs remain untracked (AGENTS
commit gating: nothing is committed before the PR ceremony), and the ceremony
allocates numbers in SKILL_PR step 1b BEFORE staging in step 2 — every staged
tree the hook ever sees is DRAFT-free by construction. The offline case is
equally safe: allocator exit 3 stops the ceremony before staging. Projects that
want the old behavior set the dial back to report-only in their own
docs/ai/docs-audit.yaml (it is project-owned config, not synced content).

### D3 — Loop drift preflight degrades silently
SKILL_LOOP's loop-start preflight runs `node .aai/scripts/layer-drift.mjs` as
ONE informational line (the script self-bounds via its default 10s timeout and
is read-only). Exit codes are never acted on — drift visibility only, mirroring
the doctor CAT-13 non-blocking mapping. When the script is absent (older
vendored layers), skip SILENTLY — same clause the docs-hygiene tick check uses
— so a stale layer does not spam every session start.

### D4 — Add rules, not prose (CHANGE-0011 diet budgets)
tests/skills/test-aai-prompt-diet.sh TEST-010 asserts a >=28672-byte net
reduction against the 357457-byte baseline; measured headroom before this
change: 25142 bytes. All prompt additions combined must stay well inside that.
TEST-003's 240-line intake budget is untouched (INTAKE_COMMON.md is not an
INTAKE_* file; its bytes are counted by TEST-010's `extra` term, already
included in the headroom figure).

## Acceptance Criteria Mapping
- Maps to: CHANGE AC-001
  - Spec-AC-01: SKILL_PR.prompt.md carries a MERGE-CONFLICT RESOLUTION section
    (INDEX regenerate / CHANGELOG stack-both / EVENTS.jsonl union-merge /
    conflict-marker grep before `git add`) plus verify-merge-happened
    (MERGE_HEAD-or-2-parents after any `git merge`) and
    cleanup-only-after-MERGED rules.
  - Verification: tests/skills/test-aai-hygiene-pack.sh test_050 (grep-RED
    against pre-edit prompt, GREEN after).
- Maps to: CHANGE AC-002
  - Spec-AC-02: INTAKE_COMMON.md (DURABLE DOC IDENTITY block) and
    SKILL_PR.prompt.md (step 1b) both carry the never-predict-a-TYPE-000N-
    number-before-allocation rule.
  - Verification: tests/skills/test-aai-hygiene-pack.sh test_051 (grep-RED →
    GREEN).
- Maps to: CHANGE AC-003
  - Spec-AC-03: docs/ai/docs-audit.yaml sets `doc_number_guard: enforce` with
    an updated comment; the pre-commit host honors it end-to-end: enforce + a
    staged fully-numbered tree exits 0, enforce + a staged DRAFT exits 1 naming
    the draft; existing doc-numbering tests keep passing.
  - Verification: tests/skills/test-aai-doc-numbering.sh test_018 (drives the
    real pre-commit-checks.sh in an isolated repo; RED before the flip is the
    repo-config grep half), plus the full doc-numbering suite.
- Maps to: CHANGE AC-004
  - Spec-AC-04: SKILL_LOOP.prompt.md loop-start preflight names
    layer-drift.mjs as an informational line with an explicit skip-silently
    degrade clause for script-absent layers.
  - Verification: tests/skills/test-aai-hygiene-pack.sh test_052 (grep-RED →
    GREEN).
- Maps to: CHANGE AC-005
  - Spec-AC-05: hygiene, doc-numbering, prompt-diet, state, dispatch, metrics,
    docs-audit suites all exit 0; repo `docs-audit --check --strict --no-event`
    verdict CLEAN; docs/INDEX.md regeneration byte-idempotent (modulo
    Generated line); check-state clean.
  - Verification: full sweep run recorded under ## Verification.

## Acceptance Criteria Status

| Spec-AC    | Description                                              | Status | Evidence | Review-By | Notes |
|------------|----------------------------------------------------------|--------|----------|-----------|-------|
| Spec-AC-01 | SKILL_PR merge-conflict + verify-merge + MERGED cleanup  | done   | docs/ai/tdd/red-learned-to-layer-test-001-002-004.log -> docs/ai/tdd/green-learned-to-layer-test-001-002-004.log | — | RED: no MERGE-CONFLICT RESOLUTION section; GREEN: all anchors present |
| Spec-AC-02 | no-number-prediction rule in INTAKE_COMMON + SKILL_PR    | done   | docs/ai/tdd/red-learned-to-layer-test-001-002-004.log -> docs/ai/tdd/green-learned-to-layer-test-001-002-004.log | — | RED: rule absent from both files; GREEN: present in both |
| Spec-AC-03 | doc_number_guard: enforce + host honors it e2e           | done   | docs/ai/tdd/red-learned-to-layer-test-003.log -> docs/ai/tdd/green-learned-to-layer-test-003.log | — | RED: dial still report-only (suite exit 1); GREEN: enforce + host passes numbered staged tree / ignores untracked draft / blocks staged DRAFT loud |
| Spec-AC-04 | SKILL_LOOP layer-drift preflight + silent degrade        | done   | docs/ai/tdd/red-learned-to-layer-test-001-002-004.log -> docs/ai/tdd/green-learned-to-layer-test-001-002-004.log | — | RED: layer-drift.mjs absent from SKILL_LOOP; GREEN: informational preflight + silent skip |
| Spec-AC-05 | full sweep green, strict audit CLEAN, index idempotent   | done   | ## Verification (2026-07-16 sweep, all exit 0) | — | prompt-diet TEST-010 net reduction 51812 bytes (floor 28672) |

Status values: planned | implementing | done | deferred | blocked | rejected
- planned: AC defined, no implementation started
- implementing: work in flight; not allowed at PASS claim time
- done: implementation complete; requires non-empty Evidence (commit SHA or RUN_ID)
- deferred: explicitly postponed; requires Review-By (minimum +14 days) + Notes
- blocked: cannot proceed; requires Review-By + Notes naming blocker
- rejected: will not be implemented; requires Notes with rationale (terminal)

Gate behavior (enforced by .aai/VALIDATION.prompt.md when this column is present):
- Any planned/implementing AC blocks PASS
- Any done AC with empty Evidence blocks PASS
- Any deferred/blocked AC with Review-By in the past blocks any PASS until re-decided
- Review-By must be at least 14 days in the future when set

## Implementation plan
- .aai/SKILL_PR.prompt.md — new step 5b MERGE-CONFLICT RESOLUTION + VERIFY
  MERGE (D1); one no-number-prediction line appended to step 1b (Spec-AC-02);
  step 6 gains the cleanup-after-MERGED sentence.
- .aai/INTAKE_COMMON.md — one no-number-prediction line in the DURABLE DOC
  IDENTITY block.
- docs/ai/docs-audit.yaml — `doc_number_guard: report-only` → `enforce`;
  comment rewritten to state the new default and the D2 safety argument.
- .aai/SKILL_LOOP.prompt.md — loop-start preflight line running
  layer-drift.mjs, informational only, silent skip when absent (D3).
- tests/skills/test-aai-hygiene-pack.sh — test_050/test_051/test_052 stanzas
  (suite convention: grep + log_fail, wired into main).
- tests/skills/test-aai-doc-numbering.sh — test_018_enforce_flip: iso repo +
  vendored pre-commit-checks.sh; enforce + numbered staged tree → exit 0;
  enforce + staged DRAFT → exit 1 naming the draft; also greps the repo
  docs/ai/docs-audit.yaml for the enforce value.
- Edge cases: allocator-absent layers (SKILL_PR step 1b fallback text
  unchanged); layer-drift-absent layers (silent skip); byte budget (D4).

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected)                                          | Description                                                              | Status  |
|----------|------------|------|---------------------------------------------------------------|--------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | int  | tests/skills/test-aai-hygiene-pack.sh (test_050_pr_merge_conflict) | SKILL_PR carries INDEX-regenerate / CHANGELOG-stack / EVENTS-union / marker-grep / MERGE_HEAD-verify / cleanup-after-MERGED anchors | green |
| TEST-002 | Spec-AC-02 | int  | tests/skills/test-aai-hygiene-pack.sh (test_051_no_number_prediction) | INTAKE_COMMON + SKILL_PR both carry the no-prediction rule               | green |
| TEST-003 | Spec-AC-03 | e2e  | tests/skills/test-aai-doc-numbering.sh (test_018_enforce_flip) | repo dial reads enforce; real pre-commit host: enforce+numbered staged tree passes, enforce+staged DRAFT blocks loud | green |
| TEST-004 | Spec-AC-04 | int  | tests/skills/test-aai-hygiene-pack.sh (test_052_loop_drift_preflight) | SKILL_LOOP preflight names layer-drift.mjs + silent-skip degrade clause  | green |
| TEST-005 | Spec-AC-05 | e2e  | full suite sweep (see Verification)                            | all suites exit 0; strict audit CLEAN; index idempotent                  | green |

Test status values: pending → red → green.

## Verification (run 2026-07-16, all in the worktree)
- bash tests/skills/test-aai-hygiene-pack.sh — exit 0 (incl. test_050/051/052)
- bash tests/skills/test-aai-doc-numbering.sh — exit 0 (18 tests incl. test_018)
- bash tests/skills/test-aai-prompt-diet.sh — exit 0 (TEST-010 net reduction
  51812 bytes >= 28672 floor after all prompt additions)
- bash tests/skills/test-aai-state.sh, test-aai-orchestration-dispatch.sh,
  test-aai-metrics.sh, test-aai-docs-audit.sh — all exit 0
- node .aai/scripts/allocate-doc-number.mjs --guard — clean on this tree (the
  branch's two DRAFT docs are untracked, proving D2 on the real repo)
- node .aai/scripts/docs-audit.mjs --check --strict --no-event — Verdict CLEAN
- node .aai/scripts/generate-docs-index.mjs — byte-idempotent modulo Generated
- node .aai/scripts/check-state.mjs docs/ai/STATE.yaml — exit 0
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal. Met at the
  implementation gate; independent validation verdict pending (status:
  implementing).

## Evidence contract
Per artifact record: ref_id (CHANGE learned-to-layer-promotion), Spec-AC/TEST
links, command, exit code, evidence path (docs/ai/tdd/red-learned-to-layer-*.log
/ green-learned-to-layer-*.log), commit SHA or diff range when available.

Notes:
This document defines HOW, not WHAT/WHY. It does not define workflow.
