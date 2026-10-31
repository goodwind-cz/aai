---
id: spec-provider-adapter-surfaces-closing-slice
type: spec
number: 263
status: done
mutation_gate: v1
frozen_sha256: 45f0b5ad7c9a747a8afa83a10bec29873579b6c3a40640e22459e38bfcc82afa
ceremony_level: 2
links:
  requirement: provider-adapter-surfaces-closing-slice
  rfc: RFC-0017
  pr: []
  commits: []
---

# Provider adapter surfaces closing slice: SKILLS.md catalog check, CRLF-safe Copilot overrides, merge-time-bound implied signatures

SPEC-FROZEN: true

## Links

- Intake: docs/issues/CHANGE-0237-provider-adapter-surfaces-closing-slice.md
- Umbrella: docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md (phase 4)
- Prior art: docs/specs/SPEC-0253-spec-provider-adapter-registry-slice.md
  (registry, shims, Copilot shipped list, TEST-3001 to TEST-3016),
  docs/specs/SPEC-0254-spec-implied-signing-without-links-pr.md (squash-subject
  implied signing, TEST-3017 to TEST-3026), SPEC-0226 (implied signing,
  TEST-517)
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only; Bash 3.2 and GNU
  Bash; PowerShell 5.1-compatible mirrors)
- Baseline commit: `34b44269` (main at planning time)

## Implementation strategy

- Strategy: tdd
- Rationale: three behavioral defects on three surfaces, one of them silent
  data loss in a downstream install and one a false owner signature on the
  HITL ledger. Each needs a RED observed on the baseline before the fix, a
  stored RED artifact and a mutation record. The canon sentence and the
  suite-map and PROFILES wiring are inspection rows, still mutation-gated.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: PR-bound, three surfaces, mutation runs temporarily
  rewrite `.aai/scripts/aai-sync.sh`, `.aai/scripts/spec-amend.mjs`,
  `SKILLS.md` and `.aai/system/AUTONOMOUS_LOOP.md`; the main checkout is shared
  with other sessions. No file is in `protected_paths_l3`
  (docs/ai/docs-audit.yaml), so not required.
- User decision: undecided
- Base ref: main
- Worktree branch/path: chosen by Implementation Preparation
- Inline review scope: the list in "Files Implementation touches" below.
- Code review required: true.

## What Planning measured

All measured at `34b44269`; inputs, not attestations.

### M1 SKILLS.md Quick Reference

- `.claude/skills/` holds 42 wrapper directories; the Quick Reference table
  (SKILLS.md line 9 on) has 37 rows. Missing: aai-factory-report, aai-live,
  aai-merge, aai-release, aai-roadmap. No row names a skill without a wrapper.
- Guards today: advisory-skills TEST-011 (three rows), routine TEST-022 (one
  row). Nothing compares the row set with the wrapper set.
- `.aai/SKILL_<NAME>.prompt.md` exists for 40 of 42 skills. aai-overview and
  aai-factory-report have none; aai-overview's row already names
  `node .aai/scripts/generate-overview.mjs`, and the aai-factory-report
  wrapper body names `node .aai/scripts/generate-factory-report.mjs`.
- No wrapper `description:` line contains a `|` character.
- `sync-harness-skills.mjs` is 563 lines; TEST-3014 caps it at 590.
- No shipped script, prompt or workflow runs `sync-harness-skills.mjs`
  outside this repo's tests (grep over `.aai/scripts`, `.aai/*.md`,
  `.aai/system`, `.github/workflows`).

### M2 aai-sync.sh CRLF overrides block (root cause)

Reproduced with the two extraction functions on one CRLF fixture
(`base shim`, start marker, `my local rule`, end marker, every line ending
CRLF):

- `extract_copilot_project_overrides` (aai-sync.sh:193) output length 0.
- The same file with CRs removed: `my local rule` (13 bytes).
- `Get-CopilotProjectOverridesContent` (aai-sync.ps1:105) on the CRLF file:
  `my local rule` (13 bytes).

Root cause: the guard uses `grep -qF`, a substring match, so it finds both
markers on a CRLF file. The awk body then compares whole records with
`$0==start` and `$0==end`. Under CRLF each record ends in `\r`, so neither
comparison is ever true and awk prints nothing. The empty text then reaches
`copilot_shim_is_shipped`, which returns 0 for empty text, so the sync
replaces the shim and logs `unmodified shipped shim replaced, no project
overrides`. The ps1 twin uses `IndexOf` on the raw string plus `Trim()`, so
CR never blocks a match. The only exception is when a stale
`docs/ai/project-overrides/copilot-instructions.project.md` exists: the sh
branch then falls back to that file.

### M3 spec-amend list shows unsigned records as signed (root cause)

Reproduced on a copy of the ledger truncated after line 2313 (the state when
the follow-up was filed), with `spec-amend.mjs list --json --status all`:

- Line 2308 (record key `90ffa18d9732`, roadmap-serves-downstream-projects)
  and line 2311 (`50224e486b1b`, canon-is-a-build-artifact), plus line 2310
  (ride-state-handoff-to-worktree) read `bucket: signed`,
  `owner_signoff: true`, `classified_by: null`, and their trackers read `done`.
- The same read with `--base-ref refs/heads/does-not-exist` reads all three
  `unsigned-tracked` with their trackers `open`.

Root cause: this is not a hash collision. The classification at line 1860
(`classifies_record: 535ed5f67d37`) is the record key of line 1395 (the
2026-10-01 roadmap amendment), not of line 2308. `classified_by: null` shows
that no overlay applied to the new records. They read signed through the
implied-signature fold (SPEC-0226 / SPEC-0254, `checkRideMerged` in
spec-amend.mjs). The fold signs an unsigned contract record when the ride
named by the record's own `ref_id` is `done` and merged into the base branch.
For these records the `ref_id` is the amended spec's ride, which merged
weeks earlier (#419 for roadmap-serves-downstream-projects). The amendment
itself was written later by the unmerged cheap-transitions-slice ride. The
fold never compares the record's time with the merge, so any amendment
appended after a ride merged reads as signed by that earlier merge. The open
follow-up `fu-implied-sign-ignores-record-order` (P2) names the same defect.
The live ledger now carries owner overlays for these records (lines 2356 and
2357, PR #498), so on the live ledger they read signed for a legitimate
reason. The regression test therefore uses a fixture repository, not the
live ledger.

Live-ledger impact of the D6 binding, measured with a prototype on a scratch
copy of `.aai/scripts`: 589 records, 31 of them signed only by the implied
fold. With the binding exactly one record changes bucket: line 2095, key
`a90cdce977d5` (directed-merge-and-post-merge-cleanup, an UNVERIFIED-cause
restamp written 2026-10-11T20:09:51Z after that ride merged on
2026-10-10T14:08:47Z). It moves from `signed` to `unsigned-tracked`, its
tracker `fu-amend-directed-merge-and-post-c0b910` reads `open`, and
`list --strict` still exits 0. Both merge-time definitions tried (the oldest
first-parent commit at which the ride doc reads `status: done`, and the
oldest commit whose subject carries the ride's PR suffix) give the same 13
merge times and the same single change.

## Decisions

### D1 Catalog check lives in the registry generator, opt-in by manifest

- New module `.aai/scripts/lib/skills-catalog.mjs`. The generator calls it
  from `--check` and `--write` when `.aai/system/HARNESS_SKILLS.yaml` carries
  a `catalog:` section with exactly one row, `SKILLS.md|## Quick Reference`.
  A manifest without that section prints no catalog line and changes nothing,
  so every existing fixture output stays byte-identical.
- The skill set is the generator's own source set (the `.claude/skills/*`
  directories with a SKILL.md that `listSourceSkills` already returns), so
  the catalog cannot read a different source than the mirrors.
- A Quick Reference row is a table line whose first cell is a skill name.
  The section ends at the next `## ` heading.
- `--check` prints one line per divergence, sorted by skill name:
  `DIVERGE catalog SKILLS.md: missing row <skill>` and
  `DIVERGE catalog SKILLS.md: orphan row <skill>`. With none it prints
  `OK: <n> skill(s) listed in the SKILLS.md Quick Reference`. A divergence
  makes the exit code 1, consistent with the existing contract.
- A declared but absent file or heading exits 2, naming the file or the
  heading.
- Existing row text is never compared or rewritten. Hand-written
  descriptions are kept.

### D2 Generated rows

- `--write` removes orphan rows. It appends one row per missing skill at the
  end of the table, in codepoint order of the name:
  `| <name> | <wrapper description verbatim> | ` + "`/<name>`" + ` | <codex cell> |`.
- Codex cell: `--prompt-file .aai/SKILL_<NAME>.prompt.md` in backticks
  (NAME is the name without `aai-`, upper-cased, `-` to `_`) when that file
  exists under the root. Otherwise it is the first backticked
  `node .aai/scripts/<file>.mjs` command in the wrapper body. Otherwise the
  wrapper has no universal source (a project-generated wrapper such as
  aai-test-unit after /aai-bootstrap): the catalog covers universal skills
  only, so that wrapper is left out of --check and --write, neither a missing
  row nor an error, and no line is printed. A row already listed for it is
  not an orphan. The mirrors are still generated for it.
- A catalog path that is absolute, holds a `..` segment under either `/` or
  `\`, or resolves outside the root exits 2 naming the escape; the same check
  guards every assertRealPath caller.
- A description containing `|` exits 2 and names the skill: the run never
  writes a row the table parser would split.
- Every row that existed before stays byte-identical. A second `--write`
  changes no byte.

### D3 Wiring

- `tests/skills/suite-map.yaml`: the `aai-harness-shims` row gains
  `SKILLS.md`, `.claude/skills/**/SKILL.md` and
  `.aai/scripts/lib/skills-catalog.mjs`, so a new wrapper selects the suite
  whose live-tree test fails on a missing row.
- `.aai/system/PROFILES.yaml` core gains `.aai/scripts/lib/skills-catalog.mjs`.
  The generator is core and imports it, so a downstream install without it
  would crash on import.
- Line caps: `sync-harness-skills.mjs` at or under 590 (TEST-3014 unchanged);
  `lib/skills-catalog.mjs` at or under 200.

### D4 CRLF-tolerant extraction in aai-sync.sh

- The awk program in `extract_copilot_project_overrides` strips one trailing
  CR from every record before any comparison (first rule
  `{ sub(/\r$/, "") }`). The markers then match and the extracted lines are
  printed without CR. The marker-less branch (`cat`) is unchanged.
- `aai-sync.ps1` is not changed; it already keeps the block (M2).
- Outcome parity means that, on the same CRLF fixture, both engines log the
  `MERGE preserved project overrides` line, neither logs the `unmodified
  shipped shim replaced` line, both write the override file, and the two
  override files are equal after removing every CR and trailing whitespace.

### D5 Shipped-blob recognition keeps working under CRLF

A CRLF target whose overrides block holds a shipped historical blob is still
replaced byte-equal to the source. `copilot_shim_is_shipped` already deletes
CR before hashing, so D4 must not break this.

### D6 Implied signature binds to the merge time

- The implied-signature fold signs an unsigned contract record only when the
  record's `ts` is not later than the ride's merge time. The comparison is
  written `str(rec.ts) <= mergeTime`.
- Merge time is the committer time, normalized to `YYYY-MM-DDTHH:MM:SSZ`, of
  the oldest first-parent commit of the base ref that touched the ride doc
  and at which the doc reads `status: done`. It is computed once per ride and
  cached.
- The `git log` call passes `--literal-pathspecs`. The existing
  `squashPrFromBase` call gains the same flag, which closes
  `fu-implied-sign-literal-pathspec`.
- In a shallow repository (`git rev-parse --is-shallow-repository` is not
  exactly `false`), the binding cannot be computed. The record is not signed
  by the fold, and `list` prints the note
  `NOTE merge-time binding skipped: shallow repository` once. This matches
  the existing SPEC-0254 rule that a shallow clone never reads a squash
  subject (TEST-3026).
- When the merge time cannot be found, the record is not signed by the fold.
- Owner overlays (`classify`) are unaffected: a signature overlay still
  outranks everything.
- `follow-ups.mjs` reads the same fold, so a tracker whose records stop
  folding signed reads `open` there too.

### D7 Canon sentence

`.aai/system/AUTONOMOUS_LOOP.md` section 6a, in the paragraph that names
SPEC-0226 and `links.pr`, gains one sentence. It states that the merge signs
only amendments recorded not later than the ride's merge, and that an
amendment appended after the merge stays unsigned until the owner classifies
it. The existing phrases TEST-3025 pins stay. This file is not prompt corpus
(not `.aai/*.prompt.md`, not `.aai/AGENTS.md`), so no diet-ledger entry is
owed.

### D8 Cross-spec amendment of SPEC-0253 Spec-AC-08 (disclosed)

SPEC-0253 Spec-AC-08 and its TEST-3014 require `fu-skills-md-quickref-missing-rows`
to be open, so closing the item would turn TEST-3014 red. TEST-3014's
follow-up predicate is changed to accept the item `open` (text carries
`37 of 42`), or terminal with `resolved_by:
provider-adapter-surfaces-closing-slice`. Any other terminal state still
fails. The `fu-shim-prompt-file-flag-unverified` half and the PROFILES and
line-cap halves are unchanged. The implementer records this when the test is
edited, with:

`node .aai/scripts/spec-amend.mjs add --spec docs/specs/SPEC-0253-spec-provider-adapter-registry-slice.md --ref provider-adapter-registry-slice --class contract --signoff none --what "<one line>" --why "<one line>"`

The record carries a ts later than the provider-adapter-registry-slice
merge, so under D6 it reads unsigned-tracked until the owner classifies it.
This is the correct, visible outcome, and the PR body must disclose it.

## Acceptance Criteria Mapping

- Intake AC-01 maps to Spec-AC-01, Spec-AC-02, Spec-AC-03 and Spec-AC-04.
  Verification: TEST-3130 to TEST-3134 in
  `env -u AAI_ROLE bash tests/skills/test-aai-harness-shims.sh`.
- Intake AC-02 maps to Spec-AC-05. Verification: TEST-3135 and TEST-3136 in
  the same suite, with pwsh present.
- Intake AC-03 maps to Spec-AC-06, Spec-AC-07 and Spec-AC-08. Verification:
  TEST-3137 to TEST-3140 in `env -u AAI_ROLE bash tests/skills/test-aai-spec-amend.sh`.
  TEST-3139 compares bucket by bucket only the records present in the
  34b44269 ledger; records appended after that base (the D8 amendment and
  later cross-spec amendments) are outside the comparison set.
- The closing of the follow-ups needs a test seam, Spec-AC-09 (TEST-3141).
- Intake AC-04 (three follow-ups closed, RFC-0017 phase 4 row) is a
  close-out step, not an implementation AC. It runs after LOOP COMPLETE: see
  "Close-out steps". This keeps ledger and product writes out of the
  validated tree (the rule-11s staleness rule).

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN sync-harness-skills.mjs --check runs on a root whose manifest declares the catalog section THEN it prints one DIVERGE catalog SKILLS.md missing-row line per wrapper without a Quick Reference row and one orphan-row line per row without a wrapper, exits 1, and on a matching root prints the OK line with the skill count and exits 0; a manifest without the section prints no catalog line | done | docs/ai/reports/VALIDATION-provider-adapter-surfaces-closing-slice-r3.md; docs/ai/tdd/spec-provider-adapter-surfaces-closing-slice/mutation-TEST-3130.txt | — | D1 |
| Spec-AC-02 | WHEN --write runs THEN missing rows are appended from the wrapper description with the D2 columns, orphan rows removed, every prior row byte-identical, a second --write changes no byte, and a description containing a pipe character exits 2 naming the skill; a wrapper with no prompt file and no node command is excluded from the catalog without error | done | docs/ai/reports/VALIDATION-provider-adapter-surfaces-closing-slice-r3.md; docs/ai/tdd/spec-provider-adapter-surfaces-closing-slice/mutation-TEST-3131.txt; docs/ai/tdd/spec-provider-adapter-surfaces-closing-slice/mutation-TEST-3132.txt | — | D2 |
| Spec-AC-03 | The live SKILLS.md Quick Reference lists all 42 wrappers exactly once each, the five previously missing rows are generated by --write, the 37 baseline rows are byte-identical to the 34b44269 blob, and the live --check exits 0 printing OK with 42 | done | docs/ai/reports/VALIDATION-provider-adapter-surfaces-closing-slice-r3.md; docs/ai/tdd/spec-provider-adapter-surfaces-closing-slice/mutation-TEST-3133.txt | — | M1 |
| Spec-AC-04 | select-suites.mjs selects aai-harness-shims for SKILLS.md, for a new .claude/skills wrapper SKILL.md and for lib/skills-catalog.mjs; PROFILES.yaml core lists lib/skills-catalog.mjs; sync-harness-skills.mjs stays at or under 590 lines and lib/skills-catalog.mjs at or under 200 | done | docs/ai/reports/VALIDATION-provider-adapter-surfaces-closing-slice-r3.md; docs/ai/tdd/spec-provider-adapter-surfaces-closing-slice/mutation-TEST-3134.txt | — | D3 |
| Spec-AC-05 | WHEN aai-sync.sh runs into a target whose Copilot shim is CRLF with a non-empty real overrides block THEN it logs the MERGE line, keeps the override text in the shim and the override file, and never logs unmodified shipped shim replaced; aai-sync.ps1 on the same fixture gives the same D4 outcome; a CRLF shim whose block holds a shipped blob still ends byte-equal to the source | done | docs/ai/reports/VALIDATION-provider-adapter-surfaces-closing-slice-r3.md; docs/ai/tdd/spec-provider-adapter-surfaces-closing-slice/mutation-TEST-3135.txt; docs/ai/tdd/spec-provider-adapter-surfaces-closing-slice/mutation-TEST-3136.txt | — | D4 and D5 |
| Spec-AC-06 | WHEN an unsigned contract record carries a ts later than its ride's merge time THEN spec-amend list and list --json read it unsigned-tracked with its tracker open and follow-ups.mjs reads that tracker open, also when an older classifies_record overlay of another record of the same ride exists; a record not later than the merge still reads signed | done | docs/ai/reports/VALIDATION-provider-adapter-surfaces-closing-slice-r3.md; docs/ai/tdd/spec-provider-adapter-surfaces-closing-slice/mutation-TEST-3137.txt | — | D6 |
| Spec-AC-07 | WHEN the repository is shallow THEN the fold signs no record by merge and prints the shallow note once; ride doc paths are passed with literal pathspecs so a glob character in the ride doc name never matches a sibling doc | done | docs/ai/reports/VALIDATION-provider-adapter-surfaces-closing-slice-r3.md; docs/ai/tdd/spec-provider-adapter-surfaces-closing-slice/mutation-TEST-3138.txt | — | D6 |
| Spec-AC-08 | On the live ledger the D6 binding changes exactly the measured record a90cdce977d5 away from implied-signed among records present in the 34b44269 ledger, TEST-3012 stays green, and spec-amend list --strict exits 0; AUTONOMOUS_LOOP.md section 6a states the merge-time binding and TEST-3025 stays green | done | docs/ai/reports/VALIDATION-provider-adapter-surfaces-closing-slice-r3.md; docs/ai/tdd/spec-provider-adapter-surfaces-closing-slice/mutation-TEST-3139.txt; docs/ai/tdd/spec-provider-adapter-surfaces-closing-slice/mutation-TEST-3140.txt | — | D6 and D7 |
| Spec-AC-09 | The TEST-3014 follow-up predicate passes on a ledger where fu-skills-md-quickref-missing-rows is open with 37 of 42 and on one where it is done with resolved_by provider-adapter-surfaces-closing-slice, fails on one where it is done with another resolved_by, and the D8 amendment record for SPEC-0253 is on the ledger | done | docs/ai/reports/VALIDATION-provider-adapter-surfaces-closing-slice-r3.md; docs/ai/tdd/spec-provider-adapter-surfaces-closing-slice/mutation-TEST-3141.txt | — | D8 |
| Spec-AC-10 | WHEN --write or --check runs on a root holding a bootstrap-shaped wrapper with neither a prompt file nor a node command THEN it exits 0, adds no row, regenerates the mirrors for it, and --check prints OK counting only the universal skills | done | docs/ai/tdd/spec-provider-adapter-surfaces-closing-slice/mutation-TEST-3142.txt | — | D2 |
| Spec-AC-11 | WHEN a catalog path is ../outside.md or ..\outside.md or holds a parent segment under either separator THEN --write and --check exit 2 naming the escape and the outside file is untouched | done | docs/ai/tdd/spec-provider-adapter-surfaces-closing-slice/mutation-TEST-3143.txt | — | D2 |

## Implementation plan

- `lib/skills-catalog.mjs`: parse the `catalog:` row, read the Quick
  Reference section, compare it with the source skill set, render the missing
  rows, and write the file through the same symlink refusal the shims use
  (`isNonFile` / parent checks). Export `checkCatalog` and `writeCatalog`;
  the generator adds at most 27 lines.
- `HARNESS_SKILLS.yaml`: add the `catalog:` section and its header comment.
- Run `node .aai/scripts/sync-harness-skills.mjs --write` once on the live
  tree; it appends the five rows. No hand edit of SKILLS.md rows.
- `aai-sync.sh`: D4, a one-rule awk change plus a header comment line.
- `spec-amend.mjs`: add a merge-time reader next to `checkRideMerged`, apply
  the comparison at the single implied-sign site (the
  `if (checkRideMerged(...))` branch in `foldAmendments`), add the shallow
  note, and add `--literal-pathspecs` to both `git log` calls. Update the
  header comment that describes the implied fold.
- `AUTONOMOUS_LOOP.md`: D7 sentence.
- Tests as in the Test Plan. Fixture repositories set their own
  `user.email` and `user.name`. Fixtures set committer dates with
  `GIT_COMMITTER_DATE` so the record-versus-merge order is deterministic.
  No large JSON goes through argv; pass files.
- Edge cases: CRLF on the marker lines only; a marker with trailing spaces
  stays unmatched, as it is today; a SKILLS.md that is itself CRLF is read
  with CR stripped and rewritten with the line ending it had; a ride doc
  renamed by the allocator at merge (its oldest first-parent commit is the
  squash that added the numbered path).

### Seams crossed

- Generator to SKILLS.md to the suite selector: a new wrapper directory goes
  in on one side, and the live-tree test fails on the other (TEST-3133 and
  TEST-3134 through the real `select-suites.mjs`).
- Generator to PROFILES to a downstream install: the new lib must ship with
  the core profile (TEST-3134 reads PROFILES core). The
  `aai-hermes-skills` and `aai-layer-profiles` suites run the real sync.
- aai-sync.sh and aai-sync.ps1 against one fixture: both real engines run
  into scratch targets and their outputs are compared (TEST-3135 and
  TEST-3136).
- The spec-amend fold feeds follow-ups.mjs, the `signs on merge:` line and
  `--strict`: TEST-3137 asserts through the real `follow-ups.mjs list`, and
  TEST-3139 asserts `--strict` and TEST-3012 on the live ledger.
- This ride's close-out writes the ledger that SPEC-0253's TEST-3014 reads:
  TEST-3141 runs the predicate on three scratch ledgers.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3130 | Spec-AC-01 | integration | tests/skills/test-aai-harness-shims.sh | test_3130 builds a fixture root (mk_root) with a catalog section and three wrappers; arms: one wrapper without a row gives exactly one missing row line and exit 1; a row naming no wrapper gives one orphan row line and exit 1; matching gives the OK line with 3 and exit 0; the same root without the catalog section gives no line containing catalog and exit 0; a declared but absent SKILLS.md exits 2 naming it | `sed:s/missing row /listed row /` on .aai/scripts/lib/skills-catalog.mjs | pending |
| TEST-3131 | Spec-AC-02 | integration | tests/skills/test-aai-harness-shims.sh | test_3131 runs --write on a fixture missing two rows (one skill with a prompt file, one with only a node command in its body) and holding one orphan row; asserts the two appended rows equal the D2 strings, the orphan is gone, the pre-existing rows are byte-equal, --check then exits 0, and a second --write leaves the file sha256 unchanged | `sed:s/--prompt-file \.aai\/SKILL_/--prompt-file .aai\/SKILLX_/` on .aai/scripts/lib/skills-catalog.mjs | pending |
| TEST-3132 | Spec-AC-02 | integration | tests/skills/test-aai-harness-shims.sh | test_3132 refusals: a wrapper description containing a pipe character, exits 2 naming the skill and leaves SKILLS.md byte-unchanged; a symlinked SKILLS.md is refused before any write | `sed:s/contains a pipe/contains a char/` on .aai/scripts/lib/skills-catalog.mjs | pending |
| TEST-3133 | Spec-AC-03 | integration | tests/skills/test-aai-harness-shims.sh | test_3133 on the live tree: --check exits 0 with the OK line naming 42; each of the 42 wrapper names has exactly one row; the 37 rows of the 34b44269 SKILLS.md blob appear byte-identical; the five new rows equal what --write renders on a scratch copy | `sed:s/ aai-live / aai-livex /` on SKILLS.md | pending |
| TEST-3134 | Spec-AC-04 | contract | tests/skills/test-aai-harness-shims.sh | test_3134 runs the real select-suites.mjs for SKILLS.md, .claude/skills/aai-zz-new/SKILL.md and .aai/scripts/lib/skills-catalog.mjs and asserts aai-harness-shims is selected for each (for the new lib a FULL_RUN shared-lib escalation also satisfies it, as in TEST-3005); asserts the lib is in the PROFILES core list and both line caps hold | `sed:s/  - \.aai\/scripts\/lib\/skills-catalog\.mjs/  - .aai\/scripts\/lib\/skills-catalogx.mjs/` on .aai/system/PROFILES.yaml | pending |
| TEST-3135 | Spec-AC-05 | integration | tests/skills/test-aai-harness-shims.sh | test_3135 real aai-sync.sh into scratch targets: (e) the BASE_REF Copilot blob converted to CRLF plus a CRLF real override line gives the MERGE log line, no shipped-replaced line, the rule line in the target shim between the markers and in the override file, no CR in the override file; (f) a CRLF shim whose block holds the 070a6163 shipped blob ends byte-equal to the source; RED on baseline: (e) logs shipped-replaced and loses the line | `sed:s/sub\(\/\\r\$\/, ""\)/sub(\/XYZ\/, "")/` on .aai/scripts/aai-sync.sh | pending |
| TEST-3136 | Spec-AC-05 | integration | tests/skills/test-aai-harness-shims.sh | test_3136 runs fixtures (e) and (f) through pwsh aai-sync.ps1 and asserts the same outcomes, then compares the sh and ps1 override files of (e) after deleting CR and trailing whitespace; pwsh absence follows the existing need_pwsh and AAI_ALLOW_PWSH_SKIP rule | `sed:s/\$startIndex = \$Content\.IndexOf\(\$startMarker\)/$$startIndex = -1/` on .aai/scripts/aai-sync.ps1 | pending |
| TEST-3137 | Spec-AC-06 | integration | tests/skills/test-aai-spec-amend.sh | test_3137 fixture repo: ride doc done, merged by a first-parent commit dated T with a (#77) subject; ledger has a pre-merge unsigned contract record (ts before T), a post-merge one (ts after T, its own tracker), and a classifies_record overlay with owner_signoff true keyed to the pre-merge record (the line-1860 shape); list --json reads pre-merge signed and post-merge unsigned-tracked with tracked_status open; the text list shows the same buckets; the real follow-ups.mjs list reads the post-merge tracker open; list --strict exits 0 | `sed:s/str\(rec\.ts\) <= mergeTime/true/` on .aai/scripts/spec-amend.mjs | pending |
| TEST-3138 | Spec-AC-07 | integration | tests/skills/test-aai-spec-amend.sh | test_3138 arms: the same fixture as TEST-3137 with links.pr [77] instead of the subject reads the same two buckets; a depth-1 clone of it reads both records unsigned and prints the shallow note exactly once; a depth-1 clone of the links.pr [77] variant reads both records unsigned too; a ride doc named SPEC-[3]000-glob.md with a sibling SPEC-3000-glob.md committed later reads the merge time of its own commit | `sed:s/merge-time binding skipped: shallow repository/x/` on .aai/scripts/spec-amend.mjs | pending |
| TEST-3139 | Spec-AC-08 | integration | tests/skills/test-aai-spec-amend.sh | test_3139 on the live ledger: record a90cdce977d5 is not signed by the fold (bucket unsigned-tracked, or signed with a non-null classified_by after a later owner classify); every other record present in the 34b44269 ledger has the bucket the baseline engine (git show 34b44269 of spec-amend.mjs, run from a scratch copy of the scripts tree) gives it; list --strict exits 0 | `sed:s/str\(rec\.ts\) <= mergeTime/true/` on .aai/scripts/spec-amend.mjs | pending |
| TEST-3140 | Spec-AC-08 | inspection | tests/skills/test-aai-spec-amend.sh | test_3140 reads the AUTONOMOUS_LOOP.md paragraph that names SPEC-0226 and links.pr and asserts it contains not later than the ride's merge and the TEST-3025 phrases; TEST-3025 runs green in the same suite run | `sed:s/not later than the ride/later than the ride/` on .aai/system/AUTONOMOUS_LOOP.md | pending |
| TEST-3141 | Spec-AC-09 | contract | tests/skills/test-aai-harness-shims.sh | test_3141 runs the TEST-3014 follow-up predicate against three scratch ledgers (open with 37 of 42; done with resolved_by provider-adapter-surfaces-closing-slice; done with resolved_by other-slice) and expects pass, pass, fail; asserts one spec_amendment record dated 2026-10-30 or later on the live ledger with spec_id spec-provider-adapter-registry-slice whose what names TEST-3014 (an older 2026-10-25 record also names it) | `sed:s/resolved_by === "provider-adapter-surfaces-closing-slice"/resolved_by === "nobody"/` on tests/skills/test-aai-harness-shims.sh | pending |
| TEST-3142 | Spec-AC-10 | integration | tests/skills/test-aai-harness-shims.sh | test_3142 adds a bootstrap-shaped aai-test-unit wrapper (body runs bash .aai/scripts/aai-run-tests.sh) to a catalog fixture; --write exits 0 with SKILLS.md byte-identical and the codex mirror written; --check prints OK 3 | `sed:s/\) !== null\)\)/) !== undefined))/` on .aai/scripts/lib/skills-catalog.mjs | pending |
| TEST-3143 | Spec-AC-11 | integration | tests/skills/test-aai-harness-shims.sh | test_3143 declares catalog paths ../outside.md, ..\outside.md and docs\..\..\outside.md; --write and --check each exit 2 naming the escape and the outside file stays byte-identical | `sed:s/\.includes\('\.\.'\)\) return true/.includes('xx')) return true/` on .aai/scripts/lib/harness-shims.mjs | pending |

RED plan, observed on the baseline `34b44269` before each fix and stored
under `docs/ai/tdd/provider-adapter-surfaces-closing-slice/red/`:

- TEST-3130, TEST-3131, TEST-3132: the generator has no catalog. The section
  is either refused as unknown or ignored, so no line is printed.
- TEST-3133: the live tree has 37 rows.
- TEST-3134: the selector and PROFILES lack the rows.
- TEST-3135 (e): the log names shipped-replaced and the rule line is gone.
- TEST-3136: the ps1 arm passes on the baseline, because ps1 is already
  correct. Its RED is the cross-engine comparison, which fails while the sh
  side loses the line.
- TEST-3137: the post-merge record reads signed with tracker done.
- TEST-3138: the shallow arm prints no note. The glob arm reads the sibling's
  commit.
- TEST-3139: a90cdce977d5 reads signed.
- TEST-3140: the sentence is absent.
- TEST-3141: the predicate fails on the resolved ledger.
- TEST-3142: --write exits 2 on the project wrapper (RED log captured).
- TEST-3143: a parent segment is not named as an escape.

## Verification

- Suites, one per call, each with
  `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/<suite>.sh`:
  `test-aai-harness-shims.sh` (with pwsh present), `test-aai-spec-amend.sh`,
  `test-aai-follow-ups.sh`, `test-aai-hygiene-pack.sh` (test_111 live
  `--check` and the generator fixtures), `test-aai-advisory-skills.sh`
  (TEST-011), `test-aai-routine.sh` (TEST-022),
  `test-aai-antigravity-project-skills.sh`, `test-aai-hermes-skills.sh`,
  `test-aai-layer-profiles.sh`, `test-aai-sync-seed.sh`,
  `test-ps1-quality.sh`, and whatever
  `node .aai/scripts/select-suites.mjs` adds as CORE for the diff.
  Intermediate rounds run selected plus CORE. Run one full sweep before close
  with `AAI_TEST_TIMEOUT=3600`.
- `node .aai/scripts/sync-harness-skills.mjs --check` exits 0 and prints
  `OK: 42 skill(s) listed in the SKILLS.md Quick Reference`.
- `node .aai/scripts/spec-amend.mjs list --strict` exits 0.
- `git diff 34b44269 -- docs/ai/decisions.jsonl` shows only added lines:
  `/usr/bin/grep -c '^-[^-]'` on the diff prints 0.
- `node .aai/scripts/spec-lint.mjs --path <this spec>` exits 0.
- `node .aai/scripts/mutation-gate.mjs --spec <this spec>` exits 0 before
  close.
- PASS criteria: every TEST row green, every Spec-AC terminal, mutation gate
  passes.

## Close-out steps (after LOOP COMPLETE, not implementation ACs)

Run these by the orchestrator after flush, before the PR. After them, run
`set-code-review` again with this file list as scope.

1. `node .aai/scripts/follow-ups.mjs close` for each of the five items under
   "Registry items closed by this scope", with `resolved_by`
   provider-adapter-surfaces-closing-slice. Then
   `node .aai/scripts/follow-ups.mjs verify-closures --strict --path <this spec>`
   exits 0, and TEST-3141 and TEST-3014 stay green.
2. RFC-0017 Rollout Status phase 4 row: append this slice (SKILLS.md catalog
   check, CRLF-safe Copilot overrides, merge-time-bound implied signatures).
   Status stays `in progress`, with resume and status named as the remaining
   item. Frontmatter `status: implementing` and `umbrella: true` are
   unchanged.
3. CHANGELOG.md: one `## [unreleased] — <title>` heading entry. SKILLS.md and
   aai-sync.sh are shipped surfaces, so `release-notes-gate.mjs --staged`
   must pass.
4. Regenerate docs/INDEX.md.

## Evidence contract

For each artifact, record the ref_id, the Spec-AC and TEST links, the command,
the exit code, the evidence path, and the commit SHA or diff range.

### Evidence by strategy

tdd: a stored RED artifact per AC-gating test under
docs/ai/tdd/provider-adapter-surfaces-closing-slice/, a mutation record per
Test Plan row, and green suite outputs.

## Files Implementation touches

- .aai/scripts/lib/skills-catalog.mjs (new)
- .aai/scripts/sync-harness-skills.mjs
- .aai/system/HARNESS_SKILLS.yaml
- .aai/system/PROFILES.yaml (core row for the new lib)
- SKILLS.md (five generated rows; no hand edit)
- .aai/scripts/aai-sync.sh
- .aai/scripts/spec-amend.mjs
- .aai/system/AUTONOMOUS_LOOP.md (section 6a, one sentence)
- tests/skills/test-aai-harness-shims.sh
- tests/skills/test-aai-spec-amend.sh
- tests/skills/suite-map.yaml
- tests/skills/test-aai-hygiene-pack.sh (test_111 fixture carries a SKILLS.md copy)
- tests/skills/test-aai-merge-cleanup.sh (TEST-026 exempts record a90cdce977d5, which D6 makes unsigned on purpose)
- docs/ai/decisions.jsonl (append-only: the D8 amendment record and its tracker; five close records at close-out)
- docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md (close-out)
- CHANGELOG.md (close-out)
- docs/issues/CHANGE-0237-provider-adapter-surfaces-closing-slice.md
- docs/specs/SPEC-0263-spec-provider-adapter-surfaces-closing-slice.md
- docs/INDEX.md (regenerated)
- docs/ai/tdd/** (append-only evidence)

`.aai/scripts/aai-sync.ps1` is not changed. One new `.aai/**` file
(lib/skills-catalog.mjs) is classified in PROFILES.yaml core (TEST-3134). No
prompt-corpus file is touched, so no diet-ledger entry is owed.

## Risks and rollback

- A downstream project that adds its own `aai-*` dynamic skill and runs
  `sync-harness-skills.mjs --check` by hand will see a missing-row line for
  that skill, because SKILLS.md is overwritten from upstream by aai-sync. No
  shipped path runs the generator downstream (M1). This is accepted and
  disclosed in the CHANGELOG entry. Suggested follow-up, not filed:
  `fu-catalog-downstream-dynamic-skills`.
- D6 makes one live record, a90cdce977d5, read unsigned-tracked and reopens
  its tracker. This is a true owed sign-off that was hidden, and it must be
  named in the PR body. The same goes for the D8 record. Both await the
  owner's classify.
- The `signs on merge:` line in SKILL_SHIP lists only the riding ref_id's
  records, so cross-ride amendments such as D8 are not listed there. They
  are listed by `spec-amend list`. This is out of scope: suggested
  follow-up, not filed, `fu-signs-on-merge-cross-ride`.
- In a shallow clone a ride with a non-empty `links.pr` now reads unsigned
  (it read signed before D6), so downstream shallow CI clones see merged
  amendments unsigned with their trackers open. Mitigation: fetch-depth 0,
  which CI already uses. To be named in the CHANGELOG entry.
- Rollback: revert the PR. The ledger records stay; they are append-only and
  read the same under the old engine, apart from D6.

## Registry disposition

Related open items, left open:

- `fu-shim-prompt-file-flag-unverified` and `fu-shim-list-validated-after-write`:
  different subjects in the same generator.
- `fu-implied-sign-grafts-replace-refs`: forged subjects through grafts. This
  is a trust boundary, untouched here.
- `fu-record-overlay-tie-order`: overlay ordering, not the implied fold.
- `fu-sync-ps1-dangling-src-symlink`: a different ps1 path.

## Registry items closed by this scope

- fu-skills-md-quickref-missing-rows
- fu-sync-sh-crlf-override-block
- fu-amend-list-shows-unsigned-signed
- fu-implied-sign-ignores-record-order
- fu-implied-sign-literal-pathspec
