# Code Review (close-out, round 2): reuse-for-docs-reading-suites

- Ride ref: reuse-for-docs-reading-suites
- Base: main (origin/main de74d468). Head: ec2123f8
- Delta reviewed: `git diff 5c4a1db2..ec2123f8` (fix commit ec2123f8), checked against `.aai/scripts/suite-reuse.mjs` and `.aai/scripts/lib/checkout-trace.mjs`
- Prior review: docs/ai/reviews/review-reuse-for-docs-reading-suites-closeout-20261102T094025Z.md (FAIL, B1-B5, NB-1/2)
- Spec: docs/specs/SPEC-0268-spec-reuse-for-docs-reading-suites.md, "Close-out steps" 1-4

## Verdict 1: spec_compliance = fail

| Close-out step | Status | Evidence |
|---|---|---|
| 1a D3 sentence and one caveat | met | Product doc lines 23-33. The blanket sentence "Anything the checker cannot account for makes the suite run" is gone, so one caveat remains. The runtime list now reads "Node version, platform, CPU architecture, git and bash versions", which matches `loadContext` runtime `{node, platform, arch, git, bash}` |
| 1b Limits: five of six suites read the whole checkout | met | Limits, first bullet (unchanged) |
| 1c Limits: reuse is off where access times are not recorded | met | New Limits bullet. It matches `if (!trace.canary) return no('trace-unavailable')` in `recordSuite` |
| 1d how to read `lint --admit` | met | Lines 41-49, now including the poisoned pass (`poisonFile`, the `poisoned run failed` path) and `--changed-since` |
| 2 one `## [unreleased]` entry naming `lint --minimal-tree` to `lint --admit` | partial | The replacement sentence went into the earlier **precise-suite-evidence-reuse** entry (CHANGELOG line 47), not into this ride's entry (line 31). Line 31, bullet 2, still says only "`lint --admit` is the new admission gate" (see B6) |
| 3 follow-ups | met | Unchanged since round 1 |
| 4 INDEX regenerated | met | Unchanged since round 1 |

## Prior findings: disposition

| Finding | Status | Evidence |
|---|---|---|
| B1 blanket guarantee and inexact runtime list | fixed | Sentence removed. Runtime list matches code lines 102-104 |
| B2 "whole closure" and `inputs-unresolvable` | fixed | Line 43 says "qualifies only when `lint --admit` passes; `explain <suite>` shows what its last record read", which matches `explainSuite` (reads the last record's trace). The Interfaces section cites `no-record`, `log-missing` and `policy`, which all exist in `checkSuite` (lines 256, 257, 263). `grep closure\|unresolv` over the product doc returns nothing |
| B3 atime-off Limit | fixed | New Limits bullet; `trace-unavailable` exists (line 295) |
| B4 CHANGELOG names the retirement | partially fixed | The wording is right and accurate (exit 2), but it was placed in another ride's entry (B6) |
| B5 RFC row tense | fixed | "three suites qualified at that slice" |
| NB-1 Interfaces lists arm/collect, `--changed-since` | fixed | Interfaces bullet 1 |
| NB-2 poisoned pass | fixed | Lines 45-47 |

## Verdict 2: code_quality = fail (B6 is documentation only; the code change is clean)

### Code change: `lint --minimal-tree` exits 2

- `suite-reuse.mjs:510`: `if (rest.includes('--minimal-tree'))` writes `lint: --minimal-tree was replaced by --admit` to stderr, sets exitCode 2 and returns before `lintManifest`. It scans the raw argv, so the position of the flag does not matter. `parseArgs` would otherwise treat `--minimal-tree` as a value-taking flag and swallow the next argument. That path is now never reached.
- Callers (`/usr/bin/grep -rn minimal-tree` over the worktree, excluding .git and the review/tdd/report trees): no caller in `.github/workflows/` (ps1-quality.yml names suite-reuse.mjs only as a path trigger), in `.aai/*.prompt.md`, `.aai/workflow/` or `tests/skills/suite-reuse.Tests.ps1`. The remaining hits are historical specs (SPEC-0266, the ride spec), the brief, decisions.jsonl, CHANGELOG, the product doc, and the new assertion. Nothing can break.
- Other lint modes, reproduced: `lint` gives rc=0. `lint --suite aai-pricing --minimal-tree` gives rc=2 with the message. `CI=true lint --admit` prints `ADMIT-OFF ci`, rc=0. The usage header (line 21) already documents only `--admit`.
- RED genuineness: `docs/ai/tdd/reuse-for-docs-reading-suites/red/minimal-tree-refusal-baseline.log` ends `FAIL: TEST-3273: lint --minimal-tree must refuse with exit 2, got 0`. Reproduced: the 5c4a1db2 version of the script run with `lint --minimal-tree` returns rc=0. The head version returns rc=2. The assertion fails without the change.
- The test's `expect` helper uses `[[ "$2" == *"$3"* ]]`, not grep, so a needle that starts with `--` is safe.
- Suite run at head (`env -u AAI_ROLE AAI_SUITE_REUSE=0 bash tests/skills/test-aai-suite-reuse.sh`): TEST-3273 PASS ("the retired --minimal-tree flag exits 2"), and TEST-3274 and TEST-3275 PASS. The suite exited 1 (4m44s) with 17 PASS lines and one FAIL: `TEST-3276: live admission exited 1`. The cause is `ADMIT-FAIL aai-docs-content ... Expected 'Verdict: CLEAN'`, which is this ride's docs-audit false-open (below). That is the known, expected failure. Every other admitted suite reached ADMIT-PASS.

### docs-audit (`node .aai/scripts/docs-audit.mjs --no-event`)

Drift report: 1 item, `reuse-for-docs-reading-suites | probable-false-open | work-item flush record`. This is the only actionable item (Verdict: NEEDS-TRIAGE, 1 item). The other sections are report-only: 8 near-miss AC tables on old ISSUE docs, and 2 missing-close-telemetry items on CHANGE-0198/SPEC-0198. Both also appear on main, where the audit reads CLEAN. The failure is expected until the PR close ceremony and confirms the known failures in test-aai-docs-content.sh and TEST-3276.

### BLOCKING

- **B6. The `--minimal-tree` retirement is attributed to the wrong CHANGELOG entry (close-out step 2; the remainder of B4).** The fix rewrote bullet 2 of the precise-suite-evidence-reuse entry (CHANGE-0240, already merged in #523). That entry now says "`lint --admit` is the admission gate and replaces `lint --minimal-tree`", which describes this ride's behaviour as CHANGE-0240's. It also sits next to that entry's unchanged "three reuse today", while this ride's entry says 11 are admitted. This ride's own entry (line 31, bullet 2) still does not name the replacement. Fix: put the sentence into line 31 bullet 2, for example "`suite-reuse.mjs lint --admit` replaces `lint --minimal-tree` as the admission gate; the old flag now refuses with exit 2". Restore the CHANGE-0240 entry's bullet 2 to its original `--minimal-tree` text. Keeping the runtime-list correction in the CHANGE-0240 bullet 1 is acceptable: main's code at #523 already compared arch, git and bash, so that edit only corrects the entry.

### NON-BLOCKING

- NB-3. The product doc lost the blank line before `## How to use it` (line 33 runs straight into the heading). It is valid CommonMark, and body lint reports 0 issues. Lines 31-32 also exceed the file's wrap width. Disposition: restore the blank line and rewrap in the same edit as B6.
- NB-4 (informational). The worktree has 3 uncommitted `docs_audit` lines in `docs/ai/EVENTS.jsonl` (09:47-09:49Z, from earlier audit runs without `--no-event`). This review did not write them. Disposition: decide at commit time; do not `git restore` the ledger.

## cannot_verify

- The CI behaviour of the suite (ADMIT-OFF under GitHub Actions) was checked only via `CI=true` locally.
- I did not re-measure the R0/R1 wall times. The doc numbers are unchanged since round 1.

## state_update_commands

```
node .aai/scripts/state.mjs set-code-review --required true --status fail \
  --report docs/ai/reviews/review-reuse-for-docs-reading-suites-closeout-r2-20261102T100415Z.md \
  --base-ref main --head-ref ec2123f8 \
  --scope ".aai/SKILL_VERIFY.prompt.md .aai/scripts/lib/checkout-trace.mjs .aai/scripts/suite-reuse.mjs .aai/system/PROFILES.yaml CHANGELOG.md docs/INDEX.md docs/ai/EVENTS.jsonl docs/ai/METRICS.jsonl docs/ai/decisions.jsonl docs/ai/overview-data.json docs/ai/overview.html docs/ai/reviews/review-reuse-for-docs-reading-suites-20261102T082812Z.md docs/ai/reviews/review-reuse-for-docs-reading-suites-closeout-20261102T094025Z.md docs/ai/roadmap.yaml docs/analysis/precise-suite-evidence-reuse.md docs/issues/CHANGE-0242-reuse-for-docs-reading-suites.md docs/product/precise-suite-evidence-reuse.md docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md docs/specs/SPEC-0268-spec-reuse-for-docs-reading-suites.md tests/skills/lib/read-trace.cjs tests/skills/lib/suite-reuse.test.mjs tests/skills/suite-map.yaml tests/skills/suite-reuse.Tests.ps1 tests/skills/suite-reuse.json tests/skills/test-aai-suite-reuse.sh tests/skills/test-framework.sh" \
  --notes "close-out r2: B1-B3, B5, NB-1/2 fixed; lint --minimal-tree exit 2 clean (no callers, RED genuine, TEST-3273 PASS). B6: --minimal-tree retirement written into CHANGE-0240's CHANGELOG entry instead of this ride's entry (step 2); move it, restore 0240 bullet 2. NB-3 blank line before 'How to use it'. docs-audit: only this ride's probable-false-open."
```
