---
id: SPEC-0013
type: spec
status: done
links:
  change: CHANGE-0007
  rfc: null
  requirement: null
  pr: []
  commits: []
---

# SPEC-0013 — Workflow hygiene pack: body lint, PR ceremony, review-response flow, warnings policy, fixture diversity, trigger/wrapper cleanup (CHANGE-0007)

SPEC-FROZEN: true

## Links
- Change request (WHAT/WHY): docs/issues/CHANGE-0007-workflow-hygiene-pack.md
- Lint engine being extended: .aai/scripts/docs-audit.mjs + .aai/scripts/lib/docs-audit-core.mjs (RFC-0002 / SPEC-0001)
- Hook being extended: .aai/scripts/install-pre-commit-hook.sh / .ps1 (SPEC-0011 G5 close-gate precedent)
- Staged-blob rule honored: docs/knowledge/LEARNED.md 2026-07-03 (gate the STAGED blob, never the worktree — PR #27 F2)
- Prompts touched (H2–H8): .aai/SKILL_PR.prompt.md (new), .aai/SKILL_CODE_REVIEW.prompt.md,
  .aai/SKILL_WRAP_UP.prompt.md, .aai/METRICS_FLUSH.prompt.md, .aai/SKILL_TDD.prompt.md,
  .aai/SKILL_TEST_CANON.prompt.md, .aai/SKILL_META.prompt.md
- Wrappers touched (H2/H8): .claude/skills/{aai-pr (new), aai-wrap-up, aai-flush, aai-docs-hub,
  aai-share, aai-tdd, aai-test-skills, aai-worktree}/SKILL.md (+ .gemini/.codex mirrors where present)
- FRESHNESS CONSTRAINT: CHANGE-0006 (SPEC-0012, PR #34) just migrated nine prompts to the
  transactional CLI `.aai/scripts/state.mjs`. Every prompt edit in this spec MUST PRESERVE
  the existing "PRIMARY PATH (transactional CLI, SPEC-0012)" text and the "state.mjs is
  absent" fallback markers. Of the prompts this spec touches, METRICS_FLUSH and SKILL_TDD
  carry the fresh migration text (protected by TEST-013/TEST-015 wiring assertions);
  SKILL_CODE_REVIEW and SKILL_WRAP_UP were untouched by SPEC-0012.
- Sibling precedent for isolation/strategy posture: docs/specs/SPEC-0010, SPEC-0011, SPEC-0012
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec frozen for implementation, work not yet started (this doc)
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: standard meanings per template

## Implementation strategy
- Strategy: hybrid
- Rationale: TDD (RED-GREEN-REFACTOR) for the deterministic engine surface — the H1 body
  linter in docs-audit-core.mjs and its CLI/hook wiring (TEST-001..009), where fixture
  diversity and RED-proof are exactly the failure class H7 codifies. Loop (grep-verified,
  RED-proven against the pre-change prompt text) for the mechanical prompt/wrapper edits
  H2–H8 (TEST-010..018). Matches the SPEC-0010/0011/0012 hybrid posture.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: touches 3+ independent modules (docs-audit engine + lib, pre-commit
  hook installers, seven prompts, eight-plus wrapper files incl. mirrors, one new prompt+wrapper)
  and is PR-bound. NOT required: no STATE schema change, no irreversible migration; every
  change is additive prose or a report-only-by-default lint; the loop's own state-mutation
  path (state.mjs) is not modified. Matches the SPEC-0010/0011/0012 `recommended` precedent.
- User decision: undecided (Implementation Preparation asks the operator; Planning does not create worktrees)
- Base ref: main
- Worktree branch/path: <decided at preparation; suggested feat/change-0007-hygiene-pack>
- Inline review scope (if inline is chosen): .aai/scripts/docs-audit.mjs,
  .aai/scripts/lib/docs-audit-core.mjs, .aai/scripts/install-pre-commit-hook.sh,
  .aai/scripts/install-pre-commit-hook.ps1, .aai/SKILL_PR.prompt.md, .aai/SKILL_CODE_REVIEW.prompt.md,
  .aai/SKILL_WRAP_UP.prompt.md, .aai/METRICS_FLUSH.prompt.md, .aai/SKILL_TDD.prompt.md,
  .aai/SKILL_TEST_CANON.prompt.md, .aai/SKILL_META.prompt.md, .aai/SKILL_INTAKE.prompt.md,
  .claude/skills/aai-pr/SKILL.md, .claude/skills/aai-wrap-up/SKILL.md, .claude/skills/aai-flush/SKILL.md,
  .claude/skills/aai-docs-hub/SKILL.md, .claude/skills/aai-share/SKILL.md, .claude/skills/aai-tdd/SKILL.md,
  .claude/skills/aai-test-skills/SKILL.md, .claude/skills/aai-worktree/SKILL.md,
  .gemini/skills/** and .codex/skills/** mirror files for the same wrappers,
  tests/skills/test-aai-docs-audit.sh, tests/skills/test-aai-hygiene-pack.sh (new),
  docs/specs/SPEC-0013-workflow-hygiene-pack.md

## Design decisions (resolved — do not reopen during implementation)

### D1 — H1 body-lint rule set (three rules, conservative by construction)
The linter operates on the body AFTER the frontmatter block, tracks fenced code blocks and
inline code spans, and NEVER flags content inside either (the CHANGE-0007 intake itself
carries `</content>` in inline code and must stay clean — this is the mandatory negative control).

Fence model (conservative, CommonMark-aligned): a fence opens with a line starting with
N >= 3 backticks or tildes; it closes only at a line of >= N of the SAME character. Nested
shorter fences inside an open fence are content, not fences. Rules:
1. `stray-tool-markup`: outside fences/inline code, a line containing any of
   `</content>`, `<content>`, `</invoke>`, `<invoke `, `<result>`, `</result>`,
   `<function_results>`, `</function_results>`, `<parameter ` (case-insensitive).
2. `unbalanced-fence`: any fence still open at EOF (length-aware matching per above).
3. `template-placeholder`: outside fences/inline code, (a) an unfilled ID of the shape
   `[A-Z]{2,}-XXXX` (literal X's, e.g. `SPEC-XXXX`, `PRD-XXXX`), or (b) the literal
   all-caps angle token `<[A-Z][A-Z0-9_]{2,}>` (e.g. `<PLACEHOLDER>`, `<TODO_FILL>`).
   Mixed-case/prose angle text (`<why isolation is or is not useful>`) is intentionally
   NOT flagged — too many legitimate uses in governed docs; false-positive posture wins.

Lint scope (which docs): exactly the governed scan set of `scanAuditDocs` (docs/** minus
EXCLUDE_DIRS: ai, knowledge, archive, _archive, project-sessions, templates), further
excluding `docs/plans/` files under `plan_scan_mode: lenient` (operator notes, not authored
content). No retro-fixing of legacy docs is required beyond what AC-08 demands (the real
repo is CLEAN today or is fixed as part of this change).

### D2 — H1 surfacing, promotion, and exit contract
- Body-lint findings are computed inside `runAudit` and returned as `result.bodyLint`
  (per-doc: rel, id, rule, line, detail).
- The digest (default and `--check`) gains a distinct `### Body lint: N` section
  (report-only wording, same visual grammar as the SPEC-0011 sections).
- Promotion: findings count toward `hardFail` ONLY when the explicit `--strict` flag is
  passed (the intake POST-SAVE invocation already passes `--strict`). They do NOT promote
  in config-enforced mode without `--strict` — mid-migration repos with a docs-audit.yaml
  must not start failing `--check` on legacy bodies (RFC-0002 posture; conservative rollout).
- New CLI modes:
  - `--lint-body` — lint-only digest over the governed scan set (honors `--path`);
    exit 0 always unless combined with `--strict` (then exit 1 on findings).
  - `--lint-body-file <file>` — pure predicate on an explicit file path (a materialized
    STAGED blob), mirroring `--gate-file` (SPEC-0011 G5): exit 1 findings / 0 clean /
    2 unreadable; prints findings; never emits a docs_audit event.
- INDEX.violations.md companion: NOT extended. The generator's violations are
  frontmatter/schema-level and independently recomputed; body lint stays in the audit
  digest to keep the change surface inside docs-audit and avoid committed-INDEX churn.
  (Resolves the intake's open question: `--check` output only.)

### D3 — H1 wiring points
- Intake POST-SAVE (SKILL_INTAKE STEP 2.5) already runs
  `docs-audit.mjs --check --strict --no-event --path <saved-file>` — body lint rides in via
  D2 promotion. Add one sentence to STEP 2.5 naming body lint so the reference is explicit
  (AC-001 "references it").
- Pre-commit hook (both installers): for each STAGED `docs/**/*.md` file (ACM), materialize
  the staged blob (`git show ":$f"` — LEARNED 2026-07-03, never the worktree file) and run
  `--lint-body-file` on it. Posture mirrors close_gate exactly: warn-and-continue by
  default; block only when docs/ai/docs-audit.yaml sets `body_lint: enforce`.

### D4 — H2 SKILL_PR content outline (new .aai/SKILL_PR.prompt.md + aai-pr wrapper)
Sections the prompt MUST contain (grep anchors in parentheses):
1. Scope derivation: read docs/ai/STATE.yaml (`code_review.scope`, `worktree.inline_review_scope`)
   and the frozen spec's inline review scope; produce an explicit in-scope file list
   ("derive the scope file-list").
2. Scope-only staging: `git add` ONLY in-scope paths; never `git add -A`/`git add .`
   ("stage ONLY in-scope paths").
3. Staged-vs-scope audit: `git diff --cached --name-only` compared against the scope list;
   any extra staged path aborts with the offending paths listed ("staged-vs-scope audit").
4. Commit message conventions: conventional-commit style consistent with AGENTS.md commit
   gating policy; commit only after gates (validation PASS + code-review PASS/waived) and
   explicit user confirmation.
5. PR body template: summary, scope list, Spec-AC/TEST evidence table, review status,
   test evidence, and links (change doc + spec).
6. Merge boundary: "NEVER merges" — `gh pr merge` is forbidden; merging is an operator
   action only ("never merge", "operator").
Wrapper `.claude/skills/aai-pr/SKILL.md`: standard shim (read .aai/SKILL_PR.prompt.md,
follow exactly, not-found fallback message) + `<SUBAGENT-STOP>` block (aai-loop template
verbatim, adapted) + "Invoke this as `/aai-pr`." line. Mirror to .gemini/.codex skill dirs.

### D5 — H3/H4/H6 exact additions to SKILL_CODE_REVIEW and SKILL_WRAP_UP
SKILL_CODE_REVIEW gains two sections and one policy upgrade:
- "## External Review Response" (H3, new section): fetch PR review threads via
  `gh api repos/{owner}/{repo}/pulls/{n}/comments` (+ `gh pr view --json reviews`);
  triage each finding as real / stale / duplicate / disputed with a one-line disposition;
  remediate real findings with a RED-proofed regression test (test observed failing before
  the fix — cite the red log); reply inline per thread citing the fixing commit SHA and
  TEST id; push; never resolve a thread without a reply. (Codifies the PR #27/#29 flow.)
- "Report staging" instruction (H4, added to Step 6 area): after writing
  docs/ai/reviews/review-<ts>.{md,json}, stage the report files together with the scope's
  commit (or the review-response commit) so reports never orphan.
- Warnings policy with teeth (H6, replaces the current one-liner in "Merge/PR readiness"):
  a PASS verdict with open WARNINGs is conditional — before closeout each WARNING must be
  either remediated, or promoted to a `docs/ai/decisions.jsonl` entry (decision id + rationale),
  or promoted to a tracked follow-up ref (ISSUE/CHANGE id in the review notes). The review
  report and STATE.yaml `code_review.notes` must name the artifact per WARNING.
SKILL_WRAP_UP gains (H4/H6, in/next to step 4/4b):
- Orphaned-review check: the uncommitted-work step explicitly calls out untracked/modified
  `docs/ai/reviews/*` files as "orphaned review reports" with the staging suggestion.
- Closeout advisory: if STATE.yaml `code_review.status == pass` and its notes carry WARNINGs
  with no decisions.jsonl entry or follow-up ref, list them as "unrecorded WARNINGs"
  (advisory only; VALIDATION 8b remains the enforcement backstop and is NOT edited by this spec).

### D6 — H5 partial-flush reset mechanism (prompt wording; no engine change)
METRICS_FLUSH step 5d condition changes from "only if NO active_work_items remain" to:
- FULL reset (existing text, preserved verbatim incl. the SPEC-0012 primary/fallback
  structure) when no active work items remain; PLUS
- PARTIAL-FLUSH reset (new): whenever a flushed ref_id equals `current_focus.ref_id`
  (or `last_validation.ref_id` names it), reset the verdict blocks even though other
  active work items remain, using the transactional CLI:
    node .aai/scripts/state.mjs set-validation --status not_run --notes "reset after flush of <ref_id>"
    node .aai/scripts/state.mjs set-code-review --required false --status not_run --notes "reset after flush of <ref_id>"
  then null the remaining leaked fields (last_validation.evidence_paths/ref_id,
  code_review.scope/base_ref/head_ref/report_paths) as a GUARDED MANUAL EDIT and validate
  with check-state.mjs.
- Mechanism decision: `set-validation`/`set-code-review` are the sanctioned flush-time
  path — they carry no pass-guard by design and self-stamp run_at_utc. `reset-block --force`
  is explicitly NOT used: its notes marker hardcodes "reset by remediation … pending
  independent re-validation" (wrong provenance for a flush) and it preserves verdict fields
  as audit history, which is exactly the leak H5 removes — the durable history already
  lives in METRICS.jsonl, which is appended BEFORE any reset (ledger-before-reset ordering
  stays mandatory). No new CLI flag is needed; H5 is prompt-only.
- The fresh SPEC-0012 migration text in METRICS_FLUSH ("PRIMARY PATH (transactional CLI,
  SPEC-0012)", "state.mjs is absent" fallback) must remain intact (TEST-013 guards it).

### D7 — H7 fixture-diversity checklist text (SKILL_TDD + SKILL_TEST_CANON)
Both prompts gain a "Fixture diversity checklist (MANDATORY when authoring fixtures)":
- [ ] degenerate/empty collection (zero items, empty file, empty map)
- [ ] fully-covered / zero-remainder case (nothing left to do — the branch test-canon missed)
- [ ] multi-source / multi-writer case (more than one contributor to the same output)
- [ ] mid-operation failure (abort between steps; partial state observed)
- [ ] negative control (input that must NOT trigger the behavior)
RED-proof rule extension (verbatim question): "would this suite stay green if the happy
path were the only path implemented?" — if yes, the suite is not evidence; add the missing
shapes. In SKILL_TDD it lands in Phase 1 (RED) as a checklist item + a Hard Blocks note;
in SKILL_TEST_CANON it lands next to the RED-stub scaffolding rule (Phase 2 step 6c).
The SPEC-0012 migration text in SKILL_TDD is untouched (TEST-015 guards the markers).

### D8 — H8 triggers.json verdict, SUBAGENT-STOP, invoke lines, SKILL_META fate
- triggers.json VERDICT: fix the docs to match reality — REMOVE the auto-trigger promise
  from SKILL_WRAP_UP (the "AUTO-TRIGGER PATTERNS … Configure in .claude/triggers.json"
  block). Grep evidence: no runtime consumer of `.claude/triggers.json` exists anywhere in
  the repo — references are documentation only (SKILL_AUTO_TRIGGER, USER_GUIDE,
  SUPERPOWERS_INTEGRATION, skill wrappers); hooks/hooks.json wires only SessionStart;
  Claude Code has no native triggers.json mechanism — its real auto-invocation channel is
  the skill description frontmatter. Creating the file would ship inert config and a false
  promise. Compensation: enrich the aai-wrap-up wrapper description with the trigger
  phrases ("wrap up", "end session", "done for today", "hotovo", "konec", "bye") so the
  native skill-matching channel actually fires. SKILL_AUTO_TRIGGER itself is out of scope
  (CHANGE-0007 scopes only the wrap-up promise); a follow-up intake may reconcile it.
- SUBAGENT-STOP: add the aai-loop-style `<SUBAGENT-STOP>` block to `aai-wrap-up` and
  `aai-flush` wrappers (text adapted: "skip this skill if dispatched as a subagent to
  execute a specific role; session wrap-up / metrics flush are operator-initiated or
  loop-final actions only").
- Invoke lines: add "Invoke this as `/aai-<name>`." to the 6 wrappers missing it:
  aai-docs-hub, aai-flush, aai-share, aai-tdd, aai-test-skills, aai-worktree.
- Mirrors: apply the same wrapper edits to the corresponding `.gemini/skills/*` and
  `.codex/skills/*` files where the wrapper exists there (they are near-identical copies;
  leaving them drifted recreates the uniformity defect H8 fixes). New aai-pr wrapper is
  created in all three trees.
- SKILL_META fate: KEEP. Grep evidence: it IS referenced by a documented loader —
  hooks/session-start.sh:11 and hooks/session-start.ps1:12 read it and inject it at
  SessionStart via hooks/hooks.json (matcher startup|resume|clear|compact), documented in
  README.md and docs/USER_GUIDE.md. It intentionally has no wrapper (it is not a slash
  skill). Action: add a short header comment to SKILL_META.prompt.md naming its loader
  ("Loaded automatically by hooks/session-start.sh/.ps1 (wired in hooks/hooks.json); not a
  slash skill — do not create a wrapper.") so the loader is self-documented at the artifact.

## Acceptance Criteria Mapping

| Req AC (CHANGE-0007) | Spec-AC | Verification (command → expected evidence) |
|---|---|---|
| AC-001 (H1 body lint) | Spec-AC-01 | tests/skills/test-aai-docs-audit.sh H1 cases (TEST-001..007) green; `docs-audit.mjs --lint-body` on a dirty fixture prints rule ids, exit 0; with `--strict` exit 1; SKILL_INTAKE STEP 2.5 + generated hook reference body lint (TEST-008) |
| AC-002 (H2 PR ceremony) | Spec-AC-02 | TEST-010 grep-wiring: SKILL_PR.prompt.md anchors (scope derivation, scope-only staging, staged-vs-scope audit, never-merge) + aai-pr wrapper shim/SUBAGENT-STOP/invoke line in all three skill trees |
| AC-003 (H3 review response) | Spec-AC-03 | TEST-011 grep-wiring: SKILL_CODE_REVIEW External Review Response section (fetch → triage → RED-proofed fix → inline reply citing commit+TEST id → push) |
| AC-003/AC-004 report staging | Spec-AC-04 | TEST-012 grep-wiring: SKILL_CODE_REVIEW report-staging instruction; SKILL_WRAP_UP orphaned `docs/ai/reviews/` call-out in the uncommitted-work step |
| AC-004 (H5 partial flush) | Spec-AC-05 | TEST-013 grep-wiring + fixture walk-through: METRICS_FLUSH partial-flush wording (current-focus condition, exact CLI commands, ledger-before-reset), SPEC-0012 markers preserved |
| AC-005 (H6 warnings policy) | Spec-AC-06 | TEST-014 grep-wiring: SKILL_CODE_REVIEW names decisions.jsonl / follow-up ref per WARNING; SKILL_WRAP_UP unrecorded-WARNINGs advisory |
| AC-006 (H7 fixture diversity) | Spec-AC-07 | TEST-015 grep-wiring: checklist items + happy-path question in SKILL_TDD and SKILL_TEST_CANON; SPEC-0012 markers preserved in SKILL_TDD |
| AC-007 (H8 cleanup) | Spec-AC-08 | TEST-016..018 grep-wiring: wrap-up promise removed + wrapper description phrases added; SUBAGENT-STOP on aai-wrap-up/aai-flush; invoke line on the 6 wrappers (+ mirrors); SKILL_META loader note present and hooks references intact |
| AC-008 (suites + repo clean) | Spec-AC-09 | TEST-009 + full-suite run: docs-audit suite green incl. new cases; `node .aai/scripts/docs-audit.mjs --check --strict --no-event` exit 0 CLEAN on the real repo; generate-docs-index idempotent |

## Acceptance Criteria Status

Tracks per-Spec-AC delivery state. Separate from per-test lifecycle below.

| Spec-AC    | Description | Status  | Evidence | Review-By | Notes |
|------------|-------------|---------|----------|-----------|-------|
| Spec-AC-01 | docs-audit body lint: 3 rules per D1, surfacing/exit per D2, wiring per D3; fence/inline-code content never flagged | done | TEST-001..008 green; RED docs/ai/tdd/red-20260704T103537Z-spec0013-h1.log; GREEN docs/ai/tdd/green-20260704T104031Z-spec0013-h1.log; review W1–W3 remediation TEST-019..021 green (RED docs/ai/tdd/red-20260704T111832Z-spec0013-w1-w4.log, GREEN docs/ai/tdd/green-20260704T112110Z-spec0013-w1-w4.log) | TDD | close-gate block hardened too — see Post-review remediation note |
| Spec-AC-02 | SKILL_PR.prompt.md + aai-pr wrapper per D4; never merges without operator action | done | TEST-010 green; RED docs/ai/tdd/red-20260704T104339Z-spec0013-h2-h8-wiring.log | — | wrappers in .claude/.gemini/.codex |
| Spec-AC-03 | SKILL_CODE_REVIEW External Review Response section per D5 | done | TEST-011 green; docs/ai/tdd/green-20260704T104658Z-spec0013-h2-h8-wiring.log | — | — |
| Spec-AC-04 | Review-report staging instruction (SKILL_CODE_REVIEW) + orphaned-reviews check (SKILL_WRAP_UP) per D5 | done | TEST-012 green; docs/ai/tdd/green-20260704T104658Z-spec0013-h2-h8-wiring.log; review W4 remediation TEST-022 green (SKILL_PR companions whitelist; RED/GREEN in the w1-w4 tdd logs) | — | — |
| Spec-AC-05 | METRICS_FLUSH partial-flush verdict reset per D6 (prompt-only; set-validation/set-code-review path; no reset-block --force) | done | TEST-013 green incl. live-CLI fixture walk-through; docs/ai/tdd/green-20260704T104658Z-spec0013-h2-h8-wiring.log | — | SPEC-0012 markers preserved |
| Spec-AC-06 | Warnings policy with named artifact (decisions.jsonl entry or follow-up ref) + wrap-up unrecorded-WARNINGs advisory per D5 | done | TEST-014 green; docs/ai/tdd/green-20260704T104658Z-spec0013-h2-h8-wiring.log | — | — |
| Spec-AC-07 | Fixture-diversity checklist in SKILL_TDD + SKILL_TEST_CANON per D7 | done | TEST-015 green; docs/ai/tdd/green-20260704T104658Z-spec0013-h2-h8-wiring.log | — | SPEC-0012 markers preserved |
| Spec-AC-08 | H8 cleanup per D8: promise removed, SUBAGENT-STOP added, 6 invoke lines, mirrors synced, SKILL_META loader note | done | TEST-016..018 green; docs/ai/tdd/green-20260704T104658Z-spec0013-h2-h8-wiring.log | — | — |
| Spec-AC-09 | All suites green; real repo `--check --strict` CLEAN; index regeneration idempotent | done | TEST-009 green; post-remediation re-run via aai-run-tests.sh: docs-audit suite 86 PASS exit 0; hygiene-pack suite 12 PASS exit 0; state suite 27 PASS exit 0; real-repo --check --strict exit 0 CLEAN; --gate SPEC-0013 exit 0 | — | — |

Status values: planned | implementing | done | deferred | blocked | rejected (gate behavior per template).

## Implementation plan
- Engine (TDD): `lintBody(content)` in docs-audit-core.mjs (pure function: frontmatter strip,
  length-aware fence tracker, inline-code-span mask, three rules) → wired into `runAudit`
  as `result.bodyLint` → digest section + `--strict` promotion in docs-audit.mjs →
  `--lint-body` / `--lint-body-file` CLI modes → hook installers (staged-blob loop mirroring
  the close-gate block, `body_lint: enforce` config key).
- Prompts (loop): D4–D8 edits; keep every SPEC-0012 primary/fallback block byte-intact.
- Wrappers (loop): edits per D8 in .claude, mirrored to .gemini/.codex where present.
- New wiring suite `tests/skills/test-aai-hygiene-pack.sh` for TEST-010..018 (grep
  assertions, SPEC-0005 TEST-015..017 style); H1 cases extend tests/skills/test-aai-docs-audit.sh.
- Edge cases owned by tests: empty body, frontmatter-only doc, stray tag inside fence,
  stray tag inside inline code, 4-backtick fence containing 3-backtick example, tilde fence,
  placeholder inside fence, `--path` scoping, unreadable file for --lint-body-file (exit 2).

## Seam analysis (cross-feature integration)
- Seam 1: body lint ↔ the real docs corpus (every governed doc becomes lint input).
  Covered end-to-end by TEST-009 (`--check --strict` on the actual repo must exit 0).
- Seam 2: pre-commit hook ↔ docs-audit CLI ↔ staged blobs (TOCTOU). Covered by TEST-008
  (integration in a fixture git repo: staged-dirty/worktree-clean file must warn; with
  `body_lint: enforce` it must block; worktree-dirty/staged-clean must pass).
- Seam 3: intake POST-SAVE `--strict` path ↔ D2 promotion. Covered by TEST-006 (exit-code
  pair) since STEP 2.5 invokes exactly `--check --strict --no-event --path`.
- Seam 4: METRICS_FLUSH prose ↔ state.mjs flag surface. The prescribed commands were
  verified against the live CLI during planning (`set-validation --status/--notes`,
  `set-code-review --required/--status/--notes` exist; reset-block guard confirmed).
  TEST-013 asserts the exact command tokens so prose/CLI drift is caught by grep.
- Seam 5: wrapper triple-tree (.claude/.gemini/.codex). Covered by TEST-017/TEST-010
  asserting the edited/new wrappers in all trees where the skill dir exists.
- Residual risk (accepted): whether Claude Code's native description-matching actually
  fires wrap-up on "hotovo"/"bye" is platform behavior not automatable here; recorded as
  manual verification. The removal of the false promise is fully testable.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected) | Description | Status |
|----------|------------|-------------|----------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-docs-audit.sh | Doc with stray `</content>` outside code → `stray-tool-markup` finding with rule id + line in `### Body lint` section | green |
| TEST-002 | Spec-AC-01 | integration | tests/skills/test-aai-docs-audit.sh | Doc with an unclosed ``` fence at EOF → `unbalanced-fence` finding | green |
| TEST-003 | Spec-AC-01 | integration | tests/skills/test-aai-docs-audit.sh | Doc with `SPEC-XXXX` body residue and `<PLACEHOLDER>` → `template-placeholder` findings; mixed-case angle prose NOT flagged | green |
| TEST-004 | Spec-AC-01 | integration | tests/skills/test-aai-docs-audit.sh | Negative controls: clean doc → zero findings; stray tag INSIDE a fenced block and INSIDE inline code → zero findings (fences-in-examples control) | green |
| TEST-005 | Spec-AC-01 | integration | tests/skills/test-aai-docs-audit.sh | Degenerate + nesting fixtures: empty body, frontmatter-only, 4-backtick fence wrapping a 3-backtick example (balanced → clean), tilde fence → no crash, correct verdicts | green |
| TEST-006 | Spec-AC-01 | integration | tests/skills/test-aai-docs-audit.sh | Promotion pair: findings present → `--check` exit 0 (report-only), `--check --strict` exit 1 naming body lint; clean corpus → both exit 0 | green |
| TEST-007 | Spec-AC-01 | integration | tests/skills/test-aai-docs-audit.sh | `--lint-body-file` predicate: dirty blob exit 1 with findings printed; clean blob exit 0; missing file exit 2 | green |
| TEST-008 | Spec-AC-01 | integration | tests/skills/test-aai-docs-audit.sh | Hook seam in fixture git repo: staged-dirty blob warns (commit allowed) by default; `body_lint: enforce` blocks; staged-clean/worktree-dirty passes (staged-blob rule) | green |
| TEST-009 | Spec-AC-09 | e2e         | tests/skills/test-aai-docs-audit.sh | Real repo: `--check --strict --no-event` exit 0 CLEAN; full docs-audit suite green; generate-docs-index.mjs idempotent | green |
| TEST-010 | Spec-AC-02 | integration | tests/skills/test-aai-hygiene-pack.sh | SKILL_PR anchors (scope derivation, scope-only staging, staged-vs-scope audit, never-merge/operator) + aai-pr wrapper shim/SUBAGENT-STOP/invoke line in .claude (+ mirrors) | green |
| TEST-011 | Spec-AC-03 | integration | tests/skills/test-aai-hygiene-pack.sh | SKILL_CODE_REVIEW External Review Response section: fetch (`gh api`), triage classes, RED-proofed regression, inline reply citing commit + TEST id, push | green |
| TEST-012 | Spec-AC-04 | integration | tests/skills/test-aai-hygiene-pack.sh | Report-staging instruction in SKILL_CODE_REVIEW; orphaned `docs/ai/reviews/` call-out in SKILL_WRAP_UP uncommitted-work step | green |
| TEST-013 | Spec-AC-05 | integration | tests/skills/test-aai-hygiene-pack.sh | METRICS_FLUSH: partial-flush condition (flushed == current_focus), exact set-validation/set-code-review command tokens, ledger-before-reset wording, NO `reset-block --force`; SPEC-0012 primary/fallback markers still present | green |
| TEST-014 | Spec-AC-06 | integration | tests/skills/test-aai-hygiene-pack.sh | Warnings policy names `decisions.jsonl` entry or follow-up ref per WARNING (SKILL_CODE_REVIEW); unrecorded-WARNINGs advisory present in SKILL_WRAP_UP | green |
| TEST-015 | Spec-AC-07 | integration | tests/skills/test-aai-hygiene-pack.sh | Fixture-diversity checklist (5 shapes) + happy-path-only question in BOTH SKILL_TDD and SKILL_TEST_CANON; SKILL_TDD SPEC-0012 markers intact | green |
| TEST-016 | Spec-AC-08 | integration | tests/skills/test-aai-hygiene-pack.sh | SKILL_WRAP_UP carries NO `.claude/triggers.json` promise; aai-wrap-up wrapper description carries the trigger phrases; `<SUBAGENT-STOP>` present in aai-wrap-up and aai-flush wrappers | green |
| TEST-017 | Spec-AC-08 | integration | tests/skills/test-aai-hygiene-pack.sh | The 6 wrappers (aai-docs-hub, aai-flush, aai-share, aai-tdd, aai-test-skills, aai-worktree) carry "Invoke this as `/aai-…`" in .claude and in existing .gemini/.codex mirrors | green |
| TEST-018 | Spec-AC-08 | integration | tests/skills/test-aai-hygiene-pack.sh | SKILL_META carries the loader note; hooks/session-start.sh + .ps1 still reference it; hooks/hooks.json still wires SessionStart | green |
| TEST-019 | Spec-AC-01 | integration | tests/skills/test-aai-docs-audit.sh | Review W1: hook reads `body_lint`/`close_gate` mode from the STAGED blob (else HEAD) of docs-audit.yaml — an UNSTAGED worktree downgrade cannot bypass enforce; staged downgrade governs (control); untracked fresh-repo config still honored | green |
| TEST-020 | Spec-AC-01 | integration | tests/skills/test-aai-docs-audit.sh | Review W2: a staged doc with a SPACE in its filename is gated, not word-split into nonexistent paths and silently skipped — body-lint block AND close-gate block (enforce must abort) | green |
| TEST-021 | Spec-AC-01 | integration | tests/skills/test-aai-docs-audit.sh | Review W3: a multi-line inline code span's interior is never flagged; a line-initial backtick run closed by a matching run on the SAME line (``` x ``` on one line) is an inline span, not a fence open — no spurious unbalanced-fence, later real findings still flagged | green |
| TEST-022 | Spec-AC-04 | integration | tests/skills/test-aai-hygiene-pack.sh | Review W4 (H2/H4 seam): SKILL_PR staged-vs-scope audit whitelists docs/ai/reviews/ report artifacts as expected companions, citing H4 | green |

Test status values: pending → red → green.

RED-proof obligation (all strategies): TEST-001..008 follow full TDD RED-GREEN against the
engine. TEST-010..018 are grep-wiring tests whose RED state is observed by running the new
suite against the PRE-CHANGE prompt/wrapper text (each assertion must FAIL before the edit
lands — e.g. TEST-016's "no triggers.json promise" fails today because SKILL_WRAP_UP:115
carries it). TEST-009 is the regression backstop (must be green before AND after; its RED
counterpart is TEST-006's strict-exit-1 fixture, which proves the gate can fail).
TEST-019..022 are the post-PASS review remediation cases (review-20260704T110648Z W1–W4):
each was proven RED against the pre-fix code (docs/ai/tdd/red-20260704T111832Z-spec0013-w1-w4.log)
and GREEN after (docs/ai/tdd/green-20260704T112110Z-spec0013-w1-w4.log).

### Post-review remediation note (2026-07-04, review-20260704T110648Z)
- W1 (staged-config read) is deliberately applied to BOTH generated-hook gate blocks —
  body-lint (this spec's H1 scope) AND the pre-existing SPEC-0011 close-gate block.
  The close-gate edit is a conscious scope extension beyond frozen H-scope: both blocks
  share the same defect class (SPEC-0011-F2, "gate the staged blob, never the worktree")
  and the reviewer flagged the pattern in both; consistency between the two byte-parallel
  gate blocks outweighs strict scope minimalism. W2 (newline-safe loop iteration) is
  likewise applied to both loops. Installer parity (.sh/.ps1) preserved byte-for-byte.

## Verification
- `bash tests/skills/test-aai-docs-audit.sh` → exit 0 (incl. TEST-001..009, TEST-019..021 cases)
- `bash tests/skills/test-aai-hygiene-pack.sh` → exit 0 (TEST-010..018, TEST-022)
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` → exit 0, Verdict CLEAN
- `node .aai/scripts/generate-docs-index.mjs` twice → second run byte-idempotent
- Full skills suites green via `.aai/scripts/aai-run-tests.sh` (LEARNED: never spawn runners directly)
- Manual (residual): run `/aai-pr` in a fixture repo with one in-scope and one out-of-scope
  dirty file — out-of-scope file must not be staged (intake Verification bullet).
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal.

## Evidence contract
For each implementation, validation, TDD, and code review artifact record: ref_id
(CHANGE-0007/SPEC-0013), Spec-AC + TEST-xxx links, command or review scope, exit code or
verdict, evidence path (docs/ai/tdd/*.log for RED/GREEN), commit SHA or diff range.

## Code review plan (initial)
- code_review.required: true (engine change + workflow-prompt changes + hook change).
- Scope: the inline review scope list above (explicit paths).
- Base ref: main. Review runs after Validation PASS, per WORKFLOW.

Notes:
This document defines HOW, not WHAT/WHY (WHY lives in CHANGE-0007).
This document does not define workflow.
