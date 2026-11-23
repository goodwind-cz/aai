# Code review: node-first-phase5-closeout (L3, recheck full)

security_relevant: true

```yaml
review:
  scope: "git diff 0ff18d63..0c9ba67a (48 files: the STATE code_review.scope paths plus tests/skills/lib/phase5-row-status.mjs, its 14 caller files, the ledgers and docs/INDEX.md)"
  spec: docs/specs/SPEC-DRAFT-spec-node-first-phase5-closeout.md (frozen, plus the 13 spec_amendment records of ref node-first-phase5-closeout)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "TEST-4024 PASS (reviewer run on a scratch clone at 0c9ba67a); RFC-0017 Kept native table, 9 rows" }
      - { ac: Spec-AC-02, call: compliant, citation: "TEST-4025 PASS (reviewer run); script-classes.mjs strict rc 0 on the worktree" }
      - { ac: Spec-AC-03, call: compliant, citation: ".aai/scripts/aai-release.mjs:42-108; TEST-4026 PASS (node --test 72/72); DR-R1 withdrawn and DR-R3 narrowed by the 03:53:32Z measurement amendment, two-token forms by 05:06:24Z" }
      - { ac: Spec-AC-04, call: compliant, citation: ".aai/scripts/aai-release.ps1 (14 code lines, ASCII, no param block); TEST-4027 matrix PASS under local pwsh 7" }
      - { ac: Spec-AC-05, call: compliant, citation: "TEST-4028 PASS locally (Pester passed=6 skipped=0 failed=0); Windows PowerShell 5.1 leg read by Validation on ps1-quality 45258428645, see cannot_verify" }
      - { ac: Spec-AC-06, call: compliant, citation: ".aai/scripts/cloudflare-share.mjs:18,43-59; TEST-4029 PASS; RED in mutation-TEST-4029.txt and the validator's red-TEST-4029-prechange-module.log" }
      - { ac: Spec-AC-07, call: compliant, citation: "tests/skills/lib/install-parity.mjs:194-207; TEST-4030 PASS including the real SY-01 and UP-01 run with twins node,launcher" }
      - { ac: Spec-AC-08, call: compliant, citation: "TEST-4031 PASS; root-cause clause NOT met, waived by the owner (hitl_decision 17:26:32Z, amendments 17:25:27Z and 19:08:34Z); allowlist row tracked by a P3 follow-up instead of D-ALLOW's accepted/removed; hosted H2 in cannot_verify" }
      - { ac: Spec-AC-09, call: compliant, citation: "install-parity.mjs:793-809; TEST-4032 PASS including the Pester function under pwsh; hosted H2 in cannot_verify" }
      - { ac: Spec-AC-10, call: compliant, citation: "TEST-4033 PASS; per-commit narrowing of the D-HOSTED diff check disclosed 21:02:30Z" }
      - { ac: Spec-AC-11, call: compliant, citation: "TEST-4034 PASS; fu-parity-win-odd-root-dirs dropped as superseded (owner amendment 17:25:27Z), not closed as done" }
      - { ac: Spec-AC-12, call: compliant, citation: "TEST-4035 PASS (33 launchers, 17 ps1, from a scratch extended install)" }
      - { ac: Spec-AC-13, call: compliant, citation: "TEST-4036 PASS; the helper is not on the ps1-quality path lists, disclosed 03:53:26Z" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: tests/skills/test-aai-phase5-closeout.sh, line: 520,
          issue: "TEST-4036 pins the literal heading '## [unreleased] — Node-first phase 5 closeout'; the release cut rolls every '## [unreleased] — ' heading into '## [vYYYY.MM.DD] — '",
          failure_scenario: "the first release after merge rolls CHANGELOG.md; the release PR's full skill-suite run (the aai-phase5-closeout suite is also selected by CHANGELOG.md) fails TEST-4036 with 'CHANGELOG.md holds 0 headings'. backed-by: repro docs/ai/reviews/review-node-first-phase5-closeout-20261123T212343Z.repro-B1.sh" }
      - { rank: BLOCKING, file: tests/skills/test-aai-phase5-closeout.sh, line: 335,
          issue: "TEST-4033 (lines 335 and 356) and TEST-4034 (line 458) require follow-up items of later work to stay open: the P3 successor fu-parity-win-odd-root-cause must remain an open P3, and the three outside-ref items must remain open P2",
          failure_scenario: "a later ride resolves fu-parity-win-odd-root-cause (the item this ride filed for exactly that) or fu-release-pwsh-identity-crash; its PR's full skill-suite fails TEST-4033 and TEST-4034 ('the successor ... is not an open P3', '... is not an open P2 outside the plan refs') for an unrelated change. backed-by: repro docs/ai/reviews/review-node-first-phase5-closeout-20261123T212343Z.repro-B2.sh" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-phase5-closeout.sh, line: 286,
          issue: "TEST-4033 requires the latest re-measure section to be section 7 (line 286) and its file table to equal the live measurement, including kept-native code-line counts (line 302); a later section 8 is refused, so the only way back to green is rewriting the dated section 7",
          failure_scenario: "the scheduled deletion of the seven deprecation launchers (next release, plan owner decision 2), or any line added to aai-run-tests.sh, test-residue.sh or claude-hook-gate.sh, fails TEST-4033 (reproduced: git rm of the seven retired launchers on a scratch clone gives 'the section 7 file table differs from the measurement')" }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-release.mjs, line: 77,
          issue: "under --launcher ps1 a switch followed by a space-separated boolean word now takes it as its value; this widens the grammar beyond the CHANGELOG's three listed boundary changes and the 05:06:24Z amendment's 'behaviour of every form accepted before is unchanged'",
          failure_scenario: "'aai-release.ps1 -DryRun false -Confirm -NoRemote -Version v9' was refused (exit 1, 'Unknown argument: false') by the frozen launcher under -File and in session; it now performs a local cut and creates chore/release-v9 (reviewer probe, pwsh 7); without -NoRemote it would reach the remote finish. The new reading matches the literal intent, but the public-boundary record does not name it" }
  cannot_verify:
    - { claim: "Hosted H1 to H3 (Windows PowerShell 5.1 and pwsh 7 Pester, windows-parity AAI-HOST-CHECK lines, wsl1, Linux gate, skill-suite) pass", closes_with: "gh run view 45258428645 and 45258436994 read by the reviewer; the reviewer only confirmed both concluded success on 5af29daa via gh run list" }
    - { claim: "The final head 0c9ba67a (allowlist tracker change, ledger lines) is green on the hosted runners; no ps1-quality or skill-suite run exists for d8b48e10 or 0c9ba67a", closes_with: "the pull request's ps1-quality and skill-suite runs on its final head (D-HOSTED step 5)" }
    - { claim: "Windows PowerShell 5.1 behaviour of the new launcher (List[string] splatting to a native command, the -Switch: and colon-dropped token shapes) beyond the six TEST-4028 cases", closes_with: "a 5.1 run of the D-RELEASE matrix (TEST-4027 runs under pwsh 7 only)" }
    - { claim: "The odd root directories are not born by the shipped path on Windows under conditions other than the hosted runner", closes_with: "fu-parity-win-odd-root-cause naming the creating process" }
  overall: fail
```

## Scope and preflight

- STATE: `worktree.user_decision: worktree`, base 0ff18d63, branch chore/node-first-phase5-closeout at HEAD 0c9ba67a (pushed). `git status --porcelain`: only the dirty telemetry the dispatch named (EVENTS.jsonl, overview*, test-runs.jsonl), outside the reviewed diff.
- Scope reviewed: `git diff 0ff18d63..0c9ba67a`, all 48 files. The STATE `code_review.scope` list names 29 paths; it omits `tests/skills/lib/phase5-row-status.mjs`, its 14 callers (rounds 2 and 3) and the ledgers. They were reviewed anyway, and the returned `set-code-review` command names the diff range.
- Dispatch prompt: it named focus areas and did not pre-rate severity or predict findings. Its exclusion of dirty telemetry covers files outside the diff only. No coaching recorded.
- The validation PASS report (VALIDATION-20261123T203850Z) was read for context only. It validated d8b48e10. 0c9ba67a adds one allowlist tracker change and four ledger lines, which were reviewed here.

## Spec compliance: deviations from the frozen spec

All of these are disclosed by an amendment unless noted otherwise.

1. DR-R1 is withdrawn and DR-R3 narrowed (03:53:32Z, measurement class). The module binds unambiguous prefixes and the first bare word, as the frozen launcher measurably did. The matrix confirms old-equal results for M15, M17, M19 and M21 to M26.
2. Two-token colon forms and colon-dropped boolean words (05:06:24Z). Finding N2 covers the part of this that the record does not name.
3. Spec-AC-08's root-cause clause is not met. It is waived by owner decision (hitl_decision 17:26:32Z; amendments 17:25:27Z and 19:08:34Z). fu-parity-win-odd-root-dirs is dropped as superseded, not fixed.
4. **Not disclosed by an amendment:** allowlist row `win-sh-odd-root-dirs` is neither removed nor `accepted` as D-ALLOW says. Instead it is tracked by the P3 follow-up `fu-parity-odd-row-tracker-successor` (0c9ba67a; validation r3 N5). This is reasonable given the waived cause. The orchestrator should add a one-line disclosure amendment.
5. TEST-4033's D-HOSTED step 4 check is per commit, not the literal `git diff <H1> HEAD` (21:02:30Z).
6. TEST-4025 lives in the hygiene pack. The helper is not on the ps1-quality path lists (03:53:26Z).
7. Evidence contract: no RED log at `docs/ai/tdd/node-first-phase5-closeout/red/` for TEST-4028, TEST-4029 or TEST-4035, and no GREEN log there for TEST-4027, TEST-4028 or TEST-4029. The substance exists elsewhere: RED mutation records for all 13 rows (replay 13/13), the validator's `red-TEST-4029-prechange-module.log`, and the reviewer's own GREEN runs.
8. The AC status table still reads `planned` for 10 rows. This is the AC-FLIP deferral to close, which the canon allows.

TEST evidence the reviewer ran (local macOS, node 22.23.1, pwsh 7):
- `node --test aai-release.test.mjs cloudflare-share.test.mjs`: 72/72, including the TEST-4027 matrix.
- `install-parity.test.mjs` TEST-4030 to TEST-4032: 30/30.
- TEST-3570 and TEST-3975: 10/10.
- The whole `test-aai-phase5-closeout.sh` on a scratch clone at 0c9ba67a: rc 0.
- `test_4025` and `test_4028_ps1_pester`: PASS.
- `script-classes.mjs strict`: rc 0.

## Findings

### B1 (BLOCKING): TEST-4036 breaks at the next release cut

- **Where:** tests/skills/test-aai-phase5-closeout.sh:520.
- **Problem:** `TITLE = "## [unreleased] — Node-first phase 5 closeout"` must occur exactly once. `/aai-release` rolls every `## [unreleased] — ` heading into `## [vYYYY.MM.DD] — `.
- **Precedent:** this class has bitten before. tests/skills/test-aai-hook-installer-docs.sh:106 and test-aai-merge-policy.sh:5413 accept both spellings for exactly this reason.
- **Failure scenario:** the release PR's full skill-suite fails TEST-4036.
- **backed-by:** repro docs/ai/reviews/review-node-first-phase5-closeout-20261123T212343Z.repro-B1.sh. It exits 0 when it bites: control PASS, rolled FAIL "CHANGELOG.md holds 0 headings".
- **Fix:** accept `## [unreleased] — ` or `## [vYYYY.MM.DD] — ` before the title, and read the body under whichever is found. Spec-AC-13's "SHALL hold one heading of the D-WIRE title" is met at merge time either way.

### B2 (BLOCKING): the record checks require later follow-ups to stay open

- **Where:** tests/skills/test-aai-phase5-closeout.sh:335 and :458 (`succ.closed || succ.severity !== "P3"`), and :356 (`it.closed || it.severity !== "P2" || inScope(it)`).
- **Problem:** TEST-4033 and TEST-4034 freeze the ledger state of 2026-11-23 into permanent assertions about items this ride does not own.
- **Failure scenario:** resolving `fu-parity-win-odd-root-cause` fails both cases. That item is the P3 successor this ride filed so the cause would be found. Resolving `fu-release-pwsh-identity-crash` (or either other outside-ref P2) fails TEST-4033. Either way, an unrelated later pull request goes red.
- **Why the suite selection does not help:** the suite is not selected by `docs/ai/decisions.jsonl`. The failure surfaces on the full skill-suite of that later PR, or in the next full sweep.
- **backed-by:** repro docs/ai/reviews/review-node-first-phase5-closeout-20261123T212343Z.repro-B2.sh. It closes each item on a scratch clone with the shipped CLI. Control PASS; three FAILs.
- **Fix:**
  - Successor: accept it open at P3, or closed (any status) once the dropped record names it.
  - Outside-ref items: check only that each named id exists and its ref lies outside the plan refs (the "why outside" claim), not that it stays open.

### N1 (NON-BLOCKING, P2): TEST-4033 forbids any later re-measure section

- **Where:** tests/skills/test-aai-phase5-closeout.sh:286 and :302.
- **Problem:** TEST-4022 (generalized by this ride) accepts the latest `## N. Re-measure` section. TEST-4033 refuses any latest section other than 7, and it compares section 7's file table, including the kept-native code-line counts, with the live tree.
- **Failure scenario:** the next edit of a kept-native script fails TEST-4033 (its counts are in the table: aai-run-tests.sh 540, test-residue.sh 526, and so on). So does the deletion of the seven retirement launchers, which section 7 itself schedules for the next release (reproduced on a scratch clone). The only way back to green is rewriting a dated record.
- **Why not BLOCKING:** the live-tree coupling is the design TEST-4022 already had, and the spec's TEST-4033 row asks for "section 7 as the latest".
- **Recommended disposition:** (a) remediate in-tree together with B2. Let TEST-4033 pass when a later re-measure section exists, and check section 7 only while it is the latest. Otherwise (b) a typed follow-up `fu-p5c-record-pins-live-tree` (P2).

### N2 (NON-BLOCKING, P3): a widened grammar form the public-boundary record does not name

- **Where:** .aai/scripts/aai-release.mjs:77.
- **Problem:** under `--launcher ps1`, a switch followed by a space-separated `true`/`false`/`$true`/`$false` now takes it as its value. This is the 5.1 `-File` colon-drop workaround.
- **Measured with the frozen reference** (reviewer probe, pwsh 7, -File and in session):
  - `-DryRun false -Confirm -NoRemote -Version v9`: old exit 1 `Unknown argument: false`; new exit 0, cuts `chore/release-v9`.
  - `-Confirm false ...`: old exit 1; new plans.
- **Assessment:** the new reading matches the literal intent, but a previously refused line can now cut a release (and, without `-NoRemote`, reach the remote finish). The CHANGELOG lists "three forms" that change, and the 05:06:24Z amendment says behaviour is unchanged for every form accepted before. Neither names this widening.
- **Recommended disposition:** (a) remediate in-tree. Add one CHANGELOG sentence and one disclosure amendment naming the space-separated boolean form. No code change is needed.

### INFO (not gating)

- The ESC handling is correct for every D-REDACT layout. The ANSI_RE order (CSI, OSC, nF, Fp, Fe, Fs, then lone ESC), the window cover after stripping, and the run-wise `[REDACTED]` all hold, and the property test runs through `run`. Two gaps remain:
  - C1 single-byte controls (U+009B CSI, U+009D OSC) are not stripped. The 8-character window property still holds around them, so this is a terminal-hygiene gap outside the spec, not a leak.
  - The eaten-character fragments of fewer than 8 characters are already tracked (fu-cfshare-redact-eaten-chars).
- `matchPs1Flag`'s ambiguous branch is unreachable with the five real flags (distinct first letters). It is tested through the injectable table.
- The sh launcher grammar is unchanged. Under `--launcher sh` or none, the join, bare-word and PS1 branches are all gated on `o.launcher === 'ps1'`, and the error text is the same token.
- The D-ODD diagnostic (`REF_GUARD_HELPER`, `oddDiagCandidates`, `runOddDiag`) is spec-required (D-ODD step 2) and off by default (install-parity.mjs:924). The CI env that set it was removed in 6742a8ea. It writes only under `<ctx.root>/odd-diag` and an mkdtemp it removes in `finally`. When on, it starts `claude`, `codex` and `gemini` with `--version`; worth stating if it is ever re-enabled.
- tests/skills/test-aai-release-cut.sh:405 and :819 interpolate `$PROJECT_ROOT` into a JS string literal. A checkout path holding `"` or `\` would break it. Suites run under POSIX paths, so there is no bite today.
- Scratch safety holds:
  - The launcher twin refuses a target outside the scratch root or an empty target.
  - release-reference.mjs and the new suite remove only marked, prefixed directories under the temp root.
  - TEST-4035 runs launchers under `env -i` with a scratch HOME and spool.
  - bootstrap-node now passes the large amendment JSON through a temp file, not a pipe.
  - No early-closing reader was found under `set -euo pipefail` in the new bash code.

## WARNING dispositions (H6)

- N1: recommended (a) remediate in-tree with B2; fallback (b) `fu-p5c-record-pins-live-tree` P2. The orchestrator records the choice.
- N2: recommended (a) remediate in-tree (CHANGELOG sentence plus disclosure amendment).

## Reviewer hazard disclosure

All probes ran on a scratch clone and a scratch probe repository under the session scratchpad. Nothing ran on the branch checkout except read-only git, the node tests, script-classes strict and `gh run list`. One probe script ran `git worktree prune` inside the scratch probe repository, which had no linked worktrees. That is the letter of HAZ-WORKTREE, though no real repository was touched.

## Next steps

1. Remediate B1 and B2 test-first: a RED case per form (rolled heading; successor or outside-ref item closed), then the fix.
2. Fold N1 into the same remediation if the orchestrator chooses (a), and add the N2 disclosure.
3. Add the D-ALLOW deviation disclosure (deviation 4).
4. Re-review: the same single pass over the new head. Then the PR's final-head CI (D-HOSTED step 5).
