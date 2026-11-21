# Code review: update-on-node (round 2, final, owner-authorized)

```yaml
review:
  scope: "git diff 30c983ef...43bb4017 (main...HEAD on feat/update-on-node), restricted to STATE code_review.scope (34 paths); remediation delta f707b98b..43bb4017 read line by line; docs/ai/EVENTS.jsonl, docs/ai/tests/test-runs.jsonl and docs/ai/reviews/*.md are telemetry/records outside it"
  spec: docs/specs/SPEC-0307-spec-update-on-node.md (plus the ref update-on-node records in docs/ai/decisions.jsonl via spec-amend list --json; spec-amend list --strict rc 0)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "tests/skills/test-aai-update-node.sh:502-514 run_update asserts the scratch root, an empty GH_CONFIG_DIR and sets the D-SAFETY env (log_fail exits, :47); tests/skills/lib/aai-update.test.mjs:204-225 scanner + positive controls :381-390; TEST-3960 passed in this review (node and bash selector)" }
      - { ac: Spec-AC-02, call: compliant, citation: "aai-update.mjs: only node: imports, spawnSync once in runChild (:34); TEST-3961 passed in this review" }
      - { ac: Spec-AC-03, call: compliant, citation: "aai-update.mjs parseArgs/resolveBase unchanged since round 1; TEST-3962 passed in this review" }
      - { ac: Spec-AC-04, call: compliant, citation: "aai-update.mjs canonicalGuard, run:439-443; TEST-3963 passed in this review" }
      - { ac: Spec-AC-05, call: compliant, citation: "aai-update.mjs:183-225 async resolveSource, child-only signal = failed attempt, own signal stops (amendments 09:22:39Z, 10:00:47Z); TEST-3964 passed in this review (13 subtests, incl. :1107-1162)" }
      - { ac: Spec-AC-06, call: compliant, citation: "aai-update.mjs:459-462 finally, :500-509 handler; TEST-3965 passed in this review" }
      - { ac: Spec-AC-07, call: compliant, citation: "aai-update.mjs resolveRunner/syncStep; TEST-3966 passed in this review" }
      - { ac: Spec-AC-08, call: compliant, citation: "aai-update.mjs:282-291 changedFiles with STATUS_MAX_BUFFER (:33, D-EVIDENCE amended); TEST-3967 incl. the 30000-line case :1698-1711 passed in this review" }
      - { ac: Spec-AC-09, call: compliant, citation: "aai-update.mjs doctorReport; TEST-3968 passed in this review" }
      - { ac: Spec-AC-10, call: compliant, citation: "TEST-3969 green in validation r5 (VALIDATION-20261121T094714Z, HEAD 51e1b049, code 9d3db7c1 = review HEAD code); not re-run here" }
      - { ac: Spec-AC-11, call: compliant, citation: "TEST-3970 green in validation r5; not re-run here" }
      - { ac: Spec-AC-12, call: compliant, citation: ".aai/scripts/aai-update.sh unchanged since round 1 (D-LAUNCH); TEST-3971 green in validation r5" }
      - { ac: Spec-AC-13, call: compliant, citation: ".aai/scripts/aai-update.ps1 unchanged since round 1; TEST-3972 Pester pwsh 7 18/0/0 in validation r5; 5.1 is hosted H1" }
      - { ac: Spec-AC-14, call: compliant, citation: "tests/skills/test-aai-update.sh unchanged since round 1; TEST-3973 green in validation r5" }
      - { ac: Spec-AC-15, call: compliant, citation: "tests/skills/aai-update.Tests.ps1 unchanged since round 1; TEST-3974 green in validation r5" }
      - { ac: Spec-AC-16, call: compliant, citation: "install-parity files unchanged since round 1; TEST-3975 green in validation r5; H2 hosted" }
      - { ac: Spec-AC-17, call: compliant, citation: "test-aai-update-node.sh:516-580 now through run_update; TEST-3976 passed in this review (bash, sh, pwsh, no-node refusal)" }
      - { ac: Spec-AC-18, call: compliant, citation: "wiring files unchanged since round 1; TEST-3977 green in validation r5" }
      - { ac: Spec-AC-19, call: compliant, citation: "docs files unchanged since round 1; TEST-3978 green in validation r5" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/lib/aai-update.test.mjs, line: 222,
          issue: "the scanner checks that run_update holds the case assertion on $src, but not that the launcher argument it passes is that same $src",
          failure_scenario: "edit test-aai-update-node.sh:509-510 to pass --repo/-Repo \"$PROJECT_ROOT\": the runtime case still checks $src and passes, TEST-3960 stays green (10/10), and TEST-3976 syncs from the checkout. backed-by: scratchpad review-r2-mutations.txt M3 (survived)" }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-update.mjs, line: 215,
          issue: "the own-signal check runs only after each clone child, not between wipe() and the next child, so a signal that arrives during wipe() (a sync rmSync of a partial clone) is only dispatched after the next attempt has run in full",
          failure_scenario: "attempt 1 (gh) leaves a large partial clone and fails; the user presses Ctrl-C while wipe() removes it; attempt 2 (git clone, stdio ignored) starts unsignalled and runs to completion or a network timeout before the run exits 130. The bash twin dies in rm -rf. Unbacked (needs a signal timed into rmSync)" }
  cannot_verify:
    - { claim: "Windows behaviour of both launchers and the module (H1: Pester under 5.1 and 7 on Windows; H2: sh:node on windows-parity)", closes_with: "the PR's ps1-quality run, recorded in the validation report" }
    - { claim: "the literal runner 'bash' exported by aai-update.sh resolves to Git Bash when node spawns it on win32, and Git Bash accepts the forward-slash C:/ paths", closes_with: "a Git Bash run of the .sh launcher on a hosted Windows runner" }
    - { claim: "fs.rmSync removes a clone's read-only pack files on Windows under Node 22/24", closes_with: "the hosted Pester clone cases on windows-5_1" }
    - { claim: "a Microsoft Store pwsh path from Get-Process can be spawned as the sync runner", closes_with: "a manual run on a Store-installed pwsh" }
    - { claim: "the real gh -> git -> anonymous-git chain against GitHub (all tests are network-free by design)", closes_with: "a manual /aai-update against goodwind-cz/aai@main" }
    - { claim: "a consumer on an older layer updates once with its old twin, which vendors the launchers and the module, and the next update runs the module", closes_with: "an aai-sync scratch install of a pre-30c983ef tag, then two /aai-update runs" }
    - { claim: "'requires Node.js 22' is stated, not enforced by either launcher", closes_with: "a run under Node 18/20, or a version check if the floor matters" }
    - { claim: "the setImmediate yield in signalled() dispatches a signal received during spawnSync on Linux CI as it does on this macOS host", closes_with: "the TEST-3964 own-signal real-process case green on the PR's Linux CI run" }
    - { claim: "TEST-3969..3970 and TEST-3972..3975, 3977, 3978 pass at 43bb4017", closes_with: "validation r5 evidence (code identical: the commits after 9d3db7c1 touch only the spec text and ledgers; gitignored evidence not re-run here)" }
  overall: pass
```

security_relevant: true

## Scope and spec

- Worktree `/Users/ales/Projects/aai-worktrees/update-on-node`, branch `feat/update-on-node`, HEAD `43bb4017`. STATE says
  `worktree.user_decision: worktree`, so the review uses the diff-range mode. `git status --porcelain` was clean.
- Scope: `git diff 30c983ef...HEAD`, restricted to the 34 paths in STATE `code_review.scope`. The remediation delta
  `git diff f707b98b..HEAD` was read line by line. It touches `.aai/scripts/aai-update.mjs`, `tests/skills/lib/aai-update.test.mjs`,
  `tests/skills/test-aai-update-node.sh`, the spec and `docs/ai/decisions.jsonl`. The other in-scope files are byte-identical
  to round 1, so their round-1 calls stand.
- Spec: `docs/specs/SPEC-0307-spec-update-on-node.md` (frozen, restamped). It has four new ledger records of ref update-on-node.
  The first is the 06:34:31Z D-SOURCE/D-EVIDENCE/TEST-3960 record. The second is the 09:22:39Z D-SOURCE record, which
  supersedes the "interrupted by" clause of the first; that clause no longer appears in the spec or the module (`grep` finds no match).
  The third is the 10:00:47Z D-MODULE measurement record. The fourth is the two P3 follow-ups.
  `spec-amend list --strict` returned rc 0, and `spec-lint --path` on the spec returned LINT PASS.
- Re-run in this review: `node --test --test-name-pattern 'TEST-396[0-8]' tests/skills/lib/aai-update.test.mjs` passed
  76 of 76. `test-aai-update-node.sh test_3960_scratch_safety` and `test_3976_scratch_install` passed (rc 0). No sweep was run.
- Mutation probes ran in a `git archive` copy under the scratchpad. The worktree was never edited. Results are in
  `/private/tmp/claude-501/-Users-ales-Projects-aai/2071b3a2-d378-409f-946d-cd8edb99948a/scratchpad/review-r2-mutations.txt`:
  - M1, the own-signal check after a clone child removed: killed.
  - M2, the maxBuffer removed: killed.
  - M3, the run_update launcher argument swapped from `$src`: survived (N-1 below).
  - M4, a launcher run outside run_update: killed.
- Dispatch notes, recorded under the anti-gaming contract: the dispatch named the round-1 findings and the remediation commits,
  and asked for a close look at the delta. It did not pre-rate severity or exclude areas. The whole scope was walked anyway.

## Round-1 closure

| Round 1 | Status at 43bb4017 | Evidence |
|---|---|---|
| B-1 TEST-3960 shell scan vacuous | **closed** | The helper is renamed `run_update` (`test-aai-update-node.sh:502`). It asserts a scratch root, a repo under it and an empty gh config through `log_fail`, which exits (`:47`). The scanner (`aai-update.test.mjs:204-225`) now also flags a named launcher plus an update argument outside the helper, a missing helper and a missing case assertion. It has positive controls on the committed suite: env stripped, gh config stripped, case removed, and two out-of-helper runs (`:381-390`). M4 is killed. Residual reach: N-1 below, and the filed `fu-update-shell-scan-bare-launcher` |
| N-1 SIGINT-killed clone continued | **closed (as parity)** | After the owner's round extension, an own-handler signal (a terminal Ctrl-C to the process group) stops the chain with 130/143 (`aai-update.mjs:196, :217`). A child-only signal is a failed attempt, as in both twins. TEST-3964 covers both arms (`:1107-1162`, the real-process own-signal case) and M1 is killed. The local arm has no test, tracked as `fu-update-local-own-signal-test` |
| N-2 git status maxBuffer | **closed** | `STATUS_MAX_BUFFER` is 1 GiB (`:33, :284`). TEST-3967 asserts the option and reads a real 30000-entry status (`:1698-1711`). M2 is killed |
| N-3, N-4 | filed | `fu-update-ps51-trailing-backslash-arg` and `fu-update-ps1-non-console-host`, both P3 (decisions.jsonl) |

## AC walk

See the yaml block. All 19 rows are compliant. Rows 01, 05, 08 and 17 are the ones the delta touched, and they were re-run here.
Rows 10 to 16, 18 and 19 rely on validation r5. Its code tree (`9d3db7c1`) is the review HEAD's code, because the later commits
change only the spec text and the ledgers.

Deviations from the frozen text, none of which gates:
- The round-1 cosmetic points remain: the Test Plan Status column says `done` for some rows and `green` for others, and the
  constitution-deviation line says "at most 13 lines" where D-LAUNCH says at most 20.
- The TEST-3960 Test Plan row describes the scan as "every update invocation helper ... asserts its repo argument lies under
  the own scratch root". The scan checks that the assertion exists, not that the argument passed is the asserted one (N-1).

## Findings

### BLOCKING

None.

### NON-BLOCKING (WARNINGs)

**N-1. The scanner does not tie run_update's launcher argument to the asserted `$src`**
(`tests/skills/lib/aai-update.test.mjs:222`; `tests/skills/test-aai-update-node.sh:509-510`).

- Failure scenario: an edit makes the `set --` lines pass `--repo "$PROJECT_ROOT"` / `-Repo "$PROJECT_ROOT"`. The runtime
  `case` still checks `$src` and passes, TEST-3960 stays green, and TEST-3976 then syncs from the checkout. The network-free
  env still holds, so nothing reaches the network.
- backed-by: M3 in `review-r2-mutations.txt` (TEST-3960 10 pass, 0 fail on the mutated suite).
- Minimal fix: in the scanner, require that every line inside `run_update` naming `aai-update.(sh|ps1)` pass the repo as
  exactly `"$src"` (`/(--repo|-Repo) "\$src"/`). Add a positive control that replaces `"$src"` on `:510` and expects at least one problem.
- Recommended disposition: (d), a P3 assurance-strength gap with no bite and no false record. It is the same class as the
  filed `fu-update-shell-scan-bare-launcher`.
  accepted residual: TEST-3960 shell scan does not bind run_update's --repo argument to the asserted $src (review r2 N-1, M3 survived); same text-lint class as fu-update-shell-scan-bare-launcher; runtime case guard and network-free env unchanged.

**N-2. A signal during `wipe()` between clone attempts is dispatched only after the next attempt**
(`.aai/scripts/aai-update.mjs:215-217`).

- Failure scenario: gh fails after a large partial download. Ctrl-C lands while `fs.rmSync` removes `<tmp>/src`, which is
  synchronous, so the handler cannot run. The next `git clone` starts with stdio ignored and runs to completion or a network
  timeout. The run then exits 130. The bash twin dies inside `rm -rf`. The outcome (130, no sync, no temp) is correct. Only the
  extra silent attempt is wrong.
- Unbacked: the repro would need a signal timed into `rmSync`.
- Minimal fix: also yield before each child, as in `wipe(); if (await signalled(state)) return { fail: { code: state.signal, line: '' } };`.
- Recommended disposition: (d), a P3 unexercised edge with no false record.
  accepted residual: a SIGINT/SIGTERM landing during the synchronous wipe() between clone attempts is dispatched only after the next attempt (review r2 N-2); exit code, no-sync and temp removal stay correct; only one extra silent attempt.

### INFO (never gate)

- `aai-update.test.mjs:213`: any line containing `PATH="$fakebin"` is exempt from the scan, whatever else it runs. The one such
  line today (`test-aai-update-node.sh:571`) uses a PATH without node. This belongs to the class of the filed `fu-update-shell-scan-bare-launcher`.
- `run_update`'s `case "$src" in "$work"/*)` accepts a `$work/../x` path. The suite builds `src` only as `$work/source`. This is text-lint reach.
- The `ownSignalCloneRun` test assumes the shim is the module's direct child (`kill $PPID`). That holds because `runUpdate`
  starts `process.execPath` directly. The test is POSIX-only, and the Windows jobs run Pester, not this node:test file.
- `STATUS_MAX_BUFFER` at 1 GiB is above V8's maximum string length (about 512 MiB). A status that large would throw, and the
  `try` would read it as none. That would take roughly 10 million entries, so it is not a realistic input.
- The pipefail audit of the delta's bash found no new pipe-into-early-closing-reader and no bare `rc=$?`.
- Safety: the delta adds no delete, no container call and no kill by pattern. The new test's shim kills only `$PPID` (the
  module it spawned) and `$$`.

## Warning dispositions (H6)

| WARNING | Recommended disposition | Artifact to record |
|---|---|---|
| N-1 | (d) accepted residual, P3 | this report's `accepted residual:` line under N-1 (quote it in notes) |
| N-2 | (d) accepted residual, P3 | this report's `accepted residual:` line under N-2 (quote it in notes) |

Round-1 N-3 and N-4 are recorded as `fu-update-ps51-trailing-backslash-arg` and `fu-update-ps1-non-console-host`. B-1, N-1
and N-2 from round 1 are remediated in `f2c1f31a` and `9d3db7c1`.

## Next steps

1. The orchestrator records the code_review block (pass), quoting both accepted-residual lines in the notes.
2. Proceed to the PR. Hosted H1/H2 and the Linux run of the TEST-3964 own-signal case close the first and the eighth cannot_verify items.
