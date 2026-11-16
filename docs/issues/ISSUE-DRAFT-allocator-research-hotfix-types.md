---
id: allocator-research-hotfix-types
type: issue
number: null
status: draft
links:
  pr: []
  commits: []
---

# The doc-number allocator refuses two intake types and goes silent through a symlinked checkout

## Summary
- `.aai/scripts/allocate-doc-number.mjs` knows six of the eight intake types the
  DURABLE DOC IDENTITY table in `.aai/INTAKE_COMMON.md` declares: `--type research` and
  `--type hotfix` exit 2 as unknown types, and `draftFilename` cannot build a DRAFT path
  for either.
- Its main() guard compares `import.meta.url` with `pathToFileURL(process.argv[1])`
  without resolving symlinks, so invoked through a symlinked checkout it exits 0 and does
  nothing — not even argument parsing. Every other `.aai/scripts/*.mjs` entry point
  resolves both sides through realpath.

## Type
- bug

## Impact
- Affected: any caller of the allocator with an intake type of `research` or `hotfix`, and
  any caller that reaches the allocator through a symlinked path (macOS `/var` ->
  `/private/var` temp checkouts, a vendored symlink). The symlink case is silent: exit 0,
  no output, no rename, so a close ceremony believes numbering succeeded.
- Severity/priority: P2 (type gap, two registry items) and P3 (realpath guard).
- Registry items closed by this intake: `fu-typemap-missing-research-hotfix` (P2),
  `fu-issue-0042-half-delivered` (P2, the same gap seen from ISSUE-0042) and
  `fu-realpath-allocate-doc-number-l3` (P3).
- Carries the remaining half of
  docs/issues/ISSUE-0042-intake-doc-identity-table-and-its-pins.md: its other three
  Verification bullets were delivered by earlier rides (registry items closed by
  `close-ceremony-sweep` and `intake-dir-pin-and-table-parser`); this ride closes it.

## Current Behavior
Measured on `origin/main` `c1034b24`:
- `TYPE_MAP` (`.aai/scripts/allocate-doc-number.mjs:78-88`) holds `rfc, spec, issue,
  change, techdebt, debt, prd, requirement, release`. `resolveType` throws on anything
  else, and main() turns that into `unknown --type "research"`, exit 2 (same for
  `hotfix`).
- The `.aai/INTAKE_COMMON.md` table rows for the two types are
  `| hotfix | issue | docs/issues | ISSUE |` and `| research | research | docs/specs | RES |`.
  `.aai/INTAKE_HOTFIX.prompt.md` saves under `docs/issues/` from `ISSUE_TEMPLATE.md`;
  `.aai/INTAKE_RESEARCH.prompt.md` saves under `docs/specs/` from `RESEARCH_TEMPLATE.md`;
  `docs/specs/` holds `RES-0001` to `RES-0004`.
- `tests/skills/test-aai-intake.sh` TEST-013 logs the two types as "TYPE_MAP has no entry
  — see spec D4, filed not fixed" and passes, so a TYPE_MAP that loses a row stays green.
- Through a symlink (`ln -s <checkout> lnk; node lnk/.aai/scripts/allocate-doc-number.mjs
  --type bogus`) the script prints nothing and exits 0.

## Expected Behavior
- `TYPE_MAP` carries `research -> docs/specs, RES` and `hotfix -> docs/issues, ISSUE`,
  exactly the table rows; `draftFilename('research', s)` is `docs/specs/RES-DRAFT-<s>.md`
  and `draftFilename('hotfix', s)` is `docs/issues/ISSUE-DRAFT-<s>.md`.
- `--type research` and `--type hotfix` are accepted exactly like `--type issue`.
- Every intake type in the table has a TYPE_MAP entry that matches it, and a missing
  entry fails TEST-013 instead of being logged.
- Invoked through a symlinked path, the allocator behaves exactly as through the real
  path (an unknown `--type` exits 2 with its message).

## Steps to Reproduce (if applicable)
1) `node .aai/scripts/allocate-doc-number.mjs --type research` -> `unknown --type
   "research"`, exit 2.
2) `ln -s "$PWD" /tmp/lnk && node /tmp/lnk/.aai/scripts/allocate-doc-number.mjs --type
   bogus` -> no output, exit 0.

## Verification
- Command(s) and expected results:
  - `tests/skills/test-aai-doc-numbering.sh` arms pinning the two new rows, the CLI
    acceptance of both types and the symlinked invocation, each proved to bite by a
    recorded mutation.
  - `tests/skills/test-aai-intake.sh` TEST-013 fails when any of the eight table types has
    no TYPE_MAP entry.
  - ISSUE-0042's four Verification bullets each hold, measured on the branch.

## Constraints / Risks
- `.aai/scripts/allocate-doc-number.mjs` is in `protected_paths_l3`: ceremony 3, the
  owner merges.
- Open PR #535 (branch `codex/singleton-reservation-portability`) also edits the
  allocator; keep the diff in that file minimal and do not touch that PR or branch.
- The `hotfix` row shares the ISSUE counter with `issue`; that is the table's design, not
  a collision.
- No secret is referenced.

## Notes
- Assumption (autopilot): `--type` alone still exits 2 "nothing selected" for every type,
  as it does for `--type issue`; "builds a DRAFT path" in ISSUE-0042 is read as the type
  resolving to its DRAFT path (`draftFilename`) and `--type` no longer being refused.
- Implementation mode: not chosen at intake (autopilot); Planning decides.
