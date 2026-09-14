# Code Review — mutation-gate-for-tests (ride ref `mutation-gate-for-tests`)

```yaml
review:
  scope: main(94a983ec)...212f0156 — every file in the diff (54 files), plus the explicit path list in the spec's "Isolation and review" section and STATE code_review.scope
  spec: docs/specs/SPEC-DRAFT-spec-mutation-gate-for-tests.md (FROZEN, frozen_sha256 anchored, mutation_gate: v1)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "TEST-471 PASS (aai-mutation-gate rc=0); .aai/scripts/mutation-run.mjs:328-389 clone+tree-hash, :583-589 D7 self-check, :489-500 record write" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "TEST-472 PASS; mutation-run.mjs:519-526 (unknown selector, exit 2), :551-556 (no-op mutation, exit 2), :626-628 finally-rm of the clone" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "TEST-473 = test-aai-hygiene-pack.sh test_094 (aai-hygiene-pack rc=0); the guard ENUMERATES from the tree (hp_scan_selector_suites) and probes each with no_such_test_xyz; 18 suites on disk now carry the declare -F refusal" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "TEST-474 PASS; mutation-run.mjs:623-625 (0/5/6), :439-471 rotateExisting" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "TEST-475 PASS; .aai/scripts/mutation-gate.mjs:209-263 collects EVERY offending row before exit 5" }
      - { ac: Spec-AC-06, call: compliant,
          citation: "TEST-476 PASS; mutation-gate.mjs:174-207 (two degrade classes, degraded=<n>), :96-99 gateError -> exit 3, :167-169 --list-degraded" }
      - { ac: Spec-AC-07, call: compliant,
          citation: "TEST-477 = test-aai-close-work-item.sh test_067 (aai-close-work-item rc=0), four arms incl. absent-key; .aai/scripts/close-work-item.mjs:1151-1188 + :1775-1789 (exit 8, pre-write position)" }
      - { ac: Spec-AC-08, call: compliant,
          citation: "TEST-478 (aai-spec-lint rc=0); .aai/scripts/spec-lint.mjs:624-630 findings, :236-266 mutationGateApplicability, :872-874 prints the applied exemption" }
      - { ac: Spec-AC-09, call: compliant,
          citation: "TEST-479 (aai-spec-lint rc=0); reviewer re-ran `spec-lint.mjs` over the live corpus: 181 scanned, 0 findings. See NB-1 — the by-name resolution silently drops an UNMAPPED header cell (1 live spec), which the AC's literal text does not cover but the module's own invariant comment does" }
      - { ac: Spec-AC-10, call: compliant,
          citation: "TEST-480 PASS + TEST-012 (aai-prompt-diet rc=0); reviewer re-measured the four corpus files main->HEAD: 360+212+232+219 = +1023 B, exactly the single JUSTIFIED_ADDITIONS credit and the want_growth delta 31803->32826" }
      - { ac: Spec-AC-11, call: compliant,
          citation: "TEST-481 PASS (5 arms incl. the concurrent-editor arm); mutation-run.mjs:633-755. See NB-3/NB-4 on the exit-code classification of two other replay paths" }
      - { ac: Spec-AC-12, call: compliant,
          citation: "TEST-482 (aai-spec-amend rc=0) — the printed remedy is captured and eval'd VERBATIM at tests/skills/test-aai-spec-amend.sh:1541, then strict exits 0" }
      - { ac: Spec-AC-13, call: compliant,
          citation: "TEST-483 (aai-spec-amend rc=0); .aai/scripts/lib/spec-contract-hash.mjs:47-48 blanks status/evidence/review-by/notes + Test Plan status" }
      - { ac: Spec-AC-14, call: compliant,
          citation: "TEST-484 (aai-spec-amend rc=0); reviewer re-ran `spec-amend list --strict` on the live tree: exit 0, `spec_degraded=174 (no freeze anchor)`" }
      - { ac: Spec-AC-15, call: compliant,
          citation: "TEST-485 (aai-spec-amend rc=0); .aai/scripts/spec-amend.mjs:351 trackerOpen = trackedItem !== null && trackedItem.closed !== true" }
      - { ac: Spec-AC-16, call: compliant,
          citation: "TEST-486 PASS; reviewer re-ran `node .aai/scripts/mutation-gate.mjs --spec <this spec>`: `GATE PASS: 24 row(s) satisfied degraded=0`, exit 0" }
      - { ac: Spec-AC-17, call: compliant,
          citation: "TEST-489 (aai-spec-tools rc=0); .aai/scripts/spec-freeze.mjs:202-222 stampAnchorAndMarker inside the single freezeContent transform; reviewer reproduced the refusal path on a scratch fixture (mutation-cell-missing -> exit non-zero, file byte-unchanged, no SPEC-FROZEN written)" }
      - { ac: Spec-AC-18, call: compliant,
          citation: "TEST-487 (aai-hygiene-pack rc=0) + TEST-488 (aai-layer-profiles rc=0); suite-map row at the parser's indentation, pin 94->95, PROFILES core: carries all four named files (plus lib/tree-hash.mjs, the fifth file the round-1 amendment added — the AC's literal word 'four' is stale, the classification is complete)" }
      - { ac: Spec-AC-19, call: compliant,
          citation: "TEST-490 run alone: PASS (the batch run of aai-follow-ups aborted earlier on a pre-existing flake, see Suite results); close-work-item-pin.sh:51 new entry 17f97f15…, TEST-008 confirms the hash is on the shared allowlist, the false 'strictly after the try/catch' sentence is gone" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/docs-model.mjs, line: 757,
          issue: "TEST_PLAN_HEADER_MAP is a CLOSED map and an unrecognised header cell silently yields '' instead of the old positional value — contradicting the function's own invariant comment ('kept byte-identical for every existing six-column table')",
          failure_scenario: "docs/specs/SPEC-0062-spec-skill-suite-linux-ci-portability.md heads its column `File path (existing suite)`; measured old-vs-new parse over the live corpus: all 9 rows lose fileCell (old='tests/skills/test-aai-prompt-diet.sh', new=''). specContentHash (docs-model:791+, consumed by orchestration-dispatch.mjs:934) silently changes for that spec, and for any FUTURE gated spec with a header variant mutation-gate.mjs:238 reports every row offending with `the row's File path cell \"\"`" }
      - { rank: NON-BLOCKING, file: .aai/scripts/spec-amend.mjs, line: 975,
          issue: "scanSpecAnchors walks a directory via walk(), which returns [] for a missing path — so the new undisclosed-amendment half of `list --strict` scans NOTHING and still prints `spec_degraded=0` and exits 0, indistinguishable from a clean corpus",
          failure_scenario: "Measured: `node .aai/scripts/spec-amend.mjs list --strict` from any cwd other than the repo root (or with `--specs-dir docs/nonexistent`) prints `spec-amend: spec_degraded=0 (no freeze anchor) specs_dir=<…>/.aai/docs/specs` and exits 0 with zero specs read. The spec's own Isolation section states the rule this breaks: 'a gate that finds nothing is indistinguishable from a gate that found compliance'. Fix: refuse (exit 2) when specsDirAbs does not exist, and print `spec_scanned=<n>` beside spec_degraded" }
      - { rank: NON-BLOCKING, file: .aai/scripts/mutation-run.mjs, line: 688,
          issue: "In --replay, a buildIsolatedClone() failure — INCLUDING TreeMismatchError, i.e. a concurrent writer touching the source tree between the hash and the clone — is counted as `failures++` (exit 1, 'a genuine regression signal'), the exact conflation NB2-r2 fixed 45 lines below at :733 for the in-run trip",
          failure_scenario: "A full sweep (which appends to the TRACKED docs/ai/tests/test-runs.jsonl) runs while a validator runs `mutation-run.mjs --replay` — this ride's own documented operating mode. The clone build refuses, replay prints `FAIL <TEST-id>: could not build an isolated clone (… clone tree hash … does not match …)` and exits 1; .aai/VALIDATION.prompt.md step 5g (added by this ride) says a record that no longer reddens is BLOCKING, so a concurrent writer manufactures a false BLOCKING verdict. Fix: classify a TreeMismatchError/clone-build failure as inconclusive++ with the same message shape as :733" }
      - { rank: NON-BLOCKING, file: .aai/scripts/mutation-run.mjs, line: 679,
          issue: "A record whose target file has vanished prints the word `INCONCLUSIVE` but is counted in `failures`, so the summary line's own arithmetic contradicts the printed line",
          failure_scenario: "One record's target is deleted: replay prints `INCONCLUSIVE TEST-xxx: target no longer exists` and then `…: N-1/N attempted records still redden (0 inconclusive of N total)` — an operator reading the summary sees zero inconclusive rows while an INCONCLUSIVE row was just printed. (The exit code, 1, is what Spec-AC-11 and the header contract ask for; only the counter and the word disagree.)" }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/tree-hash.mjs, line: 26,
          issue: "listTreeFiles enumerates only `git ls-files` + `git ls-files --others --exclude-standard`, so the D7 tripwire (and the D4 clone-vs-source comparison) are BLIND to every gitignored runtime path except docs/ai/tdd — which it excludes deliberately",
          failure_scenario: "A mutated run that writes into the SOURCE tree's docs/ai/STATE.yaml, docs/ai/briefs/, or any .aai runtime sidecar (all gitignored) leaves the tree hash unchanged: the D7 self-check at mutation-run.mjs:583-589 stays silent and the verdict is recorded as RED/STAYED GREEN. D7's prose claims the source repository is 'byte-identical outside docs/ai/tdd afterwards'; what is actually proved is 'identical across tracked + untracked-not-ignored files outside docs/ai/tdd'. Fix: name the narrowing in tree-hash.mjs's header and in D7, or hash a named allowlist of runtime paths too" }
      - { rank: NON-BLOCKING, file: .aai/scripts/spec-amend.mjs, line: 774,
          issue: "The spec_amendment record carries no anchor hashes (no from/to frozen_sha256), and restampSpecAnchor writes the spec with a bare fs.writeFileSync (:809) AFTER the ledger append — no tmp+rename, unlike spec-freeze.mjs's own atomic write discipline the function's comment claims to mirror",
          failure_scenario: "(a) Disclosure: the printed remedy is runnable verbatim with its default `--what`/`--why` ('edit this line to name what changed'), so a record that names nothing clears the gate; nothing links that record to the bytes it is supposed to explain, and a later reader cannot tell which edit it disclosed. Recording `from_hash`/`to_hash` on the entry would anchor it. (b) Atomicity: a crash or EACCES during the in-place rewrite leaves the frozen spec truncated, and because the write happens after the append, the ledger already claims a disclosure that was never stamped — the next `add` appends a SECOND record" }
      - { rank: NON-BLOCKING, file: .aai/scripts/mutation-gate.mjs, line: 210,
          issue: "Every Test Plan row of an applicable spec needs a RED record — there is no exemption for a row the ride truthfully deferred or dropped, although the AC table has exactly those terminal statuses",
          failure_scenario: "A ride defers TEST-xxx (Status `deferred`, disclosed in an amendment). The gate still requires mutation-TEST-xxx.txt with verdict RED, so close-work-item.mjs exits 8 under `enforce` and the only way to close is to fabricate a record or delete the row. Fix: exempt rows whose Status cell is terminal-not-green, and say so in D8" }
      - { rank: NON-BLOCKING, file: CHANGELOG.md, line: 41,
          issue: "The shipped claim says 'all 21 rows RED-recorded (Spec-AC-16)'; the delivered gate reports 24 rows",
          failure_scenario: "`node .aai/scripts/mutation-gate.mjs --spec docs/specs/SPEC-DRAFT-spec-mutation-gate-for-tests.md` prints `GATE PASS: 24 row(s) satisfied degraded=0` — the Test Plan grew by TEST-491/492/493 in remediation round 2. A release note that undercounts its own evidence is the class of claim this ride exists to make checkable" }
      - { rank: NON-BLOCKING, file: .aai/SKILL_TDD.prompt.md, line: 183,
          issue: "The new BLOCK line is unconditional ('Cannot proceed to REFACTOR until … the mutation-run.mjs RED record exists'), but RED is only reachable when the suite prints a `FAIL … <TEST-id>` line (mutation-run.mjs:419-428) — an AAI-suite output convention, not a property of test runners in general",
          failure_scenario: "A vendored downstream project whose suite is jest/pytest/Pester: the mutated run exits non-zero with no line naming TEST-xxx, so every record is INCONCLUSIVE (exit 6) and canon's BLOCK can never be satisfied. The close gate itself degrades safely there (report-only default, and the marker only lands via spec-freeze), but the prompt rule does not. Fix: condition the BLOCK on `mutation_gate: v1`, or name the FAIL-line grammar requirement in the prompt" }
  cannot_verify:
    - { claim: "The HAZ10 Windows / sh-less degrade ('INCONCLUSIVE: bash not found', mutation-run.mjs:560-567) behaves as documented",
        closes_with: "No test exercises the spawnError branch (grepped: no `spawnError` / PATH-stripped arm in tests/skills/test-aai-mutation-gate.sh). A fixture that runs the CLI with PATH cleared, asserting exit 6 and a record naming the degrade, would close it. Note the branch also records `rc: 0` while the header defines rc as 'the suite run's exit code'" }
    - { claim: "Spec-AC-16's end-to-end arm (the gate reading this ride's real records) holds in CI and on a fresh clone",
        closes_with: "docs/ai/tdd/** is gitignored, so TEST-486 arms B/C degrade by name off this machine (the suite says so at :890-916). Only a run in a checkout carrying the evidence proves it; this review reproduced it locally (GATE PASS 24 rows, degraded=0) by copying the evidence tree into the isolated clone" }
    - { claim: "The gate's close-time teeth hold for a ride closed from a checkout without the evidence tree",
        closes_with: "By D9's own degrade, an absent docs/ai/tdd/<spec-id>/ exits 0 ('evidence tree absent'), so a close run anywhere the gitignored evidence is missing passes trivially. Disclosed by design; a durable-evidence decision (or a close-time refusal on 'absent' for the ride's OWN spec) is what would close it" }
    - { claim: "The full 95-suite sweep is green at HEAD 212f0156",
        closes_with: "The newest sweep in docs/ai/tests/test-runs.jsonl (run test-20260914-141739, 95/95) predates the last two commits, and a round-3 sweep was still running concurrently during this review. This review ran 13 suites (list below) in an isolated clone instead" }
    - { claim: "No cross-repo / downstream install breakage from the new spec-freeze precondition",
        closes_with: "Reasoned from code and reproduced locally (a tdd spec without a Mutation column is now REFUSED at freeze, exit non-zero, nothing written). Whether vendored projects' in-flight specs hit it depends on their corpora, which this diff cannot substantiate" }
  overall: pass
```

## Scope and preflight

- STATE `worktree.user_decision: worktree`; `code_review.scope` = `main...feat/mutation-gate-for-tests` plus the spec's explicit path list. Scope established as `git diff main(94a983ec)...212f0156` — 54 files, 6041 insertions.
- Every execution in this review ran in an isolated local clone at
  `…/scratchpad/mgrev` (checked out at 212f0156, `main` = origin/main, the
  gitignored `docs/ai/STATE.yaml` and `docs/ai/tdd/spec-mutation-gate-for-tests/`
  copied in), because a full sweep and a validator run concurrently against the
  worktree. The worktree itself was read only, plus this report.

### Dispatch-prompt note (SKILL_CODE_REVIEW anti-gaming contract, rule 1)

Recorded, not acted on: the dispatch pre-characterised one item's disposition
(`frozen_sha256` laundering — "accepted design — say whether the disclosure is
adequate") and excluded one activity ("do not re-run the validator's
mutations"). No severity was pre-rated and no area of the diff was
scope-excluded. The full scope was reviewed regardless; the laundering
question is answered on its own evidence in NB-6 and below.

## Suite results (isolated clone, `env -u AAI_ROLE`, `AAI_TEST_TIMEOUT=3000`)

| Suite | rc |
|---|---|
| tests/skills/test-aai-mutation-gate.sh | 0 (24 tests) |
| tests/skills/test-aai-spec-amend.sh | 0 |
| tests/skills/test-aai-spec-lint.sh | 0 |
| tests/skills/test-aai-spec-tools.sh | 0 |
| tests/skills/test-aai-close-work-item.sh | 0 |
| tests/skills/test-aai-close-reconcile.sh | 0 |
| tests/skills/test-aai-hygiene-pack.sh (CORE) | 0 |
| tests/skills/test-aai-check-state.sh (CORE) | 0 |
| tests/skills/test-aai-docs-audit.sh (CORE) | 0 |
| tests/skills/test-aai-prompt-diet.sh | 0 |
| tests/skills/test-aai-layer-profiles.sh | 0 |
| tests/skills/test-aai-doc-numbering.sh | 0 |
| tests/skills/test-aai-follow-ups.sh | **1** — see below |

`aai-follow-ups` rc=1 is NOT a regression from this diff. It aborts in
`test_021_early_close_is_not_a_failure`, whose fifo arm dies on
`bash: …/.t021c.fifo: Interrupted system call` / `bash: 4: Bad file
descriptor`. Measured by re-running that ONE test in isolation, same host,
same wrapper: HEAD 1 fail / 3 runs, base main (94a983ec, separate checkout)
2 fail / 3 runs. The diff touches neither `follow-ups.mjs` nor
`lib/cli-pipe-guard.mjs`. The ride's own arms in that suite pass: TEST-490
run alone PASS, TEST-008 PASS (new hash `17f97f15…` on the shared allowlist),
TEST-010 PASS. Pre-existing EINTR flake in `test_021c`, worth its own
registry item, outside this scope.

Direct CLI runs (isolated clone):

- `node .aai/scripts/mutation-gate.mjs --spec docs/specs/SPEC-DRAFT-spec-mutation-gate-for-tests.md` -> exit 0, `GATE PASS: 24 row(s) satisfied degraded=0`
- `env -u AAI_ROLE node .aai/scripts/spec-amend.mjs list --strict` -> exit 0, `spec_degraded=174 (no freeze anchor)`, 18 unsigned-tracked records all with `tracked_status=open`
- `env -u AAI_ROLE node .aai/scripts/spec-lint.mjs` -> exit 0, 181 scanned, 0 findings
- prompt-diet arithmetic re-measured by hand: +360/+212/+232/+219 B = +1023 B, exactly the one ledger credit and the TEST-012 pin move

## What the design gets right (recorded because it is load-bearing)

- **Three verdicts, and they are actually wired.** `classifyVerdict`
  (mutation-run.mjs:419-428) never turns a non-zero-for-another-reason run
  into evidence, and `--replay` keeps a second counter so "I could not tell"
  and "regression" get different exit codes. NB-3/NB-4 are the two places
  that discipline has not reached, not a failure of the idea.
- **The isolation claim is proved, not asserted.** The clone-vs-source tree
  hash (D4 step 4) is a refusal, and the same module computes the fixture's
  external assertion (test suite `mg_tree_hash`) — so a bug in the tool's own
  check cannot also fabricate the test's agreement. The subject-matter
  exclusion (docs/ai/tdd) is applied on both sides.
- **`--sed`/`--patch` never touch a shell.** Every external command is
  `execFileSync`/`spawnSync` with an argv array (mutation-run.mjs:77-80, 298-313,
  397-412), so a mutation expression containing `;`, `$(…)`, backticks or
  spaces is passed literally; paths are built with `path.join`, so spaces and
  symlinked roots are safe. The dangling-symlink path copies the LINK
  (:364-374) instead of reading through it, and the whole clone build is inside
  one try that removes tmpBase on any throw (:338-388).
- **Arbitrary-patch execution is bounded by the evidence tree being
  gitignored.** Records and their stored `.patch` copies can never arrive
  through a PR, so `--replay` re-executing recorded code is a local-trust
  operation, not a supply-chain surface.
- **`frozen_sha256` laundering — the disclosure is adequate.** `add`
  re-stamps (D11), which is what makes the printed remedy actually clear the
  gate, and the same call FILES the `fu-amend-<spec>` obligation; D16's
  `trackerOpen` fix (spec-amend.mjs:351) means a dropped/closed tracker stops
  excusing the record, so the obligation cannot be laundered by discharging
  the item. The hand-editability is stated in the spec (R3) and in the code.
  The one gap is NB-6: the record itself carries no anchor hashes and the
  default `--what`/`--why` text names nothing, so the disclosure is
  guaranteed to EXIST but not to SAY anything.
- **Backward compatibility for downstream installs is real.** `GUARD_DIALS`'
  fail-open default stays `report-only` (guard-config.mjs:75-81) and only this
  repo's own `docs/ai/docs-audit.yaml` ships `enforce`; a spec with no
  `mutation_gate` marker degrades by name at exit 0 (measured: 174 legacy
  specs degrade, the live corpus lints clean). The one hard behaviour change
  for vendored projects is the new freeze precondition (reproduced: a tdd spec
  with no Mutation column is refused, file byte-unchanged) — loud, fixable,
  and named in D9.

## Warning dispositions (SPEC-0013 H6 — recommended, for the orchestrator to record)

| Finding | Recommended disposition |
|---|---|
| NB-3 (replay clone-build failure counted as a regression) | remediate-in-tree — same class as the NB2-r2 amendment already made, and it manufactures false BLOCKING verdicts in this ride's own concurrent operating mode |
| NB-8 (CHANGELOG "21 rows" vs 24) | remediate-in-tree — one line, no test needed |
| NB-1 (unmapped Test Plan header drops a cell) | promote-to-follow-up-ref, P2 |
| NB-2 (`list --strict` spec scan fails open on a missing specs dir) | promote-to-follow-up-ref, P2 |
| NB-5 (D7 tripwire blind to gitignored runtime paths) | promote-to-follow-up-ref, P2 — or a prose correction in D7 + tree-hash.mjs's header, in-tree |
| NB-4 (INCONCLUSIVE printed, counted as a failure) | promote-to-follow-up-ref, P3 |
| NB-6 (no anchor hashes on the record; non-atomic re-stamp) | promote-to-follow-up-ref, P3 |
| NB-7 (no exemption for a deferred Test Plan row) | promote-to-follow-up-ref, P3 |
| NB-9 (SKILL_TDD BLOCK unconditional vs the FAIL-line grammar) | promote-to-follow-up-ref, P3 |

INFO (never gates): `spec-freeze.mjs`'s precondition refusal tail still reads
"Fix the spec (add the missing Test Plan row(s) / record the strategy)", which
does not name the actual fix for the new `mutation-cell-missing` rule (add a
Mutation column). `rotateExisting` keys the rotated filename on the previous
record's `run_at_utc` (second resolution), so two records produced in the same
second would collide — not reachable in practice, a clone plus a suite run
per record. `.aai/system/PROFILES.yaml`'s new entries break the file's
alphabetical ordering (no check asserts it).

## Next steps

1. Orchestrator records each NB above per H6 (decision id / follow-up ref /
   `accepted residual:` line) and mirrors the choice in STATE
   `code_review.notes`.
2. NB-3 and NB-8 are cheap enough to remediate before the PR; NB-3 needs a
   Test Plan row and therefore a `spec-amend add` disclosure, which is this
   ride's own mechanism doing its job.
3. Everything else is merge-ready: both verdicts pass, the ride's own gate
   reads its own spec at `degraded=0`, and the three CORE suites plus every
   suite named in the spec's Verification section are green in an isolated
   clone at 212f0156.
