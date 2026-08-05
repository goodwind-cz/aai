---
id: altitude-replay
type: research
number: null
status: draft
links:
  pr: []
  commits: []
---

# Altitude experiment — replay results (CHANGE-0113 Phase 2, executed 2026-08-05)

27 replay runs (9 real closed rides x V0/V1/V2 of PLANNING) + 9 blind judges,
per the pre-registered protocol. Blinding unsealed only after all scores were
recorded (sealed key sha256 3196b523...). Raw per-task scores:
`altitude-aggregate.json`; judge artifacts: `altitude-judge-out/`.

## Aggregate (n = 9 tasks; Q = M1+M2+M3, 0-15)

| variant | median Q | mean Q | median halluc | mean halluc | median overreach |
|---|---|---|---|---|---|
| V0 (shipped, 11,526 B) | 11 | 11.22 | 3 | 3.89 | 1 |
| V1 (compressed, 8,109 B) | 12 | 12.00 | 4 | 4.11 | 3 |
| V2 (altitude, 7,841 B) | **13** | **12.22** | **3** | **2.67** | 2 |

Pairwise (win/loss/tie across 9 paired tasks):
- Q: V2>V0 **6-2-1** (median paired diff +2); V2>V1 **6-2-1**; V1>V0 5-2-2
- Hallucinated (lower wins): V2 vs V0 6-2-1; **V2 vs V1 7-0-2**; V1 vs V0 3-3-3
- Overreach (lower wins): V0 beats V2 7-1-1; V2 beats V1 5-3-1

## Pre-registered decision (verbatim application)

- **D1 (no quality regression): PASS** — V2>=V0 paired (6-2-1, median diff +2,
  not significantly worse); underreach medians equal (1 vs 1); M2 medians
  equal (3 vs 3).
- **D2 (compliance survives deletion): UNMET BY CONSTRUCTION** — the five
  behavioral probes (disposition rows R04, R05, R09, R21, R31) are not yet
  written; per the pre-registration, "no adoption may be recorded regardless
  of D1" until they exist and are green.
- **D3 (no extra noise): PASS** — (M4+M6) median V2 = 5 <= V0 + 1 = 6.
- **D4 (no cost regression): PASS** — V2 prompt is -32% bytes; replay run
  tokens comparable (33-42K per run across all variants).
- **Mechanism call (V2 vs V1): ALTITUDE, not compression** — V2 beats V1 on
  Q 6-2-1 AND on hallucinations 7-0-2. Compression alone (V1) raised
  hallucinations (mean 4.11 vs V0's 3.89); altitude cut them (2.67).

**Recorded outcome: D1 ∧ D3 ∧ D4 pass; D2 gate open → adoption NOT recorded.
Next deterministic step: write probes R04/R05/R09/R21/R31, green them, then
adopt V2 via a normal ride.**

## Honest limits

- Variant delivered as attachment, not system prompt (identical treatment; the
  residual bias runs AGAINST V2 per the protocol note — a V2 win is
  conservative).
- One judge per task; n=9; sign tests are directional evidence, not
  significance claims.
- Judges self-located the ground-truth REFERENCE from the repo (the harness
  did not ship it in judge-in/) — all nine did so and recorded provenance;
  treatment was uniform but this is a protocol deviation to fix in any rerun.
- Replay artifacts: today's prompt corpus names tools (spec-freeze.mjs,
  Evidence-by-strategy) that postdate the July base_refs; judges recorded
  these as shared/prompt-induced and several excluded them uniformly —
  imperfectly consistent across judges (T5/T7 excluded, T6 counted then
  flagged). Direction of any residual error is uniform across variants.
- Overreach regression of V2 vs V0 (median 2 vs 1) is real and carries into
  the adoption ride's watchlist: the altitude prompt trades a little scope
  discipline for measurability and truthfulness.
- T3 is V2's worst task (Q 9 vs V0's 12): the altitude candidate had
  well-formed ACs but three non-functional grep commands — probe R21-class
  enforcement (AC->TEST checkable commands) is exactly the missing gate.
