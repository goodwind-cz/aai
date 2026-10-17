---
id: spec-release-changelog-eol
type: spec
number: 235
status: done
frozen_sha256: 8d00259eb95377d69006439d110a8ec2480aca80f1ea77aa0f5d6934cdc7c2e2
mutation_gate: v1
ceremony_level: 2
capability: release-command-finish
user_visible: false
links:
  requirement: release-changelog-eol
  rfc: null
  pr: []
  commits: []
---

# Release finish rolls CHANGELOG bytes exactly and resumes only on exact bytes

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/ISSUE-0102-release-changelog-eol.md
- Parent capability spec: docs/specs/SPEC-0233-spec-release-command-finish.md (the finish engine and its journal/resume model)
- Sibling spec, same engine: docs/specs/SPEC-0234-spec-release-checks-registration-grace.md
- Technology contract: docs/TECHNOLOGY.md
- Seam partner (read, not changed): the CI released-region guard `released_region_verdict` in tests/skills/test-aai-release.sh (TEST-025 of that suite's shell half), which failed on release PR #473

## Implementation strategy
- Strategy: tdd
- Rationale: a byte-level defect on the one path that writes a release payload, with a resume path that must refuse what it accepted before. Every new assertion can be observed RED on the pre-change engine (the fixture CHANGELOG already ends with a newline, so the defect reproduces today), and a mutation per row proves each assertion bites. The suite's finish fixture already stubs gh and git, so RED-first costs little.

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: one engine file plus its suite; already isolated in its own worktree, decided before intake.
- User decision: worktree (already set: branch fix/release-changelog-eol, path /Users/ales/Projects/aai-fix-release-changelog-eol, base f404ef88)
- Base ref: main at f404ef88
- Inline review scope: .aai/scripts/release-finish.mjs tests/skills/test-aai-release.sh docs/product/release-command-finish.md CHANGELOG.md docs/specs/SPEC-0235-spec-release-changelog-eol.md docs/issues/ISSUE-0102-release-changelog-eol.md
- Code review required: true

## Constitution deviations

None.

Article 7 is untouched: the engine's merge path is not changed, and the ride itself merges nothing.

## Root cause (read by Planning, 2026-10-17)

- `git()` returns `stdout.trim()`. The base CHANGELOG is read with `git('show', `${baseHead}:CHANGELOG.md`)`, so `rollup()` receives a source with no trailing newline and no leading whitespace (a UTF-8 BOM is whitespace to `String.prototype.trim`). `rollup()` then records `newline=false` and the written `record.content` ends without a newline.
- `rollup()` begins with `source.replace(/\r\n/g,'\n')`, so a CRLF file comes out all-LF.
- The resume adoption check compares `trim(git('show',head+':CHANGELOG.md'))` with `trim(record.content)`, which hides EOF, surrounding whitespace and CRLF differences.
- A journal written by the defective engine carries `content` without the newline. Exact-byte adoption alone would still accept a branch built from such a journal, because the branch matches the journal. So resume must also re-derive the rollup from the journal's `baseHead` and compare.
- Other `git()`/`trim` uses were checked and stay: audit reads of the CHANGELOG (normalized on purpose), the notes comparison against the published release body (trim on both sides by design), and ref/sha reads. `AAI_VERSION.md` is written from a constant.

## Acceptance Criteria Mapping

| Requirement | Spec-AC | Verification | Observable |
|-------------|---------|--------------|------------|
| Expected Behavior: trailing newline kept | Spec-AC-01 | R TEST-067 | committed CHANGELOG blob on chore/release-v1 equals the expected byte string, last byte 0x0a |
| Expected Behavior: missing newline stays missing, leading bytes kept | Spec-AC-02 | R TEST-068 | committed blob equals the expected byte string beginning with EF BB BF and ending without 0x0a |
| Expected Behavior: CRLF untouched region preserved | Spec-AC-03 | R TEST-069 | committed blob equals the expected CRLF byte string; zero bare LF bytes |
| Expected Behavior: resume compares exact bytes | Spec-AC-04 | R TEST-070 | one REFUSED identity line per near-identical variant, zero pr create calls; the exact-bytes control exits 0 |
| Constraints: a defective-engine journal is not resumed | Spec-AC-05 | R TEST-071 | one REFUSED identity line naming the base rollup, zero pr create calls |
| Impact: the CI released-region guard passes on the rolled file | Spec-AC-06 | R TEST-072 | released_region_verdict prints PASS v0 for both base shapes |
| Constraints: git attributes cannot silently rewrite the cut bytes | Spec-AC-07 | R TEST-073 | one REFUSED changelog-normalized line, zero pr create calls, no release branch on the remote |

R = `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-release.sh <selector>` with the selector named in the Test Plan row; exit 0 and a `PASS: TEST-0xx` line decide each row.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN the base CHANGELOG blob ends with a newline (the stock finish fixture) the CHANGELOG blob of the prepared release commit on chore/release-v1 SHALL equal byte for byte the expected rollup `# Changelog\n\n## [unreleased]\n\n## [v1] — feat: alpha (#101)\n\n- alpha\n\n## [v1] — fix: beta (#102)\n\n- beta\n\n## [v0] — old\n- old\n`, read as a Buffer, not trimmed | done | TEST-067 PASS, 6 variants oracle byte-equal; docs/ai/reports/VALIDATION-20261017T203450Z-release-changelog-eol.md | — | — |
| Spec-AC-02 | WHEN the base CHANGELOG blob is the stock fixture with a leading UTF-8 BOM and without its final newline the prepared CHANGELOG blob SHALL equal the Spec-AC-01 expected string with the same BOM prefixed and its final newline removed | done | TEST-068 PASS, 8 BOM variants oracle byte-equal; docs/ai/reports/VALIDATION-20261017T203450Z-release-changelog-eol.md | — | — |
| Spec-AC-03 | WHEN every line of the base CHANGELOG blob ends with CR LF the prepared CHANGELOG blob SHALL equal the Spec-AC-01 expected string with every LF replaced by CR LF, including the two inserted scaffold lines, and SHALL contain zero LF bytes not preceded by CR | done | TEST-069 PASS, 6 CRLF variants oracle byte-equal; docs/ai/reports/VALIDATION-20261017T203450Z-release-changelog-eol.md | — | — |
| Spec-AC-04 | WHEN a resume finds a prepared commit on the release branch with the authorized parent, subject and two paths, but whose CHANGELOG blob differs from the journal content in any byte (variants: final newline toggled; every LF turned into CR LF) the engine SHALL refuse exactly once with cause `identity` (`Unbound prepared release branch`) and make no pr create call; a prepared commit with the exact journal bytes SHALL still be adopted and the run SHALL exit 0 with one PR and one merge | done | TEST-070 PASS, REFUSED identity per variant; docs/ai/reports/VALIDATION-20261017T203450Z-release-changelog-eol.md | — | — |
| Spec-AC-05 | WHEN a resume loads a journal with no PR yet whose content differs in any byte from the rollup of the exact base blob at the journal's baseHead (the defective-engine shape: final newline toggled) the engine SHALL refuse exactly once with cause `identity` and detail `Journal content differs from the base rollup`, before any worktree write, commit, push or pr create call | done | TEST-071 PASS, REFUSED identity naming base rollup; docs/ai/reports/VALIDATION-20261017T203450Z-release-changelog-eol.md | — | — |
| Spec-AC-06 | WHEN the released-region guard `released_region_verdict` (the function CI runs as TEST-025) is run on a repo whose HEAD is the prepared release commit and whose tag v0 is the base commit, its verdict SHALL be `PASS v0`, for a base CHANGELOG ending with a newline and for one ending without | done | TEST-072 PASS, released_region_verdict PASS v0 on 22 prepared commits; docs/ai/reports/VALIDATION-20261017T203450Z-release-changelog-eol.md | — | — |
| Spec-AC-07 | WHEN `.gitattributes` makes `git add` rewrite CHANGELOG.md (`CHANGELOG.md text eol=lf` over a CR LF base blob) so the committed blob of the prepared release commit differs from the journal content the engine SHALL refuse exactly once with cause `changelog-normalized` before the head is journaled, pushed or a PR created | done | TEST-073 PASS (post-freeze amendment, see decisions.jsonl) | — | — |

## Implementation plan

Components: `.aai/scripts/release-finish.mjs` (engine); `tests/skills/test-aai-release.sh` (fixture options plus cases); the product doc and a CHANGELOG entry at ship time. Both frontends (`aai-release.sh`, `aai-release.ps1`) only forward to the engine, so no frontend change; TEST-033 PowerShell parity keeps covering the forward.

1. Exact blob read. Add the literal helper `function blob(spec){return command('git',['cat-file','blob',spec]).stdout;}` (no trim). The base read becomes `rollup(blob(`${baseHead}:CHANGELOG.md`))`. `git()` itself stays trimming for refs and shas.
2. Line-ending-preserving rollup. Split with the literal `const lines=source.split('\n');` (no CRLF replacement), so each line keeps its own CR. Keep `if(newline)lines.pop();` exactly. The heading tests already tolerate a trailing CR (`\s*$`, `\S`, `l.trim()`). The two inserted scaffold lines take the CR of the first `## [` heading line (CR LF when that line ends in CR, LF otherwise). Notes strip a trailing CR per line before the existing join and trim, so `record.notes` stays LF-only and the audit and published-body comparisons are unchanged.
3. Exact adoption. In the prepared-branch recovery condition replace the `trim(...)!==trim(record.content)` arm with the literal `blob(head+':CHANGELOG.md')!==record.content`.
4. Journal re-derivation. Right after a journal loads with status ok and its identity fields match, and only while `!record.pr`, add the literal `if(!record.pr&&rollup(blob(`${record.baseHead}:CHANGELOG.md`)).content!==record.content)refuse('identity','Journal content differs from the base rollup');`. A rollup refusal there (malformed or empty notes) propagates unchanged; the base blob at a fixed sha cannot change, so a journal from the fixed engine always passes.
5. Mutation anchors. The Test Plan mutations target the literal texts in steps 1 to 4 (`['cat-file','blob',spec]).stdout;`, `if(newline)lines.pop();`, `const lines=source.split('\n');`, `blob(head+':CHANGELOG.md')!==record.content`, `)).content!==record.content`). Keep those spellings; renaming one obliges a recorded spec amendment of the matching Mutation cell.
6. Fixture. Give the finish fixture an optional base-CHANGELOG override (bytes written before the initial commit), used by TEST-068, TEST-069 and TEST-072. Read blobs in tests with `spawnSync('git',['cat-file','blob',...])` returning a Buffer; never through the trimming `run()` helper.
7. Resume variants (TEST-070, TEST-071). Run once with `AAI_RELEASE_TEST_STOP_AFTER=payload` (TEST-070) or `=worktree` (TEST-071). TEST-070 then writes the variant bytes into the journal's worktree CHANGELOG and commits them there with subject `chore(release): v1`; TEST-071 rewrites the journal's `content` with its final newline toggled (removed if present, appended if absent, so the case is RED on the pre-change engine too). Then rerun the engine.
8. Seam case (TEST-072). The node case runs the stock fixture and a no-newline fixture to `AAI_RELEASE_TEST_STOP_AFTER=prepared`, tags `v0` at the base commit, detaches HEAD at `chore/release-v1`, and prints the repo paths; the bash selector calls `released_region_verdict "$dir" "$TMP_ROOT/t716-<n>"` on each and requires `PASS v0`.
9. Case wiring. Node `check()` cases TEST-067 to TEST-072 run ONLY when `RELEASE_FINISH_CASE` equals their id (not on `all`), with bash selectors `test_711_rollup_keeps_trailing_newline` (TEST-067), `test_712_rollup_keeps_missing_newline_and_bom` (TEST-068), `test_713_rollup_keeps_crlf` (TEST-069), `test_714_resume_adopts_exact_bytes_only` (TEST-070), `test_715_resume_refuses_stale_journal` (TEST-071), `test_716_rolled_file_passes_released_region_guard` (TEST-072), registered in `main`'s list.

Edge cases decided here: a mixed-EOL file keeps each line's own ending; the inserted scaffold follows the first heading line. A file without a final newline whose last section is an `[unreleased]` entry moves that unterminated line above released sections; the joined result then carries the base's own bytes for every line and ends wherever the last released section ends (no newline added or removed relative to the base's EOF state). A non-UTF-8 CHANGELOG stays unsupported (the transport decodes UTF-8), as before.

Operator recovery out of scope: release PR #473 (v2026.10.17.2) already has a PR in its journal, so Spec-AC-05 does not apply once a PR exists. Close #473, delete `chore/release-v2026.10.17.2` and its journal, and cut fresh with the fixed engine.

## Seams

- release-finish to the CI released-region guard: TEST-072 produces the prepared commit with the real engine and runs the real `released_region_verdict` on it, the exact check that failed on #473.
- release-finish journal to resume: TEST-070 and TEST-071 write the journal and the branch with the real engine, alter one byte, and resume with the real engine.
- SPEC-0233 regression: TEST-011 (resume from every stage) and TEST-021 (SIGKILL resume) must still pass, which proves the fixed engine's own journals pass the re-derivation.
- Residual risk (no automated test crosses it): the live GitHub release workflow publishing from the rolled file; the first `/aai-release --confirm` after merge is the live proof.

Registry items with the same capability left open (different subjects, not touched): fu-release-notes-heading-multiset, fu-aai-update-guard-test-isolation, fu-release-required-contexts-unreported.

Registry items closed by this scope: none.

Hash pins: none. A repo-wide search for the sha256 prefix of release-finish.mjs (5b7cdfea6d615ec2) found no pin. tests/skills/test-aai-learned-routing.sh copies the engine into fixtures and must stay green.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---------|---------|------|----------------------|-------------|----------|--------|
| TEST-067 | Spec-AC-01 | integration | tests/skills/test-aai-release.sh | test_711_rollup_keeps_trailing_newline: stock fixture to stage prepared; the chore/release-v1 CHANGELOG blob as a Buffer deep-equals the expected bytes | sed:s/\['cat-file','blob',spec\]\)\.stdout;/['cat-file','blob',spec]).stdout.trim();/ | green |
| TEST-068 | Spec-AC-02 | integration | tests/skills/test-aai-release.sh | test_712_rollup_keeps_missing_newline_and_bom: base is BOM plus the stock bytes minus the final newline; prepared blob deep-equals BOM plus the expected bytes minus the final newline | sed:s/if\(newline\)lines\.pop\(\);/if(newline)lines.pop();else lines.push('');/ | green |
| TEST-069 | Spec-AC-03 | integration | tests/skills/test-aai-release.sh | test_713_rollup_keeps_crlf: base is the stock bytes with every LF as CR LF; prepared blob deep-equals the expected bytes with every LF as CR LF and holds zero bare LF | sed:s/const lines=source\.split\('\\n'\);/const lines=source.replace(RegExp('\r\n','g'),'\n').split('\n');/ | green |
| TEST-070 | Spec-AC-04 | integration | tests/skills/test-aai-release.sh | test_714_resume_adopts_exact_bytes_only: stop after payload, commit a variant CHANGELOG in the journal worktree, resume; final-newline-toggled and CR LF variants each refuse identity once with zero pr create calls; the exact-bytes control exits 0 with one PR and one merge | sed:s/blob\(head\+':CHANGELOG\.md'\)!==record\.content/trim(blob(head+':CHANGELOG.md'))!==trim(record.content)/ | green |
| TEST-071 | Spec-AC-05 | integration | tests/skills/test-aai-release.sh | test_715_resume_refuses_stale_journal: stop after worktree, toggle the journal content's final newline, resume; one REFUSED identity line naming Journal content differs from the base rollup, zero pr create calls, no remote release branch | sed:s/\)\)\.content!==record\.content/)).content===null/ | green |
| TEST-072 | Spec-AC-06 | integration | tests/skills/test-aai-release.sh | test_716_rolled_file_passes_released_region_guard: prepared commit from the stock and the no-newline fixture, tag v0 at base, HEAD detached at the release branch; released_region_verdict prints PASS v0 for both | sed:s/\['cat-file','blob',spec\]\)\.stdout;/['cat-file','blob',spec]).stdout.trim();/ | green |
| TEST-073 | Spec-AC-07 | integration | tests/skills/test-aai-release.sh | test_717_attribute_normalized_changelog_refused: CR LF base blob, then a commit adding `.gitattributes` `CHANGELOG.md text eol=lf`; the confirm run refuses once with changelog-normalized, makes no pr create call and leaves no release branch on the remote | sed:s/if\(blob\(made\+':CHANGELOG\.md'\)!==record\.content\)refuse/if(false)refuse/ | green |

Mutation targets: every row mutates `.aai/scripts/release-finish.mjs`. Patterns are JavaScript RegExp as `mutation-run.mjs --sed` reads them; replacements are literal.

## Verification

- RED first: add the cases and fixture options with the engine untouched and run each selector. TEST-067, TEST-068 and TEST-072 must fail on the dropped newline or BOM; TEST-069 on LF output; TEST-070 because the trimmed comparison adopts the variants and the run exits 0; TEST-071 because the stale journal is resumed. Record each observation in docs/ai/tdd/release-changelog-eol-red.log.
- GREEN: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-release.sh test_711_rollup_keeps_trailing_newline` and the same for test_712 to test_716, each exit 0 with its `PASS: TEST-0xx` line, logged to docs/ai/tdd/release-changelog-eol-green.log.
- Mutations: `node .aai/scripts/mutation-run.mjs --spec <this spec> --test-id TEST-0xx --suite tests/skills/test-aai-release.sh --selector <row selector> --target .aai/scripts/release-finish.mjs --sed '<row pattern>'` per row, each verdict RED; then `node .aai/scripts/mutation-gate.mjs --spec <this spec>` exit 0.
- Regression: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-release.sh` exit 0 (whole suite, including TEST-011, TEST-021 and TEST-033), plus `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh --skill aai-release --skill aai-learned-routing` exit 0.
- Docs: `node .aai/scripts/spec-lint.mjs --path <this spec>` exit 0; `node .aai/scripts/docs-audit.mjs --strict` before close.

## Evidence contract

- ref_id release-changelog-eol; for each TEST-067 to TEST-072: the exact command, exit code, the `PASS:` line or the failing assertion, and for the byte cases the first differing offset when RED.
- RED observations: docs/ai/tdd/release-changelog-eol-red.log. GREEN runs: docs/ai/tdd/release-changelog-eol-green.log. Mutation records: docs/ai/tdd/spec-release-changelog-eol/mutation-TEST-0xx.txt (written by mutation-run.mjs).
- The diff range against f404ef88 and the head commit SHA at validation.
- Planning claims no PASS; the verdict belongs to Validation.

### Evidence by strategy

tdd: stored RED artifact per AC-gating test (docs/ai/tdd/) plus the verification matrix above.
