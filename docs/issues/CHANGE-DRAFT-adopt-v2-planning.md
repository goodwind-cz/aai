---
id: adopt-v2-planning
number: null
type: change
status: draft
user_visible: true
ceremony_level: 2
links:
  pr: []
  commits: []
---

# Change — close CHANGE-0113's D2 gate with five behavioral probes, then adopt the altitude PLANNING prompt

Ceremony justification: L2 — the ride edits a role prompt, adds a hard refusal
path to `spec-freeze.mjs`, adds a lint rule and a role-output postcondition, and
adds one new suite. No protected surface, no schema change, no release cut; the
full pipeline (planning -> implementation -> validation -> review) applies.

## Summary
- CHANGE-0113 (altitude-prompt experiment) finished Phase 2 on 2026-08-05 with
  the pre-registered decision applied verbatim: **D1 pass** (V2 >= V0 on the
  paired sign test, 6-2-1, median Q 13 vs 11), **D3 pass** (noise median 5 <=
  V0+1), **D4 pass** (-32% prompt bytes, comparable run tokens), mechanism call
  **ALTITUDE, not compression** (V2 beat the equal-size compressed V1 6-2-1 on
  quality AND 7-0-2 on hallucinations; V1 alone made hallucinations *worse*).
  **D2 was UNMET BY CONSTRUCTION** — the five prose rules the rewrite deletes
  had no detector at all, so "compliance survives deletion" could not be
  evaluated and no adoption could be recorded regardless of D1.
- This ride does the two halves in order. PART 1 writes the five missing
  detectors (disposition rows R04/R05/R09/R21/R31 in
  docs/analysis/altitude-disposition-PLANNING.md), RED-first, changing no
  prompt. PART 2 replaces `.aai/PLANNING.prompt.md` with the V2 variant,
  reconciled against the pin map.
- The replay's own honest limits carry into scope: V2's worst task (T3, Q 9 vs
  V0's 12) produced well-formed ACs whose test commands did not run. R21 +
  R31 are exactly that gate — an AC no test claims now refuses the freeze. V2's
  other recorded regression, overreach (median 2 vs V0's 1), is NOT gated here
  and stays on the watchlist below.

## Acceptance Criteria
- AC-001: R21 — `spec-lint.mjs` reports `ac-without-test` for a Spec-AC no Test
  Plan row claims, on both the canonical gate table and the L0/L1 lean table,
  and the real corpus stays clean.
- AC-002: R31 — `spec-freeze.mjs` REFUSES (exit 3, named reason, nothing
  written) a freeze whose would-be-frozen document carries `ac-without-test` or
  `frozen-without-strategy`; `--dry-run` and `--json` refuse identically; an
  L0/L1 lean spec keeps its RFC-0009 strategy exemption.
- AC-003: R05 — `check-role-output.mjs` rejects a `role: Planning` block that
  records a validation verdict field, and still accepts `status: PASS` from
  Planning and the same verdict field from Validation.
- AC-004: R04 + R09 — `check-role-output.mjs --base-ref` rejects a Planning run
  whose diff (tracked AND untracked) leaves docs/specs/**, docs/ai/** and
  docs/INDEX.md; `--worktree-baseline` / `--worktree-guard` reject a worktree
  created during a Planning run. Both are Planning-scoped: an Implementation
  block passes the same flags with the same diff.
- AC-005: `.aai/PLANNING.prompt.md` is the V2 altitude text, every PLANNING pin
  suite is green with ZERO assertion edits, and the byte delta is ledger-
  reconciled (headroom inside [0, 2048]).

## The honest split (what these gates do NOT decide)
- **Measurability stays prompt judgment.** R31's disposition row lists three
  freeze preconditions: every AC measurable, every AC tested, strategy decided.
  Two are decidable by a parser and are now enforced. Measurability is not, and
  `spec-freeze.mjs` says so in its header and its `--help` rather than implying
  a complete gate. Principle 1 of the adopted prompt is where it lives.
- **A test row is not a running test.** `ac-without-test` proves a Test Plan row
  NAMES the AC. Whether its command runs is Validation's evidence, not a
  parser's. T3's failure mode is therefore narrowed, not eliminated.
- **R04/R09 ship as OPT-IN flags.** The orchestrator's merge-protocol step 1
  passes only `--file`; it holds neither a base ref nor a pre-dispatch
  `git worktree list` capture, and ORCHESTRATION.prompt.md sits at its hard
  40-line cap, so wiring them live would cost prompt bytes for a check the
  merge step cannot currently feed. The gates are real and proven by
  tests/skills/test-aai-planning-probes.sh (scripted fake-Planning runs that
  commit each violation on purpose); the wiring gap is stated in
  .aai/SUBAGENT_PROTOCOL.md.
- **`ac-without-test` is scoped to in-flight specs** (draft/proposed/accepted/
  implementing). Twelve `done` specs in this corpus have an untested AC; their
  suites have since been renamed or folded, so flagging them would produce
  noise, not action — and would break the real-corpus-clean pin that gives
  spec-lint its meaning.

## Pin reconciliation (why the shrink is 1299 B, not 3685 B)
V2's prose dropped the numbered step spine. Four suites pin `^11) Emit the
work-item brief` and `^12) Update docs/ai/STATE.yaml` (ceremony x2,
constitution, spec-lint), the constitution and ceremony suites bound their
assertions to the `10) ... 11)` slice, and the hygiene pack asserts the LINE
ORDER of `Set SPEC-FROZEN: true` < `docs/ai/briefs/` < `Update docs/ai/STATE.yaml
— PRIMARY PATH`. Rewriting six suites to chase a prose change would convert an
adoption into a pin migration and destroy the "nothing broke" oracle the whole
experiment rests on. Steps 10-12 therefore survive as V2's mechanical tail,
carrying those literals verbatim; everything above them is V2 text. The cost is
recorded in the ledger comment, not hidden: 11526 -> 10227 B.

## Verification
- `bash tests/skills/test-aai-spec-lint.sh` (TEST-001..005(actest) added, RED
  first: 3 of 5 arms failed before the rule).
- `bash tests/skills/test-aai-spec-tools.sh` (TEST-020..023(freeze) added, RED
  first: 3 of 4 arms failed before the preconditions).
- `bash tests/skills/test-aai-role-output.sh` (TEST-021/022 added, RED first).
- `bash tests/skills/test-aai-planning-probes.sh` (new suite, 6 probes, all 6
  RED before the flags existed).
- The full PLANNING pin set, green with zero assertion edits:
  ceremony-levels, close-work-item, constitution, delta-stage2, doctor,
  hygiene-pack (incl. test_093 registration + test_090 suite-map),
  implementation-mode, layer-profiles, prompt-diet, role-output, spec-tools,
  state, spec-lint, token-capture.
- `bash tests/skills/test-aai-prompt-diet.sh` — TEST-010 headroom 1150/2048,
  TEST-012 pin -9957 -> -11256.
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` — CLEAN.

## Constraints / Risks
- **Overreach is not gated.** The replay recorded V2 trading a little scope
  discipline for measurability (overreach median 2 vs V0's 1). R04's write-scope
  check catches only the crudest form (Planning writing code) and only when the
  flag is passed. Watch remediation rate over the next ~10 rides.
- **Fixture adjustments are the probes working.** Four lean/minimal fixtures
  (spec-lint x2, spec-tools x2, ceremony-levels x1) froze specs whose ACs had no
  tests or whose strategy was absent. Each gained the missing row rather than an
  exemption; a fixture that needed an exemption would have been evidence the
  rule was wrong.
- **spec-freeze now imports spec-lint.** One new intra-`.aai/scripts/` edge, no
  new dependency. It is deliberate: the freeze reads the lint's own rules
  against the transform's result, so the two engines cannot disagree about what
  a violation is.
- **The probes are Planning-scoped.** E-PLANNING-VERDICT and both write/worktree
  gates fire only for `role: Planning`. Other roles claiming a verdict they did
  not earn remain uncaught.

## Notes
- Sources: docs/analysis/altitude-disposition-PLANNING.md (the 44-row rule
  ledger and the pin map), docs/analysis/altitude-variants/V2-PLANNING.md (the
  adopted text), docs/analysis/altitude-replay.md (results and limits),
  docs/issues/CHANGE-0113-altitude-prompt-experiment.md (the pre-registration).
- Per CHANGE-0113's rollout order (CODE_REVIEW -> PLANNING -> SKILL_TDD ->
  IMPLEMENTATION -> VALIDATION), PLANNING is the pilot actually run; each later
  prompt would need its own disposition ledger and probe set before adoption.
