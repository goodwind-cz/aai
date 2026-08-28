---
id: intake-doc-identity-table-and-its-pins
type: issue
number: null
status: draft
links:
  pr: []
  commits: []
---

# The intake identity table is authoritative for more types than the tools support, and its pins read the wrong thing

## Summary
- Intake identity — which directory, which prefix, unnumbered draft — is stated in one
  table in `.aai/INTAKE_COMMON.md`. Eight registry items say the same thing from
  different angles: the table now covers eight types, the allocator supports six, the
  templates do not carry the key the gate demands, the fallback block instructs the exact
  filename the gate rejects, and the two arms that pin the table read it more strictly
  than the shipped parser does.

## Type
- bug

## Impact
- Affected: every intake, in every type. Two of these bit while writing THIS batch of
  intakes: the templates carry no `number:` key, so each of the fourteen documents needed
  a hand-added `number: null` before `docs-audit.mjs --intake-file` would pass.
- Two of the eight types (`research`, `hotfix`) cannot be allocated at all, and the gap is
  invisible until someone passes `--type research`.

## Current Behavior
Verified in a disposable clone of `origin/main` (`c6b32d0`):

- `fu-intake-templates-lack-number-key` (P3). Measured today with
  `/usr/bin/grep -c '^number:'` over the eight templates: `RFC_TEMPLATE.md` and
  `SPEC_TEMPLATE.md` return 1; `ISSUE`, `CHANGE`, `TECHDEBT`, `REQUIREMENT`, `RESEARCH`
  and `RELEASE` all return 0. That is SIX of eight without the key, where the registry
  entry recorded seven — the count moved, the defect did not. A verbatim copy of any of
  those six fails `docs-audit.mjs --intake-file` with `number-absent`.
- `fu-intake-common-fallback-numbers-doc` (P2). The FALLBACK block in
  `.aai/INTAKE_COMMON.md` still instructs scan-and-mint of
  `docs/<type>/<TYPE>-000N-<slug>.md` — exactly the numbered filename the `--intake-file`
  predicate rejects. The POST-SAVE escape hatch excuses only a MISSING `docs-audit.mjs`,
  not a missing allocator, so on an older layer that has the audit but no allocator the
  role follows the fallback, writes a numbered file, and then hits "fix the FILENAME and
  re-run until both pass" with no reachable fixed point.
- `fu-intake-dir-unanchored-research-hotfix` (P2), with
  `fu-typemap-missing-research-hotfix` (P2, filed under a neighbouring ref) as its
  mechanical cause. Measured at `.aai/scripts/allocate-doc-number.mjs:78-88`: `TYPE_MAP`
  holds `rfc, spec, issue, change, techdebt, debt, prd, requirement, release` and
  `resolveType` throws at `:203` on anything else. For the two types the map does not
  know, the `INTAKE_COMMON.md` row and the per-type prompt can drift TOGETHER to a wrong
  directory with the whole intake suite green: moving the research row and
  `INTAKE_RESEARCH`'s opening line both to `docs/releases` keeps rc 0, because TEST-013
  pins prompt-to-table AGREEMENT, not correctness.
- `fu-intake-table-parser-asymmetry` (P2). Measured at
  `tests/skills/test-aai-intake.sh:413-416`: `intake_table_lines` matches
  `^\| [a-z]+ \| [a-z]+ \| docs\/[a-z]+ \| [A-Z]+ \|$` — exactly one space around every
  cell — while the shipped `parseIntakeTypeTable` at `.aai/scripts/docs-audit.mjs:181-188`
  allows `\s*`. A double-spaced row is therefore LIVE in the gate and invisible to the arm
  that derives its row universe from the awk. A two-readings-agree cross-check was added,
  so the divergence is now DETECTED and named; the underlying strictness asymmetry (and
  TEST-014's table-removal `grep -v` sharing the same single-space assumption) remains.
- `fu-intake-dir-pin-is-set-not-opening` (P2). Spec-AC-02 and its evidence cell say every
  per-type prompt's OPENING directory line, but TEST-013 pins the file-wide SET of
  `docs/<dir>` mentions, which is also fence-blind. Deleting the opening line and naming
  the directory only in a footnote stays green; and the first legitimate cross-reference or
  fenced example path added to any intake prompt reddens the arm for a non-defect.
- `fu-ledger-backticks-ran-as-command` (P2) and `fu-ledger-no-backtick-claim-is-absolute`
  (P3). Unescaped backticks inside a double-quoted bash string in
  `tests/skills/lib/prompt-diet-ledger.sh` ran as command substitution on every source,
  printing `extra: command not found` to stderr and silently deleting the word from the
  ledger text. Both are remediated in tree: the entry at `:171` now states the true
  invariant ("no UNESCAPED backtick in any entry, not no backtick") and
  `tests/skills/test-aai-prompt-diet.sh` TEST-021 (`:1075-1122`) sweeps the whole library
  for the class. They were kept open pending a shipped commit sha.
- `fu-report-ids-exceed-registry-cap` (P2). Roles routinely write follow-up ids into their
  reports that the registry CLI refuses: `.aai/scripts/follow-ups.mjs:34,113` declares the
  form `^fu-[a-z0-9]+(-[a-z0-9]+)*$` with `ID_MAX_LEN = 40`. Four of six ids named in one
  round-2 report were refused with exit 2 when someone finally tried. This is the
  mechanical cause of the reported-as-filed pattern that also appears as
  `fu-suggested-ids-read-as-filed` and `fu-filed-list-trusted-again`, both filed with
  other clusters; the three should be planned once.

Where the members disagree: six of the eight are about the identity TABLE and its
consumers; `fu-report-ids-exceed-registry-cap` and the two ledger items rode in on the
same scope and share no mechanism with the table. They are enumerated here so they are
not lost, not because a single fix covers them.

## Expected Behavior
- The templates carry `number: null` so a verbatim copy passes the gate on the first try.
- The allocator knows every type the table declares, or the table declares only what the
  allocator knows.
- The fallback block instructs a filename the current gate accepts, or is deleted.
- The arms that pin the table read it exactly as the shipped parser does.
- An id a role writes into a report is one the registry can actually accept.

## Steps to Reproduce (if applicable)
1) Copy `.aai/templates/ISSUE_TEMPLATE.md` verbatim to
   `docs/issues/ISSUE-DRAFT-x.md` and run
   `node .aai/scripts/docs-audit.mjs --intake-file docs/issues/ISSUE-DRAFT-x.md`.
2) Run the allocator with `--type research` and observe exit 2, unknown type.
3) Double-space the cells of one row in the `INTAKE_COMMON.md` table and run
   `tests/skills/test-aai-intake.sh`: the shipped parser sees the row, the awk does not.

## Verification
- A verbatim template copy passes both post-save checks with no hand edit.
- `node .aai/scripts/allocate-doc-number.mjs --type research` and `--type hotfix` build a
  DRAFT path.
- A deliberately double-spaced row is seen identically by the awk and by
  `parseIntakeTypeTable`.
- An over-length follow-up id is refused at the point a role WRITES it, not only when
  someone later tries to add it.

## Constraints / Risks
- `.aai/scripts/allocate-doc-number.mjs` is in `protected_paths_l3`; editing it forces
  ceremony 3, which is why the neighbouring scope worked around it instead.
- Changing the awk to match `\s*` widens what TEST-013 and TEST-014 consider a row and
  must be proved against the current eight-row table before and after.

## Notes
- OUT OF SCOPE: the numbering rule itself. The DRAFT-then-allocate model is shipped and is
  not being reopened.
- Registry ids covered: `fu-intake-templates-lack-number-key`,
  `fu-intake-common-fallback-numbers-doc`, `fu-intake-dir-unanchored-research-hotfix`,
  `fu-intake-table-parser-asymmetry`, `fu-intake-dir-pin-is-set-not-opening`,
  `fu-ledger-backticks-ran-as-command`, `fu-ledger-no-backtick-claim-is-absolute`,
  `fu-report-ids-exceed-registry-cap`. Context: `fu-typemap-missing-research-hotfix`.
