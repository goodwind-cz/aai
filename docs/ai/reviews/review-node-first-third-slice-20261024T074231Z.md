```yaml
review:
  scope: 4d4566bc..b14ab7e3 (branch change/node-first-third-slice, worktree /private/tmp/aai-node-first-3); round 2, delta focus b14ab7e3
  spec: docs/specs/SPEC-0249-spec-node-first-third-slice.md (amended, frozen_sha256 366ae7dc...)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "TEST-2601 green; real registry 110 keys, blocked = 2 categories, CRLF/BOM deep-equal" }
      - { ac: Spec-AC-02, call: compliant, citation: "TEST-2602 green (unchanged since r1)" }
      - { ac: Spec-AC-03, call: compliant, citation: "TEST-2603 green (unchanged since r1)" }
      - { ac: Spec-AC-04, call: compliant, citation: "expert-fetch.mjs:65-78,129-140; TEST-2604/2605/2606/2627/2628/2630 green; mutations M1,M2,M4,M7a,M7b,M9,M10 killed" }
      - { ac: Spec-AC-05, call: compliant, citation: "expert-fetch.mjs:155-164; TEST-2607/2608/2609/2631 green; M5 killed (see NB-A for an unlisted write-failure shape)" }
      - { ac: Spec-AC-06, call: compliant, citation: "expert-fetch.mjs:184-191; TEST-2610/2629 green; M3, M8 killed" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-2611/2612 green; M6a-c killed, M6d survives (NB-C)" }
      - { ac: Spec-AC-08, call: compliant, citation: "TEST-2613/2614/2615 green; launchers 9 and 19 lines" }
      - { ac: Spec-AC-09, call: compliant, citation: "TEST-2616 parity, TEST-2617 Pester 12/12 0 skipped (local pwsh)" }
      - { ac: Spec-AC-10, call: compliant, citation: "TEST-2618 green" }
      - { ac: Spec-AC-11, call: compliant, citation: "TEST-2619/2620/2621 green" }
      - { ac: Spec-AC-12, call: compliant, citation: "wc -l 200+9+19 = 228 <= 230; RFC row says 444 to 228; TEST-2622 green" }
      - { ac: Spec-AC-13, call: compliant, citation: "TEST-2623 green" }
      - { ac: Spec-AC-14, call: compliant, citation: "TEST-2624 green" }
      - { ac: Spec-AC-15, call: compliant, citation: "TEST-2625 green; test_2419 and test_2518 pass on the done row" }
      - { ac: Spec-AC-16, call: compliant, citation: "TEST-2626 green; spec-amend list --strict rc 0" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/expert-fetch.mjs, line: 162,
          issue: "rmSync(tmp, { force: true }) inside the catch can itself throw, so the D-23 error line is replaced by an uncaught exception",
          failure_scenario: ".aai/cache is a regular file (or .aai/cache/experts is a file, or a directory sits at .tmp_<key>_<pid>): mkdirSync/writeFileSync throws, then rmSync throws ENOTDIR/ERR_FS_EISDIR; CLI prints a 19-line node stack trace and no 'ERROR: Cannot write the cache' line (exit 1 kept). At 42a68110 all three shapes printed the clean line. Regression introduced by the remediation." }
      - { rank: NON-BLOCKING, file: .aai/scripts/expert-fetch.mjs, line: 66,
          issue: "blocked_categories parser still fails open on three plausible registry shapes",
          failure_scenario: "(1) a second column-0 'blocked_categories:' heading: only the first list is read (old ps1 blocked); (2) '  - # 09-meta-orchestration' or '  - \"\"' yields an empty-string item, so blockedBroken stays false although no category is readable (D-1 says such a heading fails closed); (3) a stray indented non-dash line inside the list truncates it and later items are ignored (old ps1 blocked)." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-expert-fetch.sh, line: 188,
          issue: "TEST-2612 'exact import set' only collects node:-prefixed specifiers and the stdin token list misses /dev/fd/0",
          failure_scenario: "adding 'import net from \"net\";' to the module keeps TEST-2612 green (mutation M6d survived); readFileSync('/dev/fd/0') would also pass the static check." }
      - { rank: NON-BLOCKING, file: docs/ai/decisions.jsonl, line: 2281,
          issue: "the unsigned contract amendment record does not say that the Spec-AC-04 and Spec-AC-06 statement text was widened",
          failure_scenario: "the owner signs fu-amend-spec-node-first-third-slice from the 'what' line, which mentions D-1/D-22/D-23 and test rows 'mapped to Spec-AC-04, 05 and 06' but not that two AC statements now carry new SHALL clauses (fail-closed list, --body blocked check, D-22 key refusal)." }
  cannot_verify:
    - { claim: "native Windows Pester leg and hosted Linux CI stay green on b14ab7e3", closes_with: "PR CI run (ps1-quality Windows job, skills suite)" }
    - { claim: "no regression in suites outside the selected set", closes_with: "the one full sweep owed before close (AAI_TEST_TIMEOUT=3000)" }
    - { claim: "test-aai-hygiene-pack.sh suite-map pin 112", closes_with: "run in a git checkout; my scratch copy has no .git, so the suite stopped on an unrelated git-ignore case" }
    - { claim: "real gh api behaviour and downstream registries edited by hand", closes_with: "a live fetch against the pinned SHA; a downstream aai-sync install with a hand-edited registry" }
  overall: pass
```

# Code review round 2: node-first-third-slice

- Scope: `git diff 4d4566bc..b14ab7e3` in /private/tmp/aai-node-first-3 (branch change/node-first-third-slice, HEAD b14ab7e3, tree clean apart from the untracked r1 review report). Round 2 re-reads the full range and focuses on the remediation commit b14ab7e3.
- Spec: docs/specs/SPEC-0249-spec-node-first-third-slice.md, ceremony 2, mutation_gate v1, amended by one unsigned contract amendment (ts 2026-10-24T07:34:31Z, tracked by fu-amend-spec-node-first-third-slice).
- Inputs: the r1 review (docs/ai/reviews/review-node-first-third-slice-20261024T070130Z.md) and the validation r1 report (docs/ai/reports/VALIDATION-20261024T072355Z-node-first-third-slice.md).
- Dispatch note: the dispatch listed the claimed fixes and suggested probe directions. It did not pre-rate severity or exclude areas. I treated the probe list as a minimum, not a scope limit.
- Probes ran on copies under the scratch path cr14-work/ only. No restore, stash or reset was used, and the worktree module is byte-identical after the mutation runs (cmp).

## Fix-by-fix verification

| Claim | Result | Evidence |
|---|---|---|
| NB-1: blocked parser fails closed | Holds for every listed spelling. 3 residual fail-open shapes remain (NB-B) | 32-case probe matrix, below |
| NB-2: `--body` applies the blocked check through `blockedRefusal` | Holds | mjs:190; TEST-2629; M3 and M8 (whole fix reverted) killed |
| NB-3: TEST-2612 pins the exact import set | Holds for `node:` specifiers and for node:fs names. A bare specifier slips through (NB-C) | M6a, M6b, M6c killed; M6d survived |
| NB-4: TEST-2419 pass text, 110 keys | Holds | live-status suite rc 0; D-10, D-20 and TEST-2601 say 110 |
| Val NB-3: D-22, D-23 rows | Rows present. D-23 promise broken for one unlisted shape (NB-A) | spec diff; tmp-cleanup probe |
| TEST-2627..2631 with mutation records | Present and killing | each recorded mutation re-run: all killed; mutation-gate GATE PASS 31 rows; records under docs/ai/tdd/spec-node-first-third-slice/ |
| Unsigned contract amendment | Recorded and tracked. `spec-amend list --strict` rc 0, unsigned-tracked. The "what" line under-discloses the AC text changes (NB-D) | decisions.jsonl:2281-2282 |
| RFC row line count | 444 to 228, which equals the live wc -l (200 + 9 + 19) | wc -l |

### Real registry against the old ps1 logic
I ran the old ps1 regex (`blocked_categories:[\s\S]*?- $Category`) under pwsh and the new `parseRegistry` + `blockedRefusal` over all 110 real keys: the results are identical (0 blocked, because no real expert lives in 08- or 09-). With two synthetic experts appended in 09-meta-orchestration and 08-business-product, the results are again identical, and both are blocked.

### Adversarial blocked-list matrix
Each case ran with the list both before and after the `experts:` block. These cases work:
- They block correctly: tabs, tab after the dash, CRLF, a BOM before the heading, nested keys after the list, a heading with trailing spaces or a comment, quoted items, the flow form (quoted and with a comment), blank and comment lines inside the list, and NBSP indent.
- They refuse with the no-readable-item line, which is fail closed: an inline scalar after the colon, a zero-indent dash, a multi-line flow list, a bare heading, `~`, and a dash with no space.
- They serve, which is the intended behaviour: `[]` and a missing heading.

These cases still serve a blocked category (NB-B):
- A duplicate heading. Only the first list is read, so a blocked category in the second list is served, and `blocked_categories: []` followed by a real list blocks nothing. Old ps1 blocked here.
- `  - # 09-meta…` and `  - ""`. Each yields `[""]` and blockedBroken stays false. Old ps1 also served these, but amended D-1 says a heading that yields no item fails closed.
- A list broken by a stray non-dash line. The list is truncated and later items are dropped. Old ps1 blocked here.
- These also differ from ps1, but the spec accepts them: an indented `blocked_categories:` heading under another key, a different case such as `09-META`, a trailing slash, and a mapping item. D-1 chose exact comparison on purpose.

### `.tmp_` cleanup hazard
`rmSync(tmp, { force: true })` cannot delete the wrong file. The tmp path is `<cacheDir>/.tmp_<key>_<pid>`, the key is regex-guarded, and the pid is unique among live processes. After a successful rename the path no longer exists, so force makes the call a no-op. But `force` only suppresses ENOENT. On 42a68110, three write failures printed the D-23 line. On b14ab7e3 they now throw out of the catch block:

| Setup | 42a68110 | b14ab7e3 |
|---|---|---|
| `.aai/cache` is a file | `Cannot write ...: ENOTDIR`, rc 1 | uncaught ENOTDIR from rmSync, 19-line stack, rc 1 |
| `.aai/cache/experts` is a file | `Cannot write ...: EEXIST`, rc 1 | uncaught ENOTDIR, rc 1 |
| directory at `.tmp_<key>_<pid>` | `Cannot write ...: EISDIR`, rc 1 | uncaught ERR_FS_EISDIR, rc 1 |
| read-only dir / dir at `<key>.md` / dir at `.sha_<key>` | clean line | clean line, no tmp left (TEST-2631 shape) |

## Findings and dispositions (H6)

- **NB-A (P2)**, expert-fetch.mjs:162: the cleanup in the catch block can throw, which loses the D-23 error line. This regression came in with the remediation. **Recommended: remediate in tree.** Make the cleanup best-effort, for example `try { rmSync(tmp, { force: true }); } catch {}` on the same line, which keeps the 228-line budget. Add a TEST-2631 case where `.aai/cache` is a file and assert that the Cannot-write line appears with no stack. Fallback: `suggested: fu-expert-fetch-tmp-cleanup-throws`.
- **NB-B (P3)**, expert-fetch.mjs:66-74: three residual fail-open list shapes remain. **Recommended: remediate in tree for the empty item.** Add `.filter(Boolean)` on the block form, as the flow form already has. The duplicate-heading and truncated-list shapes can be fixed in tree by setting blockedBroken on a second column-0 heading, or on a dash item after an interrupting line. They can also be promoted to `suggested: fu-expert-blocked-list-residual-shapes`. Only 2 lines of headroom remain under the 230 budget.
- **NB-C (P3)**, test-aai-expert-fetch.sh:188: the TEST-2612 import pin misses bare specifiers and `/dev/fd/0`. Either remediate in tree (match every `^import .* from` line, not only `node:` ones, and add `/dev/fd/0` to the tokens), or record `accepted residual: P3 assurance strength; module imports verified at head by inspection; bare-specifier and /dev/fd/0 gaps have no bite`.
- **NB-D (P3)**, decisions.jsonl:2281: the amendment "what" line does not name the Spec-AC-04 and Spec-AC-06 statement changes. **Recommended:** before the owner signs, append one clarifying spec_amendment record (or a note) for the same ref and the same tracker. It should state that the Spec-AC-04 statement gained the D-1 spellings and fail-closed clause, and that the Spec-AC-06 statement gained the --body blocked check and the D-22 refusal. The ledger is append-only, so do not edit the existing line.
- INFO: the commit message says "--body refuses a non-registry key". The code and D-22 check key syntax only. The spec text is correct, and a stale cache for a key that was removed from the registry is still served. No action needed.

## Spec deviations
- D-23 ("a failed cache write ... prints `ERROR: Cannot write the cache under <dir>: <code>`") does not hold for ENOTDIR and EISDIR-on-tmp failures (NB-A). The parenthesised cases it lists do hold. No AC statement covers the write-failure path, so the AC walk stays compliant.
- D-1 "a heading that yields no item fails closed" does not hold for a lone empty or comment-only dash item (NB-B, shape 2).

## Commands run (scratch copies)
- `bash tests/skills/test-aai-expert-fetch.sh` (full suite, scratch tree): rc 0, 31 PASS, TEST-2601..2631.
- `bash tests/skills/test-aai-live-status.sh`: rc 0. TEST-2419 shows the new pass text.
- `bash tests/skills/test-aai-triage.sh test_2518_rfc_phase3_row`: PASS.
- Mutation replays: M1 to M10. All were killed except M6d.
- `node .aai/scripts/mutation-gate.mjs --spec …` (worktree, read-only): GATE PASS, 31 rows.
- `node .aai/scripts/spec-amend.mjs list --strict`: rc 0, with the third-slice amendment shown as unsigned-tracked.
- `node .aai/scripts/spec-lint.mjs --path …`: LINT PASS.
- pwsh old-ps1 oracle compared with node over 110 real keys plus 2 synthetic blocked keys: identical.

## Next steps
1. The orchestrator records dispositions for NB-A to NB-D. NB-A is recommended for in-tree remediation before PR.
2. If NB-A or NB-B is fixed in tree, run a short round-3 delta review of the one commit.
3. Owner sign-off on fu-amend-spec-node-first-third-slice, after NB-D's clarifying record.
4. The one full sweep owed before close.
