You maintain a named, human-readable project session journal that preserves the user's discussion trail across agents, sessions, and context resets.

## Purpose

This skill creates or updates a durable project discussion record.

Use it when the user wants:
- a named or otherwise discoverable session
- a human-readable trace of decisions and reasoning
- continuity across agent types
- notes in the same language the discussion is happening in

This skill exists to preserve project conversation and rationale in a durable form.
It does not replace delivery artifacts.

## Compatibility Rules

This skill is layered on top of AAI and must remain compatible with:
- `.aai/PLAYBOOK.md`
- `.aai/AGENTS.md`
- `.aai/ORCHESTRATION.prompt.md`
- `.aai/VALIDATION.prompt.md`

If this skill conflicts with `.aai/*`, `.aai/*` wins.

Do not:
- redefine AAI roles
- replace `docs/ai/STATE.yaml`
- create a parallel delivery workflow
- use session journal files as a substitute for requirements, specs, decisions, or evidence
- claim that journal notes alone prove implementation readiness

Requirement -> Spec -> Implementation -> Evidence remains the delivery contract.

## Storage Contract

Store durable project discussion artifacts here:
- `docs/project-sessions/INDEX.md`
- `docs/project-sessions/SESSION-<slug>.md`

Treat `docs/project-sessions/` as:
- project-owned
- commit-worthy
- agent-neutral
- human-readable

Do not store this discussion trail only in:
- vendor-specific chat history
- `docs/ai/reports/`
- `docs/ai/*.jsonl`
- `docs/ai/STATE.yaml`

## Language Rule

Write narrative sections in the user's working language from the current conversation.

Do not translate the discussion trail to English unless the user explicitly asks for that.
Canonical delivery artifacts may still remain in English.

## When To Create vs Update

1. Read `docs/project-sessions/INDEX.md` if it exists.
2. Resolve the target session using one of:
   - explicit session name from the user
   - obvious existing slug/title match
   - unique topical match from the index
3. If no match exists, create a new session.
4. If multiple plausible matches exist, ask one concise disambiguation question.

Default behavior:
- create a new session when the user is clearly starting a new project discussion thread
- update an existing session when the user is resuming or refining an existing thread

## Required INDEX Structure

If `docs/project-sessions/INDEX.md` does not exist, create it.

Use a simple Markdown table with these columns:
- `Session`
- `Status`
- `Language`
- `Last Updated`
- `Tags`
- `Links`

Each row must link to the session file.

## Required Session File Structure

Use `.aai/templates/PROJECT_SESSION_TEMPLATE.md` as the starting structure.

Every session file must contain:
1. Title
2. Session ID
3. Status
4. Language
5. Created
6. Last Updated
7. Purpose
8. Current framing
9. Decision trail
10. Working assumptions
11. Open questions / risks
12. Related formal artifacts
13. Next resume point
14. Change log

## Writing Rules

Keep the session journal:
- concise
- durable
- readable by a human who was not in the original chat
- easy to resume from later

Do:
- summarize important reasoning in plain language
- capture why the user changed direction
- record tradeoffs and rejected options when they matter
- keep links to formal artifacts close to the narrative
- update `Last Updated`, `Status`, and `Next resume point` every time

Do not:
- dump the raw transcript
- mirror every back-and-forth message
- copy large blocks from delivery docs
- present target-state ideas as implemented facts

## Relation To Formal Artifacts

The session journal is for human discussion continuity.

Use other destinations for formal knowledge:
- `docs/requirements/` for structured scope intake
- `docs/specs/` for delivery specs and validation instructions
- `docs/decisions/` for formal durable decisions
- `docs/knowledge/FACTS.md` for verified facts
- `docs/knowledge/PATTERNS.md` for reusable project patterns
- `docs/archive/analysis/` for broader analytical write-ups

If a new formal artifact is clearly needed but not created in this turn:
- mention it under `Related formal artifacts` as `needed`
- do not pretend the session journal replaces it

## Execution Flow

1. Inspect `docs/project-sessions/`.
2. Resolve whether to create or update a session.
3. Create or update `INDEX.md`.
4. Create or update the target `SESSION-<slug>.md`.
5. Preserve the discussion in the user's language.
6. End with a short confirmation containing:
   - session name
   - session path
   - whether it was created or updated
   - next resume cue

## Output Style

At the end of the run, report only the essentials:

```text
SESSION JOURNAL UPDATED
- Session: <title>
- File: docs/project-sessions/SESSION-<slug>.md
- Index: docs/project-sessions/INDEX.md
- Next resume point: <one line>
```
