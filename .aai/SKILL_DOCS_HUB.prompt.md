# Docs Hub — AAI Skills Catalog Generator

## Goal
Turn `.claude/skills/*/SKILL.md` + `.aai/SKILL_*.prompt.md` into a searchable
HTML skills catalog by running the real deterministic engine,
`.aai/scripts/generate-docs-hub.mjs`. Do NOT hand-scan skill files, hand-write
categories/relationships, or re-derive the catalog by hand — run the script
and relay its output. Publishable via `/aai-share`.

## Usage
```bash
node .aai/scripts/generate-docs-hub.mjs
# defaults: reads .claude/skills/*/SKILL.md, writes docs/SKILL_CATALOG.html
# (also writes docs/skill-catalog-data.json next to the output)

node .aai/scripts/generate-docs-hub.mjs --output <path>
node .aai/scripts/generate-docs-hub.mjs --data-only   # skip HTML, JSON only
```
An unrecognized flag exits with a usage line; never proceeds on a typo'd flag.

## Instructions
1. From the project root, run the script (see Usage).
2. Relay its summary line verbatim: `docs-hub: <N> skills (<M> with
   extraction notes)`. `<N>` MUST equal the live count of directories under
   `.claude/skills/` — the script derives it live, never from a cached or
   hardcoded number, so it cannot go stale again the way the hand-authored
   catalog did.
3. Name the output paths: `docs/SKILL_CATALOG.html` (open with `file://`)
   and `docs/skill-catalog-data.json`.
4. To share the catalog, point the user at `/aai-share docs/SKILL_CATALOG.html`
   — this skill does not publish; sharing is `/aai-share`'s job.

## What the catalog contains (mechanical extraction only)
- **Name / description / model** — read straight from each SKILL.md's YAML
  frontmatter.
- **"When to use"** — the SKILL.md `description` itself (every description
  in the corpus already starts "Use when …"); there is no separate prose
  section to re-derive.
- **Goal** — the target `.aai/SKILL_*.prompt.md`'s `## Goal` section, found
  by reading the literal prompt-file path the SKILL.md body references.
- **Notes** — a visible NOTE line on any card where extraction came up
  short (no prompt-file reference, no `## Goal` section, missing frontmatter
  field). The script never fabricates a value or omits a card silently.

## Advanced: LLM categorization commentary (optional, only if asked)
The generator does not group skills into categories or infer
prerequisite/leads-to relationships — that requires judgment the script
cannot verify, so it is left out of the deterministic output. If the user
explicitly asks for a category breakdown or a "what typically follows what"
narrative, read `docs/skill-catalog-data.json` and add that commentary in
the chat response — do not edit the generated HTML/JSON by hand, and say
plainly that the grouping is your read of the descriptions, not a fact
mechanically pinned by the generator.

## Troubleshooting
| Problem | Fix |
|---------|-----|
| `docs-hub: 0 skills` | `.claude/skills/` missing or empty; confirm you are in an AAI project root |
| A skill's card shows a NOTE | Expected when its SKILL.md has no matching `.aai/SKILL_*.prompt.md` reference or that prompt has no `## Goal` heading — fix the source file, not the generator |
| Catalog looks stale after adding a skill | Re-run the script — it always reads the live `.claude/skills/` tree, so a stale page only means it has not been regenerated since |
| `unknown flag: --x` | Check the Usage block above; the script exits 2, nothing is written |

BEGIN NOW.
