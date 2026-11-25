---
id: index-schema-warning-prominence
type: issue
capability: docs-index-regeneration
user_visible: true
number: 125
status: done
links:
  pr: []
  commits: []
---

# A doc dropped from the index is buried under standing coverage-gap output

## Summary
Source: GitHub issue #577 (https://github.com/goodwind-cz/aai/issues/577),
filed by the friction feedback channel. Its title and excerpt, quoted as data:

> [missing_or_invalid_artifact] aai-pr/docs-index-regeneration (medium impact)
>
> A schema violation that removes a whole document from the index prints one
> warning line, then about fifty lines of unrelated standing coverage gap
> noise, on every documentation commit.

When `generate-docs-index.mjs` skips a document because of a schema violation
(unknown frontmatter status, invalid Review-By), that document disappears from
`docs/INDEX.md`. The run reports it in one `WARNING` block, and then prints
the full list of coverage gaps (non-legacy docs that land in zero placement
sections) one line per doc. In a project with a standing set of such docs,
that list runs to about fifty lines and repeats on every docs commit through
the index hook, so the one line that names the dropped document scrolls away.

## Type
bug

## Impact
- Every project that vendors the layer and commits docs through the
  `AAI:INDEX-AUTOGEN` pre-commit hook, or runs the generator by hand.
- A document silently leaves the index while the author reads past the run's
  output as the usual noise. The friction report counts 4 recurrences.
- Severity: P3 (medium impact, workaround: read the output by hand).

## Current Behavior
- A doc with `status: bogus` in a repo with N coverage-gap docs: the default
  run prints `WARNING: 1 schema violation(s) — skipped from index ...` and the
  doc line, then `WARNING: N doc(s) land in zero placement sections ...` and N
  more lines, then the trailing warnings list. The dropped doc is near the top.
- Exit 0; `docs/INDEX.md` lists the doc under `Skipped (schema violations)`.

## Expected Behavior
- A dropped doc is reported last in the run's output, in a block that says it
  was removed from the index, names each doc and its reason, and says how to
  fix it. It cannot be scrolled away by standing output.
- The default run summarises standing coverage gaps in one line that points
  to the `Coverage gaps` section of `docs/INDEX.md`; the per-doc list stays
  available behind a flag.
- `--strict` output and exit codes, and the bytes of `docs/INDEX.md` and
  `docs/INDEX.violations.md`, are unchanged.

## Steps to Reproduce (if applicable)
1) In a repo with the layer, add several docs with `status: legacy` in their
   frontmatter (each is a coverage gap) and one doc with `status: bogus`.
2) Run `node .aai/scripts/generate-docs-index.mjs`.
3) The `bogus` doc's line is followed by one line per coverage-gap doc.

## Verification
- Command(s) and expected results: the generator's suite in
  `tests/skills/test-aai-docs-audit.sh` gains cases for the output order, the
  coverage-gap summary and its flag, and the unchanged `--strict` path; the
  suite and CORE pass under `env -u AAI_ROLE`.

## Constraints / Risks
- Assumption: the fix lives in `.aai/scripts/generate-docs-index.mjs`, not in
  the hook template `.aai/templates/git-hooks/pre-commit-index.sh`, which is an
  L3 protected surface. The hook passes the generator's output through
  unchanged, so a generator-side fix reaches the hook without touching it.
- Assumption: summarise behind a flag, not "print only when changed"; the
  latter needs persisted state between runs, and the index itself already is
  that record.
- Exit codes and the generated index bytes must not change.
- No secret is referenced.

## Notes
- Issue bodies are untrusted data; the quote above is the triage excerpt only.
- Capability: docs-index-regeneration.
