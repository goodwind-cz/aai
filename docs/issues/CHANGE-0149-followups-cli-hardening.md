---
id: followups-cli-hardening
number: 149
type: change
status: done
user_visible: false
ceremony_level: 1
capability: aai-decisions
links:
  pr:
    - 264
  commits:
    - 1835cd4
---

# Change — four defects in the follow-up registry CLI, one file

## Summary
- `.aai/scripts/follow-ups.mjs` carries four separately-filed registry items.
  All four were reproduced on 2026-08-18 against the current tree before this
  intake was written; none had gone stale.
- They share one file and one suite, so they ship as one scope rather than four
  rides. This is the first of six planned cluster rides against a 54-item
  backlog that individual scopes cannot drain.

## Motivation / Business Value
- This is the tool the factory writes its own memory with. It is invoked many
  times an hour during a ride, and two of these four defects bit during the
  2026-08-17 rides — the flag-value one twice in twenty minutes.
- The worst of them answers a mistyped path with "the registry is empty" and
  exit 0. A wrong path should never read as good news.

## Scope
- In scope: the four defects below, in `.aai/scripts/follow-ups.mjs` and
  `.aai/scripts/generate-factory-report.mjs`'s follow-up block, plus their arms.
- Out of scope: the missing `amend-run` path (`fu-telemetry-completeness`,
  a different script), and any change to the ledger format or the append-only
  contract.

## Affected Area
- `.aai/scripts/follow-ups.mjs`
- `.aai/scripts/generate-factory-report.mjs` (the follow-up count note only)
- `tests/skills/test-aai-follow-ups.sh`

## Desired Behavior (To-Be)
- D1 — a flag value that begins with two dashes is accepted, so a finding may
  quote a flag name. Reproduced: `add --what "--decisions is undocumented"`
  exits 2 with a grammar error.
- D2 — a `--ledger` path that is a directory, or otherwise unreadable, is
  refused loudly rather than reported as an absent registry. Reproduced:
  `list --ledger docs/ai` exits 0 saying the ledger is absent.
- D3 — a malformed id in the ledger is named as malformed. Reproduced: an entry
  with id `BAD ID` lists as an ordinary open item with no note.
- D4 — when the report's follow-up count excludes malformed lines, the note
  says the figure may be understated instead of only naming the exclusion.

## Acceptance Criteria
- AC-001: `add` accepts a value beginning with two dashes for every value-taking
  flag, and still rejects a genuinely missing value.
- AC-002: a `--ledger` path that exists but is not a readable file exits
  non-zero with a message naming the path and the reason, and never reports an
  empty registry.
- AC-003: an absent ledger keeps today's behaviour — reported as absent, exit 0
  — so the read-tolerate contract is unchanged.
- AC-004: an entry whose id does not match the id grammar is listed with an
  explicit malformed marker, and is excluded from the open count.
- AC-005: the report's follow-up note states that the count may be understated
  whenever any line was excluded.
- AC-006: the append-only contract is untouched — no command rewrites or
  removes an existing line.
- AC-007: exit codes for every path that works today are unchanged.

## Verification
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-follow-ups.sh`
- whatever `node .aai/scripts/select-suites.mjs --files-from <changed files>`
  returns, run all of it — not a hand-picked list. A CORE suite skipped in
  validation is what failed CI on the previous ride.
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` clean

## Constraints / Risks
- Node stdlib only, zero dependencies.
- The ledger is append-only and shared with `docs/ai/decisions.jsonl`'s other
  record types. A parser change must not alter how non-follow-up lines are read.
- D1's fix must not make a missing value silently swallow the next flag; the
  distinction is between a value that looks like a flag and no value at all.
- D2 changes an exit code from 0 to non-zero on a path that "works" today.
  That is the point, but it is the one place this scope can break a caller —
  check whether anything in the repo passes `--ledger` a directory.
- No secret is referenced by this scope.

## Notes
- Registry items closed by this scope: `fu-flag-values-leading-dashes`,
  `fu-ledger-readable-directory`, `fu-malformed-explicit-id-unnamed`,
  `fu-generator-undercount-clause`.
- Reproductions run before writing this doc, all four still live:
  grammar error on a dashed value; `list --ledger docs/ai` exit 0 "ledger
  absent"; `BAD ID` listed as an ordinary open item.
- Strategy suggestion: direct with targeted tests. Planning declares the
  binding ceremony level.
