---
id: spec-single-dual-verdict-review
type: spec
number: 21
status: implementing
links:
  rfc: single-dual-verdict-review
  research: RES-0001
  pr: []
  commits: []
---

# SPEC — Single Dual-Verdict Code Review (one pass, two verdicts, anti-gaming hardened)

SPEC-FROZEN: true

## Links
- RFC: single-dual-verdict-review
  (docs/rfc/RFC-0008-single-dual-verdict-review.md — accepted 2026-07-16,
  Option B confirmed by project owner)
- Research: RES-0001 findings F3 (766-line prompt is the largest in the repo)
  and F4 (two-stage review is the pattern Superpowers measured out of
  existence) — docs/specs/RES-0001-aai-competitive-gap-and-model-efficiency.md
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight (this doc)
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: standard meanings per template

## Assumptions (nailing the RFC's open questions)
- A1 — Measurement window IS a recorded gate, not an operator judgment call:
  this spec carries a dedicated `measurement-window` AC row (Spec-AC-05,
  status deferred) with a Review-By sized to land after roughly the next
  5 reviewed scopes. Comparison inputs: review tokens, review wall-clock, and
  remediation cycles for the next 5 reviewed scopes vs the two-stage history
  already in docs/ai/METRICS.jsonl. Revert path: restore the prior prompt
  from git history (one-file change).
- A2 — Re-review after remediation becomes a single dual-verdict pass
  automatically. No special casing anywhere: the remediation loop simply
  re-dispatches the same (now single-pass) review prompt.
- A3 — Whole-branch final review on the most capable model for L scopes is
  OUT of scope. Follow-up candidate, to be raised only if the measurement
  window shows size-correlated regressions.

## Design decisions

### D1 — One review pass returning a structured dual-verdict block
`.aai/SKILL_CODE_REVIEW.prompt.md` is rewritten from 766 lines to at most
250 lines. One reviewer, one pass over the diff, returning:

- `spec_compliance: pass|fail` — evidence is the AC table walk: one line per
  Spec-AC row of the frozen spec with a per-AC citation (diff file:line,
  TEST-xxx evidence, or the named gap). Deviations listed even when
  reasonable.
- `code_quality: pass|fail` — real defects only, ranked BLOCKING /
  NON-BLOCKING, each with file:line and a concrete failure scenario.
  NON-BLOCKING findings are the WARNINGs of the SPEC-0013 H6 policy and keep
  its remediate-or-promote disposition duty. Any BLOCKING finding fails the
  verdict.
- `cannot_verify: [...]` — MANDATORY section listing claims the diff alone
  cannot substantiate; an empty list is allowed but must be stated
  explicitly.
- Overall review status = pass only when BOTH verdicts pass. The two
  verdicts must cite disjoint evidence sections (blending guard).

### D2 — Preserved verbatim-or-equivalent (the ceremony that earns its cost)
- Diff-scope preflight: clean explicit scope, inline vs worktree policy,
  STOP on ambiguous scope.
- Warnings policy with teeth (SPEC-0013 H6): every WARNING gets a
  disposition — remediated, or promoted to a docs/ai/decisions.jsonl entry
  or a tracked follow-up ref; a PASS with open WARNINGs is conditional.
- External Review Response flow (SPEC-0013 H3): fetch threads, triage
  real / stale / duplicate / disputed, RED-proofed regression test per real
  finding, inline replies citing commit SHA and TEST id, push; never resolve
  a thread without a reply.
- Report location docs/ai/reviews/ + the `state.mjs set-code-review` STATE
  contract (status pass|fail|waived unchanged).
- The "never docs/validation/" lesson (SPEC-0015 review): validation/review
  evidence never goes to the audit-scanned docs/validation/ directory.
- Report-as-staged-companion rule (SPEC-0013 H4): review reports are staged
  with the scope's commit and never orphan; SKILL_PR treats them as expected
  companions.

### D3 — Cut (RES-0001 F3 named these as fiction/duplication)
- The stage-1/stage-2 duplicated process scaffolding (mandatory-order block,
  red-flag framing, per-stage report plumbing).
- Inline JavaScript regex-checker arrays (jsChecks/pyChecks/sqlChecks,
  parseDiff, generateReport) — fiction; no such engine exists.
- Fake example transcripts (usage examples with invented output).
- `.aai/code-review-config.json` configuration manual — no consumer exists.
- CI YAML (GitHub Actions workflow) and the troubleshooting table.

### D4 — Anti-gaming contract in .aai/SUBAGENT_PROTOCOL.md
New rules at the same tier as the MODEL field, applying to every review
dispatch:
1. The dispatching orchestrator MUST NOT characterize expected findings,
   pre-rate severity, or scope-exclude areas for the reviewer (no coaching).
2. The reviewer context is read-only on implementation files; it writes only
   its report (and STATE code_review via the CLI when it is the recording
   agent).
3. Diff handoff is by ref/path list (base/head refs, PR number, explicit
   paths) — never pasted inline into the dispatch prompt.

### D5 — Surface alignment
Wrapper descriptions (`.claude/.codex/.gemini skills/aai-code-review/SKILL.md`)
describe the dual-verdict single pass; `.aai/roles/ROLES.md` Code Review role
and the `.aai/AGENTS.md` skill-index line drop the two-stage wording.
Orchestration dispatch rule 13 and `state.mjs set-code-review` are unchanged.

## Implementation strategy
- Strategy: loop
- Rationale: prompt/protocol text edits plus grep-wired tests — mechanical
  wiring with no runtime code. RED-proof obligation is satisfied by running
  every new grep stanza against the pre-change files and capturing the
  failing output (grep-RED) before the edits land.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: rewrites the live review prompt and the subagent
  protocol (workflow-protected surfaces); PR-bound work.
- User decision: worktree (this branch: feat/dual-verdict-review)
- Base ref: main
- Worktree branch/path: feat/dual-verdict-review /
  /Users/ales/Projects/aai-feat-dual-verdict
- Inline review scope: .aai/SKILL_CODE_REVIEW.prompt.md,
  .aai/SUBAGENT_PROTOCOL.md, .aai/roles/ROLES.md, .aai/AGENTS.md,
  .claude/skills/aai-code-review/SKILL.md,
  .codex/skills/aai-code-review/SKILL.md,
  .gemini/skills/aai-code-review/SKILL.md,
  tests/skills/test-aai-hygiene-pack.sh,
  docs/specs/SPEC-0021-spec-single-dual-verdict-review.md,
  docs/rfc/RFC-0008-single-dual-verdict-review.md, docs/INDEX.md

## Acceptance Criteria Mapping
- RFC Option B "single reviewer, dual verdict" → Spec-AC-01 (prompt shape),
  Spec-AC-02 (preserved contracts)
- RFC "protocol hardening" → Spec-AC-03 (anti-gaming rules)
- RFC "migration/compatibility" → Spec-AC-04 (wrapper + role surfaces)
- RFC "measurement gate" → Spec-AC-05 (deferred measurement-window row)
- Repo hygiene invariant → Spec-AC-06 (suites, audit, index, state)

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | SKILL_CODE_REVIEW.prompt.md is ≤250 lines, carries the dual-verdict block (spec_compliance AC-walk, code_quality BLOCKING/NON-BLOCKING with file:line + failure scenario, MANDATORY cannot_verify) and contains NO stage-1/stage-2 scaffolding, checker-array fiction, config JSON, CI YAML, or troubleshooting table | done | TEST-001..003 green (docs/ai/tdd/green-20260715T232838Z-dual-verdict.log); RED docs/ai/tdd/red-20260715T232618Z-dual-verdict.log | — | 766 → 213 lines |
| Spec-AC-02 | Preserved contracts: diff-scope preflight, H6 warnings policy, H3 external-review-response, docs/ai/reviews/ + set-code-review STATE contract, never-docs/validation lesson, report-staging companion rule | done | TEST-004 green + pre-existing hygiene stanzas test_011/test_012/test_014 green (same green log) | — | — |
| Spec-AC-03 | SUBAGENT_PROTOCOL.md carries the three anti-gaming rules (no coaching/pre-rating/scope-exclusion; reviewer read-only on implementation files; diff handoff by ref/path list, never pasted inline) | done | TEST-005 green (same green log); RED same red log | — | — |
| Spec-AC-04 | All three wrapper descriptions match the dual-verdict shape; ROLES.md Code Review role and AGENTS.md index line carry no stage-ordering wording | done | TEST-006 green (same green log); RED same red log | — | — |
| Spec-AC-05 | measurement-window: after ~5 reviewed scopes, compare review tokens, wall-clock, and remediation cycles vs the two-stage history in docs/ai/METRICS.jsonl; keep the single-pass prompt on parity-or-better, else revert by restoring the prior prompt from git | done | Measurement gate evaluation section below (2026-07-16); METRICS.jsonl review-run durations both eras | manual:2026-07-16 | Evaluated with 5/5 data points — verdict KEEP (parity-or-better on wall-clock and catch quality; token axis unmeasurable, see caveats) |
| Spec-AC-06 | Full sweep green: hygiene, state, dispatch, metrics, docs-audit, doc-numbering, prompt-diet suites; repo-wide strict docs audit clean; docs index idempotent; check-state OK | done | TEST-007 sweep log docs/ai/tdd/sweep-20260715T233105Z-dual-verdict.log (7 suites exit 0; strict audit CLEAN; index idempotent modulo Generated stamp; check-state OK) | — | — |

Status values: planned | implementing | done | deferred | blocked | rejected
(gate behavior per template: any planned/implementing AC blocks PASS; done
requires non-empty Evidence; deferred/blocked require future Review-By).

## Implementation plan
- Components: `.aai/SKILL_CODE_REVIEW.prompt.md` (rewrite),
  `.aai/SUBAGENT_PROTOCOL.md` (new anti-gaming section),
  `.aai/roles/ROLES.md` + `.aai/AGENTS.md` (role/index alignment), the three
  `skills/aai-code-review/SKILL.md` wrappers, and
  `tests/skills/test-aai-hygiene-pack.sh` (new grep stanzas test_040..042).
- Data flows: none at runtime — prompt/protocol text and grep-wired tests.
- Edge cases: hygiene stanzas must not self-match their own negative markers;
  preserved H3/H6 anchors must keep the exact strings the pre-existing
  test_011/test_012/test_014 stanzas grep for.

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Status |
|----------|------------|------|----------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | unit | tests/skills/test-aai-hygiene-pack.sh (test_040) | `wc -l` of SKILL_CODE_REVIEW.prompt.md ≤ 250 | green |
| TEST-002 | Spec-AC-01 | unit | tests/skills/test-aai-hygiene-pack.sh (test_040) | Dual-verdict anchors present: spec_compliance, code_quality, MANDATORY cannot_verify, BLOCKING/NON-BLOCKING, per-AC citation walk, failure scenario | green |
| TEST-003 | Spec-AC-01 | unit | tests/skills/test-aai-hygiene-pack.sh (test_040) | Negative markers absent: two-stage mandatory-order block, Stage 1/Stage 2 headers, parseDiff/jsChecks fiction, code-review-config.json, CI workflow YAML, troubleshooting table | green |
| TEST-004 | Spec-AC-02 | unit | tests/skills/test-aai-hygiene-pack.sh (test_040 + existing test_011/012/014) | Preserved anchors: diff-scope preflight, SPEC-0013 H6 warnings policy, External Review Response, docs/ai/reviews/, set-code-review, never docs/validation/ | green |
| TEST-005 | Spec-AC-03 | unit | tests/skills/test-aai-hygiene-pack.sh (test_041) | SUBAGENT_PROTOCOL anti-gaming anchors: MUST NOT characterize expected findings / pre-rate severity / scope-exclude; read-only on implementation files; ref/path list, never pasted inline | green |
| TEST-006 | Spec-AC-04 | unit | tests/skills/test-aai-hygiene-pack.sh (test_042) | Wrapper descriptions carry the dual-verdict shape in every skill tree; ROLES.md/AGENTS.md carry no Stage 1/Stage 2 wording for code review | green |
| TEST-007 | Spec-AC-06 | e2e  | tests/skills/ (hygiene, state, orchestration-dispatch, metrics, docs-audit, doc-numbering, prompt-diet) + docs-audit --check --strict --no-event + generate-docs-index.mjs run-twice + check-state.mjs | Full sweep green; strict audit clean; index idempotent; STATE valid | green |

Test status values: pending → red → green. Every Spec-AC except the deferred
measurement row has at least one TEST-xxx entry; IDs stable after freeze.
Spec-AC-05 is a measurement gate, not a code behavior — its "test" is the
wrap-up METRICS comparison named in its Notes.

## Verification
- `bash tests/skills/test-aai-hygiene-pack.sh` (TEST-001..006 via
  test_040..042 + preserved test_011/012/014)
- `wc -l .aai/SKILL_CODE_REVIEW.prompt.md` (≤ 250)
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` (repo-wide)
  and `--path docs/specs/SPEC-0021-spec-single-dual-verdict-review.md`
  (non-vacuous: Scanned: 1)
- `node .aai/scripts/generate-docs-index.mjs` twice — second run reports no
  changes (idempotent)
- `node .aai/scripts/check-state.mjs docs/ai/STATE.yaml`
- Suites: test-aai-state.sh, test-aai-orchestration-dispatch.sh,
  test-aai-metrics.sh, test-aai-docs-audit.sh, test-aai-doc-numbering.sh,
  test-aai-prompt-diet.sh
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal (Spec-AC-05
  deferred with future Review-By is terminal for freeze purposes).

## Evidence contract
For each implementation, validation, and review artifact, record: ref_id,
Spec-AC + TEST-xxx links, command or review scope, exit code or verdict,
evidence path under docs/ai/tdd/ or docs/ai/reviews/, commit SHA or diff
range when available.

Notes:
This document defines HOW, not WHAT/WHY. It does not define workflow.

## Validation finding dispositions (2026-07-16)

- F1 (cross-surface drift: .codex/.gemini wrapper descriptions and
  docs/USER_GUIDE.md still advertised a "post to GitHub PR" / --post feature
  and the old ERROR/WARNING/INFO labels; the feature never had an
  implementation): REMEDIATED — wrappers de-advertised, USER_GUIDE section
  rewritten to the dual-verdict contract and BLOCKING/NON-BLOCKING labels.
- Minor ambiguity (INFO-level notes' placement in the findings schema):
  ACCEPTED — INFO notes belong in the report body, not the verdict block;
  the schema stays two-level by design (H6 dispositions cover the rest).

## Review (dogfood) finding dispositions (2026-07-16)

- NB-1 (old Stage-1/Stage-2 + ERROR taxonomy lingers on orchestration-facing
  surfaces): PROMOTED — filed as CHANGE review-taxonomy-alignment (this
  branch, draft; implementation is a follow-up scope). Fixing here would be
  scope creep on a frozen spec.
- NB-2 (STATE-write authority stated three ways; K>=2 lost-update risk):
  REMEDIATED — the review prompt now grants the STATE write only when the
  dispatch does (single-agent or explicit), deferring to SUBAGENT_PROTOCOL's
  single-writer rule in parallel mode.
- Meta friction 3 (read-only reviewer cannot file refs): REMEDIATED — prompt
  now says the reviewer NAMES dispositions and the orchestrator RECORDS them.
- Meta friction 1 (scope-direction vs coaching fuzzy line): ACCEPTED — the
  dispatch may name the diff scope and evidence axes; it must not name
  expected findings or their severity. Wording already in SUBAGENT_PROTOCOL;
  further sharpening left to the measurement-gate wrap-up.
- cannot_verify items: tracked by the deferred Spec-AC-05 measurement row
  (real-world parity), a smoke run in Codex/Gemini (operator errand), and the
  behavioral nature of rule 1 (accepted residual).

## Measurement gate evaluation (2026-07-16, 5/5 reviewed scopes)

Data (docs/ai/METRICS.jsonl Code Review role runs, duration_seconds):
- TWO-STAGE era: n=19 non-null runs (2026-06-25..07-15), mean 446 s, median 375 s.
- DUAL-VERDICT era: n=5 — ISSUE-0007 405 s, CHANGE-0015 323 s, CHANGE-0014
  355 s, CHANGE-0016 221 s, PR#67 post-merge 686 s. Mean 398 s (-11% vs
  two-stage mean), median 355 s (-5%). Spec-backed subset (n=4, excluding the
  spec-less post-merge outlier whose meta-note explains the extra reading):
  mean 326 s (-27%).

Quality axis (parity-or-better required):
- Review-FAIL rate: two-stage era caught blocking defects pre-merge (CR-1,
  B1); dual-verdict era: 0 FAILs in 5, but every review produced substantive
  NON-BLOCKING findings with dispositions (LEARNED scope mismatch, baseline
  duplication, whitelist anchoring, agent-hang risk + TOCTOU on operator
  code) — catch quality maintained, including on code no pipeline had seen.
- The mandatory cannot_verify section produced honest, closable gap lists in
  all 5 reviews (reviewers explicitly credited it for preventing implied
  passes).
- Remediation cycles attributable to review: two-stage era >=1 on most
  scopes; dual era 1 in 5 (ISSUE-0007's cycle originated in validation, not
  review). Confounded by the same-period tooling hardening — reported, not
  claimed as review-driven.

Caveats (honest limits):
- TOKEN comparison — the RFC's headline axis — is UNMEASURABLE: tokens_in/out
  are null across both eras (runtime does not expose usage; CHANGE-0010's
  warning machinery now makes the gap visible on every run). The -50% token
  claim therefore remains imported from Superpowers' evals, not locally
  demonstrated.
- Small n (5 vs 19), heterogeneous scope sizes, and the eras also differ in
  tooling maturity (dispatch mechanization landed mid-window).

VERDICT: KEEP the single dual-verdict prompt. Wall-clock is parity-or-better
(-5% median, -11..-27% mean), catch quality is maintained with strictly
better honesty artifacts (cannot_verify), and no post-merge regression
attributable to a missed review finding was observed. Revert path remains
documented and unexercised. Re-evaluate the token axis if/when the harness
exposes real usage.
