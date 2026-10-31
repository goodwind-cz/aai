---
id: provider-adapter-surfaces-closing-slice
type: change
number: 237
status: done
user_visible: true
capability: provider-adapter-registry
links:
  pr: []
  commits: []
---

# Provider adapter surfaces: generated SKILLS.md quick reference, CRLF-safe Copilot shim overrides, honest amendment sign-off listing

## Summary
- Closing slice of RFC-0017 phase 4 (provider adapter surfaces). It closes the
  three P2 follow-ups that the provider adapter registry slice (PR #502) and the
  cheap transitions slice left open. The resume/status part of phase 4 stays a
  separate later slice; the umbrella RFC stays open.

## Motivation / Business Value
- `fu-skills-md-quickref-missing-rows`: the `SKILLS.md` Quick Reference is
  hand-maintained. It lists 37 of the 42 skills in `.claude/skills/`, and
  aai-factory-report, aai-live, aai-merge, aai-release and aai-roadmap are
  missing. Only two per-skill spot rows guard it: advisory-skills TEST-011 and
  routine TEST-022. Users and agents in every harness read this table to
  discover skills, so a missing row hides a capability.
- `fu-sync-sh-crlf-override-block`: when a downstream Copilot shim uses CRLF
  line endings, `aai-sync.sh` extracts an empty overrides block, replaces the
  file and logs "unmodified shipped shim replaced". The user's overrides are
  silently lost. `aai-sync.ps1` keeps them, so the two platforms disagree on
  the same input. This is data loss in a downstream project.
- `fu-amend-list-shows-unsigned-signed`: `spec-amend.mjs list` shows unsigned
  contract amendment records (`owner_signoff: false`) as signed and their
  trackers as done. The observed case is decisions.jsonl lines 2308 and 2311,
  2026-10-24T12:53:10Z/11Z. An older `classifies_record` keyed by record hash
  (line 1860, `535ed5f67d37`) appears to match them. The `signs on merge:`
  line of /aai-ship and the merge checkpoint read this listing, so a false
  "signed" hides what the owner's merge signs.

## Scope
- In scope:
  - `SKILLS.md` Quick Reference generated from the same skill source that
    `sync-harness-skills.mjs` (provider adapter registry) uses, with a
    deterministic drift check that a test or CI runs, so a new skill without a
    row fails. Existing per-skill descriptions are preserved where present;
    the five missing skills get rows.
  - `aai-sync.sh`: extracting the overrides block from a Copilot shim tolerates
    CRLF exactly as `aai-sync.ps1` does, and keeps user overrides. Regression
    test with a CRLF shim fixture, covering both platforms where the suite
    already runs the ps1 counterpart.
  - `spec-amend.mjs list` (and its `--json`): a record's signed state is derived
    from that record's own `owner_signoff` and from signature records that
    really bind to it. A classification or signature keyed by a hash that
    another record also matches must not mark a different record signed.
    Regression test using the observed shape.
  - Close the three follow-ups via `follow-ups.mjs close`.
  - RFC-0017 Rollout Status phase 4 row: record this slice; phase 4 stays
    `in progress` with resume/status as the remaining item.
- Out of scope:
  - Resume/status work of phase 4, phase 5, and any other provider-adapter
    surface not named above.
  - Re-signing or reclassifying historical ledger records (the fix is the
    reader; append-only records are not edited).

## Affected Area
- `SKILLS.md`, `.aai/scripts/sync-harness-skills.mjs` (or a sibling generator),
  `.aai/scripts/aai-sync.sh`, `.aai/scripts/spec-amend.mjs`, their test suites,
  `docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md`.

## Desired Behavior (To-Be)
- A new skill wrapper in `.claude/skills/` without a Quick Reference row makes
  the drift check fail. Regenerating fixes the table without hand edits.
- A CRLF Copilot shim with a non-empty overrides block keeps that block after
  `aai-sync.sh`, as it does after `aai-sync.ps1`.
- `spec-amend list` reports an `owner_signoff: false` contract record as
  unsigned unless a signature record binds to that exact record.

## Acceptance Criteria
- AC-01: The SKILLS.md Quick Reference lists every skill in `.claude/skills/`,
  including the five missing ones. A drift check fails when a skill has no row
  and passes after regeneration. It is wired into an existing test suite.
- AC-02: `aai-sync.sh` keeps a non-empty overrides block of a CRLF Copilot shim.
  The regression test is RED before the fix, and sh and ps1 produce the same
  outcome on that fixture.
- AC-03: `spec-amend list` and `list --json` show an unsigned contract record as
  unsigned even when an older hash-keyed classification exists. The regression
  test reproduces the observed collision shape.
- AC-04: The three follow-ups are closed on the ledger. The RFC-0017 phase 4 row
  names this slice, and phase 4 stays in progress.

## Assumptions (autopilot)
- The Quick Reference row text comes from each skill's description, which the
  registry already reads. Planning decides between generating the whole
  section and checking a hand-written one against the registry. Either
  satisfies AC-01 if a missing row fails a test.
- If AC-03's root cause is not a hash collision, Planning records the actual
  cause; the AC stands on observed behavior.

## Notes
- Ride via /aai-ship (owner menu choice "1", 2026-10-30).
