---
id: altitude-prompt-experiment
number: 113
type: change
status: done
user_visible: true
ceremony_level: 2
links:
  pr:
    - 232
  commits:
    - 4fcda307d2f7f920d61aa5db09dcd060868d6927
---

# Change — altitude-prompt experiment: rules-as-prose vs canonical examples, decided by paired measurement

## Context (source + why now)
PRIMARY SOURCE (corrected 2026-08-02 after tracing the viral rehash): the
July 2026 Anthropic post (Thariq Shihipar) — 80% of Claude Code's system
prompt DELETED for the Claude 5 generation with no eval loss. Core thesis is
"UNHOBBLING": most prompt bulk is not knowledge but guardrails written
against failure modes of OLDER models; the new generation does not produce
those failures, so the guardrails now conflict, mis-fire on edge cases, and
crowd out model judgment. Four deletion classes (verification instructions,
review severity filters, subagent rules, derivable-content bloat) + six
shifts (rules->judgment, in-prompt examples->better TOOL design,
upfront->progressive disclosure, repeated rules->tool descriptions, manual
memory->auto-memory, prose specs->code/test references) + the /doctor
automation precedent. AAI already implements 6 of its 8 recommendations with
DETERMINISTIC enforcement (diet budget, JIT skill loading, ledger memory,
condensed subagent results, cache-aware dispatch, minimal-start economics).
The one genuinely open idea is the STYLE of the role prompts themselves:
ours are rule lists; the guidance says examples generalize better and burn
less attention. That claim is plausible, uncertain, and — uniquely in this
repo — CHEAPLY TESTABLE, because we own a deterministic "nothing broke"
oracle (pin suites + CI + replayable rides + usage telemetry).

## Measured baseline (2026-08-02, this repo's ledgers)

Corpus & coupling (size = bytes; pins = test FILES grepping the prompt):

| prompt | bytes | pin-files | dispatches (all history) | median tokens/run (n) |
|---|---|---|---|---|
| SKILL_LOOP | 24833 | 6 | (loop meta) | — |
| SKILL_PR | 21333 | 12 | (ceremony meta) | — |
| VALIDATION | 19220 | **16** | 93 | 95K (48) |
| SKILL_TDD | 17870 | 12 | 61 | 213K (41) |
| PLANNING | 12772 | 12 | 84 | 115K (37) |
| SKILL_CODE_REVIEW | 10605 | **2** | **98** | 76K (54) |
| IMPLEMENTATION | 9748 | 9 | 42 | 202K (5) |

Quality baseline: first-pass clean 88% (69/78-flagged of 147); remediation
0.30 runs/ride (31/104); external-bot dependency: 74% of sidecar-family
defects bot-found; run-token variance is HIGH (CV 21-31%) — any unpaired
A/B is underpowered at realistic N. Prompt read is 3-9% of a run's tokens,
so the DIRECT token saving is modest; the real wager is quality/attention:
one avoided remediation run saves ~124K median tokens, one avoided bot
round saves a full CI cycle (~18 min + re-review).

## Hypotheses (pre-registered, falsifiable)
- H1 (attention): canonical-example prompts reduce remediation rounds and
  blind-judged defects vs rule-list prompts of EQUAL byte size.
- H2 (compression alone is not the mechanism): V1 (dedup-compressed rules)
  underperforms V2 (altitude) at equal size — else the win is just "shorter",
  and diet rides already capture it.
- H3 (compliance survives deletion): every prose rule removed in V2 and
  replaced by a script gate or behavioral probe shows ZERO compliance
  regressions on the probe suite.

## Phase 0 — doctor-style unhobbling audit (run FIRST, cheap, standalone value)
One read-only pass over the 10 largest .aai role prompts against the
six-shift rubric, emitting docs/analysis/unhobbling-audit.md: per prompt, a
table of deletion candidates classed as {obsolete-guardrail (older-model
failure mode), derivable-from-code, repeated-rule (belongs in tool/script
description), verification-instruction, severity-filter, keep (principle |
gotcha | governance-pin)} with the pin-test coupling noted per row. This is
the /doctor idea applied to the role-prompt corpus. Output feeds BOTH the
experiment (sharper V2) and ordinary diet rides (immediate targets).
Costs one agent run; changes NOTHING.

## Design — three variants, paired replay, blind judging

Variants of ONE pilot prompt:
- V0 = status quo (rule list, current bytes)
- V1 = compression control (same rule style, deduped, target -40% bytes)
- V2 = altitude/unhobbled (3-5 principles + enforcement moved to gates/
  probes + procedure detail moved into SCRIPT INTERFACES per the
  examples->better-tools shift: clearer --help, self-explanatory errors,
  one-line tool descriptions instead of repeated prompt rules; at most ONE
  compact worked example; target -40% bytes, SAME budget as V1)

PILOT PROMPT = SKILL_CODE_REVIEW. Selection is data-driven, not taste:
highest dispatch frequency (98 runs — largest sample accrues fastest),
LOWEST pin coupling (2 test files — cheapest migration), moderate size,
and — decisively — it is the only role with an INDEPENDENT PRODUCTION
ORACLE we already collect passively: the 5d bot sweep. Every PR records
what external reviewers caught that internal review missed (this week's
live example: the phantom getpgrp API). Review-miss rate per PR is a
direct, zero-instrumentation quality metric for exactly this role.

Paired replay benchmark (primary evidence):
1. TASK SET: 8-10 real CLOSED rides (small/medium, merged this month, e.g.
   CHANGE-0104/0108/0109/0111 class) — each has an intake, a known merged
   diff, and green suites as the reference outcome.
2. For each task x each variant: one review-role run in an isolated
   worktree pinned to the task's pre-review commit, same model + effort;
   the ONLY difference is the prompt variant. Record: findings list,
   tokens (usage marker), wall-clock.
3. SCORING, blind: a judge agent receives (task diff + findings list) with
   the variant label stripped, and scores against the KNOWN ground truth =
   the union of defects actually found later (bot sweep findings + CI
   failures + post-merge fixes). Metrics per pair: recall of real defects,
   false-finding count, tokens.
4. STATS: per-task paired deltas only (kills the CV 21-31% noise); sign
   test at n>=8 pairs; publish raw table (honest nulls; no cherry-picks).

Probe suite (H3 guard, built BEFORE any rewrite):
- RULE DISPOSITION LEDGER: every prose rule in the pilot prompt gets a row:
  keep-as-principle | move-to-script-gate | move-to-behavioral-probe |
  delete (+rationale). Mirrors the diet-ledger discipline; the reviewer
  audits the table, not vibes. The 2 existing pin greps migrate to probes.
- Behavioral probe = fixture scenario where violating the rule is the
  tempting shortcut; asserts on ARTIFACTS (evidence files, verdict shape,
  exit codes), not prose. Probes run in CI like any suite.

Production confirmation (secondary, after replay picks a winner):
- Ship the winning variant; compare bot-catch-per-PR and remediation/ride
  over the next 10 rides vs the 10 before (already-collected data, no new
  instrumentation). This catches what replay cannot (novel task mix).

## Pre-registered decision rule (no post-hoc rationalization)
Adopt V2 for the pilot prompt iff ALL hold, judged on the paired table:
- D1 recall of ground-truth defects: V2 >= V0 (no regression) on the
  paired sign test;
- D2 probe suite 100% green (zero compliance regressions);
- D3 false findings: V2 <= V0 + 1 median;
- D4 tokens/run: V2 <= V0.
V2 vs V1 decides the MECHANISM: if V1 ~= V2, record "compression suffices —
altitude unproven here" and fold the learning into ordinary diet rides.
If V2 wins, roll out per-prompt in order (dispatch-freq x bytes / pin-count):
CODE_REVIEW -> PLANNING -> SKILL_TDD -> IMPLEMENTATION -> VALIDATION last
(16 pin files = costliest migration), each behind its own probe ledger.

## Cost estimate (honest)
Replay: 3 variants x 9 tasks x ~80K median = ~2.2M tokens + judge runs
(~0.3M) — roughly one heavy ride-day. Harness: probe suite + replay driver
(~1 day). NOT free; the wager is that ONE avoided remediation round per
~10 rides repays the token cost, and the attention-quality claim gets a
real answer instead of a vibe.

## Acceptance Criteria
- AC-001: rule-disposition ledger for SKILL_CODE_REVIEW complete (every
  rule dispositioned; 2 pins migrated to probes) BEFORE any rewrite lands.
- AC-002: replay harness runs 3x9 paired matrix, emits the raw results
  table as a committed artifact (docs/analysis/altitude-replay.md).
- AC-003: blind judge never sees variant labels (harness-enforced).
- AC-004: decision recorded against the PRE-REGISTERED rule D1-D4 verbatim,
  including a negative/null outcome (that is a valid, publishable result).
- AC-005: pin suites + full CI green throughout; V0 remains the shipped
  prompt until the decision lands.

## Constraints / Risks
- Ceremony L2 (touches a role prompt + adds suites; no protected surface).
- Ground truth is imperfect (defects nobody ever found stay invisible) —
  mitigated by using UNION of bot+CI+post-merge evidence, and by D-rules
  demanding non-regression rather than absolute truth.
- Judge-agent bias: single blind judge; mitigate with 2 judges + tie-break.
- Replay fidelity: historical rides ran on evolving main; worktrees pin the
  exact pre-review commit, and paired design cancels shared drift.
- Timing: run AFTER telemetry-gate data matures (~08-10) so tokens/run is
  reliable; headroom (1530 B) comfortably absorbs probe-doc pointers.

## Notes
- Parked intake (analysis branch, no PR). Related: CHANGE-0110 diet (V1 is
  exactly a diet artifact — reuse its method), CHANGE-0109 phantom pin
  (bot-catch as review-miss oracle), SPEC-0112 (measure-then-decide
  precedent).
