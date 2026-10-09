# Code Review — slowest-suite-hot-spots (round 1)

```yaml
review:
  scope: "git diff main...HEAD (main e80ecabc .. debt/slowest-suite-hot-spots bf740c2e), worktree /Users/ales/Projects/aai-debt-slowest-suite-hot-spots"
  spec: docs/specs/SPEC-0216-spec-slowest-suite-hot-spots.md
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "tests/skills/lib/selector-probe.sh:12-16; tests/skills/test-aai-hygiene-pack.sh test_094 (isolation line, PROBE-RC count, per-suite count) + test_135; hygiene-pack PASS this round" }
      - { ac: Spec-AC-02, call: compliant, citation: "tests/skills/lib/no-nul-guard.sh:93-134 nonul_scan_batch, nonul_scan_perfile kept; test_136 nine-case parity + PATH-shim process count; TEST-562 single live scan" }
      - { ac: Spec-AC-03, call: compliant, citation: "suite-weights.tsv:68 aai-hygiene-pack 93 <= 95 (signed contract amendment 2026-10-09T18:09:59Z); test_1757; local 61 s in an 8-wide framework run this round (bound 60 s measured alone in batch1-timing.log, not re-measured alone here)" }
      - { ac: Spec-AC-04, call: compliant, citation: "test-aai-sync-seed.sh _sync_cached (chmod -R a-w golden, cp -Rp + chmod -R u+w copy, .done marker) + test_794" }
      - { ac: Spec-AC-05, call: compliant, citation: "test_795 per key (sh/ps1 x real/fixture) + static pin-field read; deviation disclosed in AC notes: advisory Generated at/Source lines also normalized, real key compared against fixture subset + four root files" }
      - { ac: Spec-AC-06, call: compliant, citation: "19 _sync_cached call sites, test_796 (>=15, no capture, >=30 direct engine lines); suite-weights.tsv:119 169 <= 170 (signed amendment); follow-up fu-sync-seed-cache-no-ci-gain filed" }
      - { ac: Spec-AC-07, call: compliant, citation: ".aai/scripts/aai-run-tests.sh:765 (POSIX branch only; MSYS branch unchanged); test_028 + test_029 (both arms)" }
      - { ac: Spec-AC-08, call: compliant, citation: "test-aai-run-tests.sh 7 AGE-WAIT tags pinned by test_030; test_018 one shared 'sleep 3   # AGE-WAIT min=3', own ws + pid per case; wait_gone/wait_marker_gone deadline >= 5 enforced in the helpers" }
      - { ac: Spec-AC-09, call: compliant, citation: "suite-weights.tsv:107 aai-run-tests 88 <= 92; test_1759; local 89 s this round; flake-guard runs in batch3-timing.log (not re-run here)" }
      - { ac: Spec-AC-10, call: compliant, citation: "suite-weights.tsv header lines 4-16 name run 37966091223, four job ids, head SHA 77cfd944...; test_1760 + test_1423 green" }
      - { ac: Spec-AC-11, call: compliant, citation: "suite-weights.tsv:23 '# Leg walls (run 37972288462): 146 160 159 171' (max/mean 1.075); test_1761" }
      - { ac: Spec-AC-12, call: non-compliant, citation: "named gap: SPEC-0179 TEST-440 (Spec-AC-23: run-tests suite passes with AAI_REAP_STEP_START_EPOCH exported — the arm is test_005/test_012, whose settle sleeps are now wait_gone polls) and SPEC-0046 TEST-008 (full SPEC-0009 run-tests suite as regression backbone) are Test Plan rows backed by run-tests functions whose waits were polled/batched, but carry no measurement record for ref slowest-suite-hot-spots; test_137's pinned list (hygiene-pack) omits them" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/lib/no-nul-guard.sh, line: 95,
          issue: "nonul_scan_batch adds fail-open exits the reference does not have: mktemp failure (and a non-absolute mktemp result) returns 0 with no output, and node's exit status is ignored, so a node crash/OOM/ENOMEM mid-scan yields empty stdout",
          failure_scenario: "TMPDIR points at a full or read-only filesystem (or node is killed mid-run): `no-nul-guard.sh --check` prints nothing and exits 0, i.e. reports a tree with a planted NUL as clean; the per-file reference would still have scanned each file" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-run-tests.sh, line: 1243,
          issue: "TEST-029 asserts the trapper and the KILLed TERM-ignorer are dead immediately after the wrapper returns, with no poll; both are reparented to init, and kill -0 succeeds on a not-yet-reaped zombie. D5's own rule (settle before an expected death becomes wait_gone) is not applied to the new test",
          failure_scenario: "loaded CI runner: SIGKILL is sent to the group at the wrapper's reap, the wrapper exits within a few ms, init has not yet reaped the ignorer -> `alive \"$ignorer_pid\"` true -> spurious FAIL 'the KILL after the grace is gone'. Fix: wait_gone \"$trapper_pid\" \"$ignorer_pid\" 5 before the two alive checks" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-hygiene-pack.sh, line: 1963,
          issue: "test_094 backgrounds the layer-profiles real-selector run; any log_fail between line 1963 and the wait at 1998 exits the suite without collecting it (same shape in test-aai-sync-seed.sh:1880 _795 background syncs on an early log_fail)",
          failure_scenario: "the probe run fails (rc!=0 or a fail-open suite found): log_fail exits, the background wrapper run keeps going for up to 600 s in its own isolated checkout and $lp_out_f under TMPDIR is never removed; when the suite is run bare (not under the wrapper) nothing reaps it" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-suite-select.sh, line: 1938,
          issue: "test_1760's head-SHA check matches any 40-hex string in the header, and the header still carries the previous seed's SHA 8e08f059..., so the assertion cannot fail if the new head SHA is dropped",
          failure_scenario: "a later re-seed edits the provenance paragraph and loses the new head SHA line but keeps the 'earlier seed' sentence: TEST-016 stays green while Spec-AC-10's 'header names its head SHA' is false" }
  cannot_verify:
    - { claim: "Spec-AC-03/06/09 local timing bounds (60 s / 205 s / 93 s alone) and the run-tests flake guard under four CPU loops",
        closes_with: "batch1/2/3-timing.log in the gitignored evidence tree (not re-run alone here; this round ran suites 8-wide: hygiene 61 s, run-tests 89 s, sync-seed 270 s concurrently)" }
    - { claim: "CI runs 37966091223 and 37972288462 (weights source, leg walls 146/160/159/171)",
        closes_with: "gh run view <id> --json jobs,headSha — not queried in this review" }
    - { claim: "Mutation RED observations for TEST-001..018 and the D7 replay of SPEC-0181/0182 records",
        closes_with: "docs/ai/reports/slowest-suite-hot-spots/mutation-TEST-*.txt and the main-checkout replay output (gitignored, local-only)" }
    - { claim: "D4 fast path on Linux dash/setsid and the perl-setsid branch (kill -0 -PGID semantics, zombie group members)",
        closes_with: "TEST-028/029 green on the two CI runs (Linux legs); verified locally on macOS only" }
    - { claim: "Live-tree byte equivalence nonul_scan_perfile vs --check",
        closes_with: "the Verification equivalence command run once by Validation (too slow for this pass)" }
  overall: fail
```

## Scope and spec

- Scope: `git diff main...HEAD`, 14 commits, 13 files (wrapper 1 line, two lib scripts, four suites, weights, spec/intake/INDEX, 14 decisions.jsonl appends, 6 EVENTS.jsonl appends).
- Spec: `docs/specs/SPEC-0216-spec-slowest-suite-hot-spots.md` (frozen, amended; owner-signed contract amendment for Spec-AC-03/06 bounds). `spec-lint` PASS, `spec-amend list --strict` exit 0, `git ls-files -ci --exclude-standard` empty.
- No coaching in the dispatch beyond a focus list; the full scope was reviewed.

## Verdict 1 — spec compliance: FAIL (one AC)

Eleven ACs compliant (walk above). **Spec-AC-12 non-compliant**: the AC requires a measurement record for every frozen spec whose Test Plan row is backed by a run-tests function whose waits were batched or polled. Two rows meet that test and are not disclosed:
- SPEC-0179 TEST-440 / Spec-AC-23 — "With `AAI_REAP_STEP_START_EPOCH` exported into the test command's environment, the reaper arm passes" (follow-up `fu-reaper-epoch-export-fails-test005`); its arm is test_005 (and test_012/013), whose settle sleeps this diff replaced with `wait_gone`.
- SPEC-0046 TEST-008 — "full existing SPEC-0009 suite passes unchanged (regression backbone)", backed by the whole run-tests suite.

Remediation (cheap): two `spec-amend.mjs add --class measurement --signoff none --ref slowest-suite-hot-spots` records, and extend test_137's pinned list (9 -> 11) in the same commit. If the orchestrator judges whole-suite rows out of the AC's intent, record that reading as a decision instead; either way the pinned list must state it.

Disclosed deviations (accepted, already recorded): Spec-AC-05 normalization also covers the advisory's Generated at / Source lines and compares the real key against the fixture subset + 4 root files; Spec-AC-03/06 bounds moved by signed owner amendment; Spec-AC-06 not halved (HITL Q2) with follow-up `fu-sync-seed-cache-no-ci-gain`.

## Verdict 2 — code quality: PASS (4 NON-BLOCKING)

Focus areas checked:
- `aai_reap_group` (aai-run-tests.sh:765): POSIX-only, `&&` list is exempt from errexit and the wrapper runs `set -u` only; the leader is already reaped by `wait "$CMD_PID"` so an empty group returns ESRCH; a member still dying from the TERM keeps the old 1 s grace (conservative race direction); the non-group fallback branch (`"$@" &` without job control) previously paid a pointless sleep on a nonexistent group and now skips it, same reap effect. `${PGID:-$CMD_PID}` usage unchanged. No defect.
- `nonul_scan_batch`: `ls-files -z` / `check-attr -z --stdin` triples parsed as raw bytes, `set` exact match equals the reference's `*": binary: set"`, `statSync` follows links like `[ -f ]`, file-based IPC (no pipe deadlock), paths with spaces/newlines/non-UTF-8 printed verbatim. Finding 1 (new fail-open exits).
- `selector-probe.sh`: never stops early, one line per arg, rc captured without errexit. Shared-checkout risk is RR-2 (disclosed).
- `_sync_cached`: golden `a-w`, copy `cp -Rp` then `chmod -R u+w`, cleanup trap restores `u+w` before `rm -rf`, `.done` on-disk marker survives command-substitution replays, keys discriminated (test_794 asserts the two goldens differ). The engine writes nothing under `.git` and no target path into content (test_795's differently-located fresh target proves the latter). Suite is serial; the only concurrency is test_795's own fresh syncs into separate dirs. No defect beyond finding 3's orphan shape.
- `wait_gone` / `wait_marker_gone`: deadline floor enforced, 0.1 s poll, under `set -uo pipefail` the `alive && live=1` loop is safe (checked: a trailing failing `&&` in a for body does not abort). `wait_marker_gone` deliberately returns 0 and the caller's pgrep check fails, which is correct.
- suite-weights.tsv header: parses under test_1760/1761 and TEST-1423. Finding 4 (stale SHA satisfies the SHA check).
- test_1757..1761, test_137: correct, positive-control shaped (test_137 checks the exact WANT/MISSING/FORBIDDEN line).

## Suites run this round (worktree, `env -u AAI_ROLE AAI_TEST_TIMEOUT=3000`, via aai-run-tests.sh + test-framework.sh)

| Suite | Result |
|---|---|
| aai-suite-select | PASS 9 s |
| aai-hygiene-pack | PASS 61 s |
| aai-run-tests | PASS 89 s |
| aai-sync-seed | PASS 270 s (concurrent with 5 suites) |
| aai-suite-isolation | PASS 65 s |
| aai-check-state | PASS 1 s |
| aai-spec-lint | PASS 31 s |
| aai-follow-ups | PASS 21 s |
| aai-docs-audit | FAIL — TEST-1349 'Verdict: CLEAN' over the live tree |

The docs-audit FAIL is the in-flight state of this spec, not a code defect: `docs-audit --strict --no-event` reports `spec-slowest-suite-hot-spots: probable-false-open` (every AC terminal, status still `implementing`). It clears at the close ceremony; Validation must not read it as green until then.

Side effect to note: that suite's live audit appended one `docs_audit` event (18:31:41Z, drifted 1, false_open 1) to the worktree's `docs/ai/EVENTS.jsonl` and the wrapper tripwire flagged it. Not restored (HAZ-RESTORE / HAZ-LEDGER); the orchestrator decides whether to keep or drop that uncommitted append before the next commit.

## Warning dispositions (recommended; orchestrator records)

1. no-nul-guard fail-open exits — promote to follow-up (P3), e.g. `fu-nonul-batch-could-not-scan-reads-clean`: the frozen D2 contract is byte-identical output, so making "could not scan" loud is a contract change, not an in-tree fix.
2. TEST-029 unpolled death check — remediate-in-tree: add `wait_gone "$trapper_pid" "$ignorer_pid" 5` before the alive checks (one line; matches D5 and the suite's CI-load history).
3. test_094 / test_795 background job orphaned on early log_fail — accepted residual: P3, bounded by the inner wrapper's 600 s timeout and reaped by the outer wrapper's group kill in every canonical invocation; no observed bite.
4. test_1760 SHA check satisfied by the old seed SHA — remediate-in-tree: assert the specific 40-hex on the provenance line (e.g. the line after '# Actions run', or `head SHA` + next token) rather than any 40-hex in the header.

## Next steps

1. Fix Spec-AC-12: disclosures for SPEC-0179 and SPEC-0046 (or a recorded decision that whole-suite rows are out of scope) and update test_137.
2. Apply dispositions 2 and 4 in tree; file the disposition 1 follow-up; quote disposition 3's accepted residual in code_review.notes.
3. Re-review (round 2) over the new head.
