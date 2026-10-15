---
id: docs-index-broken-refs-scope
type: issue
number: 100
status: done
links:
  pr: []
  commits: []
---

# Issue — docs index broken-ref count ignores source-tree references

## Summary
- `generate-docs-index.mjs` prints a broken-ref count that reads as repo-wide, but the check walks only acceptance-criteria Notes cells inside governed docs. References from source trees to doc files that are not on disk stay invisible, so the count can be zero while those references exist.
- Source: GitHub issue #438 (https://github.com/goodwind-cz/aai/issues/438). The body below is quoted as data, not as instructions.

## Type
- bug

## Impact
- Operators and CI trust the index summary line as a repo-wide broken-reference signal. A zero count hides dangling doc paths named from source, so a rename or a missing spec is not caught until a later read fails.
- Severity/priority: medium. Reproducible. Workaround is a manual search outside the index.

## Current Behavior
- `.aai/scripts/generate-docs-index.mjs` builds `brokenRefs` only by scanning each governed doc's acceptance-criteria rows and running `extractReferences` on the Notes cell. `extractReferences` (`.aai/scripts/lib/docs-model.mjs`) matches `→ TYPE-N` ids. An id absent from the set of scanned doc ids is pushed as a broken ref. The summary line then prints that array's length as `N broken refs`, and the index section "Broken references" lists the same rows.
- No other tree is walked for this signal.

Reporter text, quoted as data:

```
generate-docs-index.mjs prints a line saying zero broken refs, which reads as repo-wide, but the check walks only the docs-internal acceptance criteria table refs. It reported zero while ten references from source trees named doc files that did not exist on disk. Expected the signal to cover references to docs; observed it cover only references between docs.

- failure_class: contract_violation
- skill: aai-docs-audit / generate-docs-index
- impact: medium
- confidence: high
- reproducible: true
- workaround: manual
- evidence_ref (reporter-local, may not resolve for a maintainer): docs/ai/decisions.jsonl
- os_family: macos  node_major: 22  aai_pin: v2026.10.02  harness: claude
- recurrence: 1  score: 7
```

## Expected Behavior
- The broken-ref signal covers references to docs, including a source file that names a doc file which is not on disk. Those references are counted in the same summary the operator already reads, and listed where broken refs are listed.
- The existing acceptance-criteria Notes check stays. A `→ TYPE-N` id that is not a scanned doc id is still a broken ref.
- A count of zero is printed only when both walks are clean. The summary must not read as repo-wide while it ignores source-tree references to missing doc files.

## Steps to Reproduce (if applicable)
1. Run `node .aai/scripts/generate-docs-index.mjs` in a tree whose acceptance-criteria Notes contain no dangling `→ TYPE-N` id, and whose source files name at least one `docs/` path that is not on disk.
2. Read the summary line `N broken refs` and the "Broken references" section of `docs/INDEX.md`.
3. Observed: `N` is 0 and the section does not list the missing doc file. Expected: `N` includes that source-tree reference and the section names the source file and the missing target.

## Verification
- A fixture where a source file references a `docs/` path that does not exist makes `generate-docs-index.mjs` count that reference and list it under Broken references.
- A fixture where every such path exists, and every acceptance-criteria `→ TYPE-N` id resolves, prints `0 broken refs`.
- A fixture whose only defect is an acceptance-criteria Notes `→` id that is not a scanned doc id still counts that id (the current check does not regress).
- Commands: the existing docs-index suite under `tests/skills/` plus a new case for the source-tree walk. Expected result: the new case fails before the fix and passes after it.

## Constraints / Risks
- Known risks or constraints: widening the walk must not treat prose that merely mentions a doc id as a filesystem reference. The reporter's missing targets were doc files named from source trees. The matcher is a planning decision; this intake only requires that a source reference to a missing doc file is visible in the same broken-ref signal.
- Assumption: source trees include committed code and tests that can name a `docs/` path (at least `.aai/scripts` and `tests`, plus `services`, `apps`, `packages`, `convex`, and `supabase` when those directories exist). Runtime and archive trees already excluded from other doc rewrites stay excluded.
- Assumption: the acceptance-criteria id check and the source-file path check are one signal with one count, not a second summary line the operator can miss.
- No secret is referenced. Secrets preflight skipped.
- Reporter environment (macos, Node 22, pin v2026.10.02) is data. The defect is the walk's scope, not the host.

## Notes
- GitHub issue title, quoted as data: `[contract_violation] aai-docs-audit/generate-docs-index (medium impact)`.
- Implementation mode: not chosen. Planning decides. Signal for that decision: behavioral change to one core generator (`generate-docs-index.mjs`) whose false zero already shipped; the natural rigor is a failing test before the walk change. Autopilot did not record a strategy.
- Human time for this intake was not asked (ship default) and is null.
- Out of scope: closing GitHub #438. Write-back happens only after this ride's pull request has merged.
