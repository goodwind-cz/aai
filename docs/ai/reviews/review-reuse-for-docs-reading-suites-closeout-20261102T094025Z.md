# Code Review (close-out) — reuse-for-docs-reading-suites

- Ride ref: reuse-for-docs-reading-suites
- Base: main (origin/main de74d468) — Head: 5c4a1db2
- Scope reviewed: close-out commit 5c4a1db2 (product doc, CHANGELOG entry, RFC-0017 phase 5 row, follow-ups in decisions.jsonl, INDEX) checked against `.aai/scripts/suite-reuse.mjs` and `.aai/scripts/lib/checkout-trace.mjs`; merge e5c880b7 ledger integrity.
- Spec: docs/specs/SPEC-DRAFT-spec-reuse-for-docs-reading-suites.md, section "Close-out steps" (1-4) and the D3 sentence.
- Prior review: docs/ai/reviews/review-reuse-for-docs-reading-suites-20261102T082812Z.md (NB-5 asked for the `.git` wording at close-out).

## Verdict 1: spec_compliance = fail

| Close-out step | Status | Evidence |
|---|---|---|
| 1a D3 sentence and caveat replace "complete input identity" | partial | Lines 24-35 carry the D3 sentence with the NB-5 `.git` fix, but add a second guarantee after the caveat (B1) and leave "whole closure is known" (line 43) and `inputs-unresolvable` (line 72) from the old model (B2) |
| 1b Limits: five of six named suites read the whole checkout | met | Lines 90-91 |
| 1c Limits: reuse is off where access times are not recorded | missing | No such statement; the code refuses to record when the canary fails (`if (!trace.canary) return no('trace-unavailable')`, suite-reuse.mjs record) (B3) |
| 1d how to read `lint --admit` | met | Lines 45-48 |
| 2 CHANGELOG `## [unreleased] — <title>` entry naming `lint --minimal-tree` to `lint --admit` | partial | The heading format matches the existing entries. The entry names `--admit` but not the retirement of `--minimal-tree` (B4) |
| 3 register the two Split follow-ups; close the six listed items | met | `fu-reuse-split-corpus-cases` and `fu-reuse-local-ledger-append` were added in 5c4a1db2; the six items each have a `follow_up_status done` at 2026-11-02T06:36Z. `fu-reuse-arm-dir-nonexist-case` (r5 NB1) was also added |
| 4 regenerate docs/INDEX.md | met | `generate-docs-index.mjs` rerun leaves the tree clean |

## Verdict 2: code_quality = fail (doc claims checked against code)

Identity paragraph, claim by claim:

- Bytes and executable bit of files inside the checkout, outside `.git`, that were read, replaced or deleted: matches the code (`contentHash` = sha256 + `:x`/`:-`; read = atime above the floor, inode change or missing at collect; `.git/` entries are given null and dropped from `inputs`).
- Under `.git`, only HEAD and the refs, and only when `.git` was read: matches the code (`history = trace.git_read ? historyOf(root) : ''`, where `historyOf` is `rev-parse HEAD` + `for-each-ref`).
- Every file when the index was read: matches the code (`tree_hashes` over `arm.paths`, and `pathList` on the check side).
- Path list, harness files, env, args, policy: match the code. The harness map also holds the manifest's declared `inputs`. The Data model section mentions them, so this is acceptable.
- Runtime: the doc says "the Node version and platform". The code compares `{node, platform, arch, git --version, bash --version}`. A git or bash upgrade makes every suite run, and the doc does not say so. The doc therefore does not state exactly what is compared (part of B1).
- Measurement (lines 85-96, CHANGELOG bullet 3): the numbers match docs/analysis/precise-suite-evidence-reuse.md (R0 107/110, R1 109/121, 1 of 8 reused, aai-ride-status). The doc says plainly that nothing was saved. The count of 11 matches `tests/skills/suite-reuse.json`: the 5 suites from main plus 6 new ones. The measurement is reported honestly.

### BLOCKING

- **B1. A second general guarantee after the caveat, and an inexact runtime list (product doc lines 31-35).** The paragraph's last sentence, "Anything the checker cannot account for makes the suite run.", is a blanket guarantee, and the caveat just before it contradicts it: a stat-only read, or a read outside the checkout, is something the checker cannot account for, and that suite is REUSED, not run. The code has a closed set of fail-closed reasons (`bash-startup-hook`, `manifest-invalid`, `not-declared`, `live`, `store-corrupt`, `no-record`, `policy`, a changed component, `log-missing`; on the record side `trace-unavailable`, `no-trace`, `inputs-changed-during-run` and others). Fix: delete the sentence, so that one caveat remains. Also replace "the Node version and platform" with "the runtime (Node version, platform, CPU architecture, git and bash versions)".
- **B2. Stale claims from the source-text reader (lines 43 and 72).** "A suite qualifies only when its whole closure is known" describes the retired static closure. Qualification is now `lint --admit` plus a manifest entry (lines 58-59 say so). `check` no longer emits `inputs-unresolvable`: the string does not occur in `.aai/` or test-framework.sh. Fix: line 43 should say "A suite qualifies only when `lint --admit` passes for it; `explain <suite>` shows what its last record read". Line 72 should cite current reasons, for example `no-record`, `log-missing`, `policy` or the first changed component.
- **B3. Close-out step 1 is missing "reuse is off where access times are not recorded".** On a volume where reading a file does not advance its access time (noatime, or the canary probe fails), `record` returns `trace-unavailable` and never stores a pass, so nothing is ever reused there. Fix: add one Limits bullet saying this.
- **B4. The CHANGELOG does not name the `--minimal-tree` retirement (close-out step 2).** `lint --minimal-tree` now exits 0 silently, because the flag is ignored and only the plain manifest lint runs. Anyone who scripted the old gate gets a green result that admits nothing. Fix: the second bullet should say that `lint --admit` replaces `lint --minimal-tree`, and that the old flag is no longer an admission gate.
- **B5. RFC-0017 phase 5 row keeps a present-tense claim the code no longer backs.** The edited row still says "three suites qualify today" for the first slice, next to the new sentence saying 11 are admitted. Fix: change it to "three suites qualified at that slice" (past tense, tied to the slice).

### NON-BLOCKING

- NB-1. The Interfaces section lists `check|record|forget|lint|explain` but not the `arm|collect` subcommands the framework now calls, nor `lint --admit --changed-since <ref>`. Disposition: add both in the same edit as B1-B5.
- NB-2. The `lint --admit` description (lines 45-48) leaves out the poisoned run: unread files are poisoned, and the suite must still pass when the git index is not read. This is an understatement, not an overclaim. Disposition: optional half-sentence.

## Merge e5c880b7 ledger integrity

`git diff origin/main...HEAD -- docs/ai/decisions.jsonl docs/ai/EVENTS.jsonl docs/ai/METRICS.jsonl`: 0 removed lines; +16, +1 and +1 lines. HEAD's merge parent is origin/main (de74d468), so the comparison is against current main. The diff is additions only.

## cannot_verify

- I did not reproduce the R0/R1 wall times. I checked them only against the analysis note.
- I did not run the CI behaviour of `lint --admit` (`ADMIT-OFF ci`) in this review.

## state_update_commands

```
node .aai/scripts/state.mjs set-code-review --required true --status fail \
  --report docs/ai/reviews/review-reuse-for-docs-reading-suites-closeout-20261102T094025Z.md \
  --base-ref main --head-ref 5c4a1db2 \
  --scope ".aai/SKILL_VERIFY.prompt.md .aai/scripts/lib/checkout-trace.mjs .aai/scripts/suite-reuse.mjs .aai/system/PROFILES.yaml CHANGELOG.md docs/INDEX.md docs/ai/EVENTS.jsonl docs/ai/METRICS.jsonl docs/ai/decisions.jsonl docs/ai/overview-data.json docs/ai/overview.html docs/ai/reviews/review-reuse-for-docs-reading-suites-20261102T082812Z.md docs/ai/roadmap.yaml docs/analysis/precise-suite-evidence-reuse.md docs/issues/CHANGE-DRAFT-reuse-for-docs-reading-suites.md docs/product/precise-suite-evidence-reuse.md docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md docs/specs/SPEC-DRAFT-spec-reuse-for-docs-reading-suites.md tests/skills/lib/read-trace.cjs tests/skills/lib/suite-reuse.test.mjs tests/skills/suite-map.yaml tests/skills/suite-reuse.Tests.ps1 tests/skills/suite-reuse.json tests/skills/test-aai-suite-reuse.sh tests/skills/test-framework.sh" \
  --notes "close-out review: spec_compliance fail, code_quality fail. B1 blanket 'anything unaccounted runs' sentence contradicts caveat + runtime list omits arch/git/bash; B2 stale 'whole closure' and 'inputs-unresolvable' claims; B3 missing 'off where atime not recorded' Limit; B4 CHANGELOG omits --minimal-tree retirement (flag now silently rc 0); B5 RFC row 'three suites qualify today'. Doc-only fixes; ledgers additions-only after merge."
```
