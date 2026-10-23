# Code review, round 3: node-first-sync-hook-slice (PR #495)

```yaml
review:
  scope: "37fcaad0..951dca85 (PR #495 head), excluding pure telemetry/index files"
  spec: docs/specs/SPEC-0247-spec-node-first-sync-hook-slice.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "live-spool.mjs:25-38 unchanged except :27; TEST-2401 green, mutant replay RED" }
      - { ac: Spec-AC-02, call: compliant, citation: "live-spool.mjs:27 (BOM strip, disclosed D2 amendment); TEST-2402..2406 green, replay RED; new BOM case live-spool.test.mjs:59-67" }
      - { ac: Spec-AC-03, call: compliant, citation: "CLI block live-spool.mjs:72-81 unchanged; TEST-2407 green, replay RED" }
      - { ac: Spec-AC-04, call: compliant, citation: "launchers byte-identical to 37fcaad0 (17+17 lines); TEST-2408..2410 green, replay RED" }
      - { ac: Spec-AC-05, call: compliant, citation: "TEST-2411/2412 green (local Pester Total=9); hosted 5.1 and pwsh 7 Pester 9/9 on run 40013838106" }
      - { ac: Spec-AC-06, call: compliant, citation: "TEST-2413 green, replay RED" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-2414 green, replay RED" }
      - { ac: Spec-AC-08, call: compliant, citation: "TEST-2415..2418 green, replay RED" }
      - { ac: Spec-AC-09, call: compliant, citation: "RFC-0017 phase 3 row now links CHANGE-0222 (rfc:306); TEST-2419 green" }
      - { ac: Spec-AC-10, call: compliant, citation: "wc -l 82+17+17=116; RFC row, CHANGELOG, spec disclosure all say 116; TEST-2420 green" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: CHANGELOG.md, line: 33,
          issue: "'(Windows PowerShell 5.1 adds one)' attributes the BOM to 5.1 in general; the hosted diagnostic shows it came from the .NET Framework Process.StandardInput writer of the 5.1 Pester harness (child p2 read 33 raw bytes before any launcher logic ran). Product doc live-status-dashboard.md:126-127 says the same less strongly.",
          failure_scenario: "A Windows operator reads the release notes, concludes the real Claude Code -> powershell -File live-spool.ps1 path prepends a BOM, and debugs or 'fixes' a launcher that never sees one; the note becomes a false record of production behaviour." }
      - { rank: NON-BLOCKING, file: docs/ai/decisions.jsonl, line: 2260,
          issue: "The 19:38:45Z spec_amendment says the readStdin/EOF amendment (eb109b01, record 2259) was 'removed', but part of what record 2259 added survives: the extended TEST-2410 Test Plan row (spec:387) and the 1 MB/stderr Pester assertions. Neither record 2260 nor the D2 disclosure (spec:219-229) says what was kept.",
          failure_scenario: "The owner signing fu-amend-spec-node-first-sync-hook-slice reads 2259 + 2260 as cancelling out and signs off without knowing that the TEST-2410 row was widened after freeze; an auditor diffing the frozen row against the ledger finds a widening that no surviving record names." }
  cannot_verify:
    - { claim: "No real Windows hook path (Claude Code spawning powershell 5.1 -File live-spool.ps1) delivers a BOM or otherwise differs from the Pester harness path",
        closes_with: "A native Windows run of the installed statusLine/Stop command from live-status-hooks.json with a Node-written payload, recording the spool line" }
    - { claim: "Owner sign-off on the six unsigned contract amendments (fu-amend-spec-node-first-sync-hook-slice, P2, open)",
        closes_with: "Owner signature via spec-amend classify / follow-ups status done" }
  overall: pass
```

## Scope and preflight

- Worktree `/private/tmp/aai-node-first-slice`, branch `change/node-first-sync-hook-slice`,
  HEAD `951dca85` (= PR #495 headRefOid). Scope `git diff 37fcaad0..951dca85`, minus
  pure telemetry/index files (EVENTS, METRICS, test-runs, INDEX, factory-report*,
  overview*, skill-catalog-data timestamp). Prior review reports in the range were
  read as context only.
- Dispatch note (anti-gaming contract): the dispatch named suspected areas ("is the
  net production change exactly the one-line strip", "revert residues") and a
  hypothesis for the BOM. That is focus, not severity pre-rating; the full scope was
  reviewed anyway, and the BOM hypothesis was checked against the hosted log rather
  than taken as given.

## Net production change

`git diff --stat 37fcaad0..HEAD -- .aai/` shows one file, one line:
`.aai/scripts/live-spool.mjs:27` `JSON.parse(raw)` becomes
`JSON.parse(raw.replace(/^﻿/, ''))`. `live-spool.sh` and `live-spool.ps1` are
byte-identical to 37fcaad0. No workflow change.

Correctness of the strip:
- `^` without the `m` flag and without `g` or `+`: exactly one U+FEFF at string
  start. Node's `readFileSync(0, 'utf8')` keeps U+FEFF, so the strip is needed.
- U+FEFF is not JSON whitespace, so a second leading, interior or trailing mark still
  fails `JSON.parse`, giving `null` (no line), as before.
- `raw` is always a string (the only callers are `runLiveSpool` with `stdinText`, a
  string, and tests). A non-string would throw inside the same `try` and return
  `null`. No other behaviour change.

## Revert residues

- `git grep readStdin|b168d458|eb109b01|40011517525` at HEAD hits only the spec D2
  disclosure (spec:226-227) and the ledger records 2259/2260. Those mentions are
  intended history.
- The diagnostic Pester case from 412ffa70 is gone (Tests.ps1 diff against 37fcaad0
  holds only the stderr assertions and the 1 MB case). The hosted 5.1 and pwsh 7 runs
  list 9 cases, none DIAGNOSTIC.
- RFC row, product doc and CHANGELOG mention neither the launcher rewrite nor
  readStdin. The 30-line cap is gone and the spec says the 20-line cap is "as first
  frozen".
- Mutation records (`docs/ai/tdd/spec-node-first-sync-hook-slice/`, gitignored): the
  current TEST-2401..2407/2413/2419/2420 records were restored to their 13:55Z
  originals (base 83522bb), and TEST-2410/2411 carry the restored cells. The
  rewrite-era records survive only as timestamped archives. Because the restored
  records were not re-run, I replayed all 20 rows on a scratch clone at 951dca85
  (`mutation-run.mjs --replay`): 20/20 still redden, 0 inconclusive. On the worktree,
  `mutation-gate.mjs` reports GATE PASS 20 rows, degraded=0 and uncomparable=0.
- A residue that stayed on purpose is the hardening from b168d458/eb109b01:
  test_2410 asserts empty stderr, drains a 1 MB payload and checks that the real
  launcher writes one line; Pester adds stderr checks and a 1 MB case. That hardening
  closes fu-live-spool-ps1-drain-test and belongs in the tree. It is still under-recorded
  (NB-2).

## Spec disclosures and amendment records

- The anchor chain is consistent. `contractHash` equals the stored `frozen_sha256` at
  every commit: 37fcaad0 2efa…, 999711ae c3ff…, b168d458 7d14…, eb109b01/412ffa70
  2b4a…, 951dca85 f901…. `spec-amend list --strict` returns rc 0, all six records
  `unsigned-tracked`. `spec-lint` PASS.
- D2 disclosure (spec:219-229) is accurate against the hosted log of run
  40011517525. Under 5.1, `openstdin_bytes=33` against 30 under pwsh 7 for the
  30-byte payload `{"session_id":"s1","cwd":"/x"}`, with `inenc=utf-8`. Node read all
  30/33 bytes, which disproves both earlier hypotheses. The residual-risk rewrite
  (spec:363-365) holds: H1 passes on HEAD.
- INFO, close-ceremony restamp (record 18:31:29Z, "UNVERIFIED cause"). The
  only contract-content change from 37fcaad0 to 999711ae is the allocator rewriting the
  two `CHANGE-DRAFT-node-first-sync-hook-slice.md` links to `CHANGE-0222-…`, so the
  cause is mechanical. The restamp tool reverse-applies only the SPEC-DRAFT
  self-reference substitution, not sibling CHANGE-DRAFT links, so it labelled a
  mechanical restamp as an unverified contract change that needs an owner signature.
  The record over-discloses, which is the safe direction. The tool gap is a possible
  follow-up: restamp should model the allocator's sibling-link rewrite.
- NB-2 (above): record 2260 reverses record 2259 as a whole, while the TEST-2410
  widening that 2259 introduced survives.

## Product doc and CHANGELOG (spec D5)

- `docs/product/live-status-dashboard.md:99-111` names D-1 (3 fractional digits,
  the PS copy wrote 7, misordering), D-2 (array/scalar writes no line, the bare line
  hid quotas) and D-9 (no Node, no line, passthrough kept). It describes the
  module-missing fallback the same way the launchers implement it: drain if
  redirected, passthrough for statusline only, stderr suppressed, exit 0. The "17-line
  launchers" count is right. Lines 122-125 say the ps1 launcher runs under Pester on
  the native Windows job, which run 40013838106 confirms.
- `CHANGELOG.md:25` uses the exact D5 heading as a per-entry `## [unreleased] —`
  heading. "133 to 116" is right, and so are the fallback sentences. The BOM
  attribution is NB-1.

## BOM node:test guard

`tests/skills/lib/live-spool.test.mjs:59-67` covers one leading BOM (same line as
without it), two leading, interior and trailing BOMs (each gives null). Scratch
mutation, deleting `.replace(/^﻿/, '')` on a copy: the case goes RED (12 pass /
1 fail), and it also reddens under `--test-name-pattern TEST-2403`, the selector
test_2403 uses. Mutants `/^﻿+/` and `/﻿/g` would be caught by the
two-leading and interior asserts.

INFO: the TEST-2403 Test Plan mutation cell still targets `Array.isArray`, so the
mutation gate does not pin the strip. The suite does pin it through the case above.
Accepted residual: P3 assurance-strength. The strip is covered by a test proven RED
by a scratch mutant, with no observed bite and no false record.

## Test runs

- Scratch clone at 951dca85: `bash tests/skills/test-aai-live-status.sh` gives
  "All aai-live-status tests passed" and TEST-2412 Pester Total=9 Passed=9 Skipped=0.
  node:test on the module: 13/13.
- PR #495 checks on 951dca85: all pass, including the 5.1 and pwsh 7 full Pester on
  native Windows, the WSL1 leg, the doc-numbering guards and the tracked-ignored guard.
  `git ls-files -ci` is empty.

## INFO (non-gating)

- `tests/skills/test-aai-live-status.sh:1239`: the comment "(hosted-5.1
  regression)" is left over from the readStdin hypothesis. The case runs under pwsh 7
  and guards ordinary end-to-end writing, not a 5.1 behaviour.

## Warning dispositions (H6)

- NB-1 (CHANGELOG.md:32-33, product doc :126-127, BOM attribution): **remediate-in-tree**.
  This is a false-record risk, so disposition (d) is not allowed. Reword to "a
  .NET Framework stdin writer, such as the Windows PowerShell 5.1 Pester harness, adds
  one".
- NB-2 (decisions.jsonl:2260, amendment record): **remediate-in-tree**. Append one
  `spec-amend add` record, or extend the D2 disclosure sentence, stating that the
  TEST-2410 row widening and the Pester 1 MB/stderr assertions from eb109b01 are kept.
  This is a false-record risk, so (d) is not allowed.

## Next steps

1. Fix NB-1 and NB-2. Both are docs/ledger only; NB-2 via spec-amend re-anchors
   the spec, so re-run `spec-amend list --strict` and `mutation-gate`.
2. Owner sign-off on fu-amend-spec-node-first-sync-hook-slice (P2, open) before merge.
3. Optional follow-up: teach `spec-amend restamp` the allocator's sibling CHANGE-DRAFT
   link rewrite.
