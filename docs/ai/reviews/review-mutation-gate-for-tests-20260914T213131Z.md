# Code Review (round 2, BOUNDED) — mutation-gate-for-tests

```yaml
review:
  scope: "git diff 212f0156..225a1284 (18 files, +1364/-43) — the delta since the round-1 review PASS"
  spec: docs/specs/SPEC-DRAFT-spec-mutation-gate-for-tests.md (FROZEN, frozen_sha256 fb8b4bc1…, mutation_gate: v1)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "TEST-497 + TEST-499 PASS (aai-mutation-gate rc=0, re-run 5x each); lib/tree-hash.mjs:35 RUNTIME_ALLOWLIST, mutation-run.mjs:406-423 clone reproduction, :677-683 D7 self-check. See NB-1 on the operational cost of the widened hash" }
      - { ac: Spec-AC-02, call: compliant, citation: "untouched by the delta; round-1 citation stands (mutation-run.mjs:614-623, :645-650); aai-mutation-gate rc=0 re-run at 225a1284" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "TEST-503 (aai-mutation-gate rc=0) + TEST-504 (aai-hygiene-pack rc=0, test_130 corpus parity arm); mutation-run.mjs:243-244 comment-line heredoc guard, :289-297 WS class" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "TEST-500 + TEST-502 PASS; mutation-run.mjs:501-518 suffix probe, lib/mutation-record.mjs:129-131/:154-156 suffixed names. See NB-3 (patch sibling still renamed after the live record is removed)" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "TEST-498 PASS; mutation-gate.mjs:64-67 EXEMPT_STATUSES, :226-232 per-row exemption, :281/:295 summary lines. Reviewer reproduced GATE FAIL exit 5 with a mixed spec (1 exempt + 1 offending). See NB-2 on the all-exempt case" }
      - { ac: Spec-AC-06, call: compliant, citation: "untouched by the delta; mutation-gate.mjs:190-221 two degrade classes unchanged; reviewer reproduced 'pre-change spec (no mutation_gate marker)' exit 0 on a fixture" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-477 = test-aai-close-work-item.sh test_067, aai-close-work-item rc=0 at 225a1284. See NB-2's second half (close-work-item discards the gate's EXEMPT lines on exit 0)" }
      - { ac: Spec-AC-08, call: compliant, citation: "aai-spec-lint rc=0; spec-lint.mjs:626-646 unchanged by the delta" }
      - { ac: Spec-AC-09, call: compliant,
          citation: "TEST-494 PASS (aai-spec-lint rc=0); lib/docs-model.mjs:777-789 resolveTestPlanHeaderKey, :828-848 unrecognized collection + positional fallback, spec-lint.mjs:605-616 test-plan-header-unmapped. Reviewer re-measured the live corpus: 2 specs carry an unrecognized header cell (SPEC-0002 'Discipline', SPEC-0060 'Description / executable command'), both status: done so no finding fires; 0 specs trigger the positional fallback. See NB-4" }
      - { ac: Spec-AC-10, call: compliant, citation: "untouched by the delta; prompt files unchanged 212f0156..225a1284 (git diff --stat names no .aai/*.prompt.md)" }
      - { ac: Spec-AC-11, call: compliant,
          citation: "TEST-496 + TEST-501 PASS; mutation-run.mjs:782-793 clone-build failure -> inconclusive++, :533-543 function replacement in the pointer rewrite. Full --replay at this head is in cannot_verify" }
      - { ac: Spec-AC-12, call: compliant, citation: "aai-spec-amend rc=0 (TEST-482 unchanged); spec-amend.mjs:1074-1090 remedy block untouched by the delta" }
      - { ac: Spec-AC-13, call: compliant, citation: "aai-spec-amend rc=0; lib/spec-contract-hash.mjs untouched by the delta" }
      - { ac: Spec-AC-14, call: compliant,
          citation: "TEST-495 PASS; spec-amend.mjs:1022-1034 missing-dir refusal (exit 2), :989/:1046/:1061 spec_scanned. Reviewer re-ran `list --strict` in the isolated clone: exit 0, `spec_scanned=175 spec_degraded=174`" }
      - { ac: Spec-AC-15, call: compliant, citation: "aai-spec-amend rc=0; spec-amend.mjs:351 trackerOpen untouched by the delta" }
      - { ac: Spec-AC-16, call: compliant,
          citation: "Reviewer re-ran `node .aai/scripts/mutation-gate.mjs --spec docs/specs/SPEC-DRAFT-spec-mutation-gate-for-tests.md` in the isolated clone at 225a1284: `GATE PASS: 35 row(s) satisfied degraded=0`, exit 0; CHANGELOG.md:41 now says 35 (round-1 NB-8 closed)" }
      - { ac: Spec-AC-17, call: compliant, citation: "untouched by the delta; spec-freeze.mjs unchanged 212f0156..225a1284" }
      - { ac: Spec-AC-18, call: compliant, citation: "aai-hygiene-pack rc=0 (test_129 pin 95); suite-map.yaml unchanged by the delta" }
      - { ac: Spec-AC-19, call: compliant, citation: "close-work-item.mjs unchanged by the delta, so the pinned sha256 is still current; aai-close-work-item rc=0" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/tree-hash.mjs, line: 35,
          issue: "Adding docs/ai/STATE.yaml and docs/ai/LOOP_TICKS.jsonl to the D7 before/after tree hash makes every ORDINARY concurrent ceremony write trip the tripwire — and those are precisely the two writes canon permits while a dispatched role runs (SUBAGENT_PROTOCOL ENV row: log-tick and append-event stay allowed under AAI_ROLE=subagent)",
          failure_scenario: "An orchestrator log-tick / state.mjs write lands while a validator runs `mutation-run.mjs --test-id TEST-xxx` (a 30 s-plus suite run). mutation-run.mjs:677-683 downgrades the verdict to INCONCLUSIVE (exit 6); writeRecord (:586) rotates the previous RED record aside and installs the INCONCLUSIVE one as the LIVE record; `mutation-gate.mjs --spec` then reports OFFENDING for that row and close-work-item exits 8 under `enforce`. The mechanism is proven by this ride's OWN TEST-497 (tests/skills/test-aai-mutation-gate.sh:1223-1276), which writes exactly one line into docs/ai/STATE.yaml and asserts exit 6 plus `verdict: INCONCLUSIVE` in the record. Second window: STATE.yaml changing between computeTreeFileHashes(ROOT) (:359) and the allowlist copy (:413-423) makes the CLONE hash differ -> TreeMismatchError -> exit 3 (normal run) / inconclusive (replay). Nothing is lost (the RED is rotated, not deleted) but the row must be re-run. Fix: keep the allowlist in the D4 clone-fidelity comparison and EXCLUDE it from the D7 before/after comparison, or downgrade only when a non-allowlist path also moved" }
      - { rank: NON-BLOCKING, file: .aai/scripts/mutation-gate.mjs, line: 227,
          issue: "A Test Plan whose rows are ALL terminal-not-green passes the gate vacuously, and the exemption is invisible at the gate's only enforcement consumer — close-work-item.mjs:1180-1183 `continue`s on exit 0 and parses only `OFFENDING ` lines, so the EXEMPT lines mutation-gate prints are discarded",
          failure_scenario: "Measured on a fixture (mutation_gate: v1, strategy: tdd, 2 rows with Status `deferred` / `dropped`): `GATE PASS: 0 row(s) satisfied degraded=0 exempt=2`, exit 0. close-work-item then closes with no warning, no INFO line, nothing in the close record. The D8 amendment's own claim (spec:500-507, 'named in the gate's output — never silently skipped') holds for the CLI and fails at the teeth. Fix: classify `exempt>0 && satisfied==0` as a DEGRADE class (so it reads like every other applicability degrade), and have evaluateMutationGate surface exempt counts on the exit-0 path" }
      - { rank: NON-BLOCKING, file: .aai/scripts/mutation-run.mjs, line: 560,
          issue: "The new tmp+rename atomicity covers the rotated RECORD only; the PATCH sibling is still renamed AFTER the live record is removed, so the interruption window the comment at :536-545 claims to close is merely moved",
          failure_scenario: "Process dies between fs.rmSync(live) (:560) and fs.renameSync(livePatch, rotatedPatchAbs) (:563): the rotated record on disk names `mutation-<id>.<stamp>.patch`, which was never created, and an orphan live `mutation-<id>.patch` remains. The NEXT run's rotateExisting returns early (:496, no live record) and storePatchCopy (:575) overwrites the orphan — the rotated archive is now permanently unreproducible, which is exactly the D2/D14 property this block exists to guarantee. Fix: rename the patch sibling BEFORE removing the live record" }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/docs-model.mjs, line: 840,
          issue: "The positional fallback assigns a WRONG column rather than an empty one when a header row EXISTS but a key is unresolved — it fires for testId/acCell/typeCell/fileCell whenever headerCells is merely long enough, with no check that the column at that index is unclaimed",
          failure_scenario: "A four-column Test Plan `| Test ID | Spec-AC | Description | Status |`: descriptionCell and statusCell resolve by name, then the fallback sets typeCell=2 (the Description column) and fileCell=3 (the Status column). mutation-gate.mjs:260 then compares the record's suite against the Status cell's text and reports every row offending with a nonsense quote. Measured over the live corpus (probe over all docs/specs Test Plan tables): 0 specs trigger the fallback today, so this is latent, not live. Already tracked as `fu-testplan-fallback-wrong-cell` (P3, decisions.jsonl 2026-09-14T18:11:44Z). Restated here because the module header at :797 still reads 'resolved BY NAME … never by position'. Fix: only fall back to an index no named key already claimed" }
      - { rank: NON-BLOCKING, file: .aai/scripts/mutation-run.mjs, line: 324,
          issue: "applySedExpr still uses the STRING form of String.replace — the exact js-replace-dollar-quote-corrupts trap NB3-r3 fixed 210 lines below it in rotateExisting (:536)",
          failure_scenario: "A Mutation cell such as `sed:s/foo/bar$'/` splices everything after the match back into the clone's target file. The suite then reddens for a reason unrelated to the intended mutation and a FALSE RED record is written and replayed forever — the one class this ride exists to eliminate. Disclosed only in --help (:171-172, 'repl is literal except JS $-patterns'); no refusal, no test. Fix: use a function replacement here too, or escape `$` in the parsed replacement before handing it to replace()" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-mutation-gate.sh, line: 1259,
          issue: "TEST-497 and TEST-499 tune a race with `sleep 1` against a `sleep 3` selector and assert exit 6 STRICTLY; the same write landing one step earlier produces exit 3, a different (also correct) refusal",
          failure_scenario: "If the fixture clone build (mutation-run.mjs:357-437: git clone + git apply + untracked copy + allowlist copy) ever exceeds ~1 s under CI load, the background writer's append lands INSIDE the clone-build window, the clone hash differs from the source hash, and the run exits 3 (TreeMismatchError) rather than 6 — a CI-only red on a correct product, the flake class this repo already carries several of. Reviewer re-ran both tests 5x: 5/5 green on an unloaded machine, so the margin exists but is untested under load. Fix: have the background writer wait on a marker the clone build writes, or accept exit 3 with its own named assertion message" }
      - { rank: NON-BLOCKING, file: .aai/scripts/mutation-run.mjs, line: 106,
          issue: "isRotatedFileName is imported and never used — replay filters live records with its own inline `^mutation-(TEST-\\d+)\\.txt$` at :743 and :763",
          failure_scenario: "The NB2-r3 widening of that helper's regex (lib/mutation-record.mjs:142, `(?:\\.\\d+)?`) therefore has NO production consumer: a future change to the rotated-name grammar will be 'covered' by a helper nothing calls, while the two inline regexes that actually decide live-vs-rotated drift silently. Fix: drop the import, or route replay's filter through the helper so one grammar governs both" }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-DRAFT-spec-mutation-gate-for-tests.md, line: 816,
          issue: "All 19 Spec-AC rows are still `planned` with `—` evidence at 225a1284, and close-work-item.mjs does not flip them",
          failure_scenario: "`node .aai/scripts/docs-audit.mjs --gate spec-mutation-gate-for-tests` exits 1 today with 19 Rule-1 reasons (reproduced in the isolated clone). VALIDATION.prompt.md's AC-FLIP DEFERRAL carve makes this the EXPECTED in-flight state and `--ac-flip-check` PASSES, so it blocks no verdict — but .aai/ROLE_COMMON.md's PRE-HANDOFF AC-TABLE RECONCILIATION says the rows should already be terminal with a `docs/ai/tdd/*.log` evidence path, and nothing in the close ceremony sets them. Unless a role reconciles the table before the close, the close gate stays red and the docs audit reads the spec as a probable false-open" }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-DRAFT-spec-mutation-gate-for-tests.md, line: 1649,
          issue: "The round-4 amendment calls the --sed dialect 'the runner's ERE sed'; the round-5 amendment (:1663) and the tool itself (mutation-run.mjs:16, :171) say it is a JavaScript RegExp, NOT sed BRE/ERE",
          failure_scenario: "The same document gives an operator two answers about the one thing round 5 existed to disambiguate. An author who believes the round-4 sentence writes a POSIX ERE mutation cell (`\\+`, `\\?`, `[[:space:]]`), the runner applies it as a JS RegExp, the result is a no-op, and mutation-run refuses to record — the exact confusion NB2-r5 was filed to end. Fix: correct the round-4 sentence to name the JS RegExp dialect (the escaped `\\(` form it quotes is correct either way, which is why the cell still works)" }
  cannot_verify:
    - { claim: "`mutation-run.mjs --replay --spec <this spec>` is 35/35 RED at 225a1284 (the expensive half: each stored mutation still makes its suite go red in a fresh clone)",
        closes_with: "Validation round 5 measured 35/35 at 434b8e59 (docs/ai/tdd/spec-mutation-gate-for-tests/validation-round5.txt:60); 225a1284 changed mutation-run.mjs itself (+5/-1, the --help dialect lines), which is the --target of four records. This review verified the CHEAP half at 225a1284 instead — a probe over the evidence dir confirms all 35 live records carry `verdict: RED`, their targets exist, and every recorded mutation still applies NON-TRIVIALLY to the current bytes (35 applicable, 0 problems). A `--replay` run at this head closes the rest" }
    - { claim: "The full 95-suite sweep is green at 225a1284",
        closes_with: "The newest committed sweep in docs/ai/tests/test-runs.jsonl is at 434b8e59 (95/95). `node .aai/scripts/select-suites.mjs --base-ref main` returns `FULL_RUN reason=shared-lib path=.aai/scripts/lib/docs-model.mjs`, so CI will run the full sweep on this branch regardless. This review ran 7 suites (table below) in an isolated clone" }
    - { claim: "The LOOP_TICKS.jsonl half of RUNTIME_ALLOWLIST behaves as the STATE.yaml half does",
        closes_with: "Only docs/ai/STATE.yaml is exercised (TEST-497). `grep -n LOOP_TICKS tests/skills/test-aai-mutation-gate.sh` returns nothing. A second arm writing docs/ai/LOOP_TICKS.jsonl, or a table-driven arm over RUNTIME_ALLOWLIST, would close it" }
    - { claim: "TEST-497 / TEST-499 hold under CI load (NB-6)",
        closes_with: "Both are timing-tuned. 5/5 green locally on an unloaded machine; the clone-build duration under a loaded CI runner is what decides it, and this diff cannot substantiate that" }
    - { claim: "The new `test-plan-header-unmapped` lint rule causes no noise in vendored downstream repositories",
        closes_with: "This corpus produces zero findings (measured: the 2 specs with an unrecognized header cell are both `status: done`, and the rule is in-flight-only). Another repo's in-flight specs are outside this diff" }
  overall: pass
```

## Scope and preflight

- STATE `worktree.user_decision: worktree`. Round-2 scope as dispatched:
  `git diff 212f0156..225a1284` — 18 files, +1364/-43. This is a re-review of
  the delta since the round-1 PASS, not a re-review of the whole branch;
  round-1 citations are carried for ACs the delta does not touch, and each
  such row says so.
- Every execution ran in an isolated local clone at
  `…/scratchpad/mgrev2`, checked out at 225a1284, `main` = origin/main, the
  gitignored `docs/ai/STATE.yaml` and `docs/ai/tdd/spec-mutation-gate-for-tests/`
  copied in. `git status --porcelain` in the clone is EMPTY after all suite
  runs — no suite wrote into its own shipping tree. The worktree itself was
  read only, plus this report.

### Dispatch-prompt note (SKILL_CODE_REVIEW anti-gaming contract, rules 1 and 4)

Recorded, not acted on: the dispatch named a specific hypothesis to test
("is copying `docs/ai/STATE.yaml` into the clone safe — could a suite in the
clone write STATE and break the tree-hash comparison?") and enumerated areas
of interest. No severity was pre-rated, no ranked answer key was given and no
area was scope-excluded, so this is below rule 1's bar; it is recorded because
a named hypothesis is still a steer. The full delta was reviewed regardless,
and the named hypothesis is answered on its own evidence below — the answer
is NO for the shape asked about and YES for a different one (NB-1).

## The dispatched question, answered

**Can a suite running in the clone write STATE and break the tree-hash
comparison?** No. The clone's tree is hashed ONCE, at
`mutation-run.mjs:425-426`, strictly before `runSuite` is ever called, and is
never re-hashed. The suite runs with `cwd: cloneDir` (:456-461), so any
`state.mjs` write it makes lands on the clone's own copy and is invisible to
every comparison the tool makes. Both hash inputs are symmetric — the source
side adds the allowlist by `existsSync` (`tree-hash.mjs:58-60`) and the clone
side reproduces it by `copyFileSync` (`mutation-run.mjs:413-423`), each
guarded on presence, so a checkout WITHOUT `docs/ai/STATE.yaml` (CI's shape)
skips it on both sides.

What the change does cost is the opposite direction: the SOURCE tree's
STATE.yaml and LOOP_TICKS.jsonl are now inside the D7 before/after
comparison, so an ordinary concurrent ceremony write — the two writes canon
explicitly permits a dispatched role to make — now trips the tripwire.
That is NB-1, and the ride's own TEST-497 is its proof.

Copying the LIVE ride's STATE into the clone has one further consequence
worth naming (no finding filed, no observed bite): a suite in the clone now
sees a real STATE.yaml where it previously saw none, so a STATE-sensitive
suite's behaviour inside a mutation run is no longer independent of the
ride's live bookkeeping. This makes the clone MORE faithful to the tree it
claims to reproduce (the real tree has a STATE.yaml), which is why it is not
filed as a defect — but a `--replay` months later reads a different STATE
than the recording run did, and no record field captures that.

## Suite results (isolated clone at 225a1284, `env -u AAI_ROLE`)

| Suite | rc |
|---|---|
| tests/skills/test-aai-mutation-gate.sh | 0 |
| tests/skills/test-aai-spec-amend.sh | 0 |
| tests/skills/test-aai-spec-lint.sh (CORE) | 0 |
| tests/skills/test-aai-close-work-item.sh | 0 |
| tests/skills/test-aai-hygiene-pack.sh (CORE) | 0 |
| tests/skills/test-aai-check-state.sh (CORE) | 0 |
| tests/skills/test-aai-docs-audit.sh (CORE) | 0 |
| `mutation-gate.mjs --spec <this spec>` | 0 — `GATE PASS: 35 row(s) satisfied degraded=0` |
| `spec-amend.mjs list --strict` | 0 — `spec_scanned=175 spec_degraded=174` |
| `docs-audit.mjs --ac-flip-check` | 0 |
| `docs-audit.mjs --gate` | 1 — 19 Rule-1 non-terminal rows (see NB-8) |
| TEST-497 / TEST-499 re-run 5x each | 0 (10/10) |

CORE is the four suites `tests/skills/suite-map.yaml` names
(`aai-check-state`, `aai-docs-audit`, `aai-spec-lint`, `aai-hygiene-pack`);
all four ran.

## Round-1 NB dispositions (verified in-tree at 225a1284)

| Round-1 NB | Disposition | Verified |
|---|---|---|
| NB-1 docs-model closed header map | CLOSED in-tree | `resolveTestPlanHeaderKey` (docs-model.mjs:777), unrecognized-cell collection (:828-848), `test-plan-header-unmapped` (spec-lint.mjs:605-616), TEST-494 PASS. Residual filed as `fu-testplan-fallback-wrong-cell`; see NB-4 |
| NB-2 `list --strict` scans nothing | CLOSED in-tree | spec-amend.mjs:1022-1034 refusal (exit 2, names the path), `spec_scanned` on every strict run (:1061), TEST-495 PASS; reviewer reproduced `spec_scanned=175` live |
| NB-3 replay clone-build = failures++ | CLOSED in-tree | mutation-run.mjs:782-793 `inconclusive++` + INCONCLUSIVE message, TEST-496 PASS |
| NB-4 vanished-target counter/word | FILED | `fu-replay-vanished-target-counter` (P3) present in decisions.jsonl; behaviour at :773-777 unchanged, as intended |
| NB-5 tree-hash blind to gitignored paths | CLOSED in-tree | `RUNTIME_ALLOWLIST` (tree-hash.mjs:35) + named narrowing in the module header, D7 amendment (spec:465-476), clone reproduction (mutation-run.mjs:413-423), TEST-497 PASS. See NB-1 for the cost |
| NB-6 amendment record lacks from/to hash + non-atomic restamp | FILED | `fu-amend-record-lacks-from-to-hash` (P3) present; `restampSpecAnchor`'s bare write is unchanged, as intended |
| NB-7 no exemption for a deferred row | CLOSED in-tree | `EXEMPT_STATUSES` (mutation-gate.mjs:64-67), per-row exemption (:226-232), D8 amendment (spec:500-509), TEST-498 PASS. See NB-2 for the new fail-open edge |
| NB-8 CHANGELOG says 21 rows | CLOSED in-tree | CHANGELOG.md:41 now says 35; the gate reports 35 |
| NB-9 SKILL_TDD BLOCK unconditional | FILED | `fu-tdd-block-needs-fail-line-grammar` (P3) present; prompt unchanged, as intended |

Validation-round NB follow-ups also verified present in `docs/ai/decisions.jsonl`:
`fu-testplan-fallback-wrong-cell`, `fu-deferred-row-empty-mutation-cell`,
`fu-test439-single-line-guard-grep`, `fu-runmain-runs-main-on-import` (all P3,
one ledger line each).

## Warning dispositions (H6)

Every NON-BLOCKING finding above needs one of (a) remediate, (b)/(c) a typed
follow-up, (d) `accepted residual`. Recommended disposition — the ORCHESTRATOR
records it, this reviewer does not file refs:

- **NB-1** (allowlist vs. concurrent ceremony writes) — recommend
  **remediate-in-tree**. It is the one finding with a live operational bite on
  this repository's own ride pattern, and the fix is a scoped exclusion in one
  comparison, not a redesign.
- **NB-2** (all-exempt vacuous pass, exemption invisible at the close) —
  recommend **remediate-in-tree**. It is a fail-OPEN in a gate, and the fix is
  a degrade classification plus one line in `evaluateMutationGate`.
- **NB-3** (patch sibling renamed after the live record is removed) —
  recommend **remediate-in-tree** (two statements swapped) or promote to a
  follow-up ref if the round is closing.
- **NB-4** (positional fallback picks a wrong column) — already tracked:
  `fu-testplan-fallback-wrong-cell`. No new artifact needed; the module header
  comment at docs-model.mjs:797 should be corrected either way.
- **NB-5** (`applySedExpr` string replacement) — recommend
  **promote-to-follow-up-ref**; it is the same class as the LEARNED rule this
  repo already carries and deserves a named queue item rather than a rushed
  edit.
- **NB-6** (timing-tuned TEST-497/TEST-499) — `accepted residual: both tests
  are green 10/10 in this review, the failure mode is a CI-only red on a
  correct product (exit 3 instead of exit 6, both refusals), no false pass is
  possible, and the fix costs more synchronization machinery than the flake
  costs to re-run.`
- **NB-7** (unused `isRotatedFileName` import) — `accepted residual: dead
  import only; the live-vs-rotated decision is made by two inline regexes that
  are correct today, nothing is mis-classified, and no false record exists
  anywhere.`
- **NB-8** (19 `planned` AC rows) — recommend **remediate-in-tree** before the
  close ceremony: the AC Status table must be reconciled to terminal statuses
  with `docs/ai/tdd/*.log` evidence, or `docs-audit --gate` stays red at close.
- **NB-9** (round-4 "ERE sed" vs round-5 "JavaScript RegExp") — recommend
  **remediate-in-tree** (one sentence), under the same additive-with-disclosure
  amendment convention the round-5 correction used.

## Next steps

1. Reconcile the AC Status table (NB-8) before the close ceremony; re-run
   `docs-audit.mjs --gate spec-mutation-gate-for-tests` to 0.
2. Decide NB-1 and NB-2 (both recommended remediate-in-tree); each needs one
   new Test Plan row with a mutation that reddens it, per this spec's own gate.
3. Run the full sweep at the final head (`select-suites.mjs` says FULL_RUN) and
   `mutation-run.mjs --replay --spec <this spec>` at that head, to close the
   first two `cannot_verify` entries.
