---
id: loop-ceremony-aware-dispatch
type: change
number: 30
status: done
links:
  pr:
    - 93
  commits:
    - be2a1a6
---

# Change — Ceremony-Aware LOOP Dispatch (extend L0-L3 to the runner, not just doc shape)

## Summary
SPEC-0030 (RFC-0009) defined ceremony levels 0-3 and already prunes three
`orchestration-dispatch.mjs` rules (6, 8, 13) plus the docs-audit close gate
(SPEC-0036) by level. What it never touched is the LOOP's DISPATCH BEHAVIOR
for the roles it sends work to: at every level today the loop still routes L0
and L1 scopes through the same full lane as L2/L3 — full independent
validation depth, full suite re-runs, and (per PLANNING/VALIDATION prompt
text, not the dispatch table) no shortcut for "focused scope only." This
change adds a ceremony-aware DISPATCH LANE: for L0/L1 scopes the loop runs a
lightweight lane (implementation + focused tests on the declared test scope,
not the full suite + one independent review), skipping spec freeze ceremony
and full TDD ceremony where SPEC-0030 already permits it; L2/L3 keep today's
full lane unchanged.

## Motivation / Business Value
- Operator feedback from a downstream AAI project (EEX client sFTP->API
  rewrite): a full aai-loop for a trivial follow-up change (moving
  credentials from ENV to config) took 30+ minutes and ~20% of a weekly token
  budget, because the loop re-ran full validation of everything regardless of
  how small the declared scope was.
- Today's session in this repo independently confirms the underlying gap:
  SPEC-0030 D3's table already says validation depth should be "suite run" /
  "suite re-run + targeted probe" at L0/L1 vs "full" at L2/L3, and the spec
  artifact shrinks to a tech-note/lean-SPEC — but the ROLE GUIDANCE that
  encodes "declared test scope, not the full suite" is prose in role prompts,
  never a dispatch-table lane. CHANGE-0029 (docs/issues/CHANGE-0029-validation-ac-evidence-close-time.md)
  is the concrete precedent: an L1 change (single prompt-file wording edit,
  `Ceremony justification: single prompt-file wording change, no
  engine/test surface`) still had its evidence and STATE handling worked
  out ad hoc by the runner, rather than by a canon rule, because no lane
  exists in orchestration-dispatch.mjs or the role prompts that says
  "L0/L1: focused scope only."
- Net effect without this change: ceremony level correctly shrinks the
  ARTIFACT (SPEC-0030) and the CLOSE GATE (SPEC-0036), but not the RUNTIME
  COST of getting there — the exact complaint from the EEX case.

## Scope
- In scope:
  - `.aai/scripts/orchestration-dispatch.mjs` — dispatch rule additions/
    annotations so the snapshot and `decide()` surface which lane
    (lightweight vs full) applies for the current `ceremony_level`, reusing
    the existing fail-closed level guard (SPEC-0030 D2: absent/garbage/
    out-of-range always resolves to 2/full).
  - `.aai/VALIDATION.prompt.md` and/or a new lightweight-lane guidance block:
    at L0/L1, validation runs against the DECLARED test scope (named in the
    spec/tech-note's Test Plan or lean AC table) instead of the full suite
    sweep, and requires exactly one independent review (already true at every
    level per SPEC-0030 D3's rule-13 row) rather than additional passes.
  - `.aai/PLANNING.prompt.md` / relevant role prompts: wording so the
    declared `ceremony_level` at intake/freeze is what selects the lane (no
    new frontmatter mechanism beyond SPEC-0030's existing field).
  - Guardrail wiring: confirm/extend existing `spec-lint` and the L1 close
    gate (SPEC-0036) so an L0/L1 misuse (declaring a lane too lean for the
    actual diff) is still caught at freeze and at close; the close ceremony
    itself is unchanged (SPEC-0036 stays the closing authority); audit CLEAN
    invariants (`docs-audit.mjs --check --strict`) must hold before and after.
- Out of scope:
  - Re-litigating the L0-L3 level definitions themselves (SPEC-0030 is
    frozen/done) or the close-gate lean-AC-table shape (SPEC-0036 is frozen/
    done) — this change consumes both, it does not redesign them.
  - Any new ceremony level (still exactly 0-3).
  - Mechanical protected-path diff enforcement (SPEC-0030 D5 explicitly
    deferred this; still out of scope here).

## Affected Area
- Deterministic orchestration core (`.aai/scripts/orchestration-dispatch.mjs`).
- Role prompts that currently hardcode "full suite" / "full validation depth"
  language without a level branch (`.aai/VALIDATION.prompt.md`,
  `.aai/PLANNING.prompt.md`, and any lightweight-lane skill surface such as
  `.aai/SKILL_TDD.prompt.md`'s "declared test scope" framing).
- `docs/ai/docs-audit.yaml` only if a new dial is needed to report lane
  selection (no new enforcement knob expected; reuse existing lean-gate
  rules per SPEC-0036).

## Desired Behavior (To-Be)
- Ceremony level (declared per SPEC-0030 D1, at intake/spec-freeze, with a
  `Ceremony justification:` line at L0/L1) now determines a DISPATCH LANE,
  not only the artifact shape and close gate:
  - L0/L1: lightweight lane — implementation (or TDD Implementation) covering
    the declared/focused test scope only, one independent review, validation
    that re-runs/targets the declared scope rather than the full suite sweep.
    Spec freeze and full TDD ceremony (multi-test-plan RED-GREEN-REFACTOR
    cycles beyond the declared scope) are skipped, consistent with SPEC-0030
    D3's existing "lean SPEC" / "suite re-run + targeted probe" row — this
    change makes the DISPATCH mechanically honor that row instead of leaving
    it to role-prompt prose and runner judgment.
  - L2/L3: unchanged — today's full lane (full spec freeze, full TDD/loop
    ceremony, full validation sweep, full review, L3's additional operator
    checkpoint) exactly as SPEC-0030/SPEC-0036 already specify.
- The lane selection is deterministic and fail-closed identically to
  SPEC-0030 D2: an absent, garbage, or out-of-range `ceremony_level` can only
  select the FULL lane, never the lightweight one.
- Misuse guardrails: spec-lint's L0/L1 exemption checks and the L1 close gate
  (SPEC-0036) remain the enforcement backstop for a scope that declares a
  lane too lean for its actual diff; review may re-classify the level upward
  as a recorded finding (existing SPEC-0030 policy, unchanged).

## Acceptance Criteria
- AC-001: An L0 or L1 scope with a correctly declared `ceremony_level` and
  justification line completes via the lightweight lane in <= 3 dispatched
  roles (e.g. Implementation/TDD Implementation -> Validation -> Code Review,
  or fewer when Planning/worktree gates are trivially satisfied), measured
  from `docs/ai/LOOP_TICKS.jsonl` role-dispatch count for that scope's ref_id.
- AC-002: For a lightweight-lane scope, the full repository test sweep
  (`tests/skills/*` full run) is NOT invoked by Validation; only the
  declared/focused test scope is re-run. Verified by absence of a full-sweep
  command in the validation report/evidence for that ref_id, alongside
  presence of the targeted-scope command and its exit code.
- AC-003: L2 and L3 scope behavior is byte-identical to pre-change dispatch
  output (same rule-6/8/13 firing, same role sequence, same validation
  depth) — proven by re-running the existing
  `tests/skills/test-aai-ceremony-levels.sh` and
  `tests/skills/test-aai-orchestration-dispatch.sh` suites post-change with
  no new failures and no changed pass/fail shape for L2/L3 fixtures.
- AC-004: An L0/L1 scope whose actual diff exceeds its declared lane is still
  caught — spec-lint (freeze-time) and the SPEC-0036 close gate (close-time)
  continue to fire on misuse exactly as today; no new escape hatch is
  introduced. Verified by a fixture: an L1-declared scope with a
  full-ceremony-shaped diff still fails or is flagged by the existing gates.
- AC-005: `node .aai/scripts/docs-audit.mjs --check --strict --no-event`
  stays exit 0 (CLEAN) before and after the change, over the full repo.

## Verification
- `bash tests/skills/test-aai-ceremony-levels.sh` -> exit 0.
- `bash tests/skills/test-aai-orchestration-dispatch.sh` -> exit 0 (L2/L3
  legacy parity, AC-003).
- New/extended fixture(s) proving the lightweight-lane dispatch count and
  scoped-test invocation for an L0/L1 sample scope (AC-001, AC-002).
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` -> exit 0.
- Manual/e2e trace: an L1 change comparable in shape to CHANGE-0029 dispatched
  through the new lane, with `docs/ai/LOOP_TICKS.jsonl` role count and
  elapsed time recorded as before/after evidence.

## Constraints / Risks
- Must not weaken Constitution art. 1 (evidence before claims) — the
  lightweight lane changes DEPTH and SCOPE of validation, never removes the
  requirement for recorded, executable evidence. SPEC-0030 D3 already
  establishes this boundary ("validation is required at EVERY level... only
  its DEPTH is level-scoped").
- Risk: a mis-declared lane (level too low for the real diff) escaping to
  lightweight treatment undetected — mitigated by AC-004's existing-gate
  reliance (no new detection mechanism invented, reduces risk of a second,
  divergent enforcement path).
- Dependency: this change is a pure CONSUMER of SPEC-0030 (levels, fail-closed
  default, D3 table) and SPEC-0036 (lean close gate) — both are `status: done`
  and should not need re-opening; if either needs a wording change, treat as
  a separate follow-up rather than reopening a closed spec.
- Likely touches `.aai/scripts/orchestration-dispatch.mjs`, which is on the
  `protected_paths_l3` list (docs/ai/docs-audit.yaml) — Planning should
  weigh declaring THIS change itself at L2 or L3 (not L0/L1) given it edits a
  protected surface, even though its purpose is to shrink ceremony for OTHER
  scopes.

## Notes
- Priority 1 of a six-doc intake batch responding to combined EEX operator
  feedback and in-repo evidence gathered 2026-07-17.
- Precedent cited: CHANGE-0029
  (docs/issues/CHANGE-0029-validation-ac-evidence-close-time.md, PR #92,
  ceremony_level 1) — a real L1 scope whose lean treatment was worked out by
  runner judgment rather than a canon dispatch rule.
- Builds on: SPEC-0030 (docs/specs/SPEC-0030-spec-scale-adaptive-ceremony.md,
  done) and SPEC-0036 (docs/specs/SPEC-0036-spec-l1-close-gate.md, done).
- Related follow-ups from the same batch: `dispatch-new-intake-after-completed-scope`
  (dispatcher retargeting gap) and `loop-token-usage-capture` (both surfaced
  independently in this repo's own operation).
