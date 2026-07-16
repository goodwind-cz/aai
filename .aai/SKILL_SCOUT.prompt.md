# Scout Skill - Pre-Implementation Readiness Score (Advisory)

ADVISORY ONLY — this skill never blocks, gates, or dispatches anything;
skipping or overriding it is always a valid outcome.

## Goal
Before implementation starts, measure how ready this agent actually is to
build the scoped work item — and say so in one honest number. A low score is
not a stop sign; it is a shopping list of the evidence to gather first.

Source: RES-0001 P3 recommendation 15 — pro-workflow scout readiness score.

## When
Optionally, after Planning freezes a spec and before Implementation/TDD
begins. Input: the frozen spec (or brief) for the current focus in
docs/ai/STATE.yaml. Read docs/TECHNOLOGY.md and the spec before scoring.

## Scoring — five dimensions, 0–20 each, sum 0–100
Score each dimension against its anchor. Cite the evidence (file paths,
spec sections) that justifies every score — an uncited 20 is a guessed 20.

| Dimension | 20 means | 0 means |
|---|---|---|
| Scope clarity | Every AC is measurable; in/out-of-scope lines are explicit | I could not restate the deliverable in one sentence |
| Pattern familiarity | The repo already contains an exemplar I have read for each artifact class | No comparable prior art found in this codebase |
| Dependency awareness | Every consumed script/prompt/schema is located and its contract read | Unknown what this change calls or what calls it |
| Edge cases | Failure/empty/concurrent paths are enumerated in the spec or by me | Only the happy path is understood |
| Test strategy | I know each test's file, shape, and how to see it RED first | No idea how this will be proven |

## Verdict
- Score ≥ 70 → `GO (advisory)` — readiness is adequate; proceed.
- Score < 70 → `HOLD (advisory)` — name the weakest dimensions and the
  concrete evidence-gathering step that would raise each (a file to read,
  an exemplar to find, a question for /aai-interrogate).
The verdict binds nothing: orchestration, gates, and the operator dispatch
exactly as they would have without it. A HOLD followed by proceeding anyway
is a legitimate, recordable choice.

## Output format
```
SCOUT advisory-readiness — <REF-ID>
  Scope clarity:        NN/20  <one-line evidence>
  Pattern familiarity:  NN/20  <one-line evidence>
  Dependency awareness: NN/20  <one-line evidence>
  Edge cases:           NN/20  <one-line evidence>
  Test strategy:        NN/20  <one-line evidence>
  TOTAL: NN/100 → GO|HOLD (advisory, threshold 70)
  If HOLD: next evidence steps, weakest dimension first.
```
No score is persisted; the report lives in the session (paste into the
work-item brief's notes if the operator wants it kept).

## Rules
- Score from evidence read THIS session; do not inherit scores across scopes.
- Never edit files, STATE, or the spec; this skill only reads and reports.
- Never present the verdict as a gate result — always suffix `(advisory)`.
- Cross-links: readiness gaps about unresolved decisions belong to
  `.aai/SKILL_INTERROGATE.prompt.md`; completion claims stay owned by
  `.aai/SKILL_VERIFY.prompt.md`.
