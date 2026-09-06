---
id: decision-menu-options-parser
number: 176
type: change
status: draft
capability: live-agent-dashboard
links:
  pr: []
  commits: []
---

# The dashboard turns a pending decision's options into buttons — reliably in both directions

## Summary
- Split out of `decisions-as-menus-in-dashboard` (Amendment 1) under the owner's
  two-round review cap. The write surface, the local transport and the free-text
  box shipped there; only the option PARSER is left.

## Why it needs its own ride
Two rounds failed on the same heuristic, in opposite directions:
- **Round 1** — it fabricated options out of prose. `"The reaper flake - a
  CI-load artefact, not a bug - should we re-run or investigate?"` produced two
  buttons; `"Approve <url> - the roadmap-driven ride? - approve - reject"`
  produced three, the first being the question stem.
- **Round 2** — the fix (anchor on the last marker whose stem ends in `?` or
  `:`) stopped the fabrication and began SILENTLY DROPPING real options phrased
  as questions: `"Choose: - is it a? - b - c"` → `["b","c"]`;
  `"Choose: - alpha - is it b? - gamma"` → `[]`.

The operator contract's own shape is "a question is a menu"
(`.aai/AGENTS.md`), so options phrased as questions are the EXPECTED input, and
they are exactly what the heuristic gets wrong. A third patch to the same regex
is not the answer.

## The real constraint
`state.mjs set-human-input` writes a FOLDED block scalar, so every question
arrives as one line and the newline structure an author wrote is gone before the
parser sees it. Any robust design has to either preserve that structure at the
WRITER (an options list as its own STATE field) or stop guessing.

## Acceptance Criteria
- **AC-001** Options round-trip from the writer to the page without a heuristic:
  a question authored with N options yields exactly those N, whatever their text
  contains — question marks, dashes, URLs, code spans, an em dash.
- **AC-002** A prose question with no options yields none. The corpus for this
  is the real one: every `question` in `docs/ai/decisions.jsonl`'s `hitl_decision`
  records plus the round-1/round-2 examples above, asserted as a table.
- **AC-003** A `(recommended)` option is marked, and at most one is.
- **AC-004** Whatever the mechanism, `docs/ai/STATE.yaml` stays a protected L3
  surface: this scope does not widen `state.mjs` without owner sign-off.

## Constraints / Risks
- The likely shape is a new `human_input.options` list written by
  `state.mjs set-human-input`, which is a protected L3 file — that needs the
  owner, and the ride must surface it as a decision rather than assume it.
- Fall back to free text is always available and already shipped; this ride must
  never make the page worse than the free-text box it replaces.
