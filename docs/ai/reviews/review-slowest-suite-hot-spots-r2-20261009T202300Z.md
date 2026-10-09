# Code Review — slowest-suite-hot-spots (round 2)

```yaml
review:
  scope: "git diff bf740c2e..57cbf875 (remediation 9c561cd7 + owner amendment 57cbf875) plus regression check; worktree /Users/ales/Projects/aai-debt-slowest-suite-hot-spots, branch debt/slowest-suite-hot-spots, base main e80ecabc"
  spec: docs/specs/SPEC-0216-spec-slowest-suite-hot-spots.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "unchanged code; TEST-001/002 replay RED; hygiene-pack PASS 63 s" }
      - { ac: Spec-AC-02, call: compliant, citation: "tests/skills/lib/no-nul-guard.sh:93-134 batch scan, nine-case parity still green (test_136); new fail-closed arm test-aai-hygiene-pack.sh:2100-2109; TEST-003/004 replay RED. Deviation from D2 prose listed below (N1)" }
      - { ac: Spec-AC-03, call: compliant, citation: "suite-weights.tsv aai-hygiene-pack 93 <= 95 (signed amendment 18:09:59Z); TEST-005 replay RED; test_1757 green" }
      - { ac: Spec-AC-04, call: compliant, citation: "unchanged; TEST-006 replay RED" }
      - { ac: Spec-AC-05, call: compliant, citation: "unchanged; TEST-007 replay RED; disclosed normalization deviation stands" }
      - { ac: Spec-AC-06, call: compliant, citation: "amended AC text (signed owner amendment 2026-10-09T18:57:54Z, class contract) keeps only CI weight <= 170; suite-weights.tsv 169; TEST-008/009 replay RED; Verification timing line updated (spec line 429)" }
      - { ac: Spec-AC-07, call: compliant, citation: "test-aai-run-tests.sh:1243-1244 now wait_gone (W2 fixed); TEST-010/011 replay RED" }
      - { ac: Spec-AC-08, call: compliant, citation: "TEST-012/014 replay RED; TEST-013 STAYED GREEN in the spec replay but reddened 4/4 standalone on a scratch copy (load-dependent bite, N2)" }
      - { ac: Spec-AC-09, call: compliant, citation: "aai-run-tests 88 <= 92; local 86 s this round (8-wide run); TEST-015 replay RED" }
      - { ac: Spec-AC-10, call: compliant, citation: "test-aai-suite-select.sh:1938-1942 SHA now read from the run line and the old seed SHA refused (W4 fixed; probed: SHA removed -> empty, old SHA substituted -> rejected by the != check); TEST-016 replay RED" }
      - { ac: Spec-AC-11, call: compliant, citation: "unchanged; TEST-017 replay RED" }
      - { ac: Spec-AC-12, call: compliant, citation: "decisions.jsonl 18:43:30Z records for SPEC-0179 and SPEC-0046; 11 cross-spec measurement records counted (0009 0046 0064 0069 0072 0076 0120 0157 0179 0184 0199), none for 0181/0182; test_137 pinned list 11; TEST-018 replay RED" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/lib/no-nul-guard.sh, line: 152,
          issue: "Fail-closed fix (W1) makes `--check` exit 2 and print a stderr line on an internal failure; frozen D2 says 'Output and exit code of --check stay byte-identical', and the pre-change per-file reference still exits 0 with no output in the same situation. The behaviour change is right, but no spec_amendment record discloses it (the 18:52:13Z record says 'no AC text change' and covers only evidence cells)",
          failure_scenario: "a reader or a later audit holds the spec's D2 sentence as the contract: TMPDIR on a full filesystem now gives exit 2 where the spec says the old (exit 0, empty) behaviour is preserved; the spec text is a false record of the shipped behaviour until disclosed" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-run-tests.sh, line: 749,
          issue: "TEST-013's mutation (shared age wait 'sleep 3' -> 'sleep 0') bites only when the six fixtures are set up in under ~1 s: with MIN_AGE=1 and whole-second ps etime, a slow setup ages the first reap-old fixture past the bound on its own. Not introduced by this delta",
          failure_scenario: "mutation-run --replay on this spec, run while another framework run (test-20261009-190014) and other sessions loaded the host (load avg ~3.6): 'STAYED GREEN TEST-013', replay exit 1. Same mutation on a scratch copy run alone: RED 4/4 (wait_gone found pid still alive after 5s). Validation's replay gate can go red or green by host load" }
  cannot_verify:
    - { claim: "CI weights/leg walls (runs 37966091223, 37972288462) and fail-closed no-NUL behaviour on Linux runners",
        closes_with: "gh run view <id> --json jobs,headSha; a CI run of hygiene-pack on 57cbf875" }
    - { claim: "Spec-AC-03/09 local timing bounds measured alone (this round ran 7 suites 8-wide alongside a second concurrent framework run)",
        closes_with: "batch1/batch3-timing.log in the gitignored evidence tree, or a solo re-run" }
    - { claim: "TEST-013 bites deterministically under CI-level load",
        closes_with: "a replay under bounded CPU load, or a mutation/assertion that does not depend on setup time" }
  overall: pass
```

## Scope and spec

- Scope: `git diff bf740c2e..57cbf875` (9 files: no-nul-guard.sh, three suites, spec AC table + Verification line, 4 decisions.jsonl appends, 1 EVENTS append, INDEX, round 1 review report) plus a regression run. Base for the branch: main e80ecabc.
- Spec: frozen DRAFT, frozen_sha256 re-anchored; `spec-amend list --strict` exit 0.
- Dispatch: names round 1 findings and what was fixed; no severity pre-rating or exclusion beyond that. Full delta reviewed.

## Round 1 findings, re-checked

| Round 1 | Status |
|---|---|
| AC-12 two missing disclosures | Fixed: records for SPEC-0179 and SPEC-0046 (18:43:30Z), test_137 pin 9 -> 11, green, TEST-018 replay RED |
| W1 no-NUL fail-open | Fixed in tree (mktemp, ls-files/check-attr and node failures return 1; `--check` exits 2; test_136 node-dies arm). The spec disclosure is still missing, see N1 |
| W2 TEST-029 unpolled | Fixed: wait_gone 5 s per member with labels; TEST-011 replay RED |
| W3 background job orphan (P3) | Carried unchanged: "accepted residual: test_094 / test_795 background job orphaned on early log_fail — P3, bounded by the inner wrapper's 600 s timeout and reaped by the outer wrapper's group kill; no observed bite" |
| W4 test_1760 SHA vacuous | Fixed: SHA read from the run line, old seed SHA refused; probed by hand on three mutated headers |
| Validation: evidence lacked docs/ai/tdd paths | Fixed: every Evidence cell cites docs/ai/tdd/spec-slowest-suite-hot-spots/mutation-TEST-*.txt; all 18 files exist |
| Validation: sync-seed 205 s not reproduced | Resolved by signed owner amendment 18:57:54Z (local bound dropped; CI weight 169 <= 170) |

## Commands run

| Command | Result |
|---|---|
| `env -u AAI_ROLE AAI_TEST_TIMEOUT=3000 bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh --skill aai-hygiene-pack --skill aai-run-tests --skill aai-suite-select --skill aai-check-state --skill aai-spec-lint --skill aai-follow-ups --skill aai-docs-audit` | rc 0, 7/7 PASS (check-state 2 s, suite-select 10 s, follow-ups 22 s, spec-lint 32 s, hygiene-pack 63 s, run-tests 86 s, docs-audit 119 s); tripwire 7/7 clean |
| `node .aai/scripts/spec-amend.mjs list --strict` | rc 0 |
| `node .aai/scripts/docs-audit.mjs --ac-flip-check spec-slowest-suite-hot-spots` | rc 0, AC-FLIP PASS |
| `node .aai/scripts/docs-audit.mjs --strict --no-event` | Verdict: CLEAN (no probable-false-open reported this round; 8 unreadable AC tables report-only) |
| `env -u AAI_ROLE node .aai/scripts/mutation-run.mjs --replay --spec docs/specs/SPEC-0216-spec-slowest-suite-hot-spots.md` (after suites, not concurrent) | rc 1: 17/18 RED, TEST-013 STAYED GREEN |
| TEST-013 mutation on a scratch copy, `bash tests/skills/test-aai-run-tests.sh test_018` x4 | rc 1 x4, RED as recorded |
| `git ls-files -ci --exclude-standard` | empty |

## Findings

**N1 (NON-BLOCKING): D2 deviation not disclosed.** no-nul-guard.sh:95-96, 103-110, 152. Frozen D2: "Output and exit code of `--check` stay byte-identical." The success paths still are; the failure path now exits 2 (and nonul_scan returns 1 with a stderr line) where the reference exits 0 with no output. Round 1 named this a contract change for exactly that reason. Disposition: remediate in tree by filing a spec_amendment (class contract, additive-with-disclosure, owner sign-off owed per convention) naming the new exit 2 / stderr line. It cannot be an accepted residual because the spec text is now a false record.

**N2 (NON-BLOCKING): TEST-013's mutation bite depends on host load.** test-aai-run-tests.sh:749 (`sleep 3   # AGE-WAIT min=3`) with the reap-old cases at MIN_AGE=1. Under load, the time to set up six fixtures can reach the age bound before the reaper runs, so `sleep 0` stays green. The spec replay went green this round while a second framework run (test-20261009-190014, 7 suites) shared the host. The same mutation alone went RED 4/4. This was not introduced by the delta, but it makes the replay gate (exit 1) flaky. Disposition: promote to a follow-up (P3), e.g. `suggested: fu-test013-mutation-bite-load-dependent`. Validation should re-run the replay on a quiet host before reading its result.

## INFO (no failure mode, not gating)

- Spec-AC-06 Notes still end "...so the local bound is NOT met on this host and is left unchanged for the owner". The AC text after 18:57:54Z drops that bound, so the note now reads as stale. It is chronological, but a closing clause pointing to the amendment would help.
- Spec-AC-12 Notes say "eleven measurement records plus one cell-rewrite record". The ledger holds 11 cross-spec records plus four measurement records against this spec itself (17:20:37Z, 17:24:19Z, 17:41:00Z, 18:52:13Z).

## Side effects of this review (not restored: HAZ-RESTORE/HAZ-LEDGER)

- `docs/ai/EVENTS.jsonl` gained one uncommitted `docs_audit` append (19:06:00Z, clean) from this review's docs-audit invocation.
- `docs/ai/tests/test-runs.jsonl` was already modified before the review started. This review's framework run appended run test-20261009-190050. A concurrent run, test-20261009-190014, came from another session in this worktree.

## Warning dispositions (recommended; orchestrator records)

1. N1: remediate in tree with a spec_amendment disclosure (contract class).
2. N2: promote to a follow-up (P3). Re-run the replay on a quiet host before Validation reads it.
3. W3 (round 1): accepted residual, quoted above.

## Next steps

1. File the N1 amendment, and record the N2 follow-up (or a decision).
2. Validation round 2: run the replay with no concurrent suites.
