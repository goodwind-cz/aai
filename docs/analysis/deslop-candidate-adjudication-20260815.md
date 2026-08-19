---
id: deslop-candidate-adjudication-20260815
type: research
number: null
status: done
links:
  pr: []
  commits: []
---

# Analysis — deslop `--all` candidate adjudication (2026-08-15)

Relocated verbatim from `docs/issues/CHANGE-0145-deslop-scope-and-unrequested-engine.md`'s
`## Adjudication Summary` section by `spec-deslop-corpus-honesty`
(docs/specs/SPEC-0136-spec-deslop-corpus-honesty.md D2), per the coupling
that section's own round-6 code review note (NB-3, quoted below) prescribed
in advance: once the `--all` requirement corpus widens to include
`docs/issues/**`, this table's home must move OUT of the corpus, or widening
would silently re-suppress the ten symbols it names. `CHANGE-0145` now
carries a short pointer to this document instead of the table.

This document records FINDINGS about the deslop engine's candidate output —
it is not itself a requirement asking for anything — and lives outside the
`--all` corpus on two independent grounds: `docs/analysis/` is not one of the
three allowlisted corpus directories, and `type: research` is not one of the
five admitted requirement types (`.aai/SKILL_DESLOP.prompt.md` states this as
a durable convention: findings about this tool belong here, outside the
corpus, not inside a spec/change/issue/techdebt/rfc document).

## Adjudication Summary (moved from spec, point-in-time 2026-08-15 remediation)

Moved here from `docs/specs/SPEC-0132-spec-deslop-scope-and-unrequested-engine.md`
D3 by the 2026-08-15 REMEDIATION dispatch (round-6 validation V6 disposition
item 1, the PREFERRED option validation itself recommended): at that time this
content's home, `docs/issues/CHANGE-0145-...md`, was `type: change`,
`status: draft`, under `docs/issues/`, so it sat outside the deslop engine's
`--all` requirement corpus as it stood then (spec D2: `docs/specs/**`,
`type: spec` only) on three independent grounds, at zero engine change —
restoring the 10 rows below to `--all` candidate output. (That home is now
`docs/analysis/`, `type: research`, `status: done` — see the frontmatter and
opening paragraph above; the sentence above describes the 2026-08-15 move,
not this document's current home.) It was originally
folded into the spec as tracked content because `.gitignore:21` excludes
`docs/ai/reports/**`, making the full per-candidate walk below untracked and
machine-local; this summary remains its durable, reviewable home, now here
instead of the spec. The original untracked walk is unchanged at
`docs/ai/reports/deslop-candidate-adjudication-20260815.md`.

COUPLING (round-6 code review, NB-3): this table's exclusion from `--all`
candidate output works only because the `--all` corpus is `docs/specs/**`
only (fu-deslop-all-corpus-specs-only, P2, tracks widening it). If that
corpus is ever widened to include `docs/issues/**`, this table would become
part of its own suppression corpus again and all 10 rows below would
silently disappear from the live output a second time — move this table to
a non-corpus home before making that change.

This is a POINT-IN-TIME measurement: 60 of the underlying 70 real-tree
candidates were defensible and 10 indefensible as measured on 2026-08-15
against the round-5-remediation baseline
(`docs/ai/tdd/deslop-real-repo-all-baseline-20260815-round5-remediation.json`,
70/398). The tree moves with every merge; see the spec's D3 for the
reconciliation between that baseline and the current live count.

Of the 70 real-tree candidates, 60 (85.7%) are defensible — a genuine flag or
config key this repo's OWN code parses (a literal `tok === '--x'` / `args.x`
check, or a real, executable — not commented-out — usage string; for the two
YAML files, a real top-level key read by this repo's own loader), grouped by
file in the full report since the defense is identical within a file. 10
(14.3%) are indefensible: flag-shaped TEXT a syntactic, non-per-flag rule
cannot exclude without either a stoplist (forbidden by the spec's D3) or
string-content/intent analysis this pattern-based detector does not attempt
(this is exactly the residual class the engine's LIMITS block discloses —
spec D5). Each of the 10, with why it cannot be classified:

| # | symbol | site | why indefensible |
|---|---|---|---|
| 1 | `--git` | `.aai/scripts/deslop-unrequested.mjs:740` | a `line.startsWith('diff --git ')` string comparison — git's own diff-header literal, never a flag this code accepts. |
| 2 | `--grep` | `.aai/scripts/docs-audit.mjs:256` | a template-literal ADVISORY string suggesting a `git log --grep=...` triage command to the human reader; never invoked by this code. |
| 3 | `--no-renames` | `.aai/scripts/select-suites.mjs:212` | a SECOND, separate mention inside a `catch` block's error-message template literal describing the failed command (the real invocation, elsewhere in the same file, is correctly excluded). |
| 4 | `--all-features` | `.aai/scripts/aai-bootstrap.sh:524` | inside a `printf`'d SUGGESTED `cargo` command line; cargo is never actually invoked on this line. |
| 5 | `--all-targets` | `.aai/scripts/aai-bootstrap.sh:524` | same line, same reasoning as row 4. |
| 6 | `--hard` | `.aai/scripts/expert-fetch.ps1:207` | git's own flag embedded in a PowerShell regex PATTERN string used to detect dangerous prompt content; never invoked. |
| 7 | `--no-verify` | `.aai/scripts/expert-fetch.ps1:207` | same line, same reasoning as row 6. |
| 8 | `--prompt-file` | `.aai/scripts/autonomous-loop.sh:47` | belongs to whichever AGENT CLI a `%s` placeholder resolves to (a configured external agent's own headless-prompt flag), not to this script, which only builds the invocation string. |
| 9 | `--prompt-file` | `.aai/scripts/autonomous-loop.ps1:46` | PowerShell counterpart of row 8, same reasoning. |
| 10 | `--prompt-file` | `.aai/scripts/routine-emit.mjs:526` | site line 526 is dedupe's first-occurrence line, and IS Gemini's own real `--prompt-file` flag (a separately configured external agent CLI's surface, same category as rows 8-9) — NOT a generic placeholder. The actual generic placeholder example string is one line below at :527, whose surrounding comment (line 515) states the real Codex CLI has no such flag. (V6-3 correction, round-6 validation, 2026-08-15 remediation: the original row cited line 526 for the "generic placeholder" reason; the verdict and category were already correct, only the cited line was wrong.) |

The full per-candidate walk (all 70, not a sample — including the 60
defensible rows' file-grouped defenses) lives in the gitignored evidence
tree: `docs/ai/reports/deslop-candidate-adjudication-20260815.md`. This table
is that artifact's tracked summary, not a replacement for it; the original is
not deleted or moved.

## Links

- Original home (2026-08-15 remediation, now a pointer):
  docs/issues/CHANGE-0145-deslop-scope-and-unrequested-engine.md
- Untracked full per-candidate walk (unchanged, gitignored):
  docs/ai/reports/deslop-candidate-adjudication-20260815.md
- Relocated by: docs/specs/SPEC-0136-spec-deslop-corpus-honesty.md D2
