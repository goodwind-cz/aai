---
id: planning-companion-obligations
number: 25
type: issue
status: draft
links:
  pr: []
  commits: []
---

# Planning never surfaces "companion obligations", so prompt/`.aai`-touching scopes ship incomplete and break CI

## Summary
- `.aai/PLANNING.prompt.md` tells the planner how to build Spec-ACs, a Test Plan,
  strategy, isolation, and review scope — but it NEVER reminds the planner that
  certain kinds of change carry a MANDATORY companion edit enforced only later by
  CI. As a result the spec's scope omits the companion, Implementation ships a
  "complete" change, and CI fails on an invariant the planner never saw. Two
  companion obligations recur:
  1. **prompt-diet ledger true-up** — any scope that ADDS bytes to the prompt
     corpus (`.aai/*.prompt.md`, `.aai/AGENTS.md`) MUST add an itemized
     `JUSTIFIED_ADDITIONS` entry (+ bump the TEST-012 checkpoint) in
     `tests/skills/lib/prompt-diet-ledger.sh`, or the `test-aai-prompt-diet.sh`
     TEST-010 byte-floor fails (and cascades into every suite that re-runs it:
     ceremony-levels, constitution, debug-gate, advisory-skills, delta-stage2).
     This is ALREADY documented as definition-of-done in
     `docs/knowledge/LEARNED.md` (2026-07-17, lines ~131-134) — but the knowledge
     lives in LEARNED, not in the operational prompt the planner actually reads.
  2. **PROFILES.yaml classification** — any NEW `.aai/**` vendored file MUST be
     classified in `.aai/system/PROFILES.yaml`, or `test-aai-layer-profiles.sh`
     manifest-conformance (100% classification) fails and cascades into
     `test-aai-release.sh` TEST-020.

## Type
- bug

## Impact
- Every prompt-corpus edit and every new `.aai/**` file is one forgotten companion
  away from a red CI on an otherwise-correct change, costing a full ~8-min CI cycle
  plus a reactive fix commit. Observed THREE times in one session (HITL, sweep,
  and branch-per-work-item PRs each tripped prompt-diet; branch-per-work-item also
  tripped PROFILES). Severity: medium — no product breakage, systematic waste and a
  false "done" signal at planning time.
- AAI-layer gap → every downstream project inherits it; fixing PLANNING once
  removes it everywhere via `/aai-update`.

## Current Behavior
- PLANNING produces a spec whose `## Test Plan` and scope cover the FEATURE, with
  no step that asks "does this scope touch the prompt corpus / add a `.aai` file,
  and if so is the companion edit in scope?". The invariants are discovered only
  when CI runs the byte-floor / manifest-conformance gates.

## Expected Behavior
- PLANNING carries an explicit **Companion obligations** checklist. When the
  planned scope (a) adds prompt-corpus bytes, or (b) adds a new `.aai/**` file, the
  planner MUST fold the corresponding companion (ledger true-up / PROFILES entry)
  into the spec's scope + Test Plan BEFORE freezing. The checklist is short,
  closed, and additive; it does not change how ACs or the Test Plan are built
  otherwise.

## Verification
- `.aai/PLANNING.prompt.md` gains a Companion-obligations checklist naming both
  triggers → required companion, each pointing at the concrete file
  (`tests/skills/lib/prompt-diet-ledger.sh`, `.aai/system/PROFILES.yaml`).
- A skills test asserts the checklist text is present (RED-proof: grep = 0 today)
  and names both companions + their files.
- Self-demonstration: because THIS scope edits `.aai/PLANNING.prompt.md` (prompt
  corpus), the scope MUST itself include the prompt-diet ledger true-up for its own
  byte growth — the fix obeys the rule it introduces, and the full skills suite is
  green (no byte-floor / manifest cascade) on macOS + Linux CI.

## Constraints / Risks
- MUST stay ceremony L1: touch only `.aai/PLANNING.prompt.md` (prompt), the
  prompt-diet ledger true-up (`tests/skills/lib/prompt-diet-ledger.sh` +
  `test-aai-prompt-diet.sh` checkpoint), and a NEW/updated test. Do NOT touch any
  `protected_paths_l3` (`WORKFLOW.md`, `CONSTITUTION.md`, `pre-commit-checks.*`,
  `state*.mjs`, `allocate-doc-number.mjs`) — confirmed none are needed.
- Keep the checklist SHORT — the prompt corpus is under an active byte diet; a
  bloated checklist re-breaches the floor. Minimize bytes; credit exactly the
  measured growth in the ledger (0 B headroom), consistent with recent entries.
- SKILL_PR could carry a belt-and-suspenders precondition too, but PLANNING is the
  primary home (scope is defined there); keep the first cut PLANNING-only to bound
  bytes unless review argues the second catch is worth its cost.
- Do NOT try to AUTO-DETECT companion needs in a script here — this is a
  prompt-level checklist for the planner, not a new guard (that would be a larger,
  separate scope). Fail-safe is the existing CI gates; this just moves the catch
  earlier.
- No secret referenced — SECRETS PREFLIGHT skipped.

## Notes
- This is the "shift-left" of two invariants that are currently enforced only at
  the CI trailing edge. LEARNED.md already knows rule (1); this promotes both from
  tribal knowledge into the deterministic planning surface. Companion list is
  intentionally CLOSED (two entries) — if a third recurring companion emerges, it
  is a one-line checklist append with its own ledger true-up.
