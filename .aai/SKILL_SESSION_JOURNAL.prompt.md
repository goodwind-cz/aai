You maintain a named, human-readable project session journal that preserves the user's discussion trail across agents, sessions, and context resets.

## Purpose

A durable, agent-neutral record of project conversation and rationale.
Narrative memory only — it never substitutes for requirements, specs,
decisions, or evidence. Requirement -> Spec -> Implementation -> Evidence
remains the delivery contract; if this skill conflicts with `.aai/*`,
`.aai/*` wins.

## Contract (the living convention — CHANGE-0080)

- One file per session: `docs/project-sessions/<YYYY-MM-DD>-<slug>.md`
  (date first, short kebab slug — e.g. `2026-07-27-universality-proof.md`).
- Free-form body; no mandatory template. Use headings that fit the
  discussion. Recommended anchors when they apply: what was decided and
  why, rejected alternatives, evidence links, open questions, next resume
  point.
- Language: the language the discussion is happening in (Czech, English,
  mixed is fine). Never translate the trail unless asked.
- Every session file MUST have a row in `docs/project-sessions/INDEX.md`
  — a 3-column table `| Date | Session | Focus |`, the Session cell
  linking the file. INDEX completeness is test-pinned; a journal without
  its row is the failure mode this contract exists to prevent.

## Instructions

1. Read `docs/project-sessions/INDEX.md`. If the user names or clearly
   resumes an existing session, APPEND to its file (dated section —
   never rewrite history). Otherwise create a new file per the naming
   rule and add its INDEX row in the same edit.
2. Capture the trail faithfully and concisely: summarize reasoning in
   plain language, record direction changes and tradeoffs, keep links to
   formal artifacts close to the narrative. Do not dump transcripts or
   mirror every message.
3. Promote anything durable OUT before finishing: decisions ->
   `docs/decisions/`, constraints -> `docs/specs/`, reusable facts ->
   `docs/knowledge/`. Name what is `needed` but not yet created — never
   pretend the journal replaces it.
4. Finish with a one-line confirmation: session file path,
   created/updated, next resume cue.

BEGIN NOW.
