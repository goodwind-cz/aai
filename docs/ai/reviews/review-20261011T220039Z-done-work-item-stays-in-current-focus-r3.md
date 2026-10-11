# Code review r3: done-work-item-stays-in-current-focus

- Reviewer: claude-opus-5-5, independent of the implementer (claude-sonnet-5-5). This is a delta review after r2 PASS.
- Scope: `a8b188ad..68aa6ab2`, commit "fix(metrics): --release resume never records a release twice or past a fail verdict". It addresses r2 findings N11, N12, N13, N15, N17 and N18. N14 and N16 were filed as follow-ups.
- Files:
  - `.aai/scripts/metrics-flush.mjs`
  - `.aai/system/RUNTIME_IGNORE.list`
  - `docs/specs/SPEC-0224-…md`
  - `tests/skills/test-aai-metrics.sh`
  - `tests/skills/test-aai-orchestration-dispatch.sh`
  - `docs/INDEX.md`
  - `docs/ai/EVENTS.jsonl` (2 `ac_status` lines)
  - `docs/ai/decisions.jsonl` (1 amendment)
- Behavioural evidence: validation r5 probes in `docs/ai/validation/done-work-item-stays-in-current-focus-r5/` (`probe-p2.log`, `probe-p2b.log`, `probe-p2x.log`).

```yaml
review:
  scope: a8b188ad..68aa6ab2
  spec: docs/specs/SPEC-0224-spec-done-work-item-stays-in-current-focus.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01..20, call: compliant, citation: "unchanged code paths; probe4/4p/7/7p byte-identical to r4; mutation replay 33/33; TEST-1748 now pins both refMatches copies on an 8-row shape table" }
      - { ac: Spec-AC-21, call: compliant, citation: "after-event arm: metrics-flush.mjs:1369-1373 crash hook, drop branch :1217-1222; TEST-1753; probe-p2 after-event/before-marker-removal retry appends nothing and removes the record" }
      - { ac: Spec-AC-22, call: compliant, citation: "releasedSinceLastClose :391-394 (lastRelease > lastClose, refMatches), failNamesRef :1202-1203 mirrors guards 4/4-cr; TEST-1751/1752; probe-p2x 9 fail shapes + 9 event sequences incl. close,rel,reopen,close -> resume (legit second cycle)" }
      - { ac: Spec-AC-23, call: compliant, citation: "sweepStaleReleaseTmp :1174-1184 (prefix + integer pid>0 + dead), RUNTIME_IGNORE.list:9-10; TEST-1754/1755; probe-p2x 15 sweep boundaries; downstream seed probe ignores marker and tmp" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: docs/ai/decisions.jsonl, line: 2100, issue: "R3-1: the fu-release-marker-per-ref and fu-release-pending-reporter follow_up records (N14/N16 deferrals) are working-tree only, not in 68aa6ab2", failure_scenario: "push without them: the PR claims N14/N16 are tracked but no committed record exists; nothing-left-behind cannot see them" }
      - { rank: NON-BLOCKING, file: .aai/scripts/metrics-flush.mjs, line: 1182, issue: "R3-2: sweepStaleReleaseTmp rmSync({force:true}) on a non-file throws ERR_FS_EISDIR uncaught, and the sweep runs before every guard", failure_scenario: "mkdir docs/ai/STATE.yaml.release-pending.tmp-<deadpid>; every non-dry --release then crashes with a stack trace until removed by hand (probe-p2x dir-named-tmp). Contrived; fix: lstat().isFile() check or try/catch per entry" }
      - { rank: NON-BLOCKING, file: .aai/scripts/metrics-flush.mjs, line: 1220, issue: "R3-3: the spent-record drop branch is silent and falls through to guard 2, so a retry after a completed-but-crashed release exits 1 with 'absent from active_work_items (needs done)'", failure_scenario: "operator re-runs --release after an after-event crash, sees a refusal, believes the release failed; one stderr line ('already recorded, spent record removed') would make the exit-1 self-explaining" }
      - { rank: NON-BLOCKING, file: .aai/scripts/metrics-flush.mjs, line: 1217, issue: "R3-4: the two resume branches repeat the same six-predicate conjunction, and each predicate re-reads and re-parses EVENTS.jsonl (up to 6 full reads on the resume path); one scanCloseEvents call could feed all three close predicates", failure_scenario: "a future edit changes one copy of the conjunction and not the other; slower release on a large ledger (carried from r2)" }
      - { rank: NON-BLOCKING, file: .aai/scripts/metrics-flush.mjs, line: 1181, issue: "R3-5: Number() accepts '1e3', '0x10', ' 12' as pids, so such names (inside the marker prefix only) are judged by an unrelated pid; a recycled pid keeps a dead writer's tmp forever", failure_scenario: "harmless: a removal never leaves the prefix and a misjudged pid only keeps a file; /^\\d+$/ would make the parse exact" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-metrics.sh, line: 4122, issue: "R3-6: TEST-1754's dead pid is `bash -c 'echo $$'`; a recycled pid between that and the release would flake the 'dead removed' assertion; TEST-1751(a) asserts EVENTS only, not the exit code or record removal", failure_scenario: "rare CI flake on a busy runner; a regression that keeps the record in TEST-1751(a) passes" }
  cannot_verify:
    - { claim: "Codex accepts the P1/P2 threads as resolved after this push", closes_with: "bot re-review after push; resolve threads via GraphQL" }
    - { claim: "the live CHANGE-0199 wedge on the shared checkout releases end-to-end", closes_with: "dispatch + printed remedy on the live STATE after merge" }
    - { claim: "aai-sync.ps1 seeds the new line on Windows", closes_with: "Windows Pester leg in CI (bash reconcile verified locally; PS code skips '#' lines by inspection)" }
  overall: pass
```

## Spec compliance

The delta implements Spec-AC-22 and 23 and the extended Spec-AC-21 as written.

- **Resume guard.** The resume predicate is now "no `work_item_released` after the last close, and no fail verdict naming the ref". It mirrors guard 4 exactly: same `refMatches`, same two verdict blocks. A forged or stale record therefore cannot yield an event the normal path would refuse.
- **Legitimate second cycle still works.** "After the last close" is the right anchor. A close, release, re-open, re-close cycle still resumes or releases, on the normal path and after every crash point (probe-p2x).
- **N13 is closed at the source.** RUNTIME_IGNORE.list now carries the pattern. Both the bash and PowerShell reconcilers skip the new comment line.
- **N18.** The new amendment discloses the Data-flows inversion and the dropped dedupe. Every claim in its text is present in the diff.

## Code quality

- The change is small and well commented. The fault hook follows the existing `AAI_FLUSH_INJECT_CRASH` precedent.
- The tmp sweep is correctly bounded: it removes only names in the STATE directory that start with the exact marker prefix and end in a dead positive integer pid. A dry run never sweeps.
- All findings are NON-BLOCKING. R3-1 is a pre-push housekeeping item for the orchestrator. R3-2 and R3-3 are one-line hardening changes worth taking if another round happens anyway.
