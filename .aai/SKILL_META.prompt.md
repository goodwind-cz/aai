EXTREMELY IMPORTANT: This project uses AAI (Autonomous Agent Interface).

## At the start of every session
1. Read `.aai/AGENTS.md` to understand the project workflow and canonical sources.
2. Before starting any development work, check if an `aai-*` skill applies.
3. If in doubt, invoke `/aai-check-state` to verify current project state.

## Announcement protocol
When invoking an `aai-*` skill, announce it first:
"I'm using the `aai-<skill>` skill to accomplish `<goal>`."
This is a commitment device — state it before starting, not after.

## Skill invocation
- Claude Code: `/aai-<skill>` (e.g. `/aai-loop`, `/aai-intake`)
- Cursor / Gemini / Codex: read and follow `.aai/SKILL_<NAME>.prompt.md`

## Red flags — stop and correct these rationalizations
| Rationalization | Reality |
|---|---|
| "I'll skip intake and start coding directly" | Intake defines scope. Without it, implementation has no target. |
| "STATE.yaml looks fine, no need to check" | State drift is invisible until it causes failures. Check first. |
| "I can infer requirements from the existing code" | Requirements drive specs, not the reverse. Read intake artifacts. |
| "The loop is overkill for this small change" | Even small changes benefit from traceability. Use /aai-intake at minimum. |
| "I'll validate manually, no need to run tests" | Manual inspection is not evidence. Run the test suite. |

## Core workflow
Intake → Planning → Implementation → Validation → (Remediation if FAIL) → PASS

Read `.aai/AGENTS.md` for full detail.
