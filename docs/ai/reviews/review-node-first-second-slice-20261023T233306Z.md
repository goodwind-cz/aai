```yaml
review:
  scope: 8df911c5..c6f35b2f (round 2 delta 82f2487c..c6f35b2f; branch change/node-first-second-slice, worktree /private/tmp/aai-node-first-2)
  spec: docs/specs/SPEC-0248-spec-node-first-second-slice.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "unchanged since round 1; TEST-2501 PASS (node --test 8/8, suite PASS)" }
      - { ac: Spec-AC-02, call: compliant, citation: "unchanged since round 1; TEST-2502..2506 PASS" }
      - { ac: Spec-AC-03, call: compliant, citation: "test-aai-triage.sh:162-167 adds the non-git fixture; stderr discard now pinned (mutation M2 reddens the new test, survives the 82f2487c test); TEST-2507 PASS" }
      - { ac: Spec-AC-04, call: compliant, citation: "unchanged; TEST-2508 PASS" }
      - { ac: Spec-AC-05, call: compliant, citation: "test-aai-triage.sh:274-276 in-session --check; mutation M1 reddens TEST-2511; TEST-2509..2511 PASS" }
      - { ac: Spec-AC-06, call: compliant, citation: "test-aai-triage.sh:329-335 non-ASCII fixture (M3/M3b redden); triage.Tests.ps1:109-117 new case; Pester 9/9, 0 skipped, pwsh 7.6.3; TEST-2512/2513 PASS" }
      - { ac: Spec-AC-07, call: compliant, citation: "unchanged; TEST-2514 PASS" }
      - { ac: Spec-AC-08, call: compliant, citation: "unchanged; TEST-2516/2517 PASS (TEST-2515 not rerun this round, file untouched)" }
      - { ac: Spec-AC-09, call: compliant, citation: "unchanged; TEST-2518 PASS" }
      - { ac: Spec-AC-10, call: compliant, citation: "unchanged; TEST-2519 PASS" }
      - { ac: Spec-AC-11, call: compliant, citation: "unchanged; TEST-2520 PASS" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0248-spec-node-first-second-slice.md, line: 128,
          issue: "D-14's old-ps1 column says the flag was accepted 'by parameter binding (any position, case-insensitive)', which holds only for pwsh -File. In-session (& triage.ps1 --check) the old launcher put --check in $args and ignored it (8df911c5 triage.ps1 has no $args use), so the new $args clause is a second widening on the ps1 side that D-14 does not state.",
          failure_scenario: "An operator reads D-14 to learn what changed for in-session callers: it implies nothing changed under ps1, but a PowerShell-session caller passing --check against a NEEDS-TRIAGE audit now gets exit 1 where it got exit 0 (probe: pwsh -Command \"& p.ps1 --check\" -> Check=False args=[--check])." }
  cannot_verify:
    - { claim: "The new Pester in-session case passes under real Windows PowerShell 5.1 (quoting of the spaced 'aai triage <guid>' scratch path inside -Command, exit $LASTEXITCODE propagation)",
        closes_with: "ps1-quality windows-5_1 and windows-wsl1 Pester steps green on the PR head" }
    - { claim: "Byte-identical non-ASCII output through triage.ps1 on Windows (D-6); TEST-2512's non-ASCII fixture runs only in the bash suite, which CI runs on ubuntu-latest",
        closes_with: "a Windows-side byte comparison, or the validation H1 Windows run; the spec already names this residual (spec lines 402-403, 511)" }
  overall: pass
```

# Code review, round 2: node-first-second-slice

- Scope: `8df911c5..c6f35b2f`; the delta reviewed in depth is `82f2487c..c6f35b2f` (commit c6f35b2f, six files). Round 1 (`review-node-first-second-slice-20261023T225211Z.md`) passed with NB-1..NB-4.
- Spec: `docs/specs/SPEC-0248-spec-node-first-second-slice.md` (frozen, amended in this commit).
- Dispatch note: the dispatch listed questions to check (no severity pre-rating, no scope exclusion). The full delta was reviewed anyway.

## Evidence run

| Command | Result |
|---|---|
| `node --test tests/skills/lib/triage.test.mjs` | 8 pass, 0 fail |
| `pwsh Invoke-Pester tests/skills/triage.Tests.ps1` (pwsh 7.6.3) | Total 9, Passed 9, Failed 0, Skipped 0 |
| `env -u AAI_ROLE bash tests/skills/test-aai-triage.sh` | rc 0, TEST-2501..2514, 2516..2520 PASS |
| `test_2512` and `test_2507` under `LC_ALL=C LANG=C` | PASS (simulates a C-locale CI runner) |
| `spec-lint --path <spec>` | 0 findings |
| `spec-amend list --strict` | rc 0; amendment listed as `unsigned-tracked`, class contract, tracked by `fu-amend-spec-node-first-second-slice` (open) |
| `mutation-gate --spec <spec>` (worktree, read-only) | GATE PASS, 20 rows, 0 degraded |
| `check-cd-subshell-leak.mjs` then `--record` on a scratch copy | check rc 0; the re-recorded file is byte-identical to the committed baseline |

## Does each new test guard its finding? (scratch mutations, isolated copy with its own git)

| Finding | Mutation | Result |
|---|---|---|
| NB-1 | `triage.ps1:7` `if ($Check -or ($args -contains '--check'))` changed to `if ($Check)` | TEST-2511 FAIL ("in-session --check ... got 0"); Pester: one failure, the new in-session case. Guarded on both sides. |
| NB-2 | `triage.mjs:80` stdio[2] `'ignore'` changed to `'inherit'` | New TEST-2507 FAIL ("fatal: not a git repository" on stderr); the 82f2487c version of the test PASSes under the same mutant. Guarded, and the new clause is the only guard. |
| NB-4 (ps1 side) | ps1 pipes Node output through `-replace '[^\x00-\x7e]','?'` | TEST-2512 FAIL: "non-ASCII stdout differs". |
| NB-4 (both sides) | module replaces non-ASCII with `?` before writing | TEST-2512 FAIL: "positive control failed, the em dash did not reach the output". |

The GIT_CEILING_DIRECTORIES prefix on the `cli_run` function call does reach the child process (checked: bash exports a prefix assignment into a function's children), so the non-git fixture is non-git even when TMPDIR sits inside a repository.

## Windows robustness of the new cases

- The Pester case builds `-Command "& '<launcher>' --check; exit $LASTEXITCODE"`. The backtick escapes `$`, so the child sees `$LASTEXITCODE` literally. The launcher path sits in single quotes, so the spaced scratch directory (`aai triage <guid>`) is safe. The only path that would break it is one with a `'` in it, which the GUID scratch under `GetTempPath()` does not produce on a runner. There is no skip, and the syntax is valid in 5.1.
- If 5.1 bound `--check` to `-Check` in-session, which pwsh 7 does not, the case would still pass with exit 1. So it cannot go falsely red on 5.1. In that case it would only stop guarding the `$args` clause there.
- The bash suite (including the non-ASCII fixture) runs only on `ubuntu-latest` (`skill-suite.yml`). The Windows 5.1 code page question therefore applies to no new assertion. The Pester file still asserts ASCII lines only. Windows byte-exactness stays a named residual (cannot_verify 2).

## Baseline lowering (ratchet semantics)

The baseline header says a count may fall and never rise, and a SHRINK keeps its number "until someone re-records on purpose". A lower number is the stricter bar. The five lowered rows (live-spool.sh 2->1, docs-audit 26->21, git-ref-guard 25->24, hygiene-pack 50->49, pr-platform 8->6) match the live counts exactly: a scratch `--record` reproduces the committed file byte for byte, and the checker passes. This resolves validation F1 with the generator, as the file demands. The commit message discloses it. Lowering is safe. The only consequence is that a concurrent branch that raised one of those five files to its old count would now fail the ratchet, which is the ratchet doing its job. Note that the spec's scope (line 57, lines 271-273) allowed the re-record "only if the checker reports the triage.sh count changed". The reason was the new `test-aai-triage.sh` row, not `triage.sh`. This is a deviation in wording only, and the commit message discloses it (INFO).

## D-14 / D-15 honesty and minimality

- D-15 is accurate (validation probe P9; `triage.mjs:20` uses `import.meta.url`) and minimal.
- D-14 is accurate for the sh side and for `pwsh -File`. Probe: `-File p.ps1 --check` and `--CHECK` both bind `Check=True`. It under-states the ps1 in-session widening (finding NB-A above).
- The decisions.jsonl records are append-only (four lines added, none changed). The spec_amendment is `owner_signoff:false` and is tracked by the P2 `fu-amend-spec-node-first-second-slice`, following the additive-with-disclosure convention. F7's two follow-ups are filed. The `what` text of the amendment matches the spec diff (D-13 cell, D-14, D-15, and the TEST-2507/2511/2512 descriptions). The Mutation column is unchanged, as claimed.
- Still unrecorded:
  - Validation F5 (weaker RED evidence for TEST-2512/2513) and F6 (incomplete commit message on 8b8a1526) are informational and live in the validation report. They need nothing more than the PR body disclosure.
  - `tests/skills/test-aai-hygiene-pack.sh` and `docs/ai/decisions.jsonl` are still not in the spec's Inline review scope list. The commit message discloses both (INFO).
  - The round-1 review report is still untracked in the worktree. Stage it with the next commit (SPEC-0013 H4).

## INFO (no gate)

- `test-aai-triage.sh:336`: the TEST-2512 pass message still says "seven fixtures". The non-ASCII fixture is an eighth.
- NB-3 is fixed: `test-aai-hygiene-pack.sh:2131` and `:2146` now read 111.

## Warning dispositions (H6)

| Finding | Recommended disposition |
|---|---|
| NB-A (D-14 old-ps1 cell omits the in-session widening) | (a) remediate in tree: extend the D-14 old-ps1 cell, for example "-File: binding, any position, case-insensitive; in-session `--check` landed in $args and was ignored", and add one clause to the module column. It is a text-only change under the same open amendment. P3. |

Round-1 NB-1..NB-4 are all remediated in tree (c6f35b2f) and verified by mutation above.

## Next steps

1. Fold NB-A (one spec cell). Restamp or amend under the existing tracked amendment, then rerun `spec-lint` and `mutation-gate`.
2. Stage both review reports with the scope.
3. On the PR, confirm the windows-5_1 and windows-wsl1 Pester steps are green (cannot_verify 1).
