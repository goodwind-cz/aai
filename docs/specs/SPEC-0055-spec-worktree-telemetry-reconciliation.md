---
id: spec-worktree-telemetry-reconciliation
type: spec
number: 55
status: done
ceremony_level: 2
links:
  requirement: worktree-telemetry-reconciliation
  rfc: null
  pr:
    - 107
  commits:
    - 41e44c5
---

# SPEC — reconcile worktree-stranded committed telemetry at PR time (CHANGE-0039)

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0039-worktree-telemetry-reconciliation.md
- Root-cause architecture (STATE is per-dev/gitignored; METRICS/EVENTS committed):
  docs/rfc/RFC-0001-ac-tracking-and-multi-dev-state.md (layer 5) + .gitignore
- The metrics writer whose committed-class output strands: .aai/scripts/metrics-flush.mjs
  (the METRICS.jsonl ledger append — `fs.appendFileSync(metricsPath, …)`, ~L680)
- The scope-tree close writer that already runs in the worktree (so is NOT the
  stranded artifact): .aai/scripts/close-work-item.mjs (CHANGE-0037/SPEC-0053)
- Flush stopped emitting close events (so the residual stranded EVENTS are only
  agent-emitted ac_status/ac_evidence from main): docs/specs/SPEC-0054-spec-flush-close-event-alignment.md
- Event append helper + ref-rollup convention (`--ref PARENT/suffix`): .aai/scripts/append-event.mjs
- PR ceremony where the reconciliation slots in: .aai/SKILL_PR.prompt.md
- Technology contract: docs/TECHNOLOGY.md
- Expected merge number: SPEC-0055 (highest SPEC allocated across local +
  every `origin/*` branch tree + `refs/aai/docnums/*` reservation refs is
  SPEC-0054; verified 2026-07-18). The sequential integer is reserved/stamped
  at PR by `allocate-doc-number.mjs`; the file is born
  `SPEC-0055-spec-worktree-telemetry-reconciliation.md` with `number: null`.

## Problem (frozen understanding, evidence-backed)

`docs/ai/STATE.yaml` and `docs/ai/LOOP_TICKS.jsonl` are gitignored per-developer
(RFC-0001 layer 5; confirmed in `.gitignore`). Orchestration and
`metrics-flush.mjs` therefore MUST run in the checkout where STATE lives — the
MAIN checkout. But `docs/ai/METRICS.jsonl` and `docs/ai/EVENTS.jsonl` are
COMMITTED-class shared ledgers (RFC-0001: "METRICS.jsonl stays committed";
"EVENTS.jsonl committed, append-only").

When a scope is developed in a git worktree (L3 / worktree isolation), flush
appends the scope's METRICS ledger record into the MAIN checkout's WORKING TREE,
on the intake/base branch — NOT the worktree's impl branch. The PR is opened
from the worktree branch (`.aai/SKILL_PR.prompt.md` runs in the worktree), so the
committed-class ledger record is never staged into the PR. It sits as an
uncommitted working-tree edit in main and is LOST when the branch/worktree is
cleaned up. Observed live on PR #99 (L3 numbering scope): the metrics record for
a 7-tick scope was stranded and had to be hand-carried into the PR.

Post-CHANGE-0038 (SPEC-0054), flush no longer emits `doc_lifecycle`/
`work_item_closed`, and `close-work-item.mjs` (SPEC-0053) runs in the scope tree
(worktree) — so the close-lifecycle EVENTS are NOT stranded. The residual
stranded committed-class artifacts of a worktree scope are therefore:
1. the METRICS.jsonl LEDGER RECORD written by flush in main (the primary loss);
2. any EVENTS.jsonl lines an agent emitted from the MAIN checkout for the scope
   ref (e.g. an `ac_status`/`ac_evidence` during planning/orchestration).

Secondary defect if left unhandled: after the PR merges to base, the main
checkout (on base) still carries the identical line as an uncommitted
working-tree edit; the next `git pull` collides on it (cf. LEARNED 2026-07-04:
untracked/uncommitted-vs-incoming collisions that silently abort a pull).

This is the last observed workflow gap where a committed artifact silently fails
to ship with its scope. It must be reconciled by MECHANISM, not by an agent
noticing — re-introducing agent prose here would revive exactly the improvisation
class mechanized away in CHANGE-0037/0038.

## Frozen design decision — OPTION A (deterministic helper + one PR-ceremony step)

Add `.aai/scripts/reconcile-telemetry.mjs --ref <slug>` and a PR-ceremony step in
`.aai/SKILL_PR.prompt.md` that invokes it. The helper, run FROM the scope tree at
PR time:

1. DETECT the worktree case WITHOUT reading STATE (STATE is gitignored and does
   not exist in the worktree): enumerate `git worktree list --porcelain`. If the
   current tree is the ONLY worktree, it is an inline scope → verified no-op
   (Spec-AC-03). Otherwise the OTHER worktrees are candidate SOURCES.
2. HARVEST, from each sibling worktree, its UNCOMMITTED-ADDED lines to
   `docs/ai/METRICS.jsonl` and `docs/ai/EVENTS.jsonl` — lines present in that
   worktree's working tree but absent from its own `HEAD` (via
   `git -C <sibling> diff`). This targets exactly what flush/an agent wrote in
   main and never committed; committed history is never harvested.
3. FILTER harvested lines to the scope ref: a METRICS line matches when parsed
   JSON `ref_id === <ref>` OR `String(ref_id).split('/').includes(<ref>)` (the
   `refMatches` semantics flush already uses); an EVENTS line matches when
   `ref === <ref>` OR `ref` starts with `<ref>/` (the append-event
   `--ref PARENT/suffix` sub-ref rollup). Lines for any OTHER ref are never
   touched (fail-safe: never move the wrong lines).
4. CARRY (append-only UNION) the matched lines onto the CURRENT (scope) tree's
   same two files: for each matched source line, append it IFF its full-line
   (trimmed) identity is not already present in the destination file; preserve
   source order; NEVER reorder or rewrite an existing destination line; preserve
   the destination's comment header and trailing-newline convention.
5. STAGE the destination files it changed (`git add docs/ai/METRICS.jsonl` and/or
   `docs/ai/EVENTS.jsonl`) so they land in the scope commit.
6. VERIFY-THEN-CLEAN the source (carry-before-clean ordering, mirroring flush's
   ledger-before-reset): only AFTER a carried line is confirmed present in the
   destination, remove that exact full-line from the SOURCE worktree's working
   tree — a pure relocation of an UNCOMMITTED-ADDED stray edit (guaranteed by
   step 2), never a rewrite of committed telemetry. Cleanup is skipped
   (best-effort, reported) when the source cannot be uniquely/safely resolved;
   the CARRY is the critical, must-succeed part.

### Why A, not B or C
- Option B (SKILL_PR PROSE ONLY, agent-performed union carry): rejected. It
  re-introduces agent improvisation at a committed-telemetry-integrity boundary —
  precisely the class CHANGE-0037 (close ceremony) and CHANGE-0038 (flush events)
  just mechanized. A deterministic, idempotent, fail-safe script is required.
- Option C (make flush write its committed output onto the scope/worktree tree):
  rejected as infeasible/harmful. STATE lives in main and flush is a single
  multi-file transaction that co-writes STATE (main) + METRICS in one atomic
  pass; splitting its write targets across two working trees (METRICS to the
  worktree, STATE to main) turns a completed local transaction into a fragile
  cross-tree one, and flush runs in many contexts (mid-loop, resume) that do not
  know a PR/worktree exists yet. Reconciling once, at PR time, from the scope
  tree, is strictly simpler and is a clean no-op for inline scopes.

### Detection & no-op semantics (frozen)
- Worktree case detected purely from `git worktree list --porcelain` +
  presence of scope-ref uncommitted-added source lines. No STATE read.
- Inline / single-checkout / nothing-to-carry → exit 0, zero writes, a report
  line naming why (Spec-AC-03).
- Fail-safe: any uncertainty about the source, an unparseable line, or a git
  command failure yields a NO-OP for the affected file with a report line —
  never a speculative move. The wrong-ref lines are never carried or removed.

### Union / dedupe / idempotency (frozen)
- Append-only union to the destination, dedupe by FULL-LINE identity (trimmed
  exact string), source order preserved, existing lines never reordered/rewritten
  (RFC-0001 append-only).
- Idempotent by construction: a second run finds nothing uncommitted-added in the
  source for the ref (cleanup removed it) AND every candidate already present in
  the destination (full-line dedupe) → zero writes, exit 0. Both trees stay
  consistent (Spec-AC-04). Idempotency of the CARRY does NOT depend on cleanup:
  even if cleanup was skipped, the re-harvested lines dedupe out on the
  destination.

### Exit-code contract (frozen)
- 0 = reconciled (report the carried line counts) OR nothing to carry (report why).
- 1 = a write happened and post-write VERIFY failed → fail-closed, the partial
  destination write is reverted, source untouched, nonzero exit (STOP the ceremony).
- 2 = usage error (missing/invalid `--ref`, unknown flag); nothing written.

### CLI grammar (frozen)
```
node .aai/scripts/reconcile-telemetry.mjs --ref <slug>
  [--metrics <path>] [--events <path>]   # fixture injection, default docs/ai/*
  [--no-source-cleanup]                   # carry+stage only; skip source scrub
  [--dry-run]                             # print the plan JSON, write nothing, exit 0
```
Node stdlib only (docs/TECHNOLOGY.md); no network; deterministic.

## Ceremony level
`ceremony_level: 2` (full pipeline).
- NONE of the scope paths are on `protected_paths_l3` (docs/ai/docs-audit.yaml
  lists only state.mjs, state-engine, state-core, allocate-doc-number,
  pre-commit-checks.sh/.ps1, WORKFLOW.md, CONSTITUTION.md). The new script and the
  SKILL_PR step are not protected surfaces, so L3 is not mandated.
- Not L1: although additive (one NEW script + one SKILL_PR step), the change
  WRITES the shared, COMMITTED governance ledgers (METRICS.jsonl, EVENTS.jsonl)
  across TWO working trees, and its correctness (dedupe, idempotency, never-move-
  wrong-lines, fail-safe no-op) is data-integrity-critical. That warrants the full
  pipeline — real RED proof, independent validation, code review — so L2 is the
  honest floor (mirrors SPEC-0054's L2 rationale).

## Implementation strategy
- Strategy: tdd
- Rationale: new, risky behavior at a committed-telemetry-integrity boundary
  (cross-tree file surgery + union/dedupe + idempotency + fail-safe no-op). Each
  AC-gating test has a clean RED against the ABSENT script — the two-checkout
  fixture leaves the ledger record stranded in the source (proving the loss),
  and GREEN is the record carried onto the scope tree, deduped, source-clean, and
  a verified no-op on re-run/inline. RED-proof is natural and mandatory here.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: single NEW script + one SKILL_PR prompt step + a new test
  suite on the already-active branch `feat/worktree-telemetry-reconciliation`;
  operator already chose inline for this workflow-hardening wave (STATE
  `worktree.user_decision: inline`). No cross-cutting or migration risk. (Fitting
  irony: a change ABOUT worktree telemetry stranding is itself built inline,
  which sidesteps the very stranding it fixes during its own development.)
- User decision: inline
- Base ref: main
- Worktree branch/path: n/a (inline)
- Inline review scope:
  - .aai/scripts/reconcile-telemetry.mjs (new)
  - .aai/SKILL_PR.prompt.md
  - tests/skills/test-aai-reconcile-telemetry.sh (new)

## Seam analysis
- SEAM-1 (reconcile → committed EVENTS.jsonl → docs-audit): carried EVENTS lines
  are consumed by the docs-audit engine. Covered END-TO-END by TEST-006: strand
  an `ac_evidence`/`ac_status` line for the scope ref in the source, reconcile,
  then run the REAL `docs-audit.mjs` on the scope tree and assert it parses/
  attributes the carried line with no new finding — NOT by mocking the boundary.
- SEAM-2 (reconcile → SKILL_PR staged-vs-scope audit): the helper STAGES
  METRICS.jsonl/EVENTS.jsonl, which the SKILL_PR step-3 audit (staged == scope)
  must treat as EXPECTED COMPANIONS (like docs/INDEX.md / review artifacts).
  Covered by TEST-005 (the helper stages EXACTLY the files it modified and
  nothing else — a precise, testable companion set) + TEST-008 (a grep-guard that
  SKILL_PR.prompt.md wires the reconcile step AND lists the reconciled ledgers as
  expected companions). Residual: SKILL_PR is prose, not code — the grep-guard is
  the mechanical witness that the wiring is not forgotten.
- No uncovered seam.

## Acceptance Criteria Mapping
- Maps to CHANGE-0039 AC-001 → Spec-AC-01
- Maps to CHANGE-0039 AC-002 → Spec-AC-02
- Maps to CHANGE-0039 AC-003 → Spec-AC-03
- Maps to CHANGE-0039 AC-004 → Spec-AC-04
- New (never-move-wrong-lines / fail-safe isolation) → Spec-AC-05
- New (source left consistent; PR-ceremony wiring) → Spec-AC-06

- Spec-AC-01: For a worktree-isolated scope whose METRICS.jsonl record was
  written (uncommitted) in the source/main checkout, running
  `reconcile-telemetry.mjs --ref <slug>` from the scope tree appends that exact
  record onto the scope tree's METRICS.jsonl AND stages it — no manual step, no
  loss. Verification: two-checkout fixture; assert the destination METRICS.jsonl
  now contains the record and `git diff --cached --name-only` includes it.
- Spec-AC-02: EVENTS.jsonl lines for the scope ref that are uncommitted-added in
  the source are likewise carried (append-only union, full-line deduped) onto the
  scope tree and staged. Verification: strand a scope-ref EVENTS line in the
  source; reconcile; assert it is present + staged in the scope tree.
- Spec-AC-03: For an INLINE scope (single checkout, no sibling worktree) the run
  is a VERIFIED no-op: exit 0, zero file writes, nothing staged, a report line
  stating there is nothing to carry. Verification: single-checkout fixture; assert
  no tree change and exit 0.
- Spec-AC-04: Idempotent + append-only — re-running carries nothing new, never
  rewrites/reorders an existing line, and leaves both trees consistent.
  Verification: run twice; assert the second run makes zero writes (byte-identical
  destination) and the source no longer strands the carried lines.
- Spec-AC-05: Ref isolation / never-move-wrong-lines — with stranded lines for
  TWO refs in the source, `--ref <scopeA>` carries ONLY scopeA's lines; scopeB's
  stranded lines are neither carried into the scope tree nor removed from the
  source. Verification: two-ref fixture; assert scopeB lines untouched in both
  trees. (Also: an unparseable/garbage source line is skipped, never carried.)
- Spec-AC-06: After a successful carry the SOURCE is left consistent — the exact
  carried lines are no longer a stranded uncommitted edit in the source working
  tree (default cleanup on), and the carry-before-clean ordering guarantees no
  loss (the line is proven present in the destination before removal from
  source); `--no-source-cleanup` leaves the source edit in place but still carries
  + stages. AND SKILL_PR.prompt.md wires the reconcile step and lists the
  reconciled ledgers as expected companions. Verification: assert source
  `git diff` no longer shows the carried lines after a default run (and still does
  under `--no-source-cleanup`); grep-guard on SKILL_PR.prompt.md.

## Constitution deviations

None.

- Article 5 (Additive first): the change is purely additive — a NEW script and a
  NEW SKILL_PR step; no existing behavior is removed. The only mutation of an
  existing file's content is the SOURCE-cleanup removal of lines that are
  UNCOMMITTED-ADDED stray working-tree edits being relocated (never committed
  telemetry), which is a fail-safe, default-optional (`--no-source-cleanup`)
  relocation, not a rewrite of shared history. No unjustifiable deviation → freeze
  is not blocked. (Check the live docs/CONSTITUTION.md article numbering at
  implementation; if article 5 differs, map to the "additive-first / explicit-and-
  documented breaking change" article — the reasoning is unchanged.)

## Implementation plan
- Component: `.aai/scripts/reconcile-telemetry.mjs` (NEW)
  - `parseArgs`: `--ref` (required), `--metrics`/`--events` (default
    `docs/ai/METRICS.jsonl` / `docs/ai/EVENTS.jsonl`), `--no-source-cleanup`,
    `--dry-run`. Unknown flag / missing `--ref` → exit 2.
  - Source enumeration: `git worktree list --porcelain` → all worktree paths;
    current tree = `git rev-parse --show-toplevel`; siblings = the rest.
  - Per sibling, per file: `git -C <sibling> diff --no-color --unified=0 --
    <relpath>` → parse added (`+`, excluding `+++`) lines = uncommitted-added
    working-tree lines. (A robust equivalent: working-tree lines minus HEAD-blob
    lines; either is acceptable as long as only uncommitted-added lines qualify.)
  - Filter to the scope ref (METRICS `ref_id` refMatches; EVENTS `ref` == slug or
    `slug/…`). Skip unparseable JSON lines (fail-safe).
  - Union-append matched lines to the destination file (full-line dedupe, source
    order, header + trailing-newline preserved). `git add` changed destinations.
  - VERIFY each carried line present in the destination; THEN (unless
    `--no-source-cleanup`) remove those exact full-lines from the source
    working-tree file (surgical line filter, write back). Skip+report cleanup on
    any uncertainty.
  - `--dry-run`: print `{ ref, siblings, carry:{metrics:[…],events:[…]},
    cleanup:[…], noop:<bool> }` JSON, write nothing, exit 0.
  - Report + exit-code contract as frozen above.
- Component: `.aai/SKILL_PR.prompt.md`
  - Add a new step (e.g. "2b. RECONCILE WORKTREE TELEMETRY") AFTER staging
    in-scope paths (step 2) and BEFORE the step-3 staged-vs-scope audit: run
    `node .aai/scripts/reconcile-telemetry.mjs --ref <ref>`; a nonzero (exit 1)
    STOPS the ceremony; exit 0 (carried or no-op) proceeds.
  - In step 3 (AUDIT), add `docs/ai/METRICS.jsonl` and `docs/ai/EVENTS.jsonl`
    staged by the reconcile step to the EXPECTED-COMPANIONS list (alongside
    docs/INDEX.md, review artifacts, CHANGELOG.md, docs/canonical/*).
  - FALLBACK note: if `reconcile-telemetry.mjs` is absent (older layer), NOTE and
    proceed — the merge-conflict union step 5b remains the backstop.
- Data flows: source worktree working-tree (uncommitted METRICS/EVENTS lines) →
  scope tree METRICS/EVENTS (append-only union, staged) → source lines scrubbed.
- Edge cases: (a) destination file absent → create on first carry; (b) source
  file has a `#` comment header → skipped in match/dedupe, never carried;
  (c) EVENTS line already emitted in the scope tree by close-work-item (different
  `ts`) → not full-line-identical, but is not uncommitted-added in the SOURCE, so
  not harvested (no duplicate); (d) `--dry-run` writes nothing; (e) multiple
  sibling worktrees → harvest scope-ref lines from all, still ref-filtered;
  (f) zero siblings → no-op.

## Acceptance Criteria Status

Tracks per-Spec-AC delivery state.

| Spec-AC    | Description                                                       | Status  | Evidence | Review-By | Notes |
|------------|-------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | Stranded METRICS record carried onto scope tree + staged          | done    | TEST-001 green; docs/ai/tdd/green-20260718T093538Z-test_001_metrics_carry_created_fresh.log | — | — |
| Spec-AC-02 | Scope-ref EVENTS lines carried (union, deduped) + staged           | done    | TEST-002 green; docs/ai/tdd/green-20260718T093538Z-test_002_events_carry_union_staged.log | — | — |
| Spec-AC-03 | Inline / single-checkout scope → verified no-op                   | done    | TEST-003 green; docs/ai/tdd/green-20260718T093538Z-test_003_inline_verified_noop.log | — | — |
| Spec-AC-04 | Idempotent + append-only; both trees consistent on re-run          | done    | TEST-004/TEST-007 green; docs/ai/tdd/green-20260718T093538Z-test_004_idempotent_rerun.log, docs/ai/tdd/green-20260718T093538Z-test_007_dedupe_and_dry_run.log | — | — |
| Spec-AC-05 | Ref isolation — only scope-ref lines move; wrong lines untouched   | done    | TEST-005 green; docs/ai/tdd/green-20260718T093538Z-test_005_ref_isolation_and_garbage_skip.log | — | — |
| Spec-AC-06 | Source left consistent (carry-before-clean) + SKILL_PR wired       | done    | TEST-006/TEST-008 green; docs/ai/tdd/green-20260718T093538Z-test_006_seam1_real_audit_and_cleanup_toggle.log, docs/ai/tdd/green-20260718T093538Z-test_008_skill_pr_grep_guard.log | — | — |

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                          | Description                                                                                                          | Status  |
|----------|------------|-------------|-----------------------------------------------|--------------------------------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-reconcile-telemetry.sh  | Two-checkout fixture; stranded scope-ref METRICS record in source; reconcile from worktree; assert record present in scope tree METRICS.jsonl AND `git diff --cached` includes it. | green   |
| TEST-002 | Spec-AC-02 | integration | tests/skills/test-aai-reconcile-telemetry.sh  | Stranded scope-ref EVENTS line in source; reconcile; assert carried (union) + staged in scope tree.                 | green   |
| TEST-003 | Spec-AC-03 | integration | tests/skills/test-aai-reconcile-telemetry.sh  | Single-checkout (no sibling worktree) fixture; reconcile; assert exit 0, zero writes, nothing staged, "nothing to carry" report. | green   |
| TEST-004 | Spec-AC-04 | integration | tests/skills/test-aai-reconcile-telemetry.sh  | Run reconcile twice; assert 2nd run makes zero writes (byte-identical destination), no reorder, source no longer strands the lines. | green   |
| TEST-005 | Spec-AC-05 | integration | tests/skills/test-aai-reconcile-telemetry.sh  | Source strands lines for scopeA + scopeB; `--ref scopeA`; assert ONLY scopeA carried, scopeB untouched in both trees; a garbage/unparseable source line is skipped. Also assert the run stages EXACTLY the files it modified. | green   |
| TEST-006 | Spec-AC-06 | integration | tests/skills/test-aai-reconcile-telemetry.sh  | SEAM-1: strand a scope-ref `ac_evidence` in source; reconcile; run the REAL `docs-audit.mjs` on the scope tree and assert it parses/attributes the carried line with no new finding. Also assert source cleanup left the source `git diff` free of the carried lines (and `--no-source-cleanup` leaves them). | green   |
| TEST-007 | Spec-AC-04 | integration | tests/skills/test-aai-reconcile-telemetry.sh  | Destination already contains an identical committed line; reconcile does not duplicate it (full-line dedupe). Plus `--dry-run` writes nothing and prints the plan JSON. | green   |
| TEST-008 | Spec-AC-06 | unit        | tests/skills/test-aai-reconcile-telemetry.sh  | SEAM-2 grep-guard: SKILL_PR.prompt.md wires `reconcile-telemetry.mjs` as a PR-ceremony step AND lists METRICS.jsonl/EVENTS.jsonl as expected companions in the staged-vs-scope audit. | green   |

Notes:
- Every Spec-AC has ≥1 TEST-xxx. Test IDs are stable — do not renumber post-freeze.
- RED-proof obligation (all AC-gating tests): each must be observed FAILING before
  the change. TEST-001..007 fail cleanly because `reconcile-telemetry.mjs` does not
  exist yet (the record stays stranded — the exact #99 loss reproduced in the
  fixture); TEST-008 fails because SKILL_PR.prompt.md does not yet name the step.
  GREEN once the script carries/stages/cleans and SKILL_PR is wired.
- ALL fixtures are scratch temp-dir git repos with a real linked `git worktree add`
  (the pattern is already proven in tests/skills/test-aai-worktree.sh); the real
  runtime docs/ai/*.jsonl are NEVER touched (path-flag overrides + scratch cwd).
  bash-3.2 compatible.

## Verification
- Commands:
  - `bash tests/skills/test-aai-reconcile-telemetry.sh` (TEST-001..008; full suite green)
  - Real-audit seam (TEST-006): the fixture invokes `node .aai/scripts/docs-audit.mjs`
    on the scope tree and asserts CLEAN / carried-line attribution.
  - Regression: `bash tests/skills/test-aai-metrics.sh` and
    `bash tests/skills/test-aai-close-work-item.sh` stay green (unaffected — flush
    and close are not modified by this scope).
- Evidence: RED/GREEN logs under docs/ai/tdd/; test-suite exit codes.
- PASS criteria: every TEST-xxx green AND every Spec-AC in a terminal status.

## Evidence contract
- ref_id: worktree-telemetry-reconciliation
- Spec-AC ↔ TEST links: per the Test Plan table above.
- Commands + expected exit code 0 + evidence path per Verification.
- Commit SHA / PR number stamped at close by `close-work-item.mjs`.

This document defines HOW, not WHAT/WHY. It does not define workflow.
Use plain Markdown headings and body text.
