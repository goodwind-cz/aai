# AAI Constitution

Proposed for ratification by: project owner (ales@holubec.net) — ratifies by merging the introducing PR; v1, 2026-07-16

Short, ratified principles (spec-kit pattern, RES-0001 P2 rec 10). Articles
DISTILL the canonical guides — one sentence plus a pointer to the
authoritative source; the pointer target always wins on detail. Planning
checks the articles at spec freeze (.aai/PLANNING.prompt.md step 10) and
records the result in each new spec's `## Constitution deviations` section.
Amendments bump the version and re-ratify.

## Articles

1. Evidence before claims — no completion, PASS, or done claim without executable evidence produced and read in this session. (see: .aai/AGENTS.md Rules — "Do not claim PASS without executable evidence"; .aai/SKILL_VERIFY.prompt.md)

2. Simplicity — keep solutions simple (KISS) and implement nothing speculative before a requirement exists (YAGNI). (see: .aai/AGENTS.md Engineering Best Practices)

3. Portability — every durable artifact is a plain, git-diffable file usable tri-platform (Claude/Codex/Gemini); no binary or service-bound stores. (see: .aai/AGENTS.md Canonical sources; docs/TECHNOLOGY.md; RES-0001 "Do NOT adopt")

4. Degrade and report — missing tooling degrades gracefully with an explicit report, and errors fail fast with context, never silently. (see: .aai/AGENTS.md Engineering Best Practices — explicit, actionable errors; prompt degrade instructions)

5. Additive first — prefer additive, backward-compatible edits at public boundaries (APIs, prompts, schemas, step numbering); breaking changes must be explicit and documented. (see: .aai/AGENTS.md Engineering Best Practices — backward compatibility)

6. Single-writer state — docs/ai/STATE.yaml has exactly one single writer, the transactional CLI .aai/scripts/state.mjs; never hand-edit it. (see: .aai/AGENTS.md Canonical sources — runtime state writer)

7. Operator-only merge — the agent never merges; the PR ceremony ends at `gh pr create` and merging is operator-only. (see: .aai/AGENTS.md How to run, step 3; .aai/SKILL_PR.prompt.md)

## Deviations (accountable exceptions)

- At spec freeze, Planning records `## Constitution deviations` in the spec:
  the literal `None.`, or a justified list — article number, the deviation,
  and why it is justified (spec-kit Complexity Tracking pattern).
- Required for new specs going forward; optional for pre-existing specs
  (legacy docs are never flagged for lacking the section).
- An unjustifiable deviation blocks freeze; a silent deviation is drift.
- Mechanized article checking is out of scope for v1 (phase 2 candidate).
