# Code Review r5 (final delta): node-first-third-slice

- Started: 2026-10-24T09:29:47Z
- Ended: 2026-10-24T10:03:37Z
- Report UTC stamp: 20261024T100337Z (copy as docs/ai/reviews/review-node-first-third-slice-20261024T100337Z.md)
- Reviewer: Code Review role, round 5, dispatched (the state write is returned, not run)

```yaml
review:
  scope: "9659f076..02544f7d (delta, one commit 02544f7d); full range 4d4566bc..02544f7d, rounds 1-4 reviewed the rest"
  spec: docs/specs/SPEC-0249-spec-node-first-third-slice.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "no production change in the delta; r3/r4 walk stands" }
      - { ac: Spec-AC-02, call: compliant, citation: "no production change in the delta; r3/r4 walk stands" }
      - { ac: Spec-AC-03, call: compliant, citation: "no production change in the delta; r3/r4 walk stands" }
      - { ac: Spec-AC-04, call: compliant, citation: "D-1 text at spec:140 now describes the gap by class. All six claims were checked against the old ps1 regex under pwsh 7: case, prefix, comment and later-key all match; quoted (single and double) and flow do not. Code unchanged; TEST-2630 green" }
      - { ac: Spec-AC-05, call: compliant, citation: "no production change in the delta" }
      - { ac: Spec-AC-06, call: compliant, citation: "guard at expert-fetch.mjs:189 is unchanged. TEST-2634 (expert-fetch.test.mjs:370-384), TEST-2635 (:386-397) and the launcher variants in test_2630 (test-aai-expert-fetch.sh:264-271) each go red under the mutants /.*/, /^[a-zA-Z][a-zA-Z0-9_-]*$/, /^[a-z][a-z0-9_.-]*$/ and /^[a-z][a-z0-9_-]*$/i (TEST-2635 does not cover the dot mutant, by design). The AC row Tests cell (spec:487) now lists TEST-2634 and TEST-2635, and green logs for both exist" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-2612 now uses /\\bimport\\s*\\(/ (test-aai-expert-fetch.sh:191). Restoring the old 'import(' substring check makes the shape loop go red on \"const n = await import ('node:net');\"" }
      - { ac: Spec-AC-08, call: compliant, citation: "no change in the delta" }
      - { ac: Spec-AC-09, call: compliant, citation: "no change in the delta" }
      - { ac: Spec-AC-10, call: compliant, citation: "no change in the delta" }
      - { ac: Spec-AC-11, call: compliant, citation: "no change in the delta" }
      - { ac: Spec-AC-12, call: compliant, citation: "no change in the delta" }
      - { ac: Spec-AC-13, call: compliant, citation: "no change in the delta" }
      - { ac: Spec-AC-14, call: compliant, citation: "no change in the delta" }
      - { ac: Spec-AC-15, call: compliant, citation: "no change in the delta" }
      - { ac: Spec-AC-16, call: compliant, citation: "spec-amend list --strict on the probe copy exits 0 with unsigned-untracked=0 and unclassified=0. The new 09:24:57Z record is unsigned-tracked (fu-amend-spec-node-first-third-slice, open). restamp reports that the frozen_sha256 anchor already matches the content. spec-lint passes" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-expert-fetch.sh, line: 191,
          issue: "The dynamic-import pin still misses a comment between import and the parenthesis.",
          failure_scenario: "\"await import /*x*/ ('node:net')\" is valid ESM, and /\\bimport\\s*\\(/ does not match it. The module has no dynamic import, and the only way to add one is a deliberate evasion inside a reviewed file. P3 assurance strength; nothing bit." }
  cannot_verify:
    - { claim: "mutation evidence for TEST-2634 exists under docs/ai/tdd/node-first-third-slice/mut/",
        closes_with: "the worktree has red/ and green/ logs for TEST-2634 and TEST-2635, and mut/ for TEST-2635 only. The running validator's mutation-gate pass or its logs would close this. I applied the row's own sed cell through parseSedExpr in a probe copy; TEST-2634 went red, but that is not the recorded evidence." }
    - { claim: "TEST-2635 and the Zblocked launcher case bite on a case-sensitive filesystem (Linux CI)",
        closes_with: "I measured this on macOS APFS only, where Zblocked.md and zblocked.md are one file. By reading the code: on Linux the test plants two separate files, and the loosened guard serves Zblocked.md because the registry lookup finds no category for it, so the test goes red. A CI mutation run on Linux would show it directly." }
    - { claim: "the full bash suite and the CI legs (Linux, Windows Pester) are green at 02544f7d",
        closes_with: "the validator's full sweep and CI. I ran the 28-case node file and test-aai-expert-fetch.sh in full in a probe copy; both are green." }
  overall: pass
```

## Scope and spec

- Range: 9659f076..02544f7d, one commit (02544f7d). Spec: docs/specs/SPEC-0249-spec-node-first-third-slice.md.
- All probes ran in copies under cr17-work/ made with `git archive HEAD`. The worktree /private/tmp/aai-node-first-3 was only read. HEAD there is 02544f7d.
- Coaching check: the dispatch restated the commit's claims and listed what to check. It did not pre-rate findings. Its severity guidance matches the H6 policy. I verified every claim myself.

## Checks

1. **No production code.** Confirmed. `git diff --stat 9659f076..02544f7d` shows four paths: docs/ai/decisions.jsonl, the spec, tests/skills/lib/expert-fetch.test.mjs and tests/skills/test-aai-expert-fetch.sh. expert-fetch.mjs is untouched.
2. **NB-1 (D-1 by class): closed.**
   - The parenthetical now names four classes: case-insensitive, prefix, inside a comment, and no list boundary. It gives an example of each and states the reverse direction (quoted and flow items).
   - pwsh 7 against `blocked_categories:[\s\S]*?- zblocked`:
     - case, prefix, comment and later-key all match (True);
     - single-quoted, double-quoted and flow forms do not match (False).
   - The text no longer gives an exhaustive count, so no false record remains.
   - Not a finding: the old regex also took the category unescaped as regex text. No real category holds a metacharacter that changes the match.
3. **NB-2 (case and dot pinned): closed.** Each mutant below ran against all three tests in a separate probe copy.

   | Mutant at expert-fetch.mjs:189 | TEST-2634 | TEST-2635 | test_2630 (launcher) |
   |---|---|---|---|
   | `/.*/` (TEST-2634 cell) | red | red | red on `../x` |
   | `/^[a-zA-Z][a-zA-Z0-9_-]*$/` (TEST-2635 cell) | red | red | red on `Zblocked` |
   | `/^[a-z][a-z0-9_.-]*$/` (dot allowed) | red | green (out of its scope) | red on `type.script` |
   | `/^[a-z][a-z0-9_-]*$/i` | red | red | red on `Zblocked` |

   - TEST-2629 and TEST-2610 stay green under all four mutants, which is correct.
   - Both recorded sed cells were applied through the gate's own `parseSedExpr`. Each yields exactly the intended mutant and is not a no-op.
4. **NB-3 (traceability rows and disclosure): closed.**
   - The TEST-2629 row no longer claims the `../x` case.
   - The TEST-2630 row names the planted launcher cases.
   - TEST-2634 names its plants, and there is a new TEST-2635 row.
   - The D-22 mapping line (spec:462) and the Evidence and Tests cells of Spec-AC-06 (spec:487) cite TEST-2634 and TEST-2635.
   - The AC statement text is unchanged.
   - The cited green logs exist in the worktree (gitignored).
5. **NB-4 (`import (`): closed.**
   - Three new shapes are in the loop: with a space, without a space, and with a newline.
   - Reverting the check in a test copy goes red on the space shape.
   - The module's own `import.meta` and static imports do not trip the regex; the base run is green.
6. **Ledger record.**
   - Exactly one `+` line is appended at the end of decisions.jsonl, and no earlier line is removed.
   - Its `what` matches the diff item by item: D-1 by class, TEST-2635, the TEST-2634/2629/2630/2612 rows, the D-22 mapping, the Spec-AC-06 cells, and "code is unchanged".
   - It is classed contract, tracked_by fu-amend-spec-node-first-third-slice, owner_signoff false. Under the current convention it waits on the owner's signature, not on another round.

## Findings

- **NB-1 (P3, assurance strength).** tests/skills/test-aai-expert-fetch.sh:191. A comment between `import` and `(` evades the dynamic-import pin; failure scenario in the yaml block above. Recommended disposition (d): `accepted residual: the module has no dynamic import, and evading the pin takes a deliberate comment-split inside a reviewed file; nothing bit and no false record remains.`

## Info (does not gate)

- The r1-r4 review reports are still untracked in the worktree (`?? docs/ai/reviews/review-node-first-third-slice-2026102*.md`). Per H4, stage them together with this report in the PR commit.

## Warning dispositions (H6). The orchestrator records these.

- NB-1: (d) accepted residual, quoted above. No ref is needed.

## Next steps

- No further remediation round. Await the validator's sweep and mutation evidence (cannot_verify 1 and 3), then the PR and the owner signature on fu-amend-spec-node-first-third-slice.
