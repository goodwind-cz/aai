# Interrogate Skill - Plan Decision-Walk with Ledger (Advisory)

ADVISORY ONLY — this skill never blocks, gates, or dispatches anything;
skipping or overriding it is always a valid outcome.

## Goal
Surface the decisions hiding inside a plan or spec BEFORE they surface as
rework — one at a time, each pre-answered, each recorded. The output is a
decision ledger, not a longer spec.

Source: RES-0001 P3 recommendation 15 — pro-workflow plan-interrogate /
decision-ledger pattern.

## When
Optionally, at spec-freeze time (during or right after Planning) or whenever
a plan feels underdetermined. Input: the draft/frozen spec for the current
focus in docs/ai/STATE.yaml.

## Protocol
1. Read the spec and enumerate open decisions: ambiguous ACs, unnamed
   defaults, unchosen alternatives, unstated failure behavior.
2. Codebase-first resolution: for each decision, search the repo BEFORE
   composing a question. If prior art, a convention, or a contract already
   answers it, resolve it silently and record the source as
   `inferred: <path>` — that decision never reaches the human.
3. For each decision that survives step 2, ask the human. Two iron rules:
   - ONE QUESTION AT A TIME. Never a questionnaire; the answer to one
     question reorders or deletes the rest.
   - EVERY question ships a recommended answer with a one-line rationale,
     so the human can accept with a single word. Format:
     `Q: <question>` / `Recommended: <answer> — <why>`.
4. Silence or "go with your recommendation" adopts the recommended answer
   (source `recommended-default`); an explicit reply adopts the human's
   answer (source `human`).
5. Append each resolved decision to the ledger and, when material, reflect
   it in the spec body through the normal Planning edit path.

## Decision-ledger output
Append one line per resolved decision to `docs/ai/decisions.jsonl`
(append-only — echo-append per that file's header; never edit existing
lines):

```
{"v":1,"ts":"<ISO8601Z>","actor":"interrogate","type":"planning_decision","ref_id":"<REF-ID>","question":"<the decision>","answer":"<what was decided>","source":"inferred: <path>|human|recommended-default"}
```

## Output format (session summary)
```
INTERROGATE advisory walk — <REF-ID>
  Decisions found: N (inferred: N, asked: N, defaulted: N)
  Ledger: N lines appended to docs/ai/decisions.jsonl
  Spec follow-ups: <sections needing a Planning edit, or none>
```

## Rules
- Questions must be decisions, not comprehension checks — if the repo or the
  spec already answers it, it was step-2 material (`inferred: <path>`).
- Do not renumber, freeze, or unfreeze the spec from this skill; material
  spec edits belong to Planning (.aai/PLANNING.prompt.md).
- Human-blocking escalation stays owned by the HITL flow
  (`.aai/SKILL_HITL.prompt.md`); this skill asks only while the human is
  already present in-session.
- Cross-links: pre-implementation confidence lives in
  `.aai/SKILL_SCOUT.prompt.md`; evidence-backed completion stays with
  `.aai/SKILL_VERIFY.prompt.md`.
