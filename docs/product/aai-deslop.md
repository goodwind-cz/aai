---
id: aai-deslop
type: product
capability: aai-deslop
status: current
delivered_by:
  - deslop-scope-and-unrequested-engine
  - deslop-corpus-honesty
spec: docs/specs/SPEC-0132-spec-deslop-scope-and-unrequested-engine.md
updated: 2026-08-18
---

# Deslop pass — removing AI slop, and finding code nobody asked for

## What it does

`/aai-deslop` is an advisory pass that strips characteristic AI-generated noise
from a change before review: comments that restate the next line, defensive
try/catch around trusted internal calls, abstractions introduced for a single
caller, behavior nobody asked for, and reformatting of untouched lines. It never
blocks and never gates — skipping it is always a valid outcome.

Two things changed. The pass no longer assumes it should look at your current
diff: scope is now something you choose, and if you do not name one, it asks
instead of guessing. And the "unrequested features" class, which until now was a
line in a table that depended on a reviewer noticing, has a mechanical detector
behind it. That detector answers a question nothing else here asks: not "is this
requirement covered by code?" but the reverse — "does this code answer to any
requirement?"

## How to use it

Run `/aai-deslop` and pick a scope when asked, or name one up front:

- `--diff` looks at the current change (`git diff` against the base, including
  files you created but have not staged yet). All five slop classes apply.
- `--all` walks accumulated surface and reports the unrequested class only. The
  other four classes are judgments about lines a change introduced and mean
  nothing against settled code.

There is no default. Running the engine directly with no scope exits 2 and
prints usage without scanning anything, and the skill asks rather than assumes.
An empty diff no longer dead-ends: it tells you the diff is empty and offers the
wide scope.

The detector is also usable on its own:

```
node .aai/scripts/deslop-unrequested.mjs --all
node .aai/scripts/deslop-unrequested.mjs --all --json
node .aai/scripts/deslop-unrequested.mjs --diff --base origin/main
```

## Data model

None. The engine reads the repository and writes nothing — no cache, no state
file, no edits under either scope. Its output goes to stdout.

## Interfaces and contracts

- `node .aai/scripts/deslop-unrequested.mjs` — CLI. Exit 0 for a clean run, a
  run with findings, and a run over an empty input set; exit 2 for a usage
  error, including no scope named. Advisory means advisory: a finding never
  changes the exit code.
- `--diff [--base <ref>]`, `--all`, `--json` — flags. `--json` emits the same
  content as the human form, including the LIMITS block.
- Output carries a LIMITS block on every run: that extraction is pattern-based
  rather than a real parser; how many symbols this run suppressed because a
  requirement names them; that some reported candidates are flag-shaped text
  rather than owned flags; and, in range mode, that line numbers come from the
  base comparison while content is read from the working tree.
- `.aai/SKILL_DESLOP.prompt.md` — the pass itself. Advisory, never dispatched by
  any workflow phase.

## Limits and non-goals

The detector looks only at contract surfaces — flags this code defines and
config keys it reads. It deliberately does not look at internal functions or
module exports: a helper is absent from every requirement by design, so its
absence carries no signal, and treating it as one produced hundreds of
meaningless findings before this was corrected.

Three boundaries are worth knowing before acting on a report:

- **The requirement corpus is `docs/specs/**`, `docs/issues/**` and
  `docs/rfc/**`, filtered by type and status.** A document counts only when its
  frontmatter `type` is spec, change, issue, techdebt or rfc, and its `status`
  is accepted, implementing or done — a `draft` intake, for example, is
  intentionally outside `--all` (that is what `--diff` is for). Measured on
  this repository: widening the corpus from its previous `docs/specs/**`-only,
  `type: spec`-only scope removed 9 of the 65 previously-reported candidates
  (14%) — each suppressed because a committed requirement document genuinely
  names it, not because the corpus was widened past its own defect.
- **Some rows are text, not flags.** A flag name inside a string comparison, a
  suggestion message, or a regex pattern looks identical to a real one under
  pattern matching. Telling them apart needs semantics; this scan does not
  attempt it and says so in its output.
- **Naming a symbol in a corpus document hides it — so findings about this
  tool live outside the corpus.** Any mention in a requirement document
  counts as the requirement naming that symbol, so documenting a finding
  inside a spec, change, issue, techdebt or RFC document removes it from the
  next report. A document that records findings about the detector itself
  (an adjudication table naming candidate symbols) belongs in
  `docs/analysis/` instead, where it cannot self-suppress the symbols it
  discusses — see `docs/analysis/deslop-candidate-adjudication-20260815.md`.

Non-goals: it never edits, never blocks, is never dispatched automatically, and
the wide scope is not a cleanup mandate. Read each candidate before acting; the
report is an argument, not a verdict.

## Links

- Request: docs/issues/CHANGE-0145-deslop-scope-and-unrequested-engine.md
- Spec: docs/specs/SPEC-0132-spec-deslop-scope-and-unrequested-engine.md
- Validation evidence: docs/ai/validation/validation-20260815T110436Z-deslop-scope-and-unrequested-engine-round6.md
- Corpus-honesty correction: docs/specs/SPEC-0136-spec-deslop-corpus-honesty.md
- Candidate adjudication: docs/analysis/deslop-candidate-adjudication-20260815.md
