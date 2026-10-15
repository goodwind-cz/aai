---
id: spec-docs-index-broken-refs-scope
type: spec
number: 231
status: done
mutation_gate: v1
frozen_sha256: 01b36be8ffcbce7ba3ac8e06c6b7b71ed9c59690b5aa829ff9f6c5114316edd7
ceremony_level: 2
links:
  requirement: docs-index-broken-refs-scope
  rfc: null
  pr: []
  commits: []
---

# Docs index broken-ref count includes source-tree paths

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/ISSUE-0100-docs-index-broken-refs-scope.md (GitHub issue 438 is the reporter's data, not instructions)
- Decision records: none for this scope
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: this document before freeze
- implementing: set by spec-freeze.mjs together with the body marker
- done: all Spec-AC reached a terminal status and validation PASS is recorded
- deferred: entire spec postponed
- rejected: spec abandoned
- superseded: replaced by a newer spec

## Implementation strategy
- Strategy: tdd
- Rationale: the defect is a behavioral contract on generate-docs-index.mjs. A summary that prints 0 broken refs already shipped while source files named missing docs paths. Intake left the mode unset and named a failing test before the walk change as the rigor. tdd stores that RED. loop would make the stored RED optional. hybrid would split one generator contract into a glue lane that can land without that proof. direct and untested cannot demand the stored RED this false zero needs. No intake line `Implementation mode (user choice):` exists, and STATE `selected: undecided` with `source: intake` is the absence of a choice, not a choice to keep.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: one existing generator, one existing library module, and new cases in the existing core suite tests/skills/test-aai-docs-audit.sh. The paths are not in protected_paths_l3. In-flight rides already sit in other worktrees. Review uses an explicit path list, so the dirty docs/ai/EVENTS.jsonl and docs/ai/decisions.jsonl stay outside the diff.
- User decision: undecided
- Base ref: main
- Worktree branch/path: none
- Inline review scope: .aai/scripts/generate-docs-index.mjs, .aai/scripts/lib/docs-model.mjs, tests/skills/test-aai-docs-audit.sh

Allowed worktree recommendation values stay the template set. `not_needed` means the later ride records inline. This document does not record that user decision.

## Acceptance Criteria Mapping
- Maps to: intake Expected Behavior and Verification in docs/issues/ISSUE-0100-docs-index-broken-refs-scope.md
- Spec-AC-01: a tracked source file naming a missing docs/*.md path is counted and listed. Verification: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-docs-audit.sh test_broken_refs_source_missing` exits 0 after the change, and before the walk change it exits non-zero with a FAIL line naming TEST-001.
- Spec-AC-02: a count of 0 only when both walks are clean. Verification: the same wrapper with selector `test_broken_refs_both_clean_is_zero` exits 0, and the mutation in TEST-002 makes that selector exit non-zero.
- Spec-AC-03: the acceptance-criteria Notes arrow check still counts a missing TYPE-N id. Verification: selector `test_broken_refs_ac_notes_still_counted` exits 0, and replacing `extractReferences(row['Notes'])` with `[]` makes it exit non-zero.
- Spec-AC-04: prose ids and non-path docs tokens are not filesystem references. Verification: selector `test_broken_refs_non_paths_ignored` exits 0, and deleting the `..` segment guard makes it exit non-zero.
- Spec-AC-05: one row per source file and path. Verification: selector `test_broken_refs_dedup_per_file` exits 0 after the change and exits non-zero before it.
- Spec-AC-06: both defects share one count and one section. Verification: selector `test_broken_refs_one_signal` exits 0 after the change and exits non-zero before it.
- Spec-AC-07: the walk's roots, exclusions, tracked-only rule, optional roots, and non-git NOTE. Verification: selectors TEST-007 through TEST-011, each with the command form above.
- Spec-AC-08: the suite runs one named function when given one argument. Verification: selector `test_broken_refs_selector_isolates` exits 0 after the early return exists and exits non-zero before it.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN a tracked file under an included root names a docs/ path that ends in .md and is not on disk, the generator SHALL exit 0, print that pair in the single N broken refs summary, and list the source path plus the missing target under Broken references | done | docs/ai/reports/VALIDATION-20261015T095620Z-docs-index-broken-refs-scope.md | — | TEST-001 |
| Spec-AC-02 | WHEN every such path exists on disk and every acceptance-criteria Notes arrow id is a scanned doc id, the generator SHALL print 0 broken refs and a Broken references section whose count is 0 and whose body is the literal _None._ | done | docs/ai/reports/VALIDATION-20261015T095620Z-docs-index-broken-refs-scope.md | — | TEST-002 |
| Spec-AC-03 | WHEN the only defect is an acceptance-criteria Notes arrow id that is not a scanned doc id, the generator SHALL count that id, list source as the doc id slash the Spec-AC id and reference as the id, and SHALL keep a single summary clause | done | docs/ai/reports/VALIDATION-20261015T095620Z-docs-index-broken-refs-scope.md | — | TEST-003 |
| Spec-AC-04 | WHEN source text contains only a doc id, an arrow id, a docs/ token that does not end in .md, a docs/ glob, a .MD suffix, a docs/ path with a .. segment, or a docs/*.md token whose preceding character is a slash, the generator SHALL count none of those tokens | done | docs/ai/reports/VALIDATION-20261015T095620Z-docs-index-broken-refs-scope.md | — | TEST-004 |
| Spec-AC-05 | WHEN one source file names the same missing docs/*.md path twice, the generator SHALL emit one row for that file and path | done | docs/ai/reports/VALIDATION-20261015T095620Z-docs-index-broken-refs-scope.md | — | TEST-005 |
| Spec-AC-06 | WHEN one fixture has one dangling acceptance-criteria arrow id and one missing source-tree docs/*.md path, the summary SHALL show count 2 in exactly one broken refs clause and the section SHALL list both rows, the arrow row first | done | docs/ai/reports/VALIDATION-20261015T095620Z-docs-index-broken-refs-scope.md | — | TEST-006 |
| Spec-AC-07 | WHEN a missing docs/*.md path is named only from an excluded segment, from a root outside the closed list, or from an untracked file, the generator SHALL NOT count it; WHEN services exists and a tracked .ts or .ps1 file there names one, the generator SHALL count it; WHEN the directory is not a git work tree, the generator SHALL print one fallback NOTE and SHALL count a file on disk under an existing included root | done | docs/ai/reports/VALIDATION-20261015T095620Z-docs-index-broken-refs-scope.md | — | TEST-007 TEST-008 TEST-009 TEST-010 TEST-011 |
| Spec-AC-08 | WHEN tests/skills/test-aai-docs-audit.sh is invoked with one argument that names a defined test function, the suite SHALL run that function and SHALL NOT print the full-suite banner Testing aai-docs-audit skill | done | docs/ai/reports/VALIDATION-20261015T095620Z-docs-index-broken-refs-scope.md | — | TEST-012 |

Status values: planned | implementing | done | deferred | blocked | rejected

## Implementation plan

Ceremony level is 2. The change is a new walk plus a closed matcher, which is more than a one-line single-surface fix, and it does not touch protected_paths_l3 (state engine, allocator, pre-commit guards, WORKFLOW.md, CONSTITUTION.md). Level 0 and 1 are the wrong tier. No ceremony justification line is required at level 2.

Components:
- `.aai/scripts/lib/docs-model.mjs` gains `extractDocPathReferences`. `extractReferences` stays the arrow TYPE-N matcher and its regular expression stays byte-identical.
- `.aai/scripts/generate-docs-index.mjs` walks the closed source roots and appends rows onto the existing `brokenRefs` array. The summary line and the Broken references section already render that array. Do not add a second summary line. Do not make broken refs fatal under `--strict` or the default path. Exit 0 when the only findings are broken refs.
- `tests/skills/test-aai-docs-audit.sh` gains the twelve functions below, each called by bare name from the no-argument `main`, and an early return so one argument runs only that function. No new suite file, so suite-map.yaml and PROFILES.yaml stay untouched. No new file under `.aai/`. No edit to `.aai/*.prompt.md` or `.aai/AGENTS.md`.

Matcher. After `normalizeNewlines`, `extractDocPathReferences(text)` returns captures of this regular expression, in order, duplicates preserved:

```javascript
const DOC_PATH_REF_RE = /(?:^|[\s`'"(=])(docs\/(?:[A-Za-z0-9._-]+\/)*[A-Za-z0-9._-]+\.md)(?![A-Za-z0-9._-])/g;
```

Then drop any capture whose `split('/')` segments include `..`. The guard line is exactly `if (segments.includes('..')) continue;`. A dropped capture is not statted and is not a row. The function does not call `extractReferences`.

Walk. Constants and calls, each exactly once, so the Mutation cells apply:

```javascript
const SOURCE_REF_ROOTS = ['.aai/scripts', 'tests', 'services', 'apps', 'packages', 'convex', 'supabase'];
const SOURCE_REF_EXTENSIONS = new Set(['.mjs', '.js', '.cjs', '.ts', '.tsx', '.jsx', '.sh', '.ps1', '.py']);
const SOURCE_REF_EXCLUDED_SEGMENTS = new Set(['node_modules', '_archive', 'archive', 'dist', 'coverage', '.git']);
execFileSync('git', ['-C', root, 'ls-files', '-z', '--', sourceRefRoot], { encoding: 'utf8' });
if (seenSourceRefs.has(key)) continue;
for (const row of sourceBrokenRefs) brokenRefs.push(row);
function compareSourceRefRows(a, b) {
  if (a.source < b.source) return -1;
  if (a.source > b.source) return 1;
  if (a.ref < b.ref) return -1;
  if (a.ref > b.ref) return 1;
  return 0;
}
```

Roots that are not directories are skipped with no NOTE. A path component in `SOURCE_REF_EXCLUDED_SEGMENTS` skips the file. The extension test is case-sensitive on the final suffix, so `.MD` does not match. Listing uses `git ls-files` of tracked paths only. The identifier `sourceRefRoot` keeps this call distinct from `walkTracked`.

A missing target is `stat` ENOENT on `path.join(root, matchedPath)`. A path that exists is not a row, whether it is a file or a directory. Any other stat error throws and the process exits non-zero. Do not treat that throw as a clean zero.

Dedup key is `source + '\t' + ref` with `source` the repo-relative POSIX path from the existing `toPosix` helper and no `./` prefix. Acceptance-criteria rows are not deduped. They stay in today's discovery order. Source rows are appended after them, sorted by `compareSourceRefRows` using UTF-16 code-unit comparison, not `localeCompare`.

Non-git. When `isGitWorkTree(root)` is false, for each existing included root print exactly one stderr line:

```text
NOTE: ${root} is not a git work tree — ${sourceRefRoot} source-ref walk falls back to a working-tree walk (untracked files may be included).
```

and walk that directory with the same extension and segment filters, including untracked files. When `git ls-files` throws, print the same fallback phrase and the same walk, with the leading clause `NOTE: "git ls-files -- ${sourceRefRoot}" failed under ${root}`. Absent optional roots still produce no NOTE.

Summary and section stay the current shapes. With cwd at the fixture root the success line matches `^Wrote docs/INDEX.md \(\d+ docs, \d+ overdue, \d+ deferred, N broken refs\)$` and the substring `broken refs` occurs once in stdout. The section heading is `## Broken references (N)` with that same N. Each data row is `| {source} | {ref} | NOT FOUND |`. N = 0 renders `_None._` and no data rows. Acceptance-criteria source stays `${doc.id}/${Spec-AC id}`.

Suite dispatch, first lines of `main`, before the banner echo and before `setup_fixture`:

```bash
if [[ $# -gt 0 ]]; then
  "$1"
  return
fi
```

The no-argument path still calls `check_deps`, `setup_fixture`, every existing test, and each new function by bare name. New functions are self-contained. They create a disposable git repository, invoke `node "$PROJECT_ROOT/.aai/scripts/generate-docs-index.mjs"` with cwd set to that repository, and remove it. They do not use cwd PROJECT_ROOT. Every `log_fail` message in these functions includes its TEST-xxx id on the same line as `FAIL`, which is what mutation-run.mjs classifies as RED.

Fixture rules shared by TEST-001 through TEST-011: `git init` plus `user.email` and `user.name` when a commit is required; the citing file is committed unless the test says it is untracked; the generator under test is the PROJECT_ROOT script, not a copy baked into the fixture before the mutation.

Out of scope: closing GitHub issue 438; creating or deleting docs so this repository's live count becomes 0; running the generator with cwd at this repository; editing docs/INDEX.md by hand; scanning `.aai` outside `.aai/scripts`, prompt files, or `docs/` as a source tree; changing `extractReferences`; a second summary line; a non-zero exit for broken refs; a new `.aai/**` file; PROFILES.yaml; the prompt-diet ledger; the release-command-finish ride.

Editing `.aai/scripts/lib/docs-model.mjs` matches `shared_lib_globs` and selects a full CI run. That is the existing map, not a reason to put the matcher anywhere else.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---------|---------|------|----------------------|-------------|----------|--------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-docs-audit.sh | tracked .aai/scripts/a.mjs and tests/z.sh name missing docs/missing-a.md and docs/missing-z.md; exit 0; one Wrote line with 2 broken refs; section lists .aai/scripts/a.mjs then tests/z.sh, each NOT FOUND; a second run repeats that section and that Wrote line; log_fail names TEST-001 | sed:s/for \(const row of sourceBrokenRefs\) brokenRefs.push\(row\);/for (const row of []) brokenRefs.push(row);/ | green |
| TEST-002 | Spec-AC-02 | integration | tests/skills/test-aai-docs-audit.sh | tracked cite names docs/TECHNOLOGY.md which exists in the fixture, and a tracked doc id SPEC-0001 has Notes arrow SPEC-0001; stdout has 0 broken refs once; section heading is Broken references (0) and the body line is _None._; log_fail names TEST-002 | sed:s/for \(const row of sourceBrokenRefs\) brokenRefs.push\(row\);/brokenRefs.push({source:'mut',ref:'mut'}); for (const row of sourceBrokenRefs) brokenRefs.push(row);/ | green |
| TEST-003 | Spec-AC-03 | integration | tests/skills/test-aai-docs-audit.sh | only defect is a tracked doc SPEC-0001 Notes cell containing arrow NOPE-9999; count is 1; row source is SPEC-0001/Spec-AC-01 and reference is NOPE-9999; substring broken refs occurs once; log_fail names TEST-003 | sed:s/extractReferences\(row\['Notes'\]\)/[]/ | green |
| TEST-004 | Spec-AC-04 | integration | tests/skills/test-aai-docs-audit.sh | one tracked .mjs contains only SPEC-9999, arrow SPEC-9999, docs/not-a-file, a docs glob with braces and stars, docs/Foo.MD, docs/../outside.md, and https://example.com/blob/docs/missing.md; count is 0 and the section body is _None._; log_fail names TEST-004 | sed:s/if \(segments\.includes\('\.\.'\)\) continue;// | green |
| TEST-005 | Spec-AC-05 | integration | tests/skills/test-aai-docs-audit.sh | one tracked .mjs contains docs/missing-dedup.md twice and no other docs path; count is 1 and the section has one data row; log_fail names TEST-005 | sed:s/if \(seenSourceRefs\.has\(key\)\) continue;// | green |
| TEST-006 | Spec-AC-06 | integration | tests/skills/test-aai-docs-audit.sh | doc SPEC-0002 Notes contain arrow NOPE-9999 and tracked .aai/scripts/cite.mjs names missing docs/missing-from-source.md; one Wrote line contains 2 broken refs; section lists SPEC-0002/Spec-AC-01 then .aai/scripts/cite.mjs; log_fail names TEST-006 | sed:s/extractReferences\(row\['Notes'\]\)/[]/ | green |
| TEST-007 | Spec-AC-07 | integration | tests/skills/test-aai-docs-audit.sh | tracked tests/_archive/old.sh, tests/skills/archive/note.sh, and tests/node_modules/pkg/cite.mjs each name a distinct missing docs/*.md path; count is 0; log_fail names TEST-007 | sed:s/'_archive', 'archive', // | green |
| TEST-008 | Spec-AC-07 | integration | tests/skills/test-aai-docs-audit.sh | tracked src/a.mjs and .aai/templates/cite.mjs each name a distinct missing docs/*.md path; count is 0; log_fail names TEST-008 | sed:s/'\.aai\/scripts', 'tests'/'.aai\/scripts', 'tests', 'src', '.aai\/templates'/ | green |
| TEST-009 | Spec-AC-07 | integration | tests/skills/test-aai-docs-audit.sh | services exists; tracked services/api.ts and services/tool.ps1 name two missing docs/*.md paths; a sibling services/note.txt names a third missing path and adds no row; count is 2 and both sources are the .ts and the .ps1; log_fail names TEST-009 | sed:s/'services', // | green |
| TEST-010 | Spec-AC-07 | integration | tests/skills/test-aai-docs-audit.sh | git init, .aai/scripts/cite.mjs names a missing docs/*.md path, the file is not git added; count is 0; log_fail names TEST-010 | sed:s/'ls-files', '-z', '--', sourceRefRoot/'ls-files', '-z', '--others', '--', sourceRefRoot/ | green |
| TEST-011 | Spec-AC-07 | integration | tests/skills/test-aai-docs-audit.sh | directory is not a git work tree and only .aai/scripts exists; cite.mjs names a missing docs/*.md path; exit 0; stderr contains the fallback phrase once and contains .aai/scripts; stdout count is 1; log_fail names TEST-011 | sed:s/source-ref walk falls back to a working-tree walk/source-ref walk skips this root/ | green |
| TEST-012 | Spec-AC-08 | integration | tests/skills/test-aai-docs-audit.sh | a nested bash of this suite with argument test_broken_refs_both_clean_is_zero exits 0, stdout contains the TEST-002 pass text, and stdout does not contain Testing aai-docs-audit skill; log_fail names TEST-012 | sed:s/if \[\[ \$# -gt 0 \]\]; then/if [[ 0 -gt 0 ]]; then/ | green |

Test status values: pending → red → green.

Mutation targets: TEST-004 is `.aai/scripts/lib/docs-model.mjs`. TEST-012 is `tests/skills/test-aai-docs-audit.sh`. Every other row is `.aai/scripts/generate-docs-index.mjs`. Selectors are `test_broken_refs_source_missing`, `test_broken_refs_both_clean_is_zero`, `test_broken_refs_ac_notes_still_counted`, `test_broken_refs_non_paths_ignored`, `test_broken_refs_dedup_per_file`, `test_broken_refs_one_signal`, `test_broken_refs_excluded_trees`, `test_broken_refs_closed_root_set`, `test_broken_refs_services_root`, `test_broken_refs_untracked_skipped`, `test_broken_refs_nongit_note`, `test_broken_refs_selector_isolates`, in TEST order.

Pre-change RED, observed before the walk and the early return exist: TEST-001, TEST-005, TEST-006, TEST-009, TEST-011, TEST-012. Each exits non-zero and prints a FAIL line naming its TEST id. TEST-002, TEST-003, TEST-004, TEST-007, TEST-008, and TEST-010 already exit 0 on the pre-change tree because they expect a zero count the current generator produces. Their fail proof is the Mutation cell after the green code exists, recorded by mutation-run.mjs. A green run of those six without that mutation record does not prove them.

Seams each gating test crosses:
- TEST-001, TEST-005, TEST-006, TEST-009, TEST-011: the generator process reads a real fixture file and writes both stdout and docs/INDEX.md from one `brokenRefs` array.
- TEST-003 and TEST-006: `extractReferences` on the Notes cell and the source walk append to that same array, and the section shows both producers.
- TEST-002: the target check is a real `stat` of a file the fixture created, not a stub list of ids.
- TEST-010: `git ls-files` is the enumerator. An untracked file on disk stays out until `--others` is added.
- TEST-007 and TEST-008: directory membership is the real walk, not a filtered unit list.
- TEST-004: `extractDocPathReferences` is what the generator calls. The `..` guard is in that function, and the fixture token is in a real file.
- TEST-012: the suite file itself is the dispatcher. The nested process is a second invocation, not a mock of `main`.

Residual risks, untested on purpose:
- stat errors other than ENOENT throw. No new test forces EACCES. The existing helper test_581 covers `existsOnDisk` only if this walk calls it.
- A `git ls-files` throw uses the same fallback phrase and walk. No test forces the throw.
- Allowlist suffixes `.js`, `.cjs`, `.jsx`, `.tsx`, and `.py` have no fixture of their own. `.mjs`, `.sh`, `.ts`, and `.ps1` do.
- Excluded segments `dist`, `coverage`, and `.git` share the set TEST-007 mutates only for `_archive` and `archive`. `node_modules` is a green assertion in TEST-007.
- A `.md` file under `tests/`, and any file outside the closed roots, is invisible to this signal. Prompt files under `.aai/*.prompt.md` stay invisible.
- Two runs that cross UTC midnight can differ on the Today line. The tests compare the Broken references section and the Wrote line.
- A selector that names an older function skips `setup_fixture`. The no-argument CI invocation does not.
- This repository may already contain missing docs paths. This scope does not repair them and does not require the live tree to print 0.

## Verification
- Commands, from the repository root, one selector at a time: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-docs-audit.sh <selector>`
- Full suite after the selectors are green: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-docs-audit.sh` with no selector, exit 0.
- Registration: `node .aai/scripts/check-test-registration.mjs tests/skills` exits 0.
- PASS criteria: every TEST-xxx status is green and every Spec-AC is terminal. Planning does not claim that PASS.
- Pre-change failing output for TEST-001, TEST-005, TEST-006, TEST-009, TEST-011, and TEST-012 is stored at docs/ai/tdd/red-[timestamp].log before the walk change, per .aai/SKILL_TDD.prompt.md.
- After green, each Mutation cell is executed with `node .aai/scripts/mutation-run.mjs --spec docs/specs/SPEC-0231-spec-docs-index-broken-refs-scope.md --test-id <TEST-xxx> --suite tests/skills/test-aai-docs-audit.sh --selector <function> --target <target> --sed '<cell without the sed: prefix>'`. Records land at docs/ai/tdd/docs-index-broken-refs-scope/mutation-<TEST-xxx>.txt. A record whose replay does not redden is not evidence.

## Evidence contract
- ref_id: docs-index-broken-refs-scope
- Strategy tdd may demand a stored RED artifact per AC-gating test plus the verification commands above. The pre-change RED logs cover the six tests that fail before the change. The other six owe a mutation record that reddens them, because a pre-change pass does not prove the guard.
- Spec-AC-01: selector test_broken_refs_source_missing, exit 0 after the change, evidence docs/ai/tdd/red-[timestamp].log from the pre-change failure and the later green log.
- Spec-AC-02: selector test_broken_refs_both_clean_is_zero, exit 0, plus mutation-TEST-002.txt showing RED.
- Spec-AC-03: selector test_broken_refs_ac_notes_still_counted, exit 0, plus mutation-TEST-003.txt showing RED.
- Spec-AC-04: selector test_broken_refs_non_paths_ignored, exit 0, plus mutation-TEST-004.txt showing RED.
- Spec-AC-05: selector test_broken_refs_dedup_per_file, exit 0, pre-change red log.
- Spec-AC-06: selector test_broken_refs_one_signal, exit 0, pre-change red log.
- Spec-AC-07: the five selectors, each exit 0. TEST-009 and TEST-011 have pre-change red logs. TEST-007, TEST-008, and TEST-010 have mutation records showing RED.
- Spec-AC-08: selector test_broken_refs_selector_isolates, exit 0, pre-change red log. The pre-change nested run executes the whole suite and is slow. The observable is the banner `Testing aai-docs-audit skill` present in that output.
- Validation PASS is a later role's `VALIDATION-*.md` with an admissible outcome block. This planning document does not create it.
- Code review scope is the three paths in Isolation and review. Required stays true.

### Evidence by strategy

| Strategy | Evidence this spec may demand |
|----------|-------------------------------|
| tdd / hybrid | stored RED artifact per AC-gating test (docs/ai/tdd/) plus the full verification matrix — unchanged |
| loop | per-TEST-xxx green runs; RED-proof observed, storage optional |
| direct | targeted regression tests green (exit codes) plus the scoped diff — NO stored RED artifact, NO matrix beyond the declared versions |
| untested | the recorded strategy rationale plus the scoped diff — no test suites demanded for the scope itself |

This document's recorded strategy is tdd, so the tdd row is the demand. The table above is the per-strategy legend.

## Registry items closed by this scope

none. `node .aai/scripts/follow-ups.mjs list --status open` on 2026-10-14 showed 180 open items. No open item's subject is this source-tree broken-ref walk.

Neighbours this scope does not close: fu-frozen-mutation-cells-unusable stays open because these Mutation cells are anchored to required literals and were parsed in planning, and the missing freeze-time executor is a different change. fu-docsmodel-split-generated-pages stays open because this scope adds a matcher beside extractReferences and does not move SHARED_GENERATED_PAGES. fu-leanaccepted-doc-level-scope stays open because leanAccepted is untouched. fu-testplan-fallback-wrong-cell stays open because this Test Plan uses the canonical headers and does not change the positional fallback.
