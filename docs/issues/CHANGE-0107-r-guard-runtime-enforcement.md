---
id: r-guard-runtime-enforcement
number: 107
type: change
status: done
user_visible: false
links:
  pr:
    - 210
  commits:
    - edf12f837f670b3aee13cd905256b87bba17a364
---

# Change — R-GUARD: runtime enforcement for the prose-pinned safety class

## Summary
- The factory's most consequential safety rules are prompt/markdown PROSE, pinned
  at best by grep tests. A grep proves an instruction EXISTS in a file, not that a
  run FOLLOWED it. This is the "R-GUARD class" — named as an accepted residual in
  `.aai/SUBAGENT_PROTOCOL.md:160` ("A runtime STATE-mutation guard is a
  recommended follow-up (residual risk R-GUARD), not yet built"), re-cited in
  `docs/specs/SPEC-0004-*.md:131,301`, `SPEC-0109-*.md:194-200`, `SPEC-0043-*.md:277`.
- Empirical proof that prose does not fire: CHANGE-0099
  (`docs/issues/CHANGE-0099-deterministic-friction-capture.md`) records the
  friction-capture PROSE hook writing ZERO observations across days of intense
  use ("recall-dependent and demonstrably never fires during real work"); the
  spool only filled once DETERMINISTIC capture points landed in scripts. The
  same "prompt prose does not fire, scripts always do" lesson applies to the
  higher-blast-radius rules in the R-GUARD class.
- This change proposes a MINIMAL, high-coverage, staged runtime guard focused on
  the single-writer rule (the highest-blast-radius prose rule) and the
  strategy-flip escalation SPEC-0109 RR-3 warned about — with explicit,
  non-over-claiming honesty about what each stage does and does not stop.
- Scope of THIS document is intake/analysis only (no implementation). It parks a
  designed, staged plan; Stage 1 requires an L3 escalation (touches
  `.aai/scripts/state.mjs`).

## Motivation / Business Value
- Blast radius, not aesthetics, drives this. A rogue subagent STATE write is no
  longer merely a lost update: since SPEC-0109 added the `untested` strategy lane,
  an out-of-contract `set-strategy` from a subagent can silently downgrade rigor
  (tdd -> untested escapes the RED proof) — SPEC-0109 RR-3 explicitly flags that
  it "RAISES THE PAYOFF of the pre-existing accepted residual R-GUARD ... If
  R-GUARD is ever built, strategy flips should be among its watched mutations."
- The factory already trusts deterministic guards where it counts (branch-guard,
  docs-lock, allocate-doc-number origin reservation). The single-writer rule —
  Constitution Article 6, the invariant the whole parallel-orchestration design
  rests on — is conspicuously the one core safety rule with NO runtime enforcement.
- Closing it with a narrow, additive, honestly-scoped guard removes the largest
  remaining gap between "the prompt says so" and "the machine ensures so."

## Scope
- In scope:
  - A staged runtime-enforcement design for the single-writer rule + strategy-flip
    watch (Stages 1-3 below).
  - The rule inventory that ranks the whole prose-pinned class by blast radius and
    issues a per-rule GUARD / KEEP-PROSE verdict (avoiding guard sprawl).
  - Deterministic acceptance criteria including negative controls (a simulated
    subagent STATE write is REFUSED/DETECTED) and false-positive controls
    (orchestrator writes still succeed).
- Out of scope:
  - Guarding rules whose blast radius is cost-only or whose enforcement is
    LLM-judgment-inherent (see "What NOT to guard").
  - Activating the inert `claude-hook-gate` overlay (a separate, already-designed
    lever — SPEC-0029); R-GUARD deliberately places its Stage-1 check INSIDE the
    CLI so it fires regardless of hook wiring.
  - Any behavior change when the guard marker is absent — the CLI must stay
    byte-for-byte identical to today for the orchestrator's own writes.

## Affected Area
- Stage 1 (L3): `.aai/scripts/state.mjs` (one additive guard clause in `main()`),
  plus orchestrator wiring in `.aai/ORCHESTRATION_PARALLEL.prompt.md` /
  `.aai/SUBAGENT_PROTOCOL.md` to set/unset the marker on dispatch.
- Stage 2 (not L3): `.aai/scripts/metrics-flush.mjs` (or a new
  `.aai/scripts/state-forensics.mjs`) — a validation/flush-time forensic check.
- Stage 3 (not L3 for EVENTS; strategy-flip watch rides Stage 2): a cheap
  append-only predicate for `docs/ai/EVENTS.jsonl`.
- New test suite `tests/skills/test-aai-r-guard.sh` (+ `suite-map.yaml` row).

## Rule inventory — blast-radius ranking and verdict

Detection legend: "grep-pin" = a test asserts the instruction text exists;
"runtime" = a deterministic exit-code guard fires during the operation;
"post-hoc" = only an audit/WARN after the fact; "never" = nothing detects it.

| Rule (source) | Current detection | Blast radius if violated | Verdict |
|---|---|---|---|
| Single-writer — subagent MUST NOT write STATE.yaml (SUBAGENT_CONTRACT.md; Constitution Art. 6) | grep-pin TEST-010 + docs-lock serialization; NO runtime guard on the write itself (this IS R-GUARD) | HIGH — lost update at K>=2; corrupt/duplicate-key STATE; a phantom validation/code-review verdict written under a subagent that the orchestrator never merged; feeds every downstream gate | GUARD (Stage 1) |
| Strategy flip — `set-strategy untested` mid-ride (SPEC-0109 RR-3; state.mjs cmdSetStrategy) | CLI requires a non-empty `--rationale` for `untested`; VALIDATION keys off the RECORDED strategy; NO guard on WHO wrote it | HIGH — rigor downgrade: tdd -> untested escapes the RED proof; SPEC-0109 RR-3 names this the payoff-raiser for R-GUARD | GUARD (Stage 1 refusal + Stage 2/3 watch) |
| EVENTS append-only (RFC-0001:94,136) | none runtime; `append-event.mjs` uses appendFileSync for its OWN writes only; docs-audit catches only MISSING close telemetry post-hoc | MEDIUM — a truncation/rewrite drops audit trail + close telemetry (observed failure mode: EVENTS restore wipes close events -> false-done) | GUARD (Stage 3, cheap: line-count-non-decreasing pre-commit predicate) |
| Merge-boundary — never merge, operator-only (SKILL_PR.prompt.md:5-6,266-284; Constitution Art. 7) | runtime deny keyed on `AAI_OPERATOR_MERGE=1` via claude-hook-gate — but that overlay is INERT in this repo (opt-in only) | HIGH — an agent-driven merge bypasses the operator | KEEP-PROSE here (already-designed lever; activate the overlay, not R-GUARD's job — but its env-marker pattern is the template Stage 1 mirrors) |
| HITL fail-close — proceed past a required human decision (ORCHESTRATION_HITL.prompt.md; SKILL_HITL.prompt.md) | grep-pin (TEST-001/002 existence) + check-state WARN post-hoc | MEDIUM-HIGH — loop continues past a decision that required a human | KEEP-PROSE — WHICH decisions require a human is LLM-judgment-inherent; not deterministically guardable without false-blocking |
| Worktree gate — isolation/decision before implementation (SKILL_WORKTREE.prompt.md:119-124; IMPLEMENTATION.prompt.md:22-23) | none for the gate itself; branch-guard.mjs (runtime, fail-closed) covers wrong-branch at PR time only | MEDIUM — implementation on a shared/stale line; largely backstopped by branch-guard + the L3 REQUIRED user_decision | KEEP-PROSE — adjacent runtime guard already exists at the point that matters (PR) |
| Close-before-CI ordering — 5c before 5d (SKILL_PR.prompt.md:196-264) | close-work-item.mjs self-verifies + byte-rolls-back on drift (runtime); the ORDERING itself is prose (grep TEST-009) | LOW-MEDIUM — the close mechanism is already runtime-safe; only the sweep ordering is prose | KEEP-PROSE — the consequential part is already deterministic |
| No mid-session model/effort flip (MODEL_ROUTING.yaml header) | none (TEST-019 pins the binding, NOT the no-flip rule) | LOW — cost/cache-efficiency only; no correctness or safety impact | KEEP-PROSE — cost, not safety; guarding it would be sprawl |

Top-of-list rationale: single-writer and strategy-flip are the only two prose
rules that are BOTH high-blast-radius AND have no runtime detector today AND are
deterministically guardable (they flow through one CLI, `state.mjs`). That
intersection is exactly where a guard earns its keep.

## Incidents found (evidence search)
- No logged incident of a rogue subagent STATE write: `docs/ai/EVENTS.jsonl`
  (1426 lines) has 0 hits for lost-update/single-writer/rogue; `git log --all`
  has none; `docs/knowledge/LEARNED.md` has none. The single-writer rule has
  held so far under human-supervised runs — but its enforcement is discipline,
  and blast radius (not observed frequency) is the case for the guard, matching
  the CHANGE-0099 precedent (the friction hook also "never fired" — absence of
  logged violations is consistent with a detector that cannot see them).
- The adjacent, DOCUMENTED failure that the append-only gap enables: the operator
  memory note "EVENTS restore wipes close telemetry" — a `git restore
  docs/ai/EVENTS.jsonl` drops close events -> false-done -> doc-numbering test
  fails. That is an EVENTS-append-only violation with real observed cost, and it
  is caught only post-hoc by docs-audit, motivating the Stage-3 predicate.

## Design options (coverage / evadability / false-positive / cost)

### (a) git-diff post-subagent check (orchestrator runs after each subagent)
- Mechanism: after a subagent returns and before/at merge, the orchestrator runs
  `git status`/`git diff` and refuses to merge if the subagent's changes touched
  `docs/ai/STATE.yaml` (or EVENTS beyond an append). Template: branch-guard's
  read-only, fail-closed, closed-exit-code shape.
- Coverage: catches the write regardless of HOW it was made (bypasses the CLI
  entirely — a hand-edit or a `yaml.dump`).
- Evadability: HIGH via the R-WIRE class — it depends on a live LLM orchestrator
  actually running the check (same weakness SPEC-0004 records as R-WIRE for
  docs-lock). A subagent in a SHARED worktree that also `git add`s/stages could
  further muddy the diff.
- False-positive risk: LOW (the allowed-write set is precise).
- Cost: LOW (new standalone script, NOT L3).
- Verdict: useful complement, but as a standalone it inherits R-WIRE — good as a
  defense-in-depth add, not the load-bearing stage.

### (b) state.mjs env-marker refusal (Stage 1, load-bearing)
- Mechanism: a subagent context is marked by an env var (`AAI_ROLE=subagent`,
  mirroring the EXISTING `AAI_OPERATOR_MERGE=1` marker the merge gate already
  uses). In `state.mjs main()`, before dispatching a STATE-mutating subcommand,
  if the marker says subagent -> refuse with a new closed exit code, writing
  NOTHING. `append-event.mjs` (a SEPARATE script) stays allowed — it is the
  subagent's sanctioned append path per SUBAGENT_CONTRACT.md; `log-tick` (writes
  LOOP_TICKS, not STATE) stays allowed.
- Coverage: HIGH for the honest/accidental path — the overwhelmingly common
  failure is a well-intentioned subagent rationalizing "my update is tiny"
  (exactly the rationalization row in SUBAGENT_CONTRACT.md). Fires no matter how
  `state.mjs` is invoked (unlike a hook, which is inert unless the overlay is
  installed) — this is the key reason to place it IN the CLI, not in a hook.
- Evadability: an agent that UNSETS or never inherits the marker defeats it.
  BE HONEST: this is a guardrail against habit and accident and the honest-agent
  path, NOT a security boundary — verbatim the posture SKILL_PR.prompt.md:277-280
  already takes for the merge marker ("a guardrail against habit, not a security
  boundary"). Layer (d) is the after-the-fact backstop for the unset-marker case.
- False-positive risk: the marker MUST be absent in orchestrator context, or the
  orchestrator's own (legitimate, sole-writer) mutations would be blocked. Marker
  leakage (exported and not unset before an orchestrator write) is the one
  false-positive path — mitigated by explicit unset in the orchestrator prompt +
  the marker being opt-in-present rather than opt-out.
- Cost: LOW, but L3 — `state.mjs` is a protected surface (docs-audit.yaml:39).
  The change is one additive guard clause; state-engine.mjs/state-core.mjs (also
  L3) are UNTOUCHED.

### (c) pre-commit-checks.sh STATE-mutation predicate
- Mechanism: add a check that a commit's STATE.yaml diff is consistent with an
  orchestrator write.
- Coverage: LOW today. Critical nuance found in survey: the installed
  `.git/hooks/pre-commit` (from install-pre-commit-hook.sh) does INDEX autogen +
  close-gate + body-lint; it does NOT invoke `pre-commit-checks.sh`.
  `pre-commit-checks.sh` is invoked by the (inert) claude-hook-gate `commit`
  gate and directly by skills — so it is not reliably on the git commit path here.
- Evadability: HIGH (`git commit --no-verify`; and it is off the default path).
- False-positive risk: MEDIUM (commit-time cannot see WHO made the edit).
- Cost: L3 (pre-commit-checks.sh is protected) for low marginal coverage.
- Verdict: REJECT for now — pays the L3 cost without the coverage.

### (d) forensic timeline check at flush/validation (Stage 2, anti-evasion backstop)
- Mechanism: at flush/validation time, cross the STATE-mutation timeline (git log
  --follow on `docs/ai/STATE.yaml`, author/commit timestamps) against the
  recorded `metrics.work_items[<ref>].agent_runs` windows
  (`started_utc`/`ended_utc`, already captured per run). A STATE mutation whose
  timestamp falls INSIDE a subagent's [started,ended] window — when the
  orchestrator's legitimate merge writes occur only AFTER a subagent ends — is
  flagged. Strategy-flip watch (Stage 3) is this same check narrowed to
  `set-strategy`/`implementation_strategy` mutations.
- Coverage: DETECTION (not prevention) — but it catches the (b)-evasion case (an
  agent that unset the marker still leaves durable git history).
- Evadability: LOW for the history itself (durable), though an agent that also
  rewrites history or never commits the illicit write within a window escapes;
  hence it is a backstop, not a sole control.
- False-positive risk: MEDIUM — clock skew and the spawn/merge boundary need a
  tolerance; emit WARNING, never block (mirrors metrics-flush's existing
  warn-don't-block posture for token-capture anomalies).
- Cost: MEDIUM (new forensic logic in metrics-flush.mjs — NOT L3 — or a small
  standalone script).

## Recommended staged plan

Staged so the single L3 touch is one narrow additive refusal, and each later
stage adds coverage without touching a protected surface.

- Stage 1 (L3) — (b) env-marker refusal in `state.mjs` + orchestrator wiring.
  The load-bearing, high-coverage-for-the-honest-path guard. One additive clause
  in `main()`; orchestrator sets `AAI_ROLE=subagent` on dispatch and guarantees
  it is unset for its own writes. Prevention at the exact chokepoint, fires
  regardless of hook wiring.
- Stage 2 (not L3) — (d) forensic timeline check in `metrics-flush.mjs`
  (validation/flush time). The honest anti-evasion backstop: detects a STATE
  mutation inside a subagent window even when the marker was unset. WARN, not
  block.
- Stage 3 (not L3) — strategy-flip watch (Stage-2 check narrowed to
  `set-strategy` mutations, per SPEC-0109 RR-3) + a cheap EVENTS append-only
  predicate (line-count-non-decreasing) added to a guard that IS on a real path.
- Optional defense-in-depth — (a) git-diff post-subagent check, wired into the
  parallel merge protocol, if/when the orchestrator is willing to own the R-WIRE
  responsibility. Not required for Stages 1-3.

Anti-evasion honesty (MUST ride the spec verbatim, never softened): Stage 1 (b)
is defeated by an agent that unsets or never sets the marker; Stage 2 (d) catches
that case AFTER the fact via durable git history; NEITHER is a sandbox. R-GUARD
raises the floor from "prose only" to "prose + a guardrail that stops the honest
mistake + a forensic detector for the dishonest one." It does NOT claim to make a
rogue subagent STATE write impossible. Any AC, comment, or changelog line that
implies otherwise is a defect.

## Acceptance Criteria
- AC-001 (negative control, Stage 1): with `AAI_ROLE=subagent` set, every
  STATE-mutating `state.mjs` subcommand (`set-focus`, `set-phase`,
  `set-validation`, `set-code-review`, `set-strategy`, `set-worktree`,
  `set-tdd-cycle`, `set-human-input`, `append-run`, `reset-block`) exits with the
  new refusal code and leaves `STATE.yaml` byte-for-byte identical (write count 0).
- AC-002 (false-positive control, Stage 1): with `AAI_ROLE` unset (or any value
  != `subagent`), those same subcommands succeed and write exactly as today —
  output byte-identical to a pre-change baseline (orchestrator writes still work).
- AC-003 (allowed subagent paths, Stage 1): under `AAI_ROLE=subagent`,
  `state.mjs log-tick` (LOOP_TICKS, not STATE) still succeeds, and
  `append-event.mjs` (the sanctioned subagent append path) is unaffected.
- AC-004 (closed contract, Stage 1): the refusal exits with a documented code in
  `state.mjs`'s closed exit-code contract and prints a message naming the
  single-writer rule + `.aai/SUBAGENT_CONTRACT.md`; an unknown-flag/typo still
  fails LOUD before the marker check (ordering preserved).
- AC-005 (forensic detection, Stage 2): given a STATE mutation whose git
  timestamp falls inside a recorded `agent_runs` [started_utc, ended_utc] window,
  flush/validation emits exactly one WARNING naming the ref + run; given all
  mutations outside every subagent window, the check is silent (no false WARN).
- AC-006 (strategy-flip watch, Stage 3): a `set-strategy` mutation attributable
  to a subagent window is flagged specifically as a rigor-downgrade risk (SPEC-0109
  RR-3); a legitimate orchestrator `set-strategy` is not.
- AC-007 (EVENTS append-only, Stage 3): a commit/diff that reduces
  `docs/ai/EVENTS.jsonl` line count is flagged by the predicate on its real
  invocation path; an append-only change passes.
- AC-008 (no-marker no-op, Stage 1): the full existing `test-aai-state.sh` suite
  passes unchanged with no marker in the environment (proves additive-only).

## Verification
- New suite `tests/skills/test-aai-r-guard.sh` implementing AC-001..AC-004 and
  AC-008 (Stage 1), AC-005 (Stage 2), AC-006/AC-007 (Stage 3), following the
  `test-aai-state.sh` fixture conventions (temp STATE, `ck` check-state assertions,
  byte-identity assertions). Add its `tests/skills/suite-map.yaml` row.
- Baseline byte-identity: capture `state.mjs` output on a fixture with no marker
  before and after the change; assert identical (AC-002/AC-008).
- Run the whole skills suite via `.aai/scripts/aai-run-tests.sh`.
- `node .aai/scripts/docs-audit.mjs --no-event` stays CLEAN (verified clean at
  intake time).

## Constraints / Risks
- L3 ESCALATION REQUIRED (Stage 1). `.aai/scripts/state.mjs` is a protected
  surface (`docs/ai/docs-audit.yaml:39`; `.aai/workflow/WORKFLOW.md` L3 table), so
  the implementing spec MUST declare `ceremony_level: 3` — full SPEC, full
  independent validation, MANDATORY code review on the most capable tier, and an
  operator checkpoint before merge. Exact one-function change: in `state.mjs`
  `main()`, AFTER `rejectUnknownFlags(cmd, flags)` and BEFORE resolving/dispatching
  the `MUTATORS` map, add a single guard — if `cmd` is a STATE mutator and
  `process.env.AAI_ROLE === 'subagent'`, call `fail(<message>, <new-code>)`.
  Add the new code to the closed exit-code contract comment (lines ~62-68).
  `writeState`/`loadState` in `lib/state-engine.mjs` and `lib/state-core.mjs`
  (also L3) are NOT touched — this keeps the L3 blast to one file, one branch.
- R-EVADE: the marker is defeatable (unset/never-set). Documented as accepted;
  Stage 2 is the backstop. Never claim more than delivered (see anti-evasion
  honesty above).
- R-WIRE: Stage 1 protection only exists when the orchestrator SETS the marker on
  dispatch; forgetting it fails OPEN (today's behavior). Fail-open is deliberate —
  the alternative (default-assume-subagent) would block the orchestrator's own
  legitimate writes.
- R-FALSEPOS: marker leakage into orchestrator context would block legitimate
  writes; mitigated by explicit unset + opt-in-present semantics + Stage 2 being
  WARN-only.
- Prior-art anchors to mirror: branch-guard.mjs (fail-closed, read-only,
  closed-exit-code precondition), docs-lock.mjs (atomic, fail-closed-on-ambiguity),
  claude-hook-gate.sh `merge`/`state-dump` gates (the EXISTING but inert env-marker
  deny pattern Stage 1 generalizes), learned-append.mjs (structural append-only
  gate — Stage 3 template), the enforce/report-only dial via
  `docs/ai/docs-audit.yaml` + `lib/guard-config.mjs` (graduated rollout).

## Delivery / reconcile (SPEC-0113)

The staged plan is implemented under the frozen L3 spec
`docs/specs/SPEC-0113-spec-r-guard-runtime-enforcement.md` (ceremony_level: 3).
Reconciled against this intake:

- Stage 1 (L3): the one additive env-marker refusal clause landed in
  `.aai/scripts/state.mjs` `main()` (exit code 3 added to the closed contract);
  `lib/state-engine.mjs` / `lib/state-core.mjs` untouched. Orchestrator wiring in
  `.aai/SUBAGENT_PROTOCOL.md` + `.aai/ORCHESTRATION_PARALLEL.prompt.md`.
- Stage 2/3 (not L3): implemented in `.aai/scripts/metrics-flush.mjs` as WARN-only
  forensic checks. HONEST-SCOPE CORRECTION to this intake's design-option (d):
  `docs/ai/STATE.yaml` is GITIGNORED, so the "git log --follow on STATE crossing
  agent_runs windows" timeline check is NOT honestly implementable (a STATE write
  leaves no durable, independent timestamp). Stage 2 was therefore scoped to the
  detectable subset — strategy PROVENANCE (source not intake/spec-path) — plus the
  Stage-3 rigor-downgrade narrowing (SPEC-0109 RR-3) and the EVENTS.jsonl
  append-only predicate (EVENTS *is* committed). This gap is documented in
  SPEC-0113 RR-2; the intake's higher-ambition timeline sketch is deferred as not
  honestly buildable while STATE stays gitignored.
- AC coverage: intake AC-001..004 -> Spec-AC-01..04 (test-aai-state.sh);
  AC-005/006/007 -> Spec-AC-05/06/07 (test-aai-metrics.sh); orchestrator wiring +
  L3 governance -> Spec-AC-08 (test-aai-r-guard.sh + TEST-014 + prompt-diet).
- Anti-evasion honesty rode the code, the spec, and the CHANGELOG verbatim-style
  (RR-1): Stage 1 is a guardrail, not a security boundary; Stage 2 is a forensic
  detector, not proof.

## Notes
- Guard-sprawl discipline: this design deliberately guards only 2 of 8 inventoried
  rules at Stage 1-2 (single-writer + strategy-flip), adds 1 cheap Stage-3
  predicate (EVENTS), and explicitly declines the other five — the factory's
  lesson is deterministic WHERE IT COUNTS, not everywhere.
- Relationship to claude-hook-gate (SPEC-0029): a live PreToolUse hook denying
  `state.mjs set-*` under a subagent marker would be a valid Stage-0, but that
  overlay is INERT in this repo (only `hooks/hooks.json` SessionStart is wired).
  Placing the check inside the CLI is strictly stronger: it cannot be un-wired.
