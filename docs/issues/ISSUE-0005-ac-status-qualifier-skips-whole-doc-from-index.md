---
id: ISSUE-0005
type: issue
status: done
links:
  pr: []
  commits: []
---

# Issue: a non-canonical AC status (e.g. "done (pre-existing)") skips the WHOLE spec from docs/INDEX.md

## Summary
The docs index generator validates each Acceptance-Criteria row's `Status`
against `AC_STATUS_ENUM = {planned, implementing, done, deferred, blocked,
rejected}`. A single non-canonical value in one AC cell — e.g. a human/agent
annotation like `done (pre-existing)` — is an "unknown AC status", which
(degrade-and-report) causes the **entire document** to be skipped from
`docs/INDEX.md` and listed in `docs/INDEX.violations.md`. One clearly-"done" AC
cell with a parenthetical qualifier therefore makes a whole spec disappear from
the index — the same "docs silently vanish from the index" failure family as
ISSUE-0001, DEBT-0001, and ISSUE-0003.

Observed (target project using the vendored AAI layer):
```
docs/specs/SPEC-CHANGE-141-national-team-role-final-definition.md:
  unknown AC status "done (pre-existing)" for —
```

## Type
- bug

## Impact
- Who/what is affected? Any target project whose specs carry a qualified AC
  status (`done (pre-existing)`, `done (manual)`, `blocked (external)`, etc.) —
  a common human shorthand. The whole spec drops out of the index over one cell.
- Severity/priority: **Medium** — no data loss on disk, but the spec silently
  loses index visibility (Active/Done/etc. all miss it), which is exactly what
  the index is meant to prevent. `--strict` also fails CI on it. High friction
  because the coarse granularity (whole-doc skip) is surprising relative to the
  small cause (one cell).

## Current Behavior
`.aai/scripts/lib/docs-model.mjs` defines the strict `AC_STATUS_ENUM`.
`.aai/scripts/generate-docs-index.mjs` (~line 123) pushes an "unknown AC status"
failure for any AC cell not in the enum; a doc with ANY failure is moved to the
`skipped` set (index "Skipped (schema violations)" section + `docs/INDEX.violations.md`),
so the whole doc is excluded from the real index sections. `done (pre-existing)`
is not in the enum → the spec is dropped entirely.

## Expected Behavior
A clearly-canonical status carrying a qualifier should not cost the whole spec
its index presence. Concretely, ONE of (to be decided — see Notes):
- the generator normalizes/accepts a base canonical status with a trailing
  parenthetical qualifier (`done (pre-existing)` → `done`, qualifier preserved as
  a note); OR
- an unknown AC status skips only that ROW (flagged), keeping the doc indexed; OR
- the value is rejected but with actionable guidance and the doc still appears in
  the index with a clear "AC schema violation" marker rather than vanishing.

Either way: a single bad AC cell must not silently remove an entire spec from
`docs/INDEX.md`.

## Steps to Reproduce (if applicable)
1) In any spec's Acceptance Criteria Status table, set one row's `Status` to
   `done (pre-existing)` (or any `<canonical> (<qualifier>)`).
2) `node .aai/scripts/generate-docs-index.mjs` → the spec is absent from every
   real index section and appears only under "Skipped (schema violations)" /
   `docs/INDEX.violations.md` with `unknown AC status "done (pre-existing)"`.
3) `node .aai/scripts/generate-docs-index.mjs --strict` → non-zero (fails CI).

## Verification
- After the fix: a spec with a `done (pre-existing)` AC cell appears in the
  correct index section (not silently dropped); `--strict` behaves per the chosen
  design (either accepts the normalized value or fails with only the row flagged,
  doc still listed).
- Regression test in `tests/skills/test-aai-docs-audit.sh`: a fixture spec with a
  qualified AC status is indexed (not whole-doc-skipped); a genuinely garbage AC
  status still reported.
- `docs-audit --check --strict` and the index generator stay consistent on how
  they treat qualified/unknown AC statuses.

## Constraints / Risks
- Must keep degrade-and-report: the index is always produced; violations stay
  visible. Do not weaken detection of genuinely-invalid statuses.
- If normalizing qualifiers, define the rule narrowly (leading token must be a
  canonical status; strip a single trailing `(...)`), and decide where the
  qualifier goes (Notes column / ignored) so meaning isn't lost. Keep
  `docs-audit` (AC_STATUS_ENUM consumer) and the generator aligned.
- The offending doc itself (`SPEC-CHANGE-141-…` in the reporting target project)
  is a data fix there (`done (pre-existing)` → `done`, "pre-existing" → Notes);
  THIS issue is the AAI-side tooling improvement so the failure mode is less
  surprising/costly for all target projects.

## Notes
Decision to resolve during planning (options with tradeoffs — may warrant an RFC
if the team wants a policy, not just a tolerance tweak):
1. **Normalize** `<canonical> (<qualifier>)` → base status (most forgiving; risk:
   masking typos).
2. **Row-level skip** instead of whole-doc skip (keeps the spec indexed; the bad
   row is flagged) — arguably the highest-value, lowest-risk change and directly
   addresses "a whole spec vanished".
3. **Strict + better guidance** (keep rejecting, but don't drop the doc from the
   index — list it with a violation marker, and make the message suggest the
   canonical value + Notes placement).
Recommend (2) as the core fix (granularity), optionally plus (1) for the common
`(pre-existing)`/`(manual)` qualifiers. Related: ISSUE-0001, DEBT-0001,
ISSUE-0003 (index-visibility-loss family), RFC-0002 / SPEC-0006 (docs hygiene,
degrade-and-report, coverage invariants). Component:
`.aai/scripts/lib/docs-model.mjs` (`AC_STATUS_ENUM`, `parseAcTable`),
`.aai/scripts/generate-docs-index.mjs` (violation → skip granularity),
`.aai/scripts/lib/docs-audit-core.mjs` (AC status consumer).
