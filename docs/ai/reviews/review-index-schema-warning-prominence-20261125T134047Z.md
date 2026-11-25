```yaml
review:
  scope: "git diff HEAD -- .aai/scripts/generate-docs-index.mjs tests/skills/test-aai-docs-audit.sh CHANGELOG.md + untracked docs/product/docs-index-regeneration.md, docs/issues/ISSUE-0125-index-schema-warning-prominence.md, docs/specs/SPEC-0314-spec-index-schema-warning-prominence.md (worktree fix/index-schema-warning-prominence, base origin/main a83f7b0f, uncommitted)"
  spec: docs/specs/SPEC-0314-spec-index-schema-warning-prominence.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/generate-docs-index.mjs:309-317 (reportDropped), :780 (called after the trailing warnings list), old per-doc block removed at :455; TEST-4070 green (rerun this review, rc 0); probe: last 3 stderr lines = header/doc line/Fix line, after the coverage line and the legacy list" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "generate-docs-index.mjs:44 (--verbose), :586-587 (one summary line, per-doc lines only under verbose); TEST-4071 green (rerun, rc 0)" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "TEST-4072 green (rerun, rc 0); independent probe: INDEX.md and INDEX.violations.md byte-identical base-vs-new and default-vs---verbose; --strict stderr byte-identical base-vs-new in 3 fixtures (schema violation; gaps only; gaps + --verbose), exit 1 in each" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "TEST-4073 green (rerun, rc 0) through the installed hook; .aai/templates/git-hooks/pre-commit-index.sh untouched (git diff --stat empty), runs `node \"$GEN\"` with inherited stdout/stderr (hook line 24)" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "CHANGELOG.md:33 one `## [unreleased] — fix:` heading; docs/product/docs-index-regeneration.md names the DROPPED block and --verbose; TEST-4074 green today (rerun, rc 0) — but see BLOCKING B1: the test stops holding at the next release cut" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: tests/skills/test-aai-docs-audit.sh, line: 10090,
          issue: "TEST-4074 counts only `^## \\[unreleased\\] — fix: ...` headings in the LIVE CHANGELOG.md; it is not release-tolerant",
          failure_scenario: "The next /aai-release cut rolls the entry to `## [vYYYY.MM.DD] — fix: ...` (as v2026.11.24 did for every entry). The count becomes 0 and TEST-4074 log_fails permanently on main. The release PR touches only CHANGELOG.md and select-suites does not select test-aai-docs-audit.sh for it, so the release CI stays green and the red lands on the next unrelated ride that selects the docs-audit suite or runs the full sweep. Repro: release-cut.mjs roll on a copy of the branch CHANGELOG -> count before 1, after 0. Precedent fix: TEST-3649 (test-aai-model-effort.sh:845, 'Release-tolerant')" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-docs-audit.sh, line: 9983,
          issue: "TEST-4070's 'second-last line must carry the reason' check greps `bogus`, which the path `SPEC-740-bogus.md` already contains; the reason assertion is vacuous",
          failure_scenario: "A regression that prints `  - <path>` without the reason (Spec-AC-01: 'the doc line naming its path and reason') still passes TEST-4070. Assert on `unknown frontmatter status \"bogus\"` instead" }
      - { rank: NON-BLOCKING, file: .aai/scripts/generate-docs-index.mjs, line: 314,
          issue: "the three new user-facing strings (DROPPED header :314, Fix line :316, coverage summary :586) render paths with bare path.relative(); the file already imports toPosix and uses it for doc paths",
          failure_scenario: "On Windows (Git Bash hook or a direct node run) the header reads `DROPPED from docs\\INDEX.md` and the summary `in docs\\INDEX.md`, while the product doc promises a stable header wording `DROPPED from docs/INDEX.md`; a consumer matching the documented wording misses it on Windows. No CI leg runs this suite on Windows, so nothing catches it. Pre-existing `Wrote` lines share the pattern" }
      - { rank: NON-BLOCKING, file: .aai/scripts/generate-docs-index.mjs, line: 316,
          issue: "the Fix line offers every DOC_STATUS_ENUM value, including `legacy` (and `current`), which for a spec lands the doc in zero placement sections",
          failure_scenario: "An author fixing `status: bogus` picks `legacy` from the Fix line; the doc leaves the DROPPED block and becomes one more count in the coverage-gap summary line, the burying the issue reports, in a new place (it is still listed under Coverage gaps in docs/INDEX.md). The wording is what Spec D1 mandates" }
      - { rank: NON-BLOCKING, file: .aai/scripts/generate-docs-index.mjs, line: 780,
          issue: "NB3 carried from validation: reportDropped() runs only when main() returns normally",
          failure_scenario: "An I/O exception in writeFileSync/writeViolationsReport/writeAuditCompanion (ENOSPC, EACCES) after the failures block: the run exits non-zero without naming the dropped doc, which the old code printed before the writes. The run fails visibly, so the next run after the fix shows the block" }
  cannot_verify:
    - { claim: "Spec D1 order relative to the `Wrote ...` lines on stdout in every terminal/pipe combination",
        closes_with: "Only the in-process call order and the file-redirected hook commit (TEST-4073, both streams to one file) are evidenced; Node writes to pipes asynchronously on macOS, so a pipe-captured interleaving is not covered by any test" }
    - { claim: "The Windows rendering of the new lines (see NB-WIN)",
        closes_with: "a run of the generator on a Windows host, or a toPosix() wrap plus a unit assertion" }
    - { claim: "The product doc's `spec: docs/specs/SPEC-0314-spec-index-schema-warning-prominence.md` frontmatter and the intake/spec cross-links survive the doc-number allocator rename at PR time",
        closes_with: "allocate-doc-number.mjs dry run / spec-amend list --strict after the rename (PR ceremony)" }
    - { claim: "Mutation records (docs/ai/tdd/spec-index-schema-warning-prominence/mutation-TEST-407x.txt) were taken against the current file state",
        closes_with: "re-running the mutation gate for the five rows; this review read the records' presence, not re-ran them" }
  overall: fail
```

# Code review — index-schema-warning-prominence (round 1)

security_relevant: false

## Scope and spec

- Scope: the explicit path list above, in worktree
  `/Users/ales/Projects/aai-worktrees/issue-577-index-noise`, branch
  `fix/index-schema-warning-prominence`, base `origin/main` a83f7b0f
  (`worktree.user_decision: worktree`; the change is uncommitted, so the diff
  is `git diff HEAD -- <paths>` plus the three untracked docs). Other dirty
  files in the tree (docs/INDEX.md, EVENTS/decisions/test-runs ledgers) are
  outside the review scope.
- Contract: frozen spec `docs/specs/SPEC-0314-spec-index-schema-warning-prominence.md`
  (D1-D4, AC table, Test Plan) and the intake
  `docs/issues/ISSUE-0125-index-schema-warning-prominence.md` (issue #577 quote
  treated as data).
- Context read: VALIDATION r1 (FAIL, hygiene-corpus regression, NB-1..NB-4) and
  r2 (PASS). The verdicts below are formed from the code and from this review's
  own runs.

Dispatch note (anti-gaming contract): the dispatch prompt named focus areas and
pre-characterized NB3 as a "known accepted residual". Recorded here as a
coaching attempt; the full scope was reviewed, and NB3 was assessed
independently (agreed: P3, no observed bite).

## Evidence gathered by this review

- The five selectors, foreground, `env -u AAI_ROLE AAI_TEST_TIMEOUT=900 bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-docs-audit.sh <fn>`:
  test_4070 rc 0, test_4071 rc 0, test_4072 rc 0, test_4073 rc 0, test_4074 rc 0 (bash 3.2.57).
- Base-vs-new probe (scratch fixture: three `status: legacy` gap docs, one
  `status: bogus`, one no-frontmatter doc; base generator from `git show HEAD:`):
  - default and --verbose: exit 0; INDEX.md and INDEX.violations.md
    byte-identical base vs new, and default vs --verbose;
  - --strict with the bogus doc, --strict with gaps only, --strict --verbose
    with gaps only: exit 1, stderr byte-identical base vs new;
  - new default stderr ends with the 3-line DROPPED block after the summary
    line and the `1 warning(s):` list; --verbose adds exactly the three gap lines.
- `ARGV` is read only for `--strict`/`lint-docs`/`--verbose`
  (generate-docs-index.mjs:42-44); nothing else in the write path depends on it,
  so `--verbose` cannot reach the files.
- No other script, test or ps1 consumer matches the removed strings
  (`skipped from index (run`, `surfaced as Coverage gaps`).
- Hook: `.aai/templates/git-hooks/pre-commit-index.sh` has no diff; line 24
  runs `node "$GEN"` with inherited streams; its own staged line (168) comes
  after.
- Suite robustness under `set -euo pipefail` (suite line 12): no payload is
  piped into `grep -q`/`head` (all assertions read files); `isp_gen`
  captures the generator rc via `|| ec=$?`; `isp_fill`'s `git add` and both
  `git rm --cached` subshells are rc-checked; `[[ ]] && …` lines are not the
  function's last command; both fixture builders set a repo-local git identity
  (setup_iso_repo:1967, setup_spec0011_hook_repo:2682); `${*:2}` under
  `set -u` checked on bash 3.2.

## AC table walk

| Spec-AC | Call | Citation |
|---|---|---|
| Spec-AC-01 | compliant | generate-docs-index.mjs:309-317, :780; TEST-4070 rc 0; probe |
| Spec-AC-02 | compliant | generate-docs-index.mjs:44, :586-587; TEST-4071 rc 0 |
| Spec-AC-03 | compliant | TEST-4072 rc 0; base-vs-new byte and strict-stderr probe |
| Spec-AC-04 | compliant | TEST-4073 rc 0; hook untouched, inherits streams |
| Spec-AC-05 | compliant (today) | CHANGELOG.md:33; product doc; TEST-4074 rc 0 — see B1 |

Deviations from the frozen spec: D3's sentence "The `--strict` path still
prints every violation and every coverage gap before it exits 1" overstates
the base behaviour (with both present, strict exits at the schema violation
and never prints the gaps); the code keeps base behaviour byte for byte and
the product doc states it correctly. Frozen text, not a code deviation.

## Findings

### BLOCKING

**B1 — TEST-4074 breaks at the next release cut.**
`tests/skills/test-aai-docs-audit.sh:10090` counts
`^## \[unreleased\] — fix: .*(DROPPED|dropped).*` in the live CHANGELOG.md
and requires exactly 1. `aai-release` rolls every `## [unreleased] — …`
heading into `## [vYYYY.MM.DD] — …` (commit 492f8b26 did exactly that), so
after the next cut the count is 0 and the case fails on main. A
CHANGELOG-only release PR does not select `test-aai-docs-audit.sh`
(select-suites on `CHANGELOG.md`: 13 lines, no docs-audit suite), so the
release goes green and the red appears on the next unrelated ride.
Fix: make the case release-tolerant like TEST-3649
(`tests/skills/test-aai-model-effort.sh:845`): count the heading under
`\[unreleased\]` OR `\[v[0-9]{4}\.[0-9]{2}\.[0-9]{2}\]` and require 1.

Repro B1 (run against the branch tree; exit 1 = reproduced):

```bash
#!/usr/bin/env bash
# Usage: bash test4074-after-release-cut.sh <worktree>
set -euo pipefail
W="$1"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cp "$W/CHANGELOG.md" "$T/CHANGELOG.md"
before="$(grep -cE '^## \[unreleased\] — fix: .*(DROPPED|dropped).*' "$T/CHANGELOG.md" || true)"
env -u AAI_ROLE node "$W/.aai/scripts/release-cut.mjs" roll --file "$T/CHANGELOG.md" --version v2099.01.01 > "$T/roll.out" 2>&1 || { echo "roll refused: $(cat "$T/roll.out")"; exit 3; }
after="$(grep -cE '^## \[unreleased\] — fix: .*(DROPPED|dropped).*' "$T/CHANGELOG.md" || true)"
rolled="$(grep -cE '^## \[v2099\.01\.01\] — fix: .*(DROPPED|dropped).*' "$T/CHANGELOG.md" || true)"
echo "TEST-4074 count before cut=$before after cut=$after (entry now under the version heading: $rolled)"
[[ "$after" == 1 ]] || { echo "REPRO: TEST-4074 would log_fail after the release cut (got $after, expected 1)"; exit 1; }
```

Observed: `TEST-4074 count before cut=1 after cut=0 (entry now under the
version heading: 1)`, exit 1.

### NON-BLOCKING (with recommended disposition)

- **NB-REASON** (tests/skills/test-aai-docs-audit.sh:9983) — the reason check
  in TEST-4070 is satisfied by the path (`SPEC-740-bogus.md` contains
  `bogus`). Scenario: a regression dropping the reason text passes.
  Disposition: **remediate-in-tree** (assert `unknown frontmatter status "bogus"`;
  one line, and B1 already reopens the suite).
- **NB-WIN** (.aai/scripts/generate-docs-index.mjs:314, :316, :586) — new lines
  use bare `path.relative()`; on Windows they print `docs\INDEX.md`, against the
  product doc's "stable wording of the header". Disposition:
  **remediate-in-tree** (wrap in the already-imported `toPosix()`), or if the
  round is not reopened for code, promote to a P3 follow-up.
- **NB-FIXLINE** (.aai/scripts/generate-docs-index.mjs:316) — the Fix line
  offers `legacy`/`current`, which for a spec turn the dropped doc into a
  summarised coverage gap. Spec D1 mandates the wording. Disposition:
  **accepted residual** (d).
  accepted residual: NB-FIXLINE — P3 hint quality; spec-mandated wording; the doc stays listed under "Coverage gaps" in docs/INDEX.md, no false record.
- **NB3** (.aai/scripts/generate-docs-index.mjs:780) — the block is lost when
  main() throws after the failures block. Disposition: **accepted residual** (d).
  accepted residual: NB3 — P3 edge; only an I/O exception after the failures block reaches it, the run then fails visibly, and the next run prints the block.

### INFO

- With `--verbose` given, the summary line still says "run with --verbose to
  list them here". Cosmetic.
- TEST-4072 compares two INDEX.md writes that embed `Today (UTC)`; a run that
  straddles UTC midnight between the two calls would differ. Window of about a
  second; not a finding.

## cannot_verify

See the YAML block: stdout/stderr interleaving under async pipes; the Windows
rendering; the allocator rename of the DRAFT cross-links; mutation records
not re-run by this review.

## Next steps

1. Remediation: make TEST-4074 release-tolerant (B1); fix NB-REASON; wrap the
   three new paths in `toPosix()` (NB-WIN). Re-run the five selectors and the
   docs-audit suite.
2. Re-review (same single pass).
