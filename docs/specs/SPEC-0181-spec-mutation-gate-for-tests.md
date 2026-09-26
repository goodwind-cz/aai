---
id: spec-mutation-gate-for-tests
type: spec
number: 181
status: done
frozen_sha256: 6d46c5b264d482df500c802df8d5f7daea0260d6db3e8d2de920fa8544dcc752
ceremony_level: 2
mutation_gate: v1
mutation_uncomparable: 49
links:
  requirement: docs/issues/CHANGE-0187-mutation-gate-for-tests.md
  rfc: null
  pr:
    - 384
  commits:
    - 86c6db598c185302dc598f2bc32f51df9fc4691f
---

# Spec — a test is admitted only with the mutation that reddens it

SPEC-FROZEN: true

## Links
- Requirement (primary path, unnumbered by design — `allocate-doc-number.mjs`
  assigns the number at the PR and renames the file, so every in-branch
  reference below uses the DRAFT path):
  docs/issues/CHANGE-0187-mutation-gate-for-tests.md
- Paired maintenance half: docs/issues/CHANGE-0181-unrecorded-spec-amendment-is-invisible.md
- Mandate: docs/project-sessions/2026-09-13-wave-3-subsystem-sweeps.md
  ("Re-order of 2026-09-14 (owner decision)", lines 79-89 — menu answer A, ledger
  `hitl_decision` 2026-09-14, `ref_id: wave-3-subsystem-sweeps`)
- Roadmap: docs/ai/roadmap.yaml lines 30-32 (`mutation-gate-for-tests` paired
  with `unrecorded-spec-amendment-is-invisible`, status `active`)
- Sweep 2 (merged, the evidence conventions this scope promotes to a gate):
  docs/specs/SPEC-0179-spec-test-framework-sweep.md `## Mutation checks`
- Sweep 3 (merged, the exit-code discipline this scope reuses):
  docs/specs/SPEC-0180-spec-dispatch-state-sweep.md D8 and `## Mutation checks`
- Technology contract: docs/TECHNOLOGY.md
- Ceremony table: .aai/workflow/WORKFLOW.md "Ceremony levels" (lines 45-79)

## Implementation strategy
- Strategy: tdd
- Rationale: recorded at intake (`## Verification`: "validation by a different
  model re-running every mutation record") and correct on the evidence. Every AC
  here is a REFUSAL — a gate that must exit non-zero on a state it has never been
  observed refusing is the exact defect this scope exists to remove. A green run
  of a gate proves nothing about the gate; only a run in which the gate fails,
  for the reason it claims, does. This spec is additionally the first document
  the delivered gate reads, so a strategy that did not demand a per-test mutation
  would contradict the capability being built (intake AC-008).

## Isolation and review
- Worktree recommendation: required
- Worktree rationale: this scope edits `.aai/scripts/close-work-item.mjs` — the
  close ceremony that ships every ride, hash-pinned by
  `tests/skills/lib/close-work-item-pin.sh` so that a single changed byte reddens
  four suites — and `.aai/scripts/spec-freeze.mjs` and
  `.aai/scripts/spec-amend.mjs`, which are the tools Planning and every role use
  to freeze and amend the spec of the ride currently in flight. A half-applied
  edit inline does not fail a test; it breaks the ceremony that would have
  reported the failure, for every concurrent ride in the shared checkout (P1
  scar, 2026-09-06, `docs/knowledge/LEARNED.md`). The worktree already exists.
- User decision: worktree
- Base ref: main at 94a983ec (branch `feat/mutation-gate-for-tests`, worktree
  HEAD d9dabf9b — the intake commit)
- Worktree branch/path: `feat/mutation-gate-for-tests` at the sibling worktree
  `aai-feat-mutation-gate-for-tests` beside the shipping checkout (written as a
  repo-relative sibling deliberately — `fu-specs-embed-developer-local-paths`)
- Inline review scope: not applicable — see the explicit list below.

Review scope (exact paths, the list `set-code-review --scope` records):

`.aai/scripts/mutation-run.mjs .aai/scripts/mutation-gate.mjs .aai/scripts/lib/mutation-record.mjs .aai/scripts/lib/spec-contract-hash.mjs .aai/scripts/lib/docs-model.mjs .aai/scripts/lib/guard-config.mjs .aai/scripts/spec-lint.mjs .aai/scripts/spec-freeze.mjs .aai/scripts/spec-amend.mjs .aai/scripts/close-work-item.mjs .aai/SKILL_TDD.prompt.md .aai/VALIDATION.prompt.md .aai/ROLE_COMMON.md .aai/SKILL_PR.prompt.md .aai/templates/SPEC_TEMPLATE.md .aai/system/PROFILES.yaml docs/ai/docs-audit.yaml tests/skills/suite-map.yaml tests/skills/lib/close-work-item-pin.sh tests/skills/lib/prompt-diet-ledger.sh tests/skills/test-aai-mutation-gate.sh tests/skills/test-aai-spec-lint.sh tests/skills/test-aai-spec-amend.sh tests/skills/test-aai-spec-tools.sh tests/skills/test-aai-close-work-item.sh tests/skills/test-aai-close-reconcile.sh tests/skills/test-aai-prompt-diet.sh tests/skills/test-aai-layer-profiles.sh tests/skills/test-aai-hygiene-pack.sh tests/skills/test-aai-follow-ups.sh tests/skills/test-aai-doc-numbering.sh tests/skills/test-aai-suite-select.sh tests/skills/test-aai-run-tests.sh tests/skills/test-aai-branch-guard.sh tests/skills/test-aai-session-lock.sh tests/skills/test-aai-git-ref-guard.sh tests/skills/test-aai-issues.sh tests/skills/test-aai-pr-platform.sh tests/skills/test-aai-routine.sh tests/skills/test-aai-win-fallback.sh tests/skills/test-aai-feedback-triage.sh tests/skills/test-aai-feedback-status.sh tests/skills/test-aai-feedback-upsert.sh tests/skills/test-aai-learned-routing.sh tests/skills/test-aai-live-serve.sh tests/skills/test-aai-ride-select.sh tests/skills/test-aai-unattended.sh docs/specs/SPEC-0181-spec-mutation-gate-for-tests.md docs/issues/CHANGE-0187-mutation-gate-for-tests.md docs/issues/CHANGE-0181-unrecorded-spec-amendment-is-invisible.md docs/ai/decisions.jsonl docs/ai/tests/test-runs.jsonl CHANGELOG.md`

Expected companions (not part of the scope list above but MUST be staged with
it, for the reason SPEC-0180 recorded): `docs/ai/decisions.jsonl` carries this
ride's registry closures and any post-freeze `spec_amendment` record, and every
gate reads CLEAN on its absence — a gate that finds nothing is indistinguishable
from a gate that found compliance. `docs/ai/tests/test-runs.jsonl` carries the
run ledger this ride's evidence cites.

## Ceremony level

`ceremony_level: 2`. Every path this scope edits was checked by name against
`protected_paths_l3` in `docs/ai/docs-audit.yaml` (the eight entries at lines
74-81, mirrored in `.aai/workflow/WORKFLOW.md` lines 68-74):

- `.aai/scripts/state.mjs` — NOT touched.
- `.aai/scripts/lib/state-engine.mjs` — NOT touched.
- `.aai/scripts/lib/state-core.mjs` — NOT touched.
- `.aai/scripts/allocate-doc-number.mjs` — NOT touched (its L3-adjacent
  follow-up `fu-realpath-allocate-doc-number-l3` is explicitly rejected below
  for exactly this reason).
- `.aai/scripts/pre-commit-checks.sh` / `.ps1` — NOT touched. D10 rejects the
  pre-commit placement of the amendment detector, which is the only way this
  scope could have reached these files.
- `.aai/workflow/WORKFLOW.md` — NOT touched. The mutation requirement is an
  evidence rule for the `tdd` strategy, not a ceremony-level rule, so it lands
  in `.aai/SKILL_TDD.prompt.md`, `.aai/VALIDATION.prompt.md` and
  `.aai/ROLE_COMMON.md` and not in the ceremony table.
- `docs/CONSTITUTION.md` — NOT touched.

Considered and rejected: raising to level 3 because `close-work-item.mjs` is
hash-pinned. The pin is an implementation constraint this spec plans around (D11
and the re-pin ordering in `## Implementation plan`), not a protected surface —
the L3 list is the authority and it does not carry that file. SPEC-0179 edited
`tests/skills/test-framework.sh` and `.aai/scripts/aai-run-tests.sh` at level 2
on the same reading. Review may re-classify upward as a recorded finding.

## What is established before this scope starts

Every number below was measured on 2026-09-14 in this worktree
(`feat/mutation-gate-for-tests`, HEAD d9dabf9b, based on main 94a983ec) under
`bash` with `/usr/bin/grep` — `grep` is aliased to ugrep in the authoring shell
and zsh rewrites glob-looking arguments, so neither is trusted here.

1. **Canon does not contain the word.** `.aai/SKILL_TDD.prompt.md`,
   `.aai/VALIDATION.prompt.md`, `.aai/ROLE_COMMON.md` and
   `.aai/SKILL_PR.prompt.md` carry ZERO occurrences of "mutation". The single
   mutation-testing-adjacent sentence in the whole corpus is
   `.aai/SKILL_CODE_REVIEW.prompt.md:97` ("rename it or prove the negative
   (corpus sweep / mutation)"), which is advice to a reviewer, not a produced
   artefact. `tests/skills/README.md:366` lists `- [ ] Mutation testing` as
   unchecked future work.
2. **The practice exists, unowned, in 41 suite files.** `tests/skills/*.sh`
   carries hand-rolled mutation controls with at least three incompatible
   spellings: `test-aai-close-reconcile.sh:552-606` (`TEST-011 ... MUTATION
   control`), `test-aai-git-ref-guard.sh:251-276` (`TEST-302 — THE MUTATION
   PROOF`), `test-aai-intake.sh:572` (`intake_mutant_script()`),
   `test-aai-feedback-upsert.sh:971` ("kills mutation U-05"). Highest counts:
   `test-aai-hygiene-pack.sh` 37, `test-aai-suite-isolation.sh` 35,
   `test-aai-spec-amend.sh` 19.
3. **Two record conventions already exist and disagree.** SPEC-0179 records
   `docs/ai/tdd/spec-test-framework-sweep/mutation-445.txt` (keyed on the TEST
   number); SPEC-0180 records `mutation-<Mnn>.txt` (keyed on a mutation id
   private to that spec, M1..M44). Neither is machine-readable: no header, no
   verdict token, no tree reference.
4. **The evidence tree is gitignored.** `.gitignore:35-37` ignores
   `docs/ai/tdd/**` except the directory itself and `.gitkeep`. The two sweep
   directories named above do NOT exist in this worktree (they were produced in
   their own worktrees), which is exactly the degrade the gate must survive in
   CI and on a fresh clone.
5. **No spec is in flight.** `docs/specs/` holds 183 documents, 179 with a
   `## Test Plan` section, 174 carrying the frozen marker, and ZERO with
   `status: implementing`. So every existing frozen spec is a pre-change spec
   and the degrade path is the whole corpus, not an edge case.
6. **The strict amendment gate is green today, and would be green on the
   incident.** `env -u AAI_ROLE node .aai/scripts/spec-amend.mjs list --strict`
   exits 0 in this worktree, listing 11 `unsigned-tracked` records for
   `spec-test-framework-sweep` plus one NOTE. CHANGE-0181's measurement stands:
   an amendment made without calling `spec-amend add` produces no record and the
   gate has nothing to judge.
7. **The registry's open set is 91 items** (`follow-ups.mjs list --status open
   --json`, re-derived at planning). Five of the six ids the intake names as the
   bucket are already TERMINAL: `fu-test210-branch-now-dead-code` done,
   `fu-learned-immutable-pin-lint` done, `fu-test029-count-not-subset` done,
   `fu-probe-redirect-lands-in-shipping-cwd` dropped,
   `fu-dispatch-gate-spawn-seam-untested` dropped. Only
   `fu-test-selector-unknown-id-passes` is still open. The bucket below is
   therefore re-derived from the LIVE open set by the finding class, not copied
   from the intake.
8. **The prompt corpus and its exact arithmetic.** The measured corpus is
   `.aai/*.prompt.md` (non-recursive) plus exactly three extras
   (`INTAKE_COMMON.md`, `STATE_FALLBACK.md`, `ROLE_COMMON.md`), defined at
   `tests/skills/test-aai-prompt-diet.sh:329-333`. Measured now: corpus 339634 B
   + extras 18908 B; `BASELINE_PROMPT_BYTES=357457`
   (`tests/skills/lib/prompt-diet-ledger.sh:20`),
   `REQUIRED_REDUCTION_BYTES=28672` (`:21`), `JUSTIFIED_GROWTH_BYTES=31803`
   (105 entries), `HEADROOM_CAP=2048` (`:215`). So
   `reduction = 357457 - 339634 - 18908 + 31803 = 30718` and
   `headroom = 30718 - 28672 = 2046`. TEST-010 fails when headroom is below 0
   OR above 2048. **Direction, measured, because it is easy to get backwards:**
   adding N corpus bytes LOWERS headroom to 2046-N; removing bytes RAISES it,
   and only 2 bytes may be removed before the cap bites. An itemized
   `JUSTIFIED_ADDITIONS` entry of exactly N restores headroom to 2046 and
   requires `want_growth` at `tests/skills/test-aai-prompt-diet.sh:812` to move
   31803 -> 31803+N (asserted by `test_012_growth_sum_matches_ledger`, and
   independently re-summed at `:727-729`). A credit that does not EQUAL the
   measured growth fails on one side or the other.
9. **Corpus membership of the files this scope touches.** IN the measured
   corpus: `.aai/SKILL_TDD.prompt.md` (16894 B), `.aai/VALIDATION.prompt.md`
   (20663 B), `.aai/ROLE_COMMON.md` (6528 B). OUTSIDE it (no ledger cost):
   `.aai/SUBAGENT_PROTOCOL.md`, `.aai/system/PROFILES.yaml`,
   `.aai/templates/SPEC_TEMPLATE.md` — the glob is non-recursive and the extras
   list is closed (corroborated at `prompt-diet-ledger.sh:90,93`).
10. **Test id band.** The highest `TEST-4xx` id anywhere under `tests/` or
    `docs/` is TEST-470 (`git grep -ho "TEST-4[0-9][0-9]"`). This scope
    continues at TEST-471. Per-suite sequences that this scope reuses rather
    than continues: `test-aai-prompt-diet.sh` TEST-012
    (`test_012_growth_sum_matches_ledger`, the ledger checkpoint) and
    `test-aai-spec-tools.sh`, whose own sequence ends at TEST-024.
11. **The selector fails open in FIFTEEN suites, not the three the item names.**
    `fu-test-selector-unknown-id-passes` (P2, open) names
    `test-aai-branch-guard.sh`, `test-aai-session-lock.sh` and
    `test-aai-layer-profiles.sh`. Measured, there is no shared framework
    selector at all — `test-framework.sh` has only `--skill` (suite level,
    `:945-961`) and `aai-run-tests.sh` has none — and two per-suite idioms
    exist:
    - the dynamic `ALL_TESTS` idiom (10 suites), e.g.
      `test-aai-branch-guard.sh:1305-1319`, which runs `"test_${t}"` for each
      selected id. 8 of the 10 run under `set -uo pipefail` with NO `-e`, so a
      command-not-found (127) is swallowed, `log_pass "All selected … passed"`
      prints and the script exits 0: `test-aai-branch-guard.sh`,
      `test-aai-git-ref-guard.sh`, `test-aai-issues.sh`,
      `test-aai-pr-platform.sh`, `test-aai-session-lock.sh`,
      `test-aai-run-tests.sh`, `test-aai-routine.sh`,
      `test-aai-win-fallback.sh`. The other two (`test-aai-pr-waiver.sh`,
      `test-aai-test-canon.sh`) carry `set -e` and exit 127.
    - the positional `"$1"` idiom (8 suites, the literal `SELECTED PASSED`),
      e.g. `test-aai-layer-profiles.sh:779-784`. 7 of the 8 run without `-e`
      and print `SELECTED PASSED (<name>)` after the command-not-found:
      `test-aai-feedback-triage.sh`, `test-aai-feedback-status.sh`,
      `test-aai-feedback-upsert.sh`, `test-aai-learned-routing.sh`,
      `test-aai-live-serve.sh`, `test-aai-ride-select.sh`,
      `test-aai-unattended.sh`. `test-aai-layer-profiles.sh` gained
      `set -euo pipefail` in 94a983ec (sweep 2) and now exits 127 — one of the
      three named suites is already fixed by accident, which is exactly why the
      count in a follow-up's text is not a scope.
    So the live population is 15 fail-open suites. A runner that selects ONE
    test by name inherits the defect unless it refuses first.
14. **The Test Plan reader is POSITIONAL and reads four columns.**
    `lib/docs-model.mjs:755-774` `parseTestPlanTable` never parses the header:
    it keeps any row whose first cell matches `/^TEST-\d+$/` and returns
    `{ testId: cells[0], acCell: cells[1], typeCell: cells[2], fileCell:
    cells[3] }`. Indices 4 (Description) and 5 (Status) are never read. A column
    APPENDED at the end is therefore silently ignored today — back-compat for
    179 six-column specs is free — and a column INSERTED anywhere before index 4
    silently shifts three cells with no error and no finding. `splitTableCells`
    (`:742-745`) honours an escaped `\|`.
15. **A different spec hash already exists and is the wrong one for CHANGE-0181.**
    `lib/docs-model.mjs:791-809` `specContentHash` is a sha256 over
    `ac\t<id>\t<normalized status>` plus
    `test\t<testId>\t<acCell>\t<typeCell>\t<fileCell>`. It INCLUDES each AC's
    status and EXCLUDES every Description cell and all prose — precisely
    inverted against the incident CHANGE-0181 records (SPEC-0171's Spec-AC-01
    through 03 rewritten in their Description cells, with statuses untouched).
    It is a change-detector for the AC/test SKELETON, not for the contract.
16. **The strict gate's internals.** `spec-amend.mjs:893`
    `STRICT_VIOLATION_BUCKETS = ['unsigned-untracked','unclassified']`;
    violations are computed over the whole ledger (`:906`), printed to stdout as
    `STRICT-VIOLATION <bucket> ts=<ts> ref=<ref> spec=<spec_id>` (`:923-925`)
    with one runnable `classify` line per violation on stderr (`:955`), then
    `exit(1)` (`:959`). The tracker bucketing is `trackedItem !== null` at
    `:342` — existence, not openness (`fu-spec-amend-terminal-tracker-counts`).
    `add`'s flags are `--ledger --spec --ref --what --why --signoff --authority
    --actor` (`:554-558`); it writes only the ledger today. The file contains a
    non-UTF8 byte, so `grep` needs `-a` on it.
17. **`spec-freeze.mjs` computes no hash.** It writes exactly two things in one
    in-memory transform (`freezeContent`, `:146-201`): frontmatter
    `status: implementing` (`:160`) and the body freeze marker set true
    (`:166-190`), then one `writeFileSync` to `<abs>.spec-freeze.tmp` plus
    `renameSync` (`:289-294`). `assertFrozen` (`:209-221`) re-parses the result
    and does NOT enumerate frontmatter keys, so an added key passes.
    `PRECONDITION_RULES = ['ac-without-test','frozen-without-strategy',
    'unresolved-clarification']` (`:83`) is the closed list of lint rules that
    REFUSE a freeze (exit 3, nothing written).
18. **The close ceremony has no gate table and three dialed gates.**
    `close-work-item.mjs` calls them inline: product-doc (`:1696`, exit 3),
    usage-capture (`:1711`, exit 4), evidence-path (`:1727`, exit 5); 6 is
    STATE-reconcile PARTIAL and 7 is the HEAD pin. The next free exit code is 8.
    The dial names are a closed list in `lib/guard-config.mjs:40`
    (`GUARD_DIALS`), fail-open to `report-only` (`:59-69`).
19. **The pin is one sha256 over one whole file, asserted by two suites.**
    `tests/skills/lib/close-work-item-pin.sh:35` pins
    `.aai/scripts/close-work-item.mjs`; `CLOSE_WORK_ITEM_ALLOWED_HASHES`
    (`:37-48`) holds 9 entries, each `"<sha256> <re-affirmation prose>"`;
    `close_work_item_pin_assert` (`:103-120`) fails with the message at `:112`.
    The owning suites named in its header (`:4-11`) are
    `tests/skills/test-aai-follow-ups.sh` (TEST-008, and test_010 drives the
    assert directly) and `tests/skills/test-aai-doc-numbering.sh` (TEST-029) —
    NOT `test-aai-close-work-item.sh`.
20. **Registration is two pins plus a checker.** `tests/skills/suite-map.yaml`
    needs a row `  aai-mutation-gate:` (two-space indent, `globs:` at four,
    items at six — the hand-rolled parser's contract, `:1-29`), and
    `tests/skills/test-aai-hygiene-pack.sh:1096-1099` pins the row count at the
    literal `94`, which a new suite must move to 95.
    `test_093_test_registration` (`:1016-1026`) runs
    `check-test-registration.mjs`, which refuses a `test_*()` function that is
    never referenced outside its own definition.
21. **Any edit under `.aai/scripts/lib/` escalates suite selection to a FULL
    run.** `tests/skills/suite-map.yaml:44-46`
    `full_run_triggers.shared_lib_globs: .aai/scripts/lib/**`. This scope edits
    `lib/docs-model.mjs` regardless, so every intermediate round of this ride is
    a full sweep whatever else it adds there (R8).
22. **The close ceremony already runs the strict amendment gate.**
    `.aai/SKILL_PR.prompt.md:188-196` step 4c AMENDMENT GATE runs
    `spec-amend.mjs list --strict` before the close, reading exit 1 as "it
    PRINTS one runnable classify line per offending record". So CHANGE-0181's
    detector reaches the ceremony through wiring that already exists — but the
    sentence describing the output becomes incomplete the moment a second
    violation class prints an `add` line instead.
23. **Ceremony inputs.** `protected_paths_l3` holds eight paths
    (`docs/ai/docs-audit.yaml:74-81`); the close-time dials already in that file
    are `close_gate`, `doc_number_guard`, `product_doc_gate`,
    `usage_capture_gate` and `evidence_path_gate`, each consulted by ONE caller
    to choose warn-vs-refuse. This scope adds a sixth of the same shape (D11)
    rather than inventing a new switch vocabulary.
24. **The audit is clean at the start.**
    `env -u AAI_ROLE node .aai/scripts/docs-audit.mjs --check --strict
    --no-event` exits 0 with `### Verdict: CLEAN` in this worktree.

## Decisions

### D1 — The runner is `mutation-run.mjs`, and the record schema is a module

`.aai/scripts/mutation-run.mjs` (Node ESM, stdlib only), not `mutation-run.sh`.
Three reasons, in order of weight:

1. The record is WRITTEN by the runner and READ by the gate. A schema with two
   independent implementations is the seam that produces "the writer renamed a
   field and only one side knew" — the exact shape sweep 3 closed for the
   heartbeat slot (SPEC-0180 D13, S5). One module,
   `.aai/scripts/lib/mutation-record.mjs`, exports `formatRecord()` and
   `parseRecord()`; the runner and the gate both import it, and a test drives a
   real write through a real read.
2. The suites are bash-3.2-constrained (docs/TECHNOLOGY.md); the gates are
   Node. The runner is a gate-side tool that HAPPENS to invoke a bash suite, so
   it belongs on the gate side of that line.
3. Exit-code and `--help` discipline is already uniform across `.aai/scripts/*.mjs`.

The runner never interprets the suite's internals: it invokes the suite exactly
as a human would, through `bash .aai/scripts/aai-run-tests.sh`, inside the
isolated clone.

Prior art it deliberately mirrors: `.aai/scripts/tdd-evidence-check.mjs`
classifies a RED log as `product_red` or `infra_fail` on a one-line grammar, so
that a test which failed because the harness broke is not read as proof. D6's
third verdict is that same distinction on the mutation side, and the two tools
are siblings rather than rivals — one judges the RED, the other judges the
mutation that produced it.

### D2 — One record per Test Plan row, named for the row, never deleted

Path: `docs/ai/tdd/<spec-id>/mutation-<TEST-id>.txt`, where `<TEST-id>` is the
Test ID cell VERBATIM (`mutation-TEST-471.txt`). Keyed on the test, not on a
private mutation id, because the gate's unit of judgement is a Test Plan ROW:
one row, one record, no join table. The name is derivable from the table cell
with no transformation, so the gate never guesses. It keeps the `TEST-` prefix
because the newest merged convention does (SPEC-0180 stores
`green-TEST-025.txt`), and it diverges from SPEC-0179's bare-number
`mutation-445.txt` and from SPEC-0180's private `mutation-M7.txt`; both are
pre-change specs the gate degrades by name (D9), so nothing reads them.

Fixed header, `mutation_record: v1`, one `key: value` per line, then a `---`
separator and the captured tail of the run:

```
mutation_record: v1
spec_id: spec-mutation-gate-for-tests
test_id: TEST-471
suite: tests/skills/test-aai-mutation-gate.sh
selector: test_471_runner_isolation
target: .aai/scripts/mutation-run.mjs
mutation: sed:s/EXPECTED_TREE_MATCH/SKIP_TREE_MATCH/
base_commit: <40 hex>
tree_hash: <hex of the SOURCE working tree>
run_at_utc: <ISO 8601 seconds>
rc: 1
verdict: RED
first_fail: FAIL TEST-471 clone tree hash differs from source
---
<last 200 lines of the run>
```

Never deleted, never overwritten: when `mutation-<TEST-id>.txt` already exists,
the runner RENAMES it to `mutation-<TEST-id>.<run_at_utc>.txt` before writing
the new one. A STAYED GREEN result therefore cannot be made to disappear by
running again — it can only be joined by a later record, and the older one stays
readable beside it.

### D3 — The runner refuses an unknown test, and the property is proved for EVERY suite

Two halves of `fu-test-selector-unknown-id-passes`, both delivered:

- The runner resolves `--test <selector>` against the suite file's own function
  definitions (the same grammar `check-test-registration.mjs` uses,
  `/^(test_[A-Za-z0-9_]+)\(\)\s*\{/m`) BEFORE it clones anything. Unknown name:
  exit 2, nothing cloned, nothing written, the message naming the suite and the
  three nearest existing selectors.
- Every suite that accepts a positional selector refuses an unknown one with a
  non-zero exit. The follow-up names three suites; the measured population is
  FIFTEEN (measurement 11), and one of the three it names is already fixed. So
  the deliverable is not "fix three files": it is ONE corpus-level guard that
  drives EVERY `tests/skills/test-aai-*.sh` accepting a selector with the
  literal `no_such_test_xyz` and requires a non-zero exit, plus whatever
  per-suite edits that guard turns red. A count in a follow-up's prose is a
  sighting; the guard is the property.

Mechanism preference, decided but not forced on the implementer: if a helper
already sourced by every suite exists, the refusal belongs there once; otherwise
it is a one-line `declare -F "test_${t}" >/dev/null` membership test per suite in
the two idioms of measurement 11. The AC is written against the OUTCOME (the
corpus guard), so either mechanism satisfies it and the guard is what future
suites are held to.

The runner's own check is what makes the capability trustworthy — a runner that
inherited the fail-open would record `STAYED GREEN` for a test that never ran,
which is worse than no record at all. The corpus guard is what closes the
registry item at its source, for the twelve suites nobody had counted.

### D4 — Isolation is a clone of the WORKING TREE, proved by a hash, not asserted

The mutation must be applied to the tree the implementer is actually working in,
which during a TDD ride is DIRTY: the new test exists, the fix exists, neither
is committed. A clone of HEAD would mutate a tree that does not contain the code
under test and would produce a meaningless verdict. The runner therefore:

1. `git clone --local --no-hardlinks --shared=false <repo-root> <tmpdir>` and
   checks out the same commit;
2. applies `git diff HEAD` (tracked modifications) into the clone;
3. copies every path from `git ls-files --others --exclude-standard` (untracked,
   not ignored);
4. computes a tree hash over the clone and over the SOURCE working tree with the
   same function, and REFUSES (exit 3, nothing written) when they differ.

Step 4 is the whole point: "the clone reproduces my tree" is a claim, and an
unverified claim is what this ride exists to abolish. `docs/ai/tdd/**` and other
ignored runtime paths are excluded from both sides of the comparison by the same
exclusion list, so the evidence the runner is about to write cannot change its
own verdict.

The clone lives under `$TMPDIR`, never beside the repository, and is removed on
every exit path including the refusals.

### D5 — A mutation that changes nothing is a refusal, not a result

`--sed '<expr>' --target <path>` or `--patch <file>`. After applying, the runner
compares the target's bytes before and after INSIDE the clone. Identical: exit 2,
nothing recorded, the message naming the expression and the path. A `sed`
expression whose pattern no longer matches (a rename upstream, a typo) would
otherwise produce a perfect, false `STAYED GREEN` — a recorded lie about a test
that was never challenged. This is the single most likely way this tool could be
worse than nothing, so it is a refusal at the earliest possible point.

### D6 — Three verdicts, never two

The runner classifies the mutated run three ways and the gate reads all three:

- `RED` — non-zero rc AND the output carries at least one FAIL line naming the
  selected test. Only this counts as evidence.
- `STAYED GREEN` — rc 0. Recorded, exit non-zero (5).
- `INCONCLUSIVE` — non-zero rc with no FAIL line naming the selected test: the
  suite died for another reason (the `sed` broke the file's syntax, the fixture
  could not build). Recorded, exit non-zero (6).

A tool that reported INCONCLUSIVE as RED would hand out the strongest possible
evidence for the weakest possible run, which is the failure this ride is built
from. This is SPEC-0180 D8's rule ("alive", "nothing alive" and "I could not
tell" must never render as the same answer) applied to a second surface.

### D7 — The shipping tree is proved untouched, by a tripwire, on every path

The runner writes to exactly one place: `docs/ai/tdd/<spec-id>/`. The suite
asserts it, rather than the spec claiming it: before and after a full run
(RED path, STAYED GREEN path, and each refusal path of D3 and D5), the fixture
repository's `git status --porcelain` and a tree hash computed over everything
except `docs/ai/tdd/` are byte-identical. `fu-tripwire-attributes-concurrent-writes`
(open, P3) is the reason this is asserted in the runner's OWN fixture and not
inferred from a live sweep's tripwire: a shipping-tree tripwire misattributes a
concurrent writer, so it cannot be this claim's evidence.

**Amendment (remediation round 1):** the same before/after tree hash is now
ALSO the runner's OWN self-check, not only an assertion the fixture suite
makes from outside. A mismatch downgrades the run's verdict to
`INCONCLUSIVE` (D6) rather than recording it as RED or STAYED GREEN — see
"Remediation round 1" below.

**Amendment (remediation round 3, NB-5):** the tree hash `lib/tree-hash.mjs`
computes covers tracked files plus untracked-not-ignored files, so this
section's own claim ("byte-identical outside docs/ai/tdd afterwards") is
narrower than it reads — it is BLIND to every OTHER gitignored path. A named
`RUNTIME_ALLOWLIST` (`docs/ai/STATE.yaml`, `docs/ai/LOOP_TICKS.jsonl` — hashed
when present, a closed list, never a blanket "every gitignored path") closes
the one class that matters for this claim: the gitignored runtime paths this
repository's own ceremony writes while a suite runs. `buildIsolatedClone` now
also reproduces these paths in the clone (the same treatment as an ordinary
untracked file), so the allowlist changes what the tripwire can catch without
changing what the clone can reproduce. See "Remediation round 3" below and
TEST-497.

**Amendment (remediation round 4, NB-1):** the round-3 widening above had an
operational cost this section did not disclose: `RUNTIME_ALLOWLIST` paths are
exactly the two writes canon permits a dispatched role to make WHILE another
role's suite is running (`SUBAGENT_PROTOCOL.md`'s ENV row — `log-tick` and
`state.mjs` stay allowed under `AAI_ROLE=subagent`), so putting them inside
THIS before/after comparison made an ordinary concurrent ceremony write
downgrade a genuine RED verdict to INCONCLUSIVE. Fixed at cause: the
allowlist stays inside the D4 clone-fidelity comparison above (the clone
still MUST reproduce these paths, or that is a real fidelity gap) but is now
EXCLUDED from the D7 before/after comparison specifically —
`withoutRuntimeAllowlist` (mutation-run.mjs) strips the allowlist paths from
both the "before" and "after" file-hash maps before D7 hashes/diffs them, on
BOTH the normal-run self-check and `--replay`'s own copy of it. The LIMIT
this buys is named explicitly, not left implicit: a MUTATED run that itself
writes the source copy of an allowlist path from inside the suite is now
invisible to D7 too — the allowlist is reproduced into the clone, never
tripwired in the source, full stop (see mutation-run.mjs's own LIMITS
comment). A second, narrower window closes alongside this one:
`buildIsolatedClone`'s allowlist copy loop now hashes the BYTES IT ACTUALLY
COPIES into the clone (read once, written to the clone and hashed from the
same buffer) rather than trusting the earlier `computeTreeFileHashes(ROOT)`
snapshot for those paths — a concurrent ceremony write landing between that
early snapshot and the later copy could otherwise make the D4 clone-fidelity
comparison itself throw a spurious `TreeMismatchError` over a race, not a
real reproduction gap. See "Remediation round 4" below and TEST-497 (both
arms: `docs/ai/STATE.yaml` and `docs/ai/LOOP_TICKS.jsonl`).

**Amendment (remediation round 5, NB1-r6, validation round 6):** the SECOND
window named directly above ("hashes the bytes it actually copies … rather
than trusting the earlier snapshot") was, at round 4, a mutation-free
survivor — TEST-497's own two arms proved only the D7 exclusion, never the D4
second-window fix, and reverting the fix alone (deleting the
`sourceTreeFiles.set(rel, createHash('sha256').update(bytes).digest('hex'))`
line in `buildIsolatedClone`) left TEST-497 fully GREEN. Closed with a THIRD
arm: a rapid appender (~50ms interval) writes to the SOURCE
`docs/ai/STATE.yaml` for the WHOLE run (clone build through suite exit), not
only a single well-timed write — under the shipped code this still records
RED (exit 0), five times out of five; reverting the fix throws
`TreeMismatchError … changed: docs/ai/STATE.yaml` (exit 3) every time. See
"Remediation round 5" below and TEST-497 arm 3.

### D8 — The gate reads rows, and answers in three exit codes

`node .aai/scripts/mutation-gate.mjs --spec <path> [--json] [--list-degraded]`.
For each `## Test Plan` row of an applicable spec (D9) it requires ALL of:

- the Mutation cell is non-empty and is not a placeholder (`-`, `—`, `TBD`,
  `pending`);
- `docs/ai/tdd/<spec-id>/mutation-<TEST-id>.txt` exists and parses as
  `mutation_record: v1`;
- its `test_id` equals the row's Test ID and its `suite` equals the row's File
  path cell (a record copied from another row is caught here);
- `verdict: RED`;
- `base_commit` is an ancestor of HEAD (`git merge-base --is-ancestor`), so a
  record produced on an abandoned or rebased history is not evidence for the
  tree being closed;
- **(remediation round 5, D8 amendment, BLOCKING-1)** when the record carries
  an OPTIONAL `target_sha256`, the LIVE target's `sha256` still equals it —
  a record whose target changed (`STALE <id>: target <path> changed since
  the record — re-run mutation-run.mjs (or --replay) for this row`) or
  vanished (`STALE <id>: target <path> missing — …`, remediation round 6,
  NB3-r7) is OFFENDING even though the record itself still parses and still
  names `verdict: RED`; a record carrying no `target_sha256` at all
  (predating this field) is exempt from this ONE condition and counted
  instead in a named `unstamped=<n>` degrade (never blocking).

Exit codes: `0` every applicable row satisfied (degraded rows named, see D9);
`5` at least one row unsatisfied — EVERY offending row is printed with the
reason, including a STALE row (a record whose own target changed or vanished
since it was produced, remediation round 5/6), never just the first; `3` the
gate itself could not run (spec unreadable, Test Plan unparseable, `git`
unavailable); `2` usage. The three-way split is the same rule as D6.

**Amendment (remediation round 3, NB-7):** a row whose Status cell is a
TERMINAL-NOT-GREEN value (`deferred`, `dropped`, `rejected` — the vocabulary
the live corpus's own Test Plan Status columns already use) is EXEMPT from
the RED-record requirement above, named `EXEMPT <TEST-id>: status <value>` in
the gate's output — never silently skipped, and never counted toward
`degraded` (a different class: applicability, not disposition). Without this,
a ride that truthfully defers or drops a row (disclosed in an amendment) had
only two ways to satisfy the gate: fabricate a RED record, or delete the row.
Exemption is per-row: a spec with both exempt and satisfied rows reports the
satisfied count excluding the exempt ones. See "Remediation round 3" below
and TEST-498.

**Amendment (remediation round 4, NB-2):** the round-3 exemption above had a
fail-open edge this section did not name: a Test Plan whose EVERY row is
exempt satisfies `0 row(s) satisfied degraded=0` — vacuously PASS, exit 0,
indistinguishable in shape from an empty spec that has nothing to say at all.
Fixed at cause, two halves: (1) `exempt.length > 0 && satisfied === 0` is now
its own named DEGRADE class, `DEGRADED: every row exempt (n) degraded=n
exempt=n`, exit 0 unchanged but never printed as an ordinary PASS line; (2)
`close-work-item.mjs`'s `evaluateMutationGate` — D12's own close-time
consumer — previously `continue`d past EVERY exit-0 gate result without
reading a byte of its output, so even an ORDINARY `GATE PASS` carrying a
partial `exempt=n` was invisible at the close, not only the new all-exempt
case. It now captures the gate's `exempt=`/`degraded=` counts from the
summary line on every resolved spec doc and, when `exempt` is non-zero,
prints a WARNING naming them — under `mutation_gate: enforce` exactly as
under `report-only` (this is never a refusal: the gate did not fail). D9's
OWN degrade classes (`pre-change spec`, `evidence tree absent`) are
deliberately NOT surfaced this way — they carry `degraded=n` but never
`exempt=n`, and stay exactly as silent at the close as before this fix,
since an inapplicable/absent-evidence spec is a different, already-understood
class this finding was never about. See "Remediation round 4" below, TEST-498
(the gate side) and TEST-505 (the close side).

### D9 — Applicability is a marker, not a date

A spec is gated when its frontmatter carries `mutation_gate: v1` AND its
strategy is `tdd` or `hybrid` — read with `spec-lint.mjs`'s own precedence
(`:659-668`: an explicit `--strategy`, then frontmatter `strategy:`, then the
`- Strategy: <v>` body line), never a private parser. `spec-freeze.mjs` writes
the marker at freeze when the strategy is `tdd` or `hybrid` AND the Test Plan
carries a Mutation column.

Applicability is therefore read differently on the two sides of the freeze, and
deliberately so: BEFORE the freeze there is no marker to read, so
`spec-freeze.mjs` decides on the strategy alone and REFUSES (exit 3, nothing
written — its existing refusal shape) a `tdd`/`hybrid` spec whose Test Plan has
no Mutation column, by adding the new lint rule to its closed
`PRECONDITION_RULES` list (measurement 17). AFTER the freeze the marker is the
authority, because the strategy of a frozen spec can be amended and the gate
must not retro-apply to a document nobody stamped.

Rejected: anchoring on a date. A date mis-sorts precisely the documents that
matter — a spec planned before this change and frozen after it would be gated
against records nobody was told to produce, and a spec frozen before the cutoff
by a clock skew would be exempt for no reason a reader can see. The marker is
written by the tool that owns the freeze, is greppable, and says what it means.

Degrade, always BY NAME and never silently: a spec without the marker is
reported as `DEGRADED: pre-change spec (no mutation_gate marker)` and exits 0; a
missing evidence DIRECTORY (the CI and fresh-clone case, measurement 4) is
reported as `DEGRADED: evidence tree absent` for every row at once, in ONE line
carrying the count, and exits 0. `--list-degraded` prints the per-row detail —
174 frozen specs must not produce 174 lines on every run, or the output becomes
something people learn to scroll past. A degrade is never printed in the same
shape as a pass: the summary line always carries `degraded=<n>`. **Amendment
(remediation round 5/6, D8 amendment):** a `GATE PASS` or `GATE FAIL` summary
line (never a `DEGRADED` one — that class was never about per-record
staleness) also always carries `unstamped=<n>`, the count of records
predating the `target_sha256` field (D8's own sixth condition above).

### D10 — The amendment anchor is a frontmatter hash over a CONTRACT PROJECTION

CHANGE-0181's hard part, named in its own Constraints: the anchor must survive a
rebase and a squash merge. `frozen_sha256: <hex>` in the spec's frontmatter,
written by `spec-freeze.mjs` in the same atomic write that sets the body freeze
marker and `status: implementing`, does — it travels with the file's content, not
with history. A `spec_frozen` ledger record does not: `docs/ai/decisions.jsonl`
is append-only and union-merged, but a spec frozen on a branch has no ledger line
in the tree that the close gate runs in until the branch merges, which is one
tick too late.

The hash is NOT taken over the file. It is taken over a normalized CONTRACT
PROJECTION computed by `.aai/scripts/lib/spec-contract-hash.mjs`, imported by
both `spec-freeze.mjs` and `spec-amend.mjs` (one definition, D1's rule again):

- the frontmatter block is removed entirely (so `status: implementing`,
  `number`, `links.pr` and `frozen_sha256` itself never enter the hash — no
  self-reference, and the close flip is not an amendment);
- in the `## Acceptance Criteria Status` table, the Status, Evidence, Review-By
  and Notes cells are blanked, and in `## Test Plan` the Status cell is blanked
  (these are the ride's own bookkeeping, written by canon on every TDD cycle);
- the Spec-AC Description cells, the Test Plan Description, File path, Spec-AC
  and Mutation cells, and every prose section are kept VERBATIM;
- trailing whitespace and trailing newlines are normalized.

That projection is exactly the set of bytes an amendment changes. The measured
incident (SPEC-0171, CHANGE-0181 lines 22-31) rewrote Spec-AC-01..03 in their
Description cells — inside the projection, caught. A status flip from `planned`
to `done` with an evidence path — outside it, not an amendment, not a refusal.
Blanking the whole AC table, the obvious cheap alternative, would have been
blind to the one incident on record.

Rejected explicitly: reusing `specContentHash` (`lib/docs-model.mjs:791-809`),
which already exists and already hashes a spec. Measured (measurement 15), it
hashes the AC/test SKELETON — ids, statuses, and each test row's Spec-AC, type
and file cells — INCLUDING every AC status and EXCLUDING every Description cell
and all prose. Against the one incident on record it is inverted on both axes:
it would have missed the rewritten AC text entirely, and it would have fired on
every ordinary `planned` to `done` flip. It stays untouched and keeps its own
consumers; this is a second, differently-shaped hash with a different job, and
the two are named apart so nobody later "unifies" them.

### D11 — The strict gate judges the hash; the refusal prints the line that clears it

`spec-amend.mjs list --strict` today judges RECORDS: it buckets every
`spec_amendment` line and refuses the two buckets in `STRICT_VIOLATION_BUCKETS`
(measurement 16). It gains a SECOND, spec-keyed violation list — one check per
frozen spec in `docs/specs/`: recompute the projection hash and compare it with
`frozen_sha256`. The two lists share the existing output shape (a
`STRICT-VIOLATION <class> …` line on stdout, a runnable remedy per violation on
stderr, `exit(1)`), so the close ceremony's existing reading of exit 1 is
unchanged. On a mismatch with no `spec_amendment` record for that spec: exit 1,
print `STRICT-VIOLATION undisclosed-amendment spec=<spec_id> path=<path>`, and
print the runnable remediation verbatim —

```
node .aai/scripts/spec-amend.mjs add --spec <path> --ref <ride-ref> \
  --what "<one line>" --why "<one line>" --signoff none
```

and `add` RE-STAMPS `frozen_sha256` to the current projection in the same call
that appends the record and files the `fu-amend-…` obligation. That is what
makes the printed line actually clear the refusal, and it is what keeps the
gate live for the SECOND undisclosed edit — a one-shot "a record exists, so
nothing is checked any more" would re-open the hole after the first honest
amendment. `--signoff owner` is unchanged; nothing here adds pressure to sign
(CHANGE-0181 AC-003).

Degrade by name: a frozen spec with no `frozen_sha256` (all 174 today,
measurement 5) is listed as `degraded: no freeze anchor` and never turns the
gate red. Honesty, stated once: a `frozen_sha256` can be hand-rewritten by
anyone who can edit the spec, exactly as `AAI_ROLE` can be unset. This is a
guardrail against the honest omission — the incident on record — not a security
boundary.

### D12 — The close ceremony runs the gate, and the dial is the sixth of its kind

The gate is wired into `.aai/scripts/close-work-item.mjs`, not into
`.aai/SKILL_PR.prompt.md` step 4a. Operator-contract rule 5: a rule that must
hold wherever AAI is installed is a guard, not a note — a prompt instruction
reaches the orchestrator that reads it, while the script reaches every project
that vendored it and every close that does not go through the PR skill. It also
costs zero corpus bytes, which the prose wiring (D13) needs.

Behaviour: for a closing ride whose spec is applicable (D9), run the gate; on a
non-zero exit, refuse the close with a NEW exit code 8 (3, 4 and 5 are the three
existing dialed gates, 6 is the STATE-reconcile PARTIAL and 7 is the HEAD pin —
measurement 18) and name the offending rows. It takes the same position as its
three siblings: after the evidence-path gate, skipped under `--dry-run` and
reported informationally there, returning the same
`{ severity: 'none' or 'warn' or 'refuse', reason }` shape, so it is a fourth
member of a pattern rather than a new one. The switch is a new
`mutation_gate: enforce or report-only` key in `docs/ai/docs-audit.yaml` plus
its name in the closed `GUARD_DIALS` list at `lib/guard-config.mjs:40`: absent,
invalid or `report-only` means WARN loudly and continue; AAI core ships
`enforce`, because this repository is the one making the claim. A non-TDD ride
and a pre-change spec are untouched on either setting.

The cost this decision accepts: `close-work-item.mjs` is pinned by one sha256
over the whole file in `tests/skills/lib/close-work-item-pin.sh:37-48`, so the
edit reddens the two suites that assert it — `tests/skills/test-aai-follow-ups.sh`
(TEST-008 and test_010) and `tests/skills/test-aai-doc-numbering.sh` (TEST-029)
— until a new itemized entry is appended, in the same commit as the edit,
re-affirming both frozen invariants (the procedure at `:22-29`). The re-pin is
therefore the LAST implementation step, and it is the same edit that fixes
`fu-closeworkitem-pin-tail-wording` — the pin entry's own prose currently claims
the STATE reconcile runs strictly after the try/catch, which is false on the
D6.2 idempotency short-circuit. A pin is a signed statement about a file;
re-cutting it while correcting a false sentence inside it is one action, not two.

### D13 — Canon gains three sentences and one command, and the ledger is trued up exactly

- `.aai/SKILL_TDD.prompt.md` Phase 2 (GREEN), step 3 "Capture GREEN Evidence"
  and the `**BLOCK:**` line at :179: GREEN is not complete until the test has
  been reddened by a named mutation, with the `mutation-run.mjs` command line.
- `.aai/VALIDATION.prompt.md` step 5g (the anti-tautology RED-proof check,
  :196-208 — the semantic sibling, so the rule lands where a reader already
  looks): re-run every mutation record for the scope with ONE command and treat
  any record that no longer reddens as BLOCKING.
- `.aai/ROLE_COMMON.md`: one line in the evidence rules naming the record path
  shape, so a role that stores evidence elsewhere is wrong by canon.
- `.aai/SKILL_PR.prompt.md:188-190`: the AMENDMENT GATE bullet says exit 1
  "PRINTS one runnable `spec-amend.mjs classify` line per offending record".
  D11 adds a violation class whose remedy is an `add` line for a SPEC, so that
  sentence becomes false on the day this ships. It is corrected in place (a
  handful of bytes), not left to be read as a promise the tool stops keeping.

Budget: these are corpus files (measurement 9). The plan is a measured true-up,
not a diet: after the prose lands, measure the growth N with
`prompt-diet-ledger.sh`'s own arithmetic, append ONE
`JUSTIFIED_ADDITIONS+=( "<N> mutation-gate-for-tests …" )` entry, and move
`want_growth` at `tests/skills/test-aai-prompt-diet.sh:812` from 31803 to
31803+N. Headroom then returns to 2046 (measurement 8), which is what the cap
requires — a credit larger than the measured growth fails on the cap side, a
credit smaller fails on the floor side, so the number is measured and not
estimated. Target N is under 800 B (three sentences and two command lines); the
uncredited ceiling is 2046 B, so the ride cannot be blocked by the cap, and no
diet of another prompt is needed. If the prose lands above 2046 B uncredited at
any intermediate commit, the ledger entry is what fixes it — not a deletion
somewhere else.

`.aai/SUBAGENT_PROTOCOL.md`, `.aai/templates/SPEC_TEMPLATE.md` and
`.aai/system/PROFILES.yaml` are outside the measured corpus, so the Test Plan
column's documentation lands in the TEMPLATE at no ledger cost.

### D14 — Validation's re-run is a command, not a reading exercise

`mutation-run.mjs --replay --spec <path>` re-applies every recorded mutation for
that spec, in a fresh clone each time, and exits non-zero naming every record
whose test no longer goes RED. Validation cites one command; the prompt costs
one sentence instead of a paragraph; and the claim "the validator re-ran every
mutation" becomes an artefact with an exit code instead of a sentence in a
report. A replay that cannot find the recorded target file (the code moved)
reports `INCONCLUSIVE` per D6 and is non-zero — a moved target invalidates the
evidence, and silence about it is the failure mode.

**Amendment (remediation round 1):** a `--patch` record's mutation content is
stored beside its `.txt` record under the evidence directory (never a `/tmp`
path), so the record is self-contained. `--replay`'s exit contract gains a
fourth path: `1` when at least one record replayed cleanly but is a genuine
regression, `4` when the only problem is one or more records that could not
even be APPLIED (a missing/stale patch, a `git apply` error — caught and
printed as `INCONCLUSIVE <TEST-id>: could not apply the recorded mutation
(...)`, never an uncaught stack trace), `0` only when every record was
attempted and still reddens.

### D15 — The Test Plan gains a seventh column, and the reader accepts six

`parseTestPlanTable` is positional today and reads only cells 0-3 (measurement
14), so a `Mutation` column APPENDED at the end is invisible rather than
breaking — back-compat across the 179 six-column specs is free, and it is also
why the reader cannot stay as it is: the gate needs that cell. The reader
therefore parses the HEADER row and resolves columns BY NAME, keeps
`testId`/`acCell`/`typeCell`/`fileCell` byte-identical for a six-column table
(the existing four consumers, `specContentHash` included, must not move), and
adds `descriptionCell`, `statusCell`, `mutationCell` and the raw `header` array.
Resolving by name is not cosmetic: measurement 14 shows that a column inserted
anywhere before index 4 today shifts three cells silently, and this ride is the
one adding a column.

`spec-lint.mjs` gains two findings, raised ONLY for an applicable spec (D9) and
attached to the existing Test Plan walk at `:547-561`, which already carries
`row.line`: `mutation-cell-missing` (no Mutation column, or an empty cell) and
`mutation-cell-malformed` (a placeholder such as `-`, `TBD` or `pending`, or a
cell naming no target). `mutation-cell-missing` also joins
`spec-freeze.mjs`'s `PRECONDITION_RULES` (D9), which is what stops a `tdd` spec
freezing without the column. Terminal specs (`done`, `deferred`, `rejected`,
`superseded`) and specs without the marker are exempt, and the lint names which
exemption it applied. `.aai/templates/SPEC_TEMPLATE.md` gains the column and the
marker.

The hand-written `## Mutation checks` section that five merged specs
(SPEC-0176 through SPEC-0180) carry is NOT promoted to the template and is NOT
read by the gate. The column is the authoritative, machine-read statement — one
row, one mutation, one record — and a prose section beside it would be a second
place to say the same thing, which is how the two incompatible record
conventions of measurement 3 came about. A spec may still keep such a section
for narrative; nothing reads it.

### D16 — The unsigned-tracked bucket requires an OPEN tracker

`fu-spec-amend-terminal-tracker-counts` (P2, open) measures the defect in the
very gate D11 extends: `spec-amend.mjs` computes `closed` at :313 and then
buckets on `trackedItem !== null` at :342, so a DROPPED tracker satisfies the
strict gate forever. The tracker must be OPEN for the record to count as
tracked; a terminal tracker makes the record `unsigned-untracked`, which is what
the strict gate already refuses. Fixed here because this ride is the one
rewriting that function, and leaving a fail-open inside the gate that this ride
exists to strengthen would be the joke version of the capability.

### D17 — Registration and classification, measured not assumed

`tests/skills/test-aai-mutation-gate.sh` is a NEW suite. Three things follow,
all measured (measurement 20), none optional: a `  aai-mutation-gate:` row in
`tests/skills/suite-map.yaml` at the parser's exact indentation, with globs
covering the four new scripts and the surfaces this scope edits; the row-count
pin at `tests/skills/test-aai-hygiene-pack.sh:1096-1099` moved from `94` to
`95`; and every `test_*()` it defines referenced by its `main()` so
`check-test-registration.mjs` does not report an orphan.

The four new `.aai/**` files (`mutation-run.mjs`, `mutation-gate.mjs`,
`lib/mutation-record.mjs`, `lib/spec-contract-hash.mjs`) go in PROFILES.yaml's
`core:` list beside their siblings `spec-freeze.mjs`, `spec-lint.mjs`,
`spec-amend.mjs`, `close-work-item.mjs` and `tdd-evidence-check.mjs` — they are
gates, which is the classification rule's own word for core.

These are the two closed-list companion obligations of
`.aai/PLANNING.prompt.md`, and both are Test Plan rows, not prose.

### D18 — What this scope does not do

- No retro-fitting of records to sweeps 1-3. Their validators re-ran their
  mutations; D9's marker degrade is what makes that honest instead of silent.
- No coverage scoring. One mutation per Test Plan row is the bar. A percentage
  invites optimizing the percentage.
- No PowerShell suites. Pester has its own idiom and its own runner; filed as
  `fu-mutation-gate-skips-pester` (P3) in the same ride, so the gap is a
  registry item rather than a sentence in a spec nobody re-reads.

## Constitution deviations

None. (`docs/CONSTITUTION.md` was read at planning; this scope adds a gate and
its evidence, changes no article, and takes no exception.)

## Acceptance Criteria Mapping

- Intake AC-001 -> Spec-AC-01, Spec-AC-02, Spec-AC-03.
- Intake AC-002 -> Spec-AC-04.
- Intake AC-003 -> Spec-AC-05, Spec-AC-06.
- Intake AC-004 -> Spec-AC-07.
- Intake AC-005 -> Spec-AC-08, Spec-AC-09.
- Intake AC-006 -> Spec-AC-10, Spec-AC-11.
- Intake AC-007 (CHANGE-0181) -> Spec-AC-12, Spec-AC-13, Spec-AC-14,
  Spec-AC-17.
- Intake AC-008 -> Spec-AC-16 and the `## Verification` gate run.
- Intake AC-009 -> `## Registry items closed by this scope` and
  `## Registry items rejected by this scope`, each id named with the Spec-AC
  that closes it or the reason it is not closed; verified mechanically by
  `follow-ups.mjs verify-closures` at the close.
- CHANGE-0181 AC-001 -> Spec-AC-12. AC-002 -> Spec-AC-12 (the printed line, run
  verbatim). AC-003 -> Spec-AC-13. AC-004 -> Spec-AC-13. AC-005 -> Spec-AC-14.
- Spec-AC-15, Spec-AC-18 and Spec-AC-19 carry no intake id: the first is the
  `fu-spec-amend-terminal-tracker-counts` fail-open found in the gate this ride
  rewrites, the second is the Planning companion-obligations check, and the
  third is the hash-pin obligation that Spec-AC-07's edit creates
  (`fu-closeworkitem-pin-tail-wording` rides with it).

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN mutation-run.mjs is given a spec id, a suite, a selector, a target and a mutation, it SHALL build an isolated clone whose tree hash equals the SOURCE working tree's, apply the mutation only inside that clone, run only the selected test, and write docs/ai/tdd/<spec-id>/mutation-<TEST-id>.txt carrying every field of the v1 header; and the source repository SHALL be byte-identical outside docs/ai/tdd afterwards. | done | e646f850; TEST-471, TEST-497, TEST-499 green with RED mutation records (gate 43/43, replay 43/43); validation-round8.txt (rounds 1-8), review rounds 1-2 PASS | — | TEST-471 |
| Spec-AC-02 | WHEN --test names a selector the suite does not define, or the mutation leaves the target file byte-identical inside the clone, the runner SHALL exit 2, write no record, create no clone that outlives the call, and name the cause. | done | e646f850; TEST-472 green with RED mutation records (gate 43/43, replay 43/43); validation-round8.txt (rounds 1-8), review rounds 1-2 PASS | — | TEST-472 |
| Spec-AC-03 | WHEN any tests/skills/test-aai-*.sh suite that accepts a positional selector is invoked with a selector no function of that suite defines, the suite SHALL exit non-zero naming the unknown selector; a defined selector SHALL still run exactly that one test and exit 0; and a corpus guard SHALL assert this for every such suite, so the count is measured on every run rather than copied from a follow-up. | done | e646f850; TEST-473, TEST-491, TEST-493, TEST-503, TEST-504 green with RED mutation records (gate 43/43, replay 43/43); validation-round8.txt (rounds 1-8), review rounds 1-2 PASS | — | TEST-473 |
| Spec-AC-04 | WHEN the mutated run exits 0 the record SHALL carry verdict STAYED GREEN and the runner SHALL exit 5; WHEN it exits non-zero with no FAIL line naming the selected test the record SHALL carry verdict INCONCLUSIVE and the runner SHALL exit 6; and WHEN a record for that TEST-id already exists the previous file SHALL still be readable under its run-stamped name afterwards. | done | e646f850; TEST-474, TEST-500, TEST-502 green with RED mutation records (gate 43/43, replay 43/43); validation-round8.txt (rounds 1-8), review rounds 1-2 PASS | — | TEST-474 |
| Spec-AC-05 | WHEN mutation-gate.mjs runs against an applicable spec, it SHALL exit 5 and print one line per offending Test Plan row for each of an empty Mutation cell, a missing record, a record whose verdict is not RED, a record whose test_id or suite disagrees with the row, and a record whose base_commit is not an ancestor of HEAD; and it SHALL exit 0 when every row is satisfied. | done | e646f850; TEST-475, TEST-498, TEST-506, TEST-507, TEST-509, TEST-510 green with RED mutation records (gate 43/43, replay 43/43); validation-round8.txt (rounds 1-8), review rounds 1-2 PASS | — | TEST-475 |
| Spec-AC-06 | WHEN the spec carries no mutation_gate marker, or its strategy is not tdd or hybrid, or the evidence directory is absent, the gate SHALL exit 0 with a summary line carrying degraded=<n> and naming the degrade class, printing per-row detail only under --list-degraded; and WHEN the gate itself cannot run it SHALL exit 3, never 0 and never 5. | done | e646f850; TEST-476 green with RED mutation records (gate 43/43, replay 43/43); validation-round8.txt (rounds 1-8), review rounds 1-2 PASS | — | TEST-476 |
| Spec-AC-07 | WHEN close-work-item.mjs closes a ride whose spec is applicable and whose gate exits non-zero, the close SHALL be refused naming the offending rows under mutation_gate enforce and SHALL warn and continue under report-only or an absent key; a non-TDD ride and a pre-change spec SHALL close exactly as today under both settings. | done | 86c6db59; TEST-477, TEST-505, TEST-511, TEST-512 green with RED mutation records (gate 43/43, replay 43/43); validation-round8.txt (rounds 1-8), review rounds 1-2 PASS | — | TEST-477 |
| Spec-AC-08 | WHEN spec-lint.mjs reads an applicable spec whose Test Plan has no Mutation column, an empty Mutation cell, or a placeholder cell, it SHALL report mutation-cell-missing or mutation-cell-malformed naming the row and exit 1; a terminal spec and a spec without the marker SHALL be exempt and the applied exemption SHALL be named in the output. | done | e646f850; TEST-478 green with RED mutation records (gate 43/43, replay 43/43); validation-round8.txt (rounds 1-8), review rounds 1-2 PASS | — | TEST-478 |
| Spec-AC-09 | The Test Plan reader in lib/docs-model.mjs SHALL resolve columns by header name, SHALL parse a six-column and a seven-column table into the same row shape, and a spec-lint run over the live docs/specs corpus SHALL report zero findings attributable to the new column. | done | e646f850; TEST-479, TEST-494 green with RED mutation records (gate 43/43, replay 43/43); validation-round8.txt (rounds 1-8), review rounds 1-2 PASS | — | TEST-479 |
| Spec-AC-10 | .aai/SKILL_TDD.prompt.md GREEN, .aai/VALIDATION.prompt.md step 5g and .aai/ROLE_COMMON.md SHALL each name the mutation obligation and the runnable command; and the prompt-diet ledger SHALL carry one JUSTIFIED_ADDITIONS entry equal to the measured corpus growth with the TEST-012 checkpoint moved by the same number, so headroom returns to 2046. | done | e646f850; TEST-012, TEST-480 green with RED mutation records (gate 43/43, replay 43/43); validation-round8.txt (rounds 1-8), review rounds 1-2 PASS | — | TEST-480, TEST-012 |
| Spec-AC-11 | WHEN mutation-run.mjs --replay --spec <path> runs, it SHALL re-apply every recorded mutation of that spec in a fresh clone, SHALL exit non-zero naming every record whose test no longer goes RED or whose target no longer exists, and SHALL exit 0 only when every record still reddens. | done | e646f850; TEST-481, TEST-492, TEST-496, TEST-501, TEST-508 green with RED mutation records (gate 43/43, replay 43/43); validation-round8.txt (rounds 1-8), review rounds 1-2 PASS | — | TEST-481 |
| Spec-AC-12 | WHEN a spec frozen by spec-freeze.mjs is edited inside the contract projection with no spec_amendment record, spec-amend.mjs list --strict SHALL exit non-zero naming that spec and printing the spec-amend add line; and that printed line, run verbatim, SHALL append the record, re-stamp frozen_sha256, and make the next strict run exit 0. | done | e646f850; TEST-482 green with RED mutation records (gate 43/43, replay 43/43); validation-round8.txt (rounds 1-8), review rounds 1-2 PASS | — | TEST-482 |
| Spec-AC-13 | WHEN a frozen spec is edited AND a matching spec_amendment record exists, the strict gate SHALL pass whether the record is signed or unsigned-tracked; and editing a non-frozen spec, a non-spec document, or only the Status, Evidence, Review-By or Notes cells of a frozen spec SHALL change the gate's output not at all. | done | e646f850; TEST-483 green with RED mutation records (gate 43/43, replay 43/43); validation-round8.txt (rounds 1-8), review rounds 1-2 PASS | — | TEST-483 |
| Spec-AC-14 | WHEN a frozen spec carries no frozen_sha256, the strict gate SHALL list it as degraded by name and SHALL NOT turn red for it; and the gate run against this repository SHALL exit 0 while naming the count of degraded specs. | done | e646f850; TEST-484, TEST-495 green with RED mutation records (gate 43/43, replay 43/43); validation-round8.txt (rounds 1-8), review rounds 1-2 PASS | — | TEST-484 |
| Spec-AC-15 | WHEN a spec_amendment record's tracked_by item exists but is closed or dropped, spec-amend.mjs list --strict SHALL classify the record as unsigned-untracked and refuse; only an OPEN tracker SHALL satisfy the unsigned-tracked bucket. | done | e646f850; TEST-485 green with RED mutation records (gate 43/43, replay 43/43); validation-round8.txt (rounds 1-8), review rounds 1-2 PASS | — | TEST-485 |
| Spec-AC-16 | Every Test Plan row of THIS spec SHALL carry a Mutation cell and a RED record produced by mutation-run.mjs, and mutation-gate.mjs against this spec SHALL exit 0 with degraded=0 before the close ceremony runs. | done | e646f850; TEST-486 green with RED mutation records (gate 43/43, replay 43/43); validation-round8.txt (rounds 1-8), review rounds 1-2 PASS | — | TEST-486 |
| Spec-AC-17 | WHEN spec-freeze.mjs freezes a spec it SHALL write SPEC-FROZEN true, status implementing, frozen_sha256 and, for a tdd or hybrid spec whose Test Plan carries a Mutation column, mutation_gate v1, in ONE atomic write, and SHALL leave the file unchanged when any precondition refuses. | done | e646f850; TEST-489 green with RED mutation records (gate 43/43, replay 43/43); validation-round8.txt (rounds 1-8), review rounds 1-2 PASS | — | TEST-489 |
| Spec-AC-18 | tests/skills/test-aai-mutation-gate.sh SHALL carry a suite-map.yaml row at the parser's exact indentation with the suite-map row-count pin moved from 94 to 95 and check-test-registration.mjs exiting 0 over the live tree, and .aai/system/PROFILES.yaml SHALL classify all four new .aai files so the layer-profiles union check passes. | done | e646f850; TEST-487, TEST-488 green with RED mutation records (gate 43/43, replay 43/43); validation-round8.txt (rounds 1-8), review rounds 1-2 PASS | — | TEST-487, TEST-488 |
| Spec-AC-19 | WHEN close-work-item.mjs is edited for Spec-AC-07, tests/skills/lib/close-work-item-pin.sh SHALL carry a new itemized allowlist entry for the new sha256 re-affirming both frozen invariants, added in the same commit as the edit, and the entry's prose SHALL NOT claim the STATE reconcile runs strictly after the try or catch block, which is false on the idempotency short-circuit. | done | e646f850; TEST-490 green with RED mutation records (gate 43/43, replay 43/43); validation-round8.txt (rounds 1-8), review rounds 1-2 PASS | — | TEST-490 |

## Implementation plan

Components, in the order the seams make safest:

1. `lib/mutation-record.mjs` — the schema, written first because both consumers
   import it and every later test drives a real write through a real read.
2. `mutation-run.mjs` — D3's refusals before D4's clone before D5's no-op check
   before D6's classification. The refusals land first so no intermediate commit
   can write a record the tool cannot justify.
3. `mutation-gate.mjs` — D8 and D9, over hand-built record fixtures, so the gate
   is proved against a malformed record before the runner ever feeds it one.
4. `lib/docs-model.mjs` + `spec-lint.mjs` — D15. Back-compat (Spec-AC-09) is the
   first test of this step, not the last.
5. The three suites' positional selectors — D3's second half.
6. `lib/spec-contract-hash.mjs`, then `spec-freeze.mjs`, then `spec-amend.mjs` —
   D10, D11, D16. The hash module lands before either writer.
7. THIS spec is stamped: once step 6 exists, `spec-freeze.mjs` re-stamps
   `frozen_sha256` for `SPEC-0181-spec-mutation-gate-for-tests.md`, which is
   the moment CHANGE-0181's gate starts watching this ride's own spec. Every
   later edit to this document's contract projection needs a `spec-amend add`
   record, by the mechanism this ride is delivering.
8. Prose: `SKILL_TDD.prompt.md`, `VALIDATION.prompt.md`, `ROLE_COMMON.md`,
   `templates/SPEC_TEMPLATE.md` — D13, D15.
9. Companion obligations, because they MEASURE what steps 1-8 added:
   `PROFILES.yaml`, `suite-map.yaml`, and the diet-ledger true-up with the
   TEST-012 re-sum.
10. `close-work-item.mjs` + the `mutation_gate` dial in `docs-audit.yaml` — D12.
11. LAST, alone, and in the SAME commit as step 10's edit (the pin library's own
    procedure requires it, `close-work-item-pin.sh:22-29`): append the new
    itemized allowlist entry and correct the pin entry's tail wording —
    Spec-AC-19. A pin is a signed statement about a file; it is re-signed only
    when that file has stopped changing (`close-work-item hash pin`, LEARNED.md),
    so every other defect in `close-work-item.mjs` this ride might notice is
    batched into step 10 or left alone.

Data flows: `mutation-run.mjs` writes records that `mutation-gate.mjs` reads and
that `mutation-run.mjs --replay` re-executes; `spec-freeze.mjs` writes a
frontmatter field that `spec-amend.mjs` reads and re-stamps; `docs-model.mjs`
parses the Test Plan for `spec-lint.mjs` AND for `mutation-gate.mjs`;
`close-work-item.mjs` consumes the gate's exit code. Each crossing has a seam row.

Edge cases carried explicitly: a spec whose Test Plan lists the same TEST id
twice (the gate REFUSES the ambiguity rather than reading one record for two
rows); a record written before a rebase; an evidence directory present but
empty; a suite file whose selector exists twice; a `sed` expression containing a
character the shell would re-interpret (the runner passes it as an argv element,
never through a shell); a spec frozen with the marker whose strategy is later
amended to `direct` (the strategy is read at gate time, not at freeze time).

## Test Plan

Test ids continue the reserved `TEST-4xx` band, whose highest live id is TEST-470
(measurement 10); the two per-suite exceptions are TEST-012 in
`tests/skills/test-aai-prompt-diet.sh` (the existing ledger checkpoint, reused
rather than renumbered) and the new rows in `test-aai-spec-tools.sh`, which are
allocated from the same 4xx band because that suite's own sequence (ending at
TEST-024) collides with three other suites' sequences.

Every row names the mutation that MUST redden it (D2, Spec-AC-16): the record
`docs/ai/tdd/spec-mutation-gate-for-tests/mutation-<TEST-id>.txt` is the
evidence, produced by `mutation-run.mjs` itself.

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Mutation | Status |
|----------|------------|------|----------------------|-------------|----------|--------|
| TEST-471 | Spec-AC-01 | integration | tests/skills/test-aai-mutation-gate.sh | Runner isolation and record shape — a fixture repository with a dirty tracked file and an untracked file is driven through a full RED run; the clone's tree hash equals the source's, every v1 header field is present and correct (spec_id, test_id, suite, selector, target, mutation, base_commit, tree_hash, run_at_utc, rc, verdict, first_fail), the record lands under docs/ai/tdd/<spec-id>/, and the fixture's git status plus a tree hash excluding docs/ai/tdd are byte-identical before and after. | Append a byte to the SOURCE tree's copy of --target after the clone write (fs.appendFileSync(path.join(ROOT, targetRel), " ")) — a runner that writes into the shipping tree must redden both the runner's own D7 self-check and this row's tree-hash assertion. | green |
| TEST-472 | Spec-AC-02 | integration | tests/skills/test-aai-mutation-gate.sh | Runner refusals — an unknown selector exits 2, names the suite and writes no file and leaves no clone directory; a sed expression matching nothing exits 2 naming the expression and the target; both refusal paths leave the fixture tree byte-identical. | Replace the selector existence check with a constant true, so an unknown selector proceeds to a run. | green |
| TEST-473 | Spec-AC-03 | integration | tests/skills/test-aai-hygiene-pack.sh | Selector fails closed, corpus-wide — every tests/skills/test-aai-*.sh that accepts a positional selector is enumerated from the tree and invoked with the literal no_such_test_xyz; each must exit non-zero naming it; three of them (one per idiom plus the already-fixed one) are then invoked with a selector they really define and must exit 0 having run exactly that test. | Restore the bare positional dispatch (run the argument with no membership test) in one suite; the corpus arm must redden naming exactly that suite, proving the guard enumerates rather than sampling. | green |
| TEST-474 | Spec-AC-04 | integration | tests/skills/test-aai-mutation-gate.sh | Three verdicts and no deletion — a mutation the test cannot see records STAYED GREEN and exits 5; a mutation that breaks the target's syntax records INCONCLUSIVE and exits 6; a second run over an existing record leaves the first file present under its run-stamped name with its original bytes. | Collapse the INCONCLUSIVE branch into RED (classify on rc alone), so a suite that died for another reason is recorded as proof. | green |
| TEST-475 | Spec-AC-05 | integration | tests/skills/test-aai-mutation-gate.sh | Gate refusals — five fixture specs, each with one defective row (empty Mutation cell, absent record, verdict STAYED GREEN, record whose test_id names another row, base_commit on an orphan commit), each exit 5 with that row named; a fixture with two defective rows names BOTH; an all-satisfied fixture exits 0. | Make the gate return after the first offending row instead of collecting them all; the two-defective-rows arm must redden while the single-row arms stay green. | green |
| TEST-476 | Spec-AC-06 | integration | tests/skills/test-aai-mutation-gate.sh | Degrade and could-not-run — a spec without the marker, a spec whose strategy is direct, and an applicable spec whose evidence directory does not exist each exit 0 with a summary line carrying degraded and the class; --list-degraded prints per-row detail and the default run does not; an unreadable spec exits 3 and a tree with no git exits 3. | Make the absent-evidence-directory case exit 0 with degraded=0 and no class named, the silent-pass shape the whole ride exists to refuse. | green |
| TEST-477 | Spec-AC-07 | integration | tests/skills/test-aai-close-work-item.sh | Close wiring — a fixture ride whose spec is applicable and whose gate exits 5 is refused by close-work-item.mjs under mutation_gate enforce, naming the rows, with the doc statuses unflipped; the same fixture under report-only warns on stderr and closes; a fixture whose spec has no marker closes identically under both settings; an absent key behaves as report-only. Amendment (remediation round 4): arm E (an all-exempt spec) is recorded as its own row, TEST-505, sharing this same test function. | Invert the dial default so an absent mutation_gate key means enforce; the absent-key arm must redden, proving the fail-open default is asserted rather than assumed. | green |
| TEST-478 | Spec-AC-08 | integration | tests/skills/test-aai-spec-lint.sh | Mutation cell lint — an applicable fixture spec with a missing column, an empty cell and a placeholder cell each produce the named finding and exit 1; a terminal fixture spec and an unmarked fixture spec each exit 0 with the applied exemption named in the output. | Drop the terminal-status exemption, so a done spec is linted; the exemption arms must redden while the finding arms stay green. | green |
| TEST-479 | Spec-AC-09 | integration | tests/skills/test-aai-spec-lint.sh | Column back-compat — a six-column and a seven-column fixture table parse into the same row shape with the same Spec-AC and file-path values; a table whose columns are reordered still resolves by header name; and a spec-lint run over the live docs/specs corpus reports zero findings mentioning the Mutation column. | Restore positional column indexing in the Test Plan reader; the reordered-header arm and the six-column arm must redden. | green |
| TEST-480 | Spec-AC-10 | unit | tests/skills/test-aai-mutation-gate.sh | Canon carries the rule — .aai/SKILL_TDD.prompt.md GREEN, .aai/VALIDATION.prompt.md step 5g and .aai/ROLE_COMMON.md each contain the mutation obligation AND a runnable mutation-run.mjs command line; the command lines named there are asserted to parse as valid invocations of the delivered CLI rather than merely to exist as text. | Change the command line in one prompt to a flag the CLI does not accept; the parse arm must redden while the presence arm stays green. | green |
| TEST-481 | Spec-AC-11 | integration | tests/skills/test-aai-mutation-gate.sh | Replay — a spec with two RED records replays to exit 0; with the code under test fixed so one mutation no longer reddens, replay exits non-zero naming that record; with a record whose target file has been deleted, replay reports INCONCLUSIVE for it and exits non-zero. Amendment (remediation round 2, NB2-r2): a fifth arm simulates a CONCURRENT EDITOR of the source tree (a background write to a tracked file while replay runs a deliberately slow selector) — replay must report it INCONCLUSIVE (exit 4), naming the changed path, never as a genuine regression (exit 1). | Make --replay skip a record whose target is missing instead of reporting it; the deleted-target arm must redden. Round-2 mutation: in the D7-trip branch of replay(), route the concurrent-editor case back into the `failures` counter instead of `inconclusive` (`inconclusive++; // NB2-r2 D7 trip during replay is inconclusive, not a regression` -> `failures++; // NB2-r2 ...`); arm 5 must redden (exit 1 instead of the expected 4). | green |
| TEST-482 | Spec-AC-12 | integration | tests/skills/test-aai-spec-amend.sh | Undisclosed amendment is caught — a fixture spec is frozen by the real spec-freeze.mjs, a Spec-AC Description cell is then edited with no record, and list --strict exits non-zero naming the spec and printing the add line; that line is captured from the output and run verbatim, after which strict exits 0 and frozen_sha256 matches the edited projection. | Compare the stored hash against the WHOLE file instead of the contract projection; the status-flip arm of TEST-483 must redden and this test must stay green, proving the two tests separate the projection from the file. | green |
| TEST-483 | Spec-AC-13 | integration | tests/skills/test-aai-spec-amend.sh | Honest edits and non-targets — a frozen fixture spec edited WITH a record passes whether the record is signed or unsigned-tracked; an unfrozen spec, a non-spec document and a frozen spec whose only edits are Status, Evidence, Review-By and Notes cells plus a Test Plan Status cell each leave the gate's output byte-identical to the unedited run. | Include the AC-table Status and Evidence cells in the projection; the bookkeeping-edit arm must redden, which is the arm that keeps the gate from firing on every TDD cycle. | green |
| TEST-484 | Spec-AC-14 | integration | tests/skills/test-aai-spec-amend.sh | Legacy degrades by name — a fixture corpus of three frozen specs with no frozen_sha256 and one with a valid one, where the anchored one is edited without a record, exits non-zero for the anchored spec only and lists the three others as degraded by name; a run over the live repository exits 0 and names the degraded count. | Treat a missing frozen_sha256 as a mismatch; the three-legacy-specs arm must redden, which is the retroactive-red failure CHANGE-0181 AC-005 forbids. | green |
| TEST-485 | Spec-AC-15 | integration | tests/skills/test-aai-spec-amend.sh | Tracker must be open — a record whose tracked_by item is open stays unsigned-tracked and passes strict; the same record with that item closed, and again with it dropped, is classified unsigned-untracked and refused; the refusal names the item and its status. | Restore the existence-only bucketing (trackedItem !== null); the closed-tracker and dropped-tracker arms must redden. | green |
| TEST-486 | Spec-AC-16 | integration | tests/skills/test-aai-mutation-gate.sh | The gate reads this ride — a fixture copy of this spec together with the real records produced for every row of this Test Plan is gated and exits 0 with degraded=0; the same fixture with one record removed exits 5 naming that row. | Remove the base_commit ancestry check; the arm that plants a record from an orphan commit must redden, proving the ancestry rule is exercised by this spec's own evidence and not only by a synthetic fixture. | green |
| TEST-487 | Spec-AC-18 | unit | tests/skills/test-aai-hygiene-pack.sh | Suite registration — the suite-map row-count pin reads 95 and matches the live row count, every test-aai-*.sh has a row, check-test-registration.mjs exits 0 over the live tree, and select-suites.mjs given .aai/scripts/mutation-gate.mjs returns the new suite. | Delete the new suite's suite-map.yaml row via a unified diff whose content is copied into the evidence directory at mutation time (D14 — never a /tmp path), so the record is reproducible off this machine; the existence arm must redden naming the unregistered suite and the count arm must redden on 94 against a pin of 95. | green |
| TEST-490 | Spec-AC-19 | unit | tests/skills/test-aai-follow-ups.sh | Pin re-cut — close_work_item_pin_assert over the live tree returns OK for the edited close-work-item.mjs, the allowlist carries a new entry whose prose re-affirms both frozen invariants, and a grep asserts no allowlist entry claims the reconcile runs strictly after the try or catch block. | Amendment (remediation round 5, BLOCKING-1, validation round 6): the RECORDED mutation is now RE-PIN-PROOF — a static sed nulling one hard-coded historical allowlist entry (17f97f15…) went stale the moment a LATER remediation round re-pinned the file (the entry it targeted stopped being the live one), so the record stayed a false RED forever. The mutation disables close_work_item_pin_assert itself instead of any one hash line: `sed:s/close_work_item_pin_assert() {/close_work_item_pin_assert() { return 1;/` on tests/skills/lib/close-work-item-pin.sh (the runner's own single-line sed emulator has no multiline flag, so the replacement stays on the SAME source line as the opening brace — the unchanged body below is dead code, still syntactically valid bash) — verified by hand (bash -n on the mutated file, and sourcing it directly): close_work_item_pin_assert now returns 1 with empty stdout before it ever reads a hash, so the assert arm must redden (empty $result, no `OK <hash>` line) regardless of which entry is currently live. | green |
| TEST-488 | Spec-AC-18 | unit | tests/skills/test-aai-layer-profiles.sh | Classification — the union check over the live .aai tree passes and each of mutation-run.mjs, mutation-gate.mjs, lib/mutation-record.mjs and lib/spec-contract-hash.mjs is asserted present in exactly one of the two lists. | Remove one of the four new files from PROFILES.yaml via a unified diff whose content is copied into the evidence directory at mutation time (D14 — never a /tmp path); the union check must redden naming that file. | green |
| TEST-489 | Spec-AC-17 | integration | tests/skills/test-aai-spec-tools.sh | Freeze writes the anchors atomically — a fixture tdd spec with a Mutation column gains SPEC-FROZEN true, status implementing, frozen_sha256 and mutation_gate v1 in one write; a fixture whose strategy is direct gains the anchor but not the marker; and a fixture that fails an existing freeze precondition is left byte-identical with none of the four written. | Write frozen_sha256 in a second pass after the status write; the refusal arm must redden with a half-written file, which is the atomicity claim. | green |
| TEST-012 | Spec-AC-10 | unit | tests/skills/test-aai-prompt-diet.sh | Corpus true-up — the existing checkpoint re-sums against the JUSTIFIED_ADDITIONS entry added for this ride's SKILL_TDD, VALIDATION and ROLE_COMMON bytes, so the measured growth equals the credited growth and headroom returns to 2046. | Add one uncredited byte to .aai/SKILL_TDD.prompt.md; TEST-010's headroom arm must redden and the TEST-012 re-sum must stay green, proving the two checks are independent. | green |
| TEST-491 | Spec-AC-03 | integration | tests/skills/test-aai-mutation-gate.sh | Amendment (remediation round 2, NB3-r2/NB4-r2) — heredoc-aware selector extraction: (A) a fixture suite whose heredoc BODY contains `test_9002_farewell() {` text (round 1's NB5 regression shape) must never appear in an unknown-selector refusal's nearest-selector suggestions; (B) a fixture suite with an UNTERMINATED heredoc (no line before EOF equals the marker) must not swallow the rest of the file — a real selector defined after it (`test_bbb`, `test_ccc`) is still found. | Disable stripHeredocs (`return [...stripHeredocs(suiteContent).matchAll(` -> `return [...(suiteContent).matchAll(`); arm A must redden, naming `test_9002_farewell` in the suggestions it must never appear in. | green |
| TEST-492 | Spec-AC-11 | integration | tests/skills/test-aai-mutation-gate.sh | Amendment (remediation round 2, NB7-r2) — a rotated record's `mutation:` field follows its own rotated patch copy: two `--patch` runs on the same test id rotate the first record aside; the rotated record's `mutation:` field must resolve to a file whose bytes equal the FIRST patch, never the live patch name (whose bytes now belong to the second run). | In rotateExisting, skip the pointer rewrite (`if (hasPatch && parsed.ok && parsed.fields.mutation.startsWith('patch:')) {` -> `if (false) {`); the rotated record keeps the live patch name and the test must redden. | green |
| TEST-493 | Spec-AC-03 | integration | tests/skills/test-aai-mutation-gate.sh | Amendment (remediation round 2, NB6-r2) — a record names whether its own row's suite actually honours the positional `selector` it names: a fixture suite whose main() ignores $1 and runs every test produces a record carrying `selector_honoured: no (suite runs every test)` plus a printed NOTE; a fixture suite that dispatches on `$1` (`declare -F "$1"`) produces `selector_honoured: yes`. | Drop the false branch (`selector_honoured: selectorHonoured ? 'yes' : 'no (suite runs every test)'` -> `selector_honoured: 'yes'`); the non-dispatching arm's record no longer carries the honest "no" value and the test must redden. | green |
| TEST-494 | Spec-AC-09 | integration | tests/skills/test-aai-spec-lint.sh | Amendment (remediation round 3, NB-1) — Test Plan header cells resolve by PREFIX, not a closed exact map: a SPEC-0062-shaped header ("File path (existing suite)") at a NON-canonical column position resolves fileCell correctly (never masked by a positional fallback that happens to line up); an in-flight spec with a genuinely unrecognized header cell ("Flavor") gets a new `test-plan-header-unmapped` finding naming it; the same well-known variant produces no false alarm; the live corpus produces zero such findings. | In `resolveTestPlanHeaderKey` (lib/docs-model.mjs), narrow the file-path resolver from a prefix match back to an exact-match closed set (`if (h.startsWith('file path')) return 'fileCell';` becomes an exact-match test against only `'file path (expected)'` and `'file path'`); the SPEC-0062-shaped-header arm must redden. | green |
| TEST-495 | Spec-AC-14 | integration | tests/skills/test-aai-spec-amend.sh | Amendment (remediation round 3, NB-2) — `list --strict` refuses (exit 2, naming the path) when `--specs-dir` does not exist, rather than silently scanning nothing and printing a clean-looking `spec_degraded=0`; a plain `list` (no `--strict`) is unaffected; an existing (even empty) dir is scanned and `spec_scanned=<n>` is always printed beside `spec_degraded`, including a non-zero count over the live repository. | Disable the existence refusal (`if (opts.strict && !fs.existsSync(specsDirAbs)) {` -> `if (false) {`); the missing-dir arm must redden (no refusal, exit 0 over an empty scan instead of the required exit 2). | green |
| TEST-496 | Spec-AC-11 | integration | tests/skills/test-aai-mutation-gate.sh | Amendment (remediation round 3, NB-3) — a `buildIsolatedClone()` failure during `--replay` (a `.git` directory made unreadable, forcing the very first git command to refuse) is classified `inconclusive` (exit 4), never `failures` (exit 1): the exact conflation the round-2 D7-trip fix left unaddressed 45 lines below its own branch. | In `replay()`'s clone-build catch block, route the failure back into `failures` instead of `inconclusive` (`inconclusive++;` -> `failures++;`, the line immediately preceding the `could not build an isolated clone` message); the test must redden, reporting exit 1 (FAIL) instead of the required exit 4 (INCONCLUSIVE). | green |
| TEST-497 | Spec-AC-01 | integration | tests/skills/test-aai-mutation-gate.sh | Amendment (remediation round 4, NB-1; supersedes the round-3 NB-5 shape) — a concurrent write to a RUNTIME_ALLOWLIST path (`docs/ai/STATE.yaml`, arm 1; `docs/ai/LOOP_TICKS.jsonl`, arm 2) during a normal (non-replay) run must NOT downgrade the run's own verdict: the allowlist is reproduced into the clone (D4) but excluded from the D7 before/after comparison, so the RED verdict survives (exit 0), never INCONCLUSIVE. Amendment (remediation round 5, NB1-r6) — arm 3 (new): a RAPID (~50ms interval) appender writes to `docs/ai/STATE.yaml` for the WHOLE run (clone build through suite exit, not one well-timed write), proving the D4 second window (buildIsolatedClone hashing the bytes it actually copies into the clone rather than the earlier snapshot) closes under load, not only under a single-write mutation. | In `withoutRuntimeAllowlist` (mutation-run.mjs), put the allowlist back into the D7 comparison (`for (const rel of RUNTIME_ALLOWLIST) filtered.delete(rel);` -> `for (const rel of []) filtered.delete(rel);`); both arms must redden, the concurrent allowlist write downgrading the verdict to INCONCLUSIVE (exit 6) instead of the required RED (exit 0). Round-5 mutation (NB1-r6, the LIVE recorded mutation — the round-4 mutation above is preserved as a rotated record, D2): delete `sourceTreeFiles.set(rel, createHash('sha256').update(bytes).digest('hex'));` in `buildIsolatedClone` (mutation-run.mjs); arm 3 must redden, throwing `TreeMismatchError … changed: docs/ai/STATE.yaml` (exit 3) under the rapid appender instead of the required RED (exit 0) — arms 1-2 are unaffected by this mutation (a different property) and stay green. | green |
| TEST-498 | Spec-AC-05 | integration | tests/skills/test-aai-mutation-gate.sh | Amendment (remediation round 3 NB-7, round 4 NB-2) — a Test Plan row whose Status cell is a terminal-not-green value (deferred/dropped/rejected) is EXEMPT from the RED-record requirement, named `EXEMPT <TEST-id>: status <value>` in the gate's output; exemption is per-row (a mixed spec's satisfied count excludes the exempt rows) and case-insensitive; an ALL-exempt Test Plan (arms A and D) is its own named DEGRADE class (`DEGRADED: every row exempt (n)`), never a vacuous `GATE PASS: 0 row(s) satisfied`. | Disable the round-4 DEGRADE branch (`if (exempt.length > 0 && satisfied === 0) {` -> `if (false) {`); arms A and D must redden, the all-exempt fixtures reporting `GATE FAIL` (an empty Mutation cell is no longer exempted from the RED-record requirement it was just exempted from) instead of the required `DEGRADED: every row exempt`. The round-3 mutation this cell previously named (emptying `EXEMPT_STATUSES`) is preserved as a rotated record (D2) and remains provable — arms A-C still require the exemption to hold. | green |
| TEST-499 | Spec-AC-01 | integration | tests/skills/test-aai-mutation-gate.sh | Amendment (remediation round 3, NB1-r3) — the NORMAL-run (non-replay) D7 self-check also names the changed path, exactly like `--replay`'s own message: a concurrent editor of a tracked file during a slow selector's run is caught (exit 6, INCONCLUSIVE) and the record's `first_fail` names the changed path. Closes the round-2 amendment's own mutation-free survivor (M9): the normal-run half of the D7 path-naming fix had no test of its own. | Drop `${describeTreeDiff(treeDiff)}` from the NORMAL-run D7 message (reverting it to the round-2 wording, which named no path), keeping the INCONCLUSIVE downgrade itself intact; the test must redden, the message no longer naming CONCURRENT_MARKER.txt. | green |
| TEST-500 | Spec-AC-04 | integration | tests/skills/test-aai-mutation-gate.sh | Amendment (remediation round 3, NB2-r3) — a rotated-name collision (two rotations sharing one `run_at_utc` second) gets a monotonic `.1`/`.2` suffix rather than silently overwriting the earlier archive: a pre-occupied bare-stamp name survives untouched, and the real record is archived at the next free suffix. | Disable the collision probe (`while \(taken\(suffix\)\) {` -> `while (false) {`); the test must redden: the pre-existing archives (bare record name, `.1` patch name) are overwritten instead of the real record and its patch landing together at `.2` landing at the `.1` suffix. | green |
| TEST-501 | Spec-AC-11 | integration | tests/skills/test-aai-mutation-gate.sh | Amendment (remediation round 3, NB3-r3) — `rotateExisting`'s `mutation:` pointer rewrite survives a `$`-bearing spec id (`fixture-spec-501-a$&b`, the `js-replace-dollar-quote-corrupts` trap this repo's own LEARNED rule names): the rotated record still parses as v1 and its `mutation:` field resolves to the rotated patch's OWN repo-relative path, literally, never re-interpreted as a `$&`/`$'` replacement pattern. | Revert the function-replacement to a plain string (`.replace(re, () => \`mutation: patch:${rotatedPatchRel}\`)` -> `.replace(re, \`mutation: patch:${rotatedPatchRel}\`)`); the test must redden, the rotated record's tail duplicating and the `mutation:` line corrupting rather than resolving cleanly. | green |
| TEST-502 | Spec-AC-04 | integration | tests/skills/test-aai-mutation-gate.sh | Amendment (remediation round 3, NB5-r3) — `parseRecord`'s tolerance of an unrecognized header key is proved by a test, not merely asserted in prose (the exact back-compat property `selector_honoured`, NB6-r2, depends on): a hand-built record carrying an extra header key still parses as v1 and still satisfies the gate. | Extend the `mutation_record` version guard (`if (fields.mutation_record !== MUTATION_RECORD_VERSION) {`) with an additional OR-condition rejecting any header key outside `HEADER_FIELDS` and `selector_honoured`; the test must redden, the gate refusing a record it must tolerate (GATE FAIL instead of the required GATE PASS). | green |
| TEST-503 | Spec-AC-03 | integration | tests/skills/test-aai-mutation-gate.sh | Amendment (remediation round 3, NB6-r3) — a heredoc opener mentioned inside a full-line COMMENT (`# example: cat <<EOS`) never opens a real heredoc, so it cannot consume a LATER, legitimate heredoc sharing the same marker and swallow the selectors defined in between; a real selector defined right after the comment is still found. | Restore unconditional heredoc-opener recognition, dropping the comment-line guard (`const m = isCommentLine ? null : /<<-?\s*(['"]?)([A-Za-z_][A-Za-z0-9_]*)\1/.exec(line);` -> `const m = /<<-?\s*(['"]?)([A-Za-z_][A-Za-z0-9_]*)\1/.exec(line);`); the test must redden, `test_swallowed` disappearing from the unknown-selector suggestions. | green |
| TEST-504 | Spec-AC-03 | integration | tests/skills/test-aai-hygiene-pack.sh | Amendment (remediation round 3, NB4-r3) — the Node copy of the six positional-dispatch idioms (`mutation-run.mjs` `POSITIONAL_DISPATCH_PATTERNS`) stays aligned with `hp_scan_selector_suites`' own POSIX `[[:space:]]` whitespace grammar: the two scanners agree on every real suite in `tests/skills`, and BOTH now recognize a synthetic vertical-tab dispatch line the bash copy already matched. | Narrow the Node whitespace class back to `[ \t]` (`const WS = ' \\t\\v\\f';` -> `const WS = ' \\t';`); the vertical-tab arm must redden, the Node scanner missing a dispatch line the bash scanner still finds. | green |
| TEST-505 | Spec-AC-07 | integration | tests/skills/test-aai-close-work-item.sh | Amendment (remediation round 4, NB-2; round 5, NB6-r6/NB3-r6) — its OWN test function and selector, `test_068_mutation_gate_all_exempt_notice` (round 4 recorded this as arm E of TEST-477's own `test_067_mutation_gate_close_wiring`, sharing that selector — a drift risk NB6-r6 named: a future edit to one function's FAIL text mentioning the other's id could silently swap record attribution). Arm A: an applicable spec whose ONLY Test Plan row is exempt passes the real gate vacuously (exit 0, `DEGRADED: every row exempt`), even under `mutation_gate: enforce` (never a refusal); `evaluateMutationGate` surfaces the exempt/degraded counts as a WARNING rather than silently `continue`ing past them, and the close proceeds to `done`. Arm B (new, NB3-r6): a MIXED spec (one offending row, one exempt row) refuses under enforce, and the REFUSED reason names BOTH the offending row AND the exempt count — `reason` previously dropped `notices` entirely on the offending path. | Disable the exit-0 notices surfacing (`if (notices.length === 0) return { severity: 'none' };` -> `if (true) return { severity: 'none' };`); arm A must redden, the all-exempt close going silent (no WARNING, no exempt/degraded count) instead of the required surfaced counts. | green |
| TEST-506 | Spec-AC-05 | integration | tests/skills/test-aai-mutation-gate.sh | Amendment (remediation round 5, D8 amendment, BLOCKING-1, validation round 6) — a record's own `target_sha256` lets the gate see that its target changed SINCE the record was produced: an unchanged target's record satisfies the gate (`unstamped=0`); editing the target afterward turns the row OFFENDING, named `STALE TEST-9001: target … changed since the record — re-run mutation-run.mjs (or --replay) for this row`, exit 5; re-stamping `target_sha256` to the new bytes restores `GATE PASS`; a LEGACY record with no `target_sha256` field at all is counted in a named `unstamped=1` degrade, never mistaken for stale, and the gate stays exit 0. | Drop the STALE comparison (`if (liveSha256 !== f.target_sha256) {` -> `if (false) {`); the changed-target arm must redden, the STALE row going unnoticed (`GATE PASS`) instead of the required `OFFENDING`/exit 5. | green |
| TEST-507 | Spec-AC-05 | integration | tests/skills/test-aai-mutation-gate.sh | Amendment (remediation round 6, NB1-r7, validation round 7) — the PRODUCER half of the D8 amendment (`mutation-run.mjs` stamping `target_sha256` into every new record) had no test of its own; only a hand-built record's consumer side was covered by TEST-506. This arm drives the REAL runner against an isolated git fixture: a freshly produced record's `target_sha256` equals `shasum -a 256` of the fixture's own target at record time, and editing that target afterward turns the row OFFENDING/STALE at the gate — reached through the producer, never a hand-built record. | Delete the stamping line from the producer's record fields (`target_sha256: targetSha256,` -> removed); the arm must redden, a freshly produced record carrying no `target_sha256` line at all. | green |
| TEST-508 | Spec-AC-11 | integration | tests/skills/test-aai-mutation-gate.sh | Amendment (remediation round 6, NB2-r7, validation round 7) — `--replay`'s OTHER stale-target symptom: when the recorded mutation no longer CHANGES the target (`before === after`, the likelier way a record goes stale, since a re-pinned/edited target commonly breaks its own recorded pattern before it stops reddening), the `FAIL … replayed mutation no longer changes <target>` line now also carries `(target changed since the record)` whenever the record's `target_sha256` no longer matches the live target — the same note the "no longer reddens" branch already carried. | Disable the new comparison (`if (liveSha256 !== fields.target_sha256) beforeAfterStaleNote` -> `if (false) beforeAfterStaleNote`); the arm must redden, the FAIL line losing its stale-target note. | green |
| TEST-509 | Spec-AC-05 | integration | tests/skills/test-aai-mutation-gate.sh | Amendment (remediation round 6, NB3-r7, validation round 7) — a DELETED (or renamed) target is a DIFFERENT cause from an EDITED one: the gate now reports it `target <path> missing`, never borrowing the hash-mismatch comparison's `changed since the record` wording for a target that simply vanished. | Revert the missing-target wording to the changed-target one (`target ${f.target} missing` -> `target ${f.target} changed since the record`); the arm must redden, a deleted target once again reported as merely changed. | green |
| TEST-510 | Spec-AC-05 | integration | tests/skills/test-aai-mutation-gate.sh | Amendment (remediation round 6, NB6-r7, validation round 7) — the `NOTE: unstamped=<n> …` line's own wording was a mutation-free survivor: the summary line's shared `unstamped=<n>` substring let a mutation renaming the NOTE's own token alone (`NOTE: unstamped=` -> `NOTE: skipped=`) go unnoticed. The NOTE line's full text is now asserted directly, not only the substring it shares with the summary line. | Rename the NOTE line's own token (`NOTE: unstamped=` -> `NOTE: skipped=`); the arm must redden, the NOTE line's wording changing while the summary line's `unstamped=1` (asserted separately) stays intact. | green |
| TEST-511 | Spec-AC-07 | integration | tests/skills/test-aai-close-work-item.sh | Amendment (remediation round 6, NB4-r7, validation round 7) — `unstamped=<n>` reaches the close now too, the identical "a named degrade the close silently discarded" shape round 4's NB-2 fixed for `exempt=<n>`: a spec whose only record is a LEGACY one (no `target_sha256`) still passes the gate (`unstamped=1`, never a refusal), and `evaluateMutationGate` now surfaces that count as a WARNING exactly as it already does for `exempt`. | Drop the new OR-condition (`if (exemptN > 0 \|\| unstampedN > 0) {` -> `if (exemptN > 0) {`); arm C must redden, a satisfied-but-unstamped spec's close going silent again (no WARNING, no `unstamped=1`). | green |
| TEST-512 | Spec-AC-07 | integration | tests/skills/test-aai-close-work-item.sh | Amendment (PR ceremony 2026-09-17, cross-ride reconciliation with SPEC-0178) — the close-time usage-capture gate accepts the `tokens_total` FIELD that `state.mjs append-run --tokens-total` records as usage capture under enforce; a null total is still refused | `if (run.tokensTotal !== null && run.tokensTotal !== undefined && run.tokensTotal >= 0) return true;` -> `if (false) return true;` in `close-work-item.mjs`; the test must redden, the field-only run being refused under enforce | green |
| TEST-513 | Spec-AC-02 | integration | tests/skills/test-aai-mutation-gate.sh | Amendment (remediation round 7, PR #384 Codex P1; validation rounds 10 and 11) — a `--patch` that touches ANY path other than `--target` is refused: exit 2, the foreign path named, no record, no clone left (a named INCONCLUSIVE under `--replay`); a single-file patch still records RED. Two guards, each with an arm only it catches: `git apply --numstat -z` before the apply (post-image paths: another prefix, a C-quoted name, CRLF headers, a gitignored creation) and the clone tree hashed before and after the apply (a rename whose SOURCE is a foreign file, which numstat never prints). The round-7 hand-written header parser is gone. | `if (offending.length) {` -> `if (false) {` in `refuseForeignPaths` of `mutation-run.mjs` (as the runner applies it: `s/if \(offending\.length\) \{/if (false) {/`); the test must redden at arm A, the two-file patch being recorded RED instead of refused | green |
| TEST-514 | Spec-AC-13 | integration | tests/skills/test-aai-spec-amend.sh | Amendment (remediation round 7, Codex P1, PR #384) — an anchored spec (`frozen_sha256` present) that lost its `SPEC-FROZEN` body marker was skipped BEFORE `scanSpecAnchors` even compared the anchor, silently bypassing the whole undisclosed-amendment gate. A spec carrying `frozen_sha256` is now ALWAYS scanned; an anchor with no marker is its own STRICT violation (`anchor-without-freeze-marker`), named with a runnable remedy (restore the marker line). Proved against a REAL `spec-freeze.mjs` anchor whose marker is then deleted alongside a body edit. | `if (!frozenMarker \&\& anchor === null) continue;` -> `if (!frozenMarker) continue;` in `spec-amend.mjs`; the test must redden, the anchored-but-unmarked spec going silently unscanned again. | green |
| TEST-515 | Spec-AC-12 | integration | tests/skills/test-aai-spec-amend.sh | Amendment (remediation round 7, Codex P1, PR #384) — `lib/spec-contract-hash.mjs` split Test Plan/AC table rows on a plain `split('\|')`, so an escaped `\|` inside a Mutation cell (this spec's OWN TEST-511 row has one) shifted the columns, and a routine Status flip on that row changed the contract hash (a false undisclosed-amendment). `blankTableSection` now reuses `lib/docs-model.mjs`'s `splitRawTableCells` — the SAME escaping rule `splitTableCells` (the Test Plan reader) already builds on — instead of a second hand-rolled splitter. | `splitRawTableCells(line)` -> `line.split('\|')` (both call sites) in `lib/spec-contract-hash.mjs`; the test must redden, a Status-only flip on a row carrying an escaped pipe in its Mutation cell changing the contract hash. | green |
| TEST-516 | Spec-AC-13 | integration | tests/skills/test-aai-spec-amend.sh | Amendment (remediation round 7, Codex P2, PR #384) — an unreadable spec file was silently OMITTED from the strict scan (a bare `catch { continue; }`). `scanSpecAnchors` now fails CLOSED: reported as its own STRICT violation bucket (`unreadable-spec`) naming the file, never silently skipped. | `violations.push({ spec_id: path.basename(abs), path: rel, bucket: 'unreadable-spec', error: err.message });` -> `void err;` in `spec-amend.mjs`; the test must redden, an unreadable spec passing strict silently instead of refusing. | green |
| TEST-517 | Spec-AC-06 | integration | tests/skills/test-aai-mutation-gate.sh | Amendment (remediation round 7, Copilot, PR #384) — `mutation-gate.mjs`'s `--spec` accepted a FOLLOWING FLAG as its own value (`--spec --json` exited 3 "cannot read --json" instead of a usage error). A missing value, or a value starting with `--`, is now exit 2 usage. | `if (v === undefined \|\| v.startsWith('--')) {` -> `if (false) {` in `mutation-gate.mjs`'s `requireValue`; the test must redden, `--spec --json` swallowing `--json` as the spec path instead of exiting 2. | green |
| TEST-518 | Spec-AC-17 | integration | tests/skills/test-aai-spec-tools.sh | Amendment (remediation round 7, Copilot, PR #384) — the byte-correctness check for `spec-freeze.mjs`'s minimal no-H1 fixture was SELF-REFERENTIAL: it read `frozen_sha256` back out of the file under test and built the expected output FROM that same value, so a WRONG hash would still "pass". The check now recomputes the contract-projection hash independently via `lib/spec-contract-hash.mjs`'s `contractHash()` on the frozen file's own bytes and asserts the stored anchor equals it. | `const hash = contractHash(out);` -> `const hash = contractHash('');` in `spec-freeze.mjs`; the test must redden, a freeze that writes the hash of the empty string as `frozen_sha256` going uncaught. | green |
| TEST-519 | Spec-AC-02 | integration | tests/skills/test-aai-mutation-gate.sh | Amendment (remediation round 7, Copilot, PR #384) — `mutation-run.mjs`'s OTHER value-taking flags (`--spec`, `--test-id`, `--suite`, `--selector`, `--target`, `--sed`, `--patch`) shared TEST-517's shape: a following flag was silently accepted as the value. Every one now refuses (exit 2) a missing value or one that looks like another flag. | `if (v === undefined \|\| v.startsWith('--')) {` -> `if (false) {` in `mutation-run.mjs`'s `requireValue`; the test must redden, every value-taking flag accepting a following flag as its own value instead of exiting 2. | green |

Every Spec-AC has at least one TEST row and every TEST row names exactly one
Spec-AC. Every row carries a Mutation cell — the column this ride introduces,
applied to itself.

## Seams

Each row is a boundary this change shares with something it does not own, with
the test that produces on one side and asserts on the other.

| Seam | Produced by | Asserted by | Test |
|------|-------------|-------------|------|
| S1 | `mutation-run.mjs` writes a record | `mutation-gate.mjs` parses it and `--replay` re-executes it | TEST-486 gates the REAL records this ride produced, not hand-written fixtures; TEST-481 replays real records |
| S2 | `spec-freeze.mjs` writes `frozen_sha256` and `mutation_gate` | `spec-amend.mjs list --strict` and `mutation-gate.mjs` read them | TEST-489 freezes with the real tool and TEST-482 judges with the real gate over that same file |
| S3 | `lib/docs-model.mjs` parses the Test Plan | BOTH `spec-lint.mjs` and `mutation-gate.mjs` consume the rows | TEST-479 drives the live corpus through the lint; TEST-475 drives the same reader through the gate |
| S4 | `mutation-gate.mjs` exit code | `close-work-item.mjs` branches on it, under a dial in `docs-audit.yaml` | TEST-477 runs the REAL close CLI against a fixture ride whose gate genuinely exits 5 |
| S5 | the prose in three prompt files | the delivered CLI's own flag grammar | TEST-480 parses the command line named in canon with the real CLI, so a prompt that names a flag the tool does not accept fails |
| S6 | corpus bytes added by S5's prose | `tests/skills/lib/prompt-diet-ledger.sh` arithmetic and TEST-012's pin | TEST-012 re-sums the ledger against the measured growth |
| S7 | the runner's clone | the shipping repository it was cloned from | TEST-471 hashes both sides and asserts the source is untouched, on the success path AND on both refusal paths |
| S8 | this spec's own frozen projection | the gate delivered by this ride, watching this ride | implementation step 7 stamps it; any later edit needs a `spec-amend add` record, which is the capability proving itself |

## Residual risks and owner questions

- **R1 — a rebase or a squash invalidates every record.** `base_commit` must be
  an ancestor of HEAD (D8). A ride that rebases its branch after producing
  records will see the gate refuse until the records are re-produced. That is
  the correct polarity (evidence about a tree that no longer exists is not
  evidence) but it is real friction, and `--replay` is the one-command answer.
- **R2 — the projection hash is a heuristic about which bytes are the
  contract.** D10 names the split. A spec that records substantive content in a
  Notes cell would change the contract without tripping the gate. The measured
  incident is covered; the general case is not provable.
- **R3 — `frozen_sha256` is hand-editable**, like every marker in this
  repository. It guards the honest omission, which is the incident on record,
  not a determined author.
- **R4 — the runner's clone costs wall-clock time.** One `git clone --local` per
  mutation, per test. On a 20-row Test Plan that is 20 clones for the ride and
  20 more for the validator's replay. Measured mitigation is deliberately NOT
  taken here (a shared clone reused across mutations would reintroduce
  cross-contamination between runs, which is the property the isolation buys).
  If the cost proves material it is a follow-up with a measurement behind it.
- **R5 — one mutation per row is a floor, not coverage.** D18 says so. A test
  can pass its single mutation and still miss the property it claims. The gate
  moves the floor from zero to one; it does not certify a test.
- **R6 — the selector fix (Spec-AC-03) touches up to fifteen suite files**, some
  owned by rides that have not started and one (`test-aai-learned-routing.sh`)
  edited by sweep 3 last week. The edit is one line in each suite's dispatcher
  and the corpus guard is what makes it verifiable; the merge-conflict cost is
  named rather than avoided, and it is the reason a shared helper is preferred
  where one already exists (D3).
- **R7 — the amendment gate stays wired by a PROMPT, not by the close script.**
  `spec-amend list --strict` runs at `.aai/SKILL_PR.prompt.md:188-196`
  (measurement 22), so a close that does not go through the PR skill never runs
  it. By this spec's own D12 argument that is a note where a guard belongs, and
  it is not fixed here: adding a SECOND new gate and a second new exit code to a
  hash-pinned file in the same ride doubles the blast radius of the one edit
  that reddens two other suites. The exact shape a later ride adds is the one
  D12 uses — an `evaluateAmendmentGate()` beside its three siblings, exit 9,
  dial `amendment_gate` in `GUARD_DIALS`.
- **R8 — every intermediate round of this ride is a FULL sweep.**
  `tests/skills/suite-map.yaml:44-46` escalates any edit under
  `.aai/scripts/lib/**` to a full run, and this scope edits `lib/docs-model.mjs`
  and adds two modules there. The owner's standing decision (selected plus CORE
  between rounds, one full sweep before close, 2026-09-13) cannot be honoured
  literally for this ride; the full sweep needs `AAI_TEST_TIMEOUT=3000`
  (LEARNED.md) and costs roughly half an hour per round. Named so the cost is a
  decision and not a surprise.
- **DEBT-0007 is NOT resolved by this scope, and its residual is named.**
  `docs/issues/DEBT-0007-withdrawn-claim-sweeps-are-not-verifiable.md` asks for a
  repeatable way to RETRACT a claim across the corpus. A mutation gate proves a
  TEST fails without the change; it says nothing about whether a sentence was
  retracted everywhere it appears. Its one still-open registry id is
  `fu-spec-d6-enumeration-stale`; four of its six named ids are terminal and
  `fu-overview-shows-closed-ride-inflight` was closed by sweep 3. Intake AC-009
  is discharged by naming this residual, not by claiming the debt.

## Verification

Commands, in the order the evidence is produced:

- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-mutation-gate.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-spec-amend.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-spec-lint.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-spec-tools.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-close-work-item.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-close-reconcile.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-layer-profiles.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-hygiene-pack.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-follow-ups.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-doc-numbering.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-suite-select.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-run-tests.sh`
- regression consumers of the edited surfaces:
  `tests/skills/test-aai-docs-audit.sh`, `tests/skills/test-aai-ceremony-levels.sh`,
  `tests/skills/test-aai-branch-guard.sh`, `tests/skills/test-aai-session-lock.sh`,
  plus the remaining selector suites named in measurement 11
- `node .aai/scripts/mutation-gate.mjs --spec docs/specs/SPEC-0181-spec-mutation-gate-for-tests.md`
  exits 0 with `degraded=0` (Spec-AC-16)
- `node .aai/scripts/mutation-run.mjs --replay --spec docs/specs/SPEC-0181-spec-mutation-gate-for-tests.md`
  exits 0 (the validator's own command, D14)
- `env -u AAI_ROLE node .aai/scripts/spec-amend.mjs list --strict` exits 0
- one full sweep before close, `AAI_TEST_TIMEOUT=3000`
- `env -u AAI_ROLE node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0181-spec-mutation-gate-for-tests.md`
- `env -u AAI_ROLE node .aai/scripts/docs-audit.mjs --check --strict --no-event`

PASS criteria: every TEST-xxx green, every Spec-AC in a terminal status, and
every Test Plan row's mutation observed RED with its record present and read by
the gate.

## Evidence contract

All evidence for this scope lives under
`docs/ai/tdd/spec-mutation-gate-for-tests/`:

- `red-<TEST-id>.txt` — the failing run of each test on the pre-change tree.
- `green-<TEST-id>.txt` — the passing run after the edit.
- `mutation-<TEST-id>.txt` — the v1 record written by `mutation-run.mjs` for
  that row's Mutation cell. One per Test Plan row, no exceptions and no
  substitutions: this spec may not use the "mutation-only, no RED" carve-out
  SPEC-0179 needed, because every test here asserts behaviour that does not
  exist on the pre-change tree.
- `measurements.txt` — the re-run of the `## What is established before this
  scope starts` probes, so every number above is reproducible at review.
- `gate-close.txt` — the Spec-AC-16 gate run over this spec.
- `replay-<ts>.txt` — the validator's `--replay` run.
- `sweep-<ts>.txt` — the full-suite sweep before close.

Each artifact records: ref_id `mutation-gate-for-tests`, the Spec-AC and
TEST-xxx it belongs to, the exact command, the exit code, and the commit or diff
range it was produced against.

### Evidence by strategy

Strategy `tdd`: a stored RED artifact per AC-gating test, a stored mutation
record per Test Plan row, and the full verification matrix. That is what the
contract above demands, and it is the contract this ride makes mechanical.

## Registry items closed by this scope

`node .aai/scripts/follow-ups.mjs list --status open --json` was re-derived in
full at planning on 2026-09-14: 91 open items. The intake's named bucket is
STALE — five of its six ids are already terminal (measurement 7) — so the set
below is re-derived from the live open set by the finding class the intake
describes: a control that claims a property it does not test, a test whose
mutation is unreachable, or a selector or probe that fails open. It is
deliberately selective: an item is here only when this scope's own diff closes
it.

CLOSED FULLY:

- `fu-test-selector-unknown-id-passes` (P2) — closed by Spec-AC-02 and
  Spec-AC-03, and closed WIDER than it was filed: the item names three suites,
  the measured population is fifteen (measurement 11), and one of the three it
  names was already fixed by sweep 2. What ships is a corpus guard that
  enumerates every selector-accepting suite on every run, so the number stops
  being a sighting in a follow-up's prose. The runner that depends on selecting
  one test refuses an unknown name before it clones anything. This is the item
  the whole capability rests on: a runner built on a fail-open selector would
  record verdicts for tests that never ran.
- `fu-spec-amend-terminal-tracker-counts` (P2) — closed by Spec-AC-15. The
  unsigned-tracked bucket requires an OPEN tracker, so a dropped tracker stops
  satisfying the strict gate forever. Closed here because this ride rewrites
  that exact function (D11, D16).
- `fu-closeworkitem-pin-tail-wording` (P3) — closed by Spec-AC-19 (implementation
  plan step 11). The pin entry's prose currently asserts something untrue of the
  D6.2 idempotency short-circuit path; the re-pin this ride must do anyway is
  the one moment that sentence can be corrected without touching a pinned file
  for no reason.

## Registry items rejected by this scope

NOT CLOSED, with the reason:

- `fu-pindirfast-gitdir-untested` (P3) — the same class ("no test a mutation
  reddens") but a different surface: `branch-guard.mjs`'s GIT_DIR deference.
  Closing it means writing a branch-guard test, and this scope touches neither
  that script nor its guarantee. The gate delivered here is what will demand the
  mutation on the ride that next touches it.
- `fu-seed-partial-verdict-unasserted` (P3) — class match, wrong subsystem:
  `tests/skills/test-framework.sh` is sweep 2's file and a concurrent surface.
- `fu-ps1-quality-outside-sweep-glob` (P3) — a guard that never runs, which is
  the class; but it is a PowerShell suite, explicitly out of scope (D18), and
  the gap is re-filed as `fu-mutation-gate-skips-pester`.
- `fu-tripwire-attributes-concurrent-writes` (P3) — read at planning and used
  (D7) as the reason the runner's isolation is proved in its OWN fixture rather
  than through the live tripwire. Fixing the tripwire's attribution is sweep 2's
  surface.
- `fu-prompt-diet-fixture-real-root-race` (P2) — a suite writing into the real
  project root, adjacent to D7's isolation claim but living in
  `test-aai-prompt-diet.sh`'s fixture handling, which is sweep 2's material.
  This ride edits that file only at line 812 (the checkpoint number).
- `fu-verify-closures-strict-value-off` (P2) and
  `fu-verify-closures-corpus-cwd-silent` (P3) — both are gates that fail open,
  and both live in `follow-ups.mjs verify-closures`, the closure verifier. They
  are the close-ceremony sweep's surface (sweep 5 in the re-ordered wave), and
  closing them inside the ride whose own closure claims they verify would make
  this scope its own auditor.
- `fu-openct-unrdbl-report` (P2), `fu-pgq-grep-error-reopened` (P3),
  `fu-posix-predicate-exit-conflates-infra` (P2),
  `fu-sync-hash-compare-fails-open` (P2) — all four are the fail-open class in
  four other subsystems (the factory report, the pipe-grep ratchet, the POSIX
  path predicate, `aai-sync.sh`). Each needs its own measurement; folding four
  unrelated scripts into this ride would be the scope-by-class mistake the wave
  order exists to prevent.
- `fu-gate-ac-duplicate-id-pipe-drop` (P2) and `fu-ac-flip-guard-lean-table-blind`
  (P3) — gates blind on a path, in `docs-audit`. Adjacent to D15's table reader
  but in a different parser with a different owner; the close-ceremony sweep
  carries them.
- `fu-realpath-allocate-doc-number-l3` (P3) — the class fits (a main guard that
  exits 0 silently), but `allocate-doc-number.mjs` is `protected_paths_l3`.
  Absorbing it would move this ride to ceremony 3 for one line, which is a
  scope decision the owner should make deliberately, not a side effect.
- `fu-amend-spec-test-framework-sweep` (P2), `fu-amend-spec-dispatch-state-sweep`
  (P2) and the five other open `fu-amend-*` items — owner menu. They are
  sign-off obligations on existing unsigned amendments; no code in this ride can
  discharge one. D11 makes the NEXT undisclosed amendment impossible, which is
  the forward half of the same problem.
- `docs/issues/DEBT-0007-withdrawn-claim-sweeps-are-not-verifiable.md` — not
  absorbed; the residual is named in `## Residual risks and owner questions`.

## GitHub issues

None filed by this scope. `fu-mutation-gate-skips-pester` (P3) is filed in the
registry at implementation time, per D18.

## Amendment (post-freeze, 2026-09-14 — TDD run 3's two Mutation-cell deviations)

Two Test Plan rows record a mutation that differs from the one their own
Mutation cell names (the cells are left VERBATIM — an amendment discloses,
never silently edits, the frozen contract projection). Both were found while
producing this spec's own mutation records (implementation step 7, run 3);
this section is the disclosure the D11 mechanism exists to require, dogfooded
on this spec itself the moment `spec-freeze.mjs` first stamps its
`frozen_sha256` (Seam S8).

- **TEST-482 (Spec-AC-12).** The cell reads: "Compare the stored hash against
  the WHOLE file instead of the contract projection; the status-flip arm of
  TEST-483 must redden and this test must stay green, proving the two tests
  separate the projection from the file." A literal whole-file hash cannot be
  built: `frozen_sha256` is a field INSIDE the file being hashed, so hashing
  "the whole file" is self-referential the moment the field is written — there
  is no well-defined "before" state to compare against. The actually recorded
  mutation (`docs/ai/tdd/spec-mutation-gate-for-tests/mutation-TEST-482.txt`)
  instead disables `lib/spec-contract-hash.mjs`'s frontmatter-stripping line
  (`if (fm) norm = norm.slice(fm[0].length);` -> `if (false) ...`), which
  folds the frontmatter block — `frozen_sha256` included — into the hashed
  projection, the closest coherent approximation of "hash more than the
  projection" available. It reddens TEST-482 itself directly (the baseline
  strict run, re-hashed with the frontmatter included, is no longer clean),
  which is a STRONGER proof than the cell's original two-test-separation
  design: it demonstrates the projection/frontmatter split is load-bearing
  for THIS test's own record, not only inferred from a sibling's behavior.
- **TEST-489 (Spec-AC-17).** The cell reads: "Write `frozen_sha256` in a
  second pass after the status write; the refusal arm must redden with a
  half-written file, which is the atomicity claim." `spec-freeze.mjs` writes
  its whole output as ONE in-memory transform followed by ONE
  `writeFileSync` (measurement 17) — there is no second write pass to move
  code into, so a "second-pass write" mutation cannot be expressed against
  the delivered structure. The actually recorded mutation
  (`docs/ai/tdd/spec-mutation-gate-for-tests/mutation-TEST-489.txt`) instead
  disables the change-detection guard around the write
  (`if (changed) {` -> `if (false) {`), which reddens the row's own
  "freeze writes anchors atomically" assertion directly — the one-write
  structure has no seam a second-pass mutation could target, so the guard
  immediately around the single write is the nearest real fault injection
  the atomicity claim admits.

`SPEC-FROZEN: true` is preserved; nothing above moves or deletes an existing
AC's or Test Plan row's text — the Mutation cells stay exactly as frozen, and
this section is the disclosure that their prose and their evidence
legitimately diverge, with the reason named for both. Every fact above was
verified against the real record files and the real source lines before this
Amendment was written (`docs/knowledge/LEARNED.md` "Amendment record from
text, not report").

### Remediation round 1 (2026-09-14 — validation round 1 FAIL, d4274359)

Validation round 1 (claude-opus-5, `docs/ai/tdd/spec-mutation-gate-for-tests/validation-round1.txt`)
found three BLOCKING gaps between a D-decision's wording and what the delivered
code actually tests. All three are fixed at cause; this section discloses the
wording each fix adds to its D-decision, and the two Test Plan Mutation cells
whose text changes as a direct result (TEST-471, D2 rotation — the row was
REPLACED, never deleted).

- **D7 (Spec-AC-01, B1).** Added: the shipping-tree tripwire is now ALSO the
  runner's OWN self-check, not only an assertion the fixture suite makes from
  outside. `mutation-run.mjs` computes a tree hash of the source working tree
  (excluding `docs/ai/tdd/`, the SAME `computeTreeHash` shape D4 step 4 already
  used, now factored into `.aai/scripts/lib/tree-hash.mjs` so both checks read
  one implementation) before building the clone, and again immediately after
  the mutated suite run completes (both the normal-run path and `--replay`).
  A mismatch means the run itself wrote outside its lane — the verdict it
  produced cannot be trusted, so it is downgraded to `INCONCLUSIVE` (normal
  run: recorded, exit 6; replay: counted as a genuine regression, exit 1)
  rather than recorded as RED or STAYED GREEN. `tests/skills/test-aai-mutation-gate.sh`
  TEST-471 asserts the SAME tree hash from outside the tool (`git status
  --porcelain` alone is blind to a content change in an already-dirty tracked
  file — D7's original gap). TEST-471's Mutation cell now names the mutation
  that actually reddens this property: an append into the SOURCE tree's copy
  of `--target` after the clone write, the exact defect a runner-internal
  write into the shipping tree looks like.
- **D14 (Spec-AC-11, B3).** Added two things. First, a self-contained record:
  a `--patch` mutation's content is copied beside its `.txt` record, under the
  SAME evidence directory (`docs/ai/tdd/<spec-id>/mutation-<TEST-id>.patch`,
  rotated in lockstep with the record per D2), and the record's `mutation:`
  field is rewritten to name the stored copy — never a path outside the repo
  (e.g. `/tmp/*.patch`), which may not exist on another machine or even
  survive to the next `--replay` on the SAME machine. Second, `--replay`'s exit
  contract gains a fourth path: applying a record's stored mutation is now
  wrapped so a failure to apply it (a missing/unreadable patch, a `git apply`
  error) is caught and printed as `INCONCLUSIVE <TEST-id>: could not apply the
  recorded mutation (...)` rather than an uncaught stack trace — and it is
  counted separately from a record that replayed cleanly but no longer
  reddens. `--replay` exits `1` when at least one record is a genuine
  regression (STAYED GREEN / suite-died-for-another-reason / malformed /
  target gone / the D7 tripwire fired), `4` when the only problem is one or
  more records that could not be REPLAYED at all (an apply failure), and `0`
  only when every record was attempted and still reddens — SPEC-0180 D8's
  rule ("alive", "nothing alive", "I could not tell" must never render as the
  same answer) applied a second time, to replay. TEST-487 and TEST-488's
  Mutation cells now name that the patch is stored under the evidence
  directory at mutation time, not a `/tmp` path.
- **B2 (Spec-AC-03, no D-decision wording change).** D3's own words already
  said "ONE corpus-level guard that drives EVERY `tests/skills/test-aai-*.sh`
  accepting a selector" and "enumerated from the tree" (TEST-473's cell) — the
  delivered `test_094` read an 18-name hardcoded literal instead. Fixed at
  cause: `test_094` now scans the tree for the idioms this repository's
  suites actually use (a helper `hp_scan_selector_suites`), proved against an
  isolated positive/negative-control fixture before it is trusted against the
  live tree. The mechanical scan is honest about what it found: FOUR MORE
  live suites (`test-aai-doctor.sh`, `test-aai-friction-capture-points.sh`,
  `test-aai-friction-wiring.sh`, `test-aai-product-docs.sh`) carried the exact
  unguarded `"$1"`-with-a-trailing-success-message shape
  `fu-test-selector-unknown-id-passes` describes — real, live fail-opens the
  18-name literal had never covered — each now carries the same named
  `declare -F "$1"` guard the other 18 already do; `test-aai-layer-profiles.sh`
  (NB6, already in the old 18 by accident) gets the same named guard in place
  of its accidental `command not found` (rc 127). No D-decision's wording
  changes: D3 already required this outcome.

Also fixed at cause, no D-decision wording change: NB1 (a dangling untracked
symlink is reproduced as a symlink, never followed, and the clone build is
wrapped so ANY failure removes the tmp clone — not only the two paths that
used to call `rmSync` explicitly); NB3 (`test_483`'s arm C fixture, which
already carries an unfrozen spec beside a frozen one, now pins
`spec_degraded=0` at baseline — the count the `specFrozenInBody` skip exists
to keep at zero); NB4 (TEST-472's leftover-clone count now runs under a
PRIVATE `$TMPDIR`, immune to a concurrent runner elsewhere — the same
`fu-tripwire-attributes-concurrent-writes` class D7 already names); NB5
(`extractSelectors` strips heredoc bodies before matching, so a fixture suite
that WRITES another suite's source as heredoc text no longer leaks that
text's function names into its own selector grammar — closes the duplicate
`test_9002_farewell` suggestion); the Windows/sh-less hazard named in round 1
now degrades by name (`runSuite` reports a distinct `spawnError` shape,
surfaced as `INCONCLUSIVE: bash not found (...)`) rather than being
misread as exit 124; submodule non-reproduction and concurrent-runner
last-writer-wins are named as LIMITS in the runner's own header comment,
unchanged in behavior (round 1 accepted both as-is). NB2 (Spec-AC-12): the
undisclosed-amendment refusal's printed `spec-amend.mjs add` remedy now
carries the offending spec's own frontmatter id as `--ref` and a real default
sentence for `--what`/`--why` — no `<placeholder>` token — so Spec-AC-12's
"run VERBATIM" is exercised literally by TEST-482, which now runs the printed
line with zero substitution. NB7 and NB8 needed no action (round 1 already
recorded them as not-this-ride / expected in-flight state).

`SPEC-FROZEN: true` is preserved; nothing above moves or deletes an existing
AC's or Test Plan row's text outside the two named Mutation cells (TEST-471,
487, 488), which are edited in place per D2's own rotation rule — the OLD
record for each is rotated aside, never deleted, and this section is the
disclosure of why the new one differs from what was frozen.

Authority: `docs/ai/decisions.jsonl`, `type: spec_amendment`,
`ref_id: mutation-gate-for-tests`, `--signoff none`.

### Cross-ride fixture reconciliation (full sweep on d4274359)

- `tests/skills/test-aai-branch-guard.sh` TEST-408 pinned ONE pre-change file
  (`branch-guard.mjs`, a blob) and extracted its importers from the moving
  `origin/main`; once CHANGE-0180 merged (PR #381) main's
  `check-committed-scope.mjs` imported `checkBranchPin`, which the pinned
  blob does not export, and the arm died on a module error ("exit code changed
  with no pin (old 1, new 0)") in every isolated clone — a latent red on main
  itself. The pre-change side is now one consistent tree
  (`PRE_CHANGE_0180_COMMIT`, the last main commit before PR #381), every
  ceremony script and lib extracted from it, the blob pin cross-checked
  against it, and a lib absent at that commit is absent rather than an empty
  file. Reddens when the new script prints one extra line with no pin
  (observed).
- `lib/mutation-record.mjs` named the heartbeat in a comment; the heartbeat
  corpus guard (`test-aai-heartbeat.sh` TEST-012) counts mentions, not seams.
  The comment says "liveness slot" now; no seam was ever there.

Authority: `docs/ai/decisions.jsonl`, `type: spec_amendment`,
`ref_id: mutation-gate-for-tests`, `--signoff none`.

### Full sweep on dedaf385 — the suite must not skip itself

- `test-aai-mutation-gate.sh` TEST-486 arms B/C read the live, gitignored
  evidence tree and used `log_skip` when it was absent; `log_skip` is exit 42
  and voids the whole suite, so in the sweep's isolated clone (and in CI) the
  gate's own suite reported SKIP and proved nothing. The arms now degrade by
  name (`DEGRADED (named): evidence tree absent …`) and arm A, which produces
  its own records with the runner, carries the ancestry proof. Sweep: 94/95
  with the skip; the suite passes in the isolated clone after the change.

Authority: `docs/ai/decisions.jsonl`, `type: spec_amendment`,
`ref_id: mutation-gate-for-tests`, `--signoff none`.

### Remediation round 2 (2026-09-14 — validation round 2 PASS, non-blocking findings folded in)

Validation round 2 (`docs/ai/tdd/spec-mutation-gate-for-tests/validation-round2.txt`)
PASSED with ten named NON-BLOCKING observations (NB1-r2..NB10-r2). Five are
fixed at cause in this round, each with a test a mutation reddens; the
remaining five needed no action, as the validator itself already recorded
(NB1-r2 defence-in-depth with no test of its own, NB5-r2/NB9-r2/NB10-r2
disclosed-and-clean, NB8-r2 disclosed design — see below).

- **NB2-r2 (D7, Spec-AC-01/Spec-AC-11).** The D7 tripwire (before/after tree
  hash of the source tree) cannot distinguish the run's OWN write from a
  CONCURRENT EDITOR's — another process touching the source tree while a run
  is in flight (AAI's own full-sweep workflow does exactly this). It already
  failed closed (INCONCLUSIVE, never a false RED); the gap was that
  `--replay` counted a D7 trip into `failures` (a genuine-regression signal,
  exit 1), directly against the ride's own D6/D8 rule ("I could not tell"
  must never render as "regression"). Fixed at cause: `mutation-run.mjs`
  `buildIsolatedClone()` now keeps the per-file hash map
  (`tree-hash.mjs` `computeTreeFileHashes`/`hashFromFileHashes`, new exports
  alongside the existing `computeTreeHash`/`listTreeFiles`) it derives the
  summary hash from, not only the summary hash itself; both the normal-run
  D7 self-check and `--replay`'s own D7 self-check now diff the before/after
  maps (`diffTreeFileHashes`/`describeTreeDiff`, also new in
  `tree-hash.mjs`) and name the changed path(s) in the INCONCLUSIVE message
  ("the source tree changed during this run (this run, or another writer) —
  changed: \<path\>"). `--replay`'s D7-trip branch now increments
  `inconclusive` (exit 4) instead of `failures` (exit 1) — SPEC-0180 D8's
  three-way rule applied to replay a second time, this time correctly. The
  runner's own LIMITS header gains the disclosure this fix makes true: "the
  tripwire cannot distinguish the runner's own write from a concurrent one;
  it fails closed and names the changed path(s)." TEST-481 gains a fifth arm
  (a background writer touching a tracked marker file while replay runs a
  deliberately slow selector) — see the Test Plan row for the exact mutation
  that reddens it.
- **NB3-r2 / NB4-r2 (Spec-AC-03, `stripHeredocs`).** `stripHeredocs`
  (extractSelectors' own heredoc-body filter, added in remediation round 1
  for NB5) had no test of its own — disabling it regressed the
  unknown-selector suggestion list back to round 1's exact NB5 shape with no
  suite turning red. Separately, an UNTERMINATED heredoc (no line before EOF
  equals the marker) swallowed every line after its opener to EOF, silently:
  a real selector defined after a stray `<<MARKER` would be refused as
  unknown with no trace of why. Fixed at cause (the two share one function,
  so one test arm each): `stripHeredocs` now looks ahead for the terminator
  BEFORE consuming any lines; when none is found before EOF, the heredoc is
  treated as NO heredoc at all — the opener line and everything after it is
  left for the normal per-line scan, so a real trailing selector is still
  found (the alternative, closing at EOF, would make one stray `<<MARKER`
  anywhere in a suite blind this tool to every real test defined after it —
  a worse failure mode than occasionally scanning a few lines of undelimited
  heredoc text). New TEST-491 covers both: arm A plants
  `test_9002_farewell() {` inside a heredoc body and asserts it never
  appears in the nearest-selector suggestions; arm B plants an unterminated
  heredoc with real selectors (`test_bbb`, `test_ccc`) after it and asserts
  they are still found.
- **NB6-r2 (Spec-AC-03).** Four of this ride's own 21 records
  (TEST-478/TEST-479 -> `test-aai-spec-lint.sh`, TEST-489 ->
  `test-aai-spec-tools.sh`, TEST-012 -> `test-aai-prompt-diet.sh`) name a
  `selector:` for a suite whose `main()` ignores `$1` and runs every test —
  the verdicts stay honest (the suite genuinely reddened) but the record's
  `selector` field does not isolate what it appears to. Fixed at cause:
  `mutation-run.mjs` re-implements, BY HAND, the same six command-position
  idioms `tests/skills/test-aai-hygiene-pack.sh` `hp_scan_selector_suites`
  (B2's own corpus scanner, TEST-473) detects — re-implemented rather than
  called via a shared bash lib, because `hp_scan_selector_suites` is bash
  and this check runs from `mutation-run.mjs`'s own Node process at
  record-write time, against the suite text `extractSelectors` already read;
  the two lists are kept in sync by hand, with `hp_scan_selector_suites`'s
  own corpus test (`test_094`) as the authority for the live tree. Every new
  record now carries an OPTIONAL `selector_honoured: yes` /
  `selector_honoured: no (suite runs every test)` header field
  (`lib/mutation-record.mjs` `formatRecord` writes it only when the caller
  supplies it; `parseRecord` needed no change — it already keys header
  fields by name and accepts any line's key, so an older record without the
  field still parses as v1) and prints a one-line `NOTE:` to stdout on the
  "no" branch. The field is deliberately NOT added to `HEADER_FIELDS`
  (mutation-gate.mjs's D8 satisfaction criteria stay unchanged — this is
  observability, not a new gate requirement), so the other 17 live records
  need no regeneration; TEST-478, TEST-479, TEST-489 and TEST-012 ARE
  regenerated with the identical mutation, suite, selector and target
  already frozen in their Mutation cells (D2 rotation — same verdict, same
  evidence, now carrying the field) so the record shape catches up honestly
  with what validation already observed. New TEST-493 covers both directions
  (a non-dispatching fixture suite -> "no" + NOTE; a `declare -F "$1"`
  fixture suite -> "yes").
- **NB7-r2 (D2, D14, Spec-AC-11).** A rotated record's `mutation:` field kept
  naming the LIVE patch file, not its own rotated copy — `rotateExisting`
  renamed the `.txt` and `.patch` files in lockstep but never rewrote the
  text inside the rotated `.txt`, so the comment at `mutation-run.mjs`
  (rotateExisting, "a rotated record's mutation stays reproducible too") was
  false the moment a SECOND `--patch` run landed on the same test id: the
  rotated record's `mutation:` line still pointed at the live `.patch` name,
  whose bytes now belonged to the NEXT run. No live path was affected
  (`--replay` reads only the live `.txt`), but a hand-replay of an archived
  rotated record would silently apply the wrong patch. Fixed at cause:
  `rotateExisting` now rewrites the rotated text's `mutation: patch:...` line
  to name the rotated patch's own repo-relative path (single
  `String.replace` against the exact frozen line shape, everything else
  byte-identical) before writing the rotated `.txt` and renaming the
  `.patch` alongside it — the comment's claim is now true. New TEST-492
  produces two `--patch` records for the same test id and asserts the
  rotated record's `mutation:` field resolves to a file whose bytes equal
  the FIRST patch, never the live name.
- **NB8-r2 (D8, disclosed design — no test, per the finding's own
  disposition).** `mutation-gate.mjs` gains one paragraph in its own header
  naming the limit directly: the gate reads Test Plan ROWS, not the suite's
  own text, so a renamed selector clears a satisfied record's gate at PASS
  (only `--replay` re-runs the recorded mutation and can catch that
  staleness); `close-work-item.mjs` runs the gate, not `--replay`, so a
  "GATE PASS" is proof a record satisfying the row's shape was once
  produced, never proof the evidence is fresh.
- **Not actioned, per validation round 2's own disposition (no D-decision
  wording change, no test needed):** NB1-r2 (the runner's D7 self-check is
  defence-in-depth; TEST-471's own tree-hash assertion already covers the
  property from outside the tool); NB5-r2 (the shell-side corpus scanner's
  false-positive idioms are fail-CLOSED and no live suite trips them today —
  candidate follow-up territory, not a defect this ride's own Test Plan
  claims to cover); NB9-r2 (docs-audit `--gate`'s nineteen Rule-1
  non-terminal rows are the expected shape of an in-flight `implementing`
  spec, deferred to the close ceremony per `VALIDATION.prompt.md`'s own AC
  STATUS GATE carve-out); NB10-r2 (round 1's NB7 — branch-guard red in a
  clone — is confirmed gone, nothing to re-fix).

`SPEC-FROZEN: true` is preserved; nothing above moves or deletes an existing
AC's or Test Plan row's text — TEST-481's Mutation cell gains a sentence
disclosing its new fifth arm and mutation (D2: the row's evidence is
regenerated for the SAME test id, rotating the prior record aside, never
deleted), and three new rows (TEST-491, TEST-492, TEST-493) are added for
properties this round newly covers.

Authority: `docs/ai/decisions.jsonl`, `type: spec_amendment`,
`ref_id: mutation-gate-for-tests`, `--signoff none`.

### Remediation round 3 (2026-09-14 — code review PASS + validation round 3 PASS, non-blocking findings folded in)

Code review (`docs/ai/reviews/review-mutation-gate-for-tests-20260914T154613Z.md`,
overall PASS, 9 NON-BLOCKING findings) and validation round 3
(`docs/ai/tdd/spec-mutation-gate-for-tests/validation-round3.txt`, PASS at
04b50286, 9 NB findings) both passed with named non-blocking findings. Two —
B1-r3 (a corpus-guard word) and NB9-r3 (a hardcoded 60s ceiling) — were already
fixed in the worktree before this round began (commit 2d4a3241) and are not
repeated here. NB8-r3 needed no action (an in-flight spec's own expected
Rule-1 state, per `VALIDATION.prompt.md`'s AC STATUS GATE carve-out). Of the
rest, six are fixed at cause in this round, each with a NEW Test Plan row a
mutation reddens; three are FILED as follow-ups (their fix is a different
scope's surface, or the finding's own disposition asked for a registry item
rather than a code change); one (NB-8) is a one-line prose correction.

- **NB-1 (Spec-AC-09, `lib/docs-model.mjs` `resolveTestPlanHeaderKey`).**
  `TEST_PLAN_HEADER_MAP` was a CLOSED exact-match map, so a header cell
  spelled differently than the template's own (SPEC-0062's own "File path
  (existing suite)") silently yielded `''` for that whole column. Fixed at
  cause: a new `resolveTestPlanHeaderKey` prefix-matches the columns measured
  to vary with a parenthetical suffix or vendor wording (`test id*`,
  `spec-ac*`, `file path*`, `mutation*`, `status*`; `type`/`description` stay
  exact — neither varies in the corpus), and a column that STILL resolves to
  nothing falls back to its CHANGE-0120 fixed position (0-3) only for the
  four byte-identical keys, never silently dropping a cell. A genuinely
  unrecognized header cell on an IN-FLIGHT spec is now a new
  `test-plan-header-unmapped` spec-lint finding, naming the cell. TEST-494
  covers both directions, deliberately placing the file-path column at a
  NON-canonical position so the positional fallback cannot mask a broken
  resolver.
- **NB-2 (Spec-AC-14, `spec-amend.mjs` `scanSpecAnchors`).** `walk()` returns
  `[]` for a missing directory (shared behavior with every other walk()
  caller, so walk() itself was not the thing to change) — `list --strict`
  from the wrong cwd, or with a typo'd `--specs-dir`, scanned NOTHING and
  still printed `spec_degraded=0`, exit 0: indistinguishable from a clean
  corpus, exactly the failure this spec's own Isolation section names. Fixed
  at cause: `list --strict` now refuses (exit 2, naming the path) when
  `--specs-dir` does not exist, and `spec_scanned=<n>` is printed beside
  `spec_degraded` on every strict run, naming how many frozen specs were
  actually looked at. TEST-495.
- **NB-3 (Spec-AC-11, `mutation-run.mjs` `replay()`).** A
  `buildIsolatedClone()` failure during `--replay` — a concurrent writer
  touching the source tree between the hash and the clone build, THIS RIDE's
  own documented operating mode — was counted as `failures++` (exit 1, "a
  genuine regression"), the exact conflation NB2-r2 fixed 45 lines below for
  the in-run trip. Fixed at cause: the clone-build catch block now increments
  `inconclusive` instead, with the same INCONCLUSIVE message shape as the
  sibling branches. TEST-496.
- **NB-5 (Spec-AC-01, `lib/tree-hash.mjs` / `mutation-run.mjs`).** The D7/D4
  tree hash covered tracked files plus untracked-not-ignored files only, so
  it was BLIND to every OTHER gitignored path outside `docs/ai/tdd` — D7's
  own prose claim ("byte-identical outside docs/ai/tdd afterwards") was
  narrower than it read. Fixed at cause (disclosed inline in D7 above): a
  named `RUNTIME_ALLOWLIST` (`docs/ai/STATE.yaml`, `docs/ai/LOOP_TICKS.jsonl`
  — hashed when present, never a blanket "every gitignored path")
  `listTreeFiles` now includes. Fixing this exposed a SECOND, undisclosed
  defect the fix itself would otherwise have shipped: `buildIsolatedClone`
  never copied these newly-hashed paths INTO the clone, so every real run in
  a checkout carrying `docs/ai/STATE.yaml` would have spuriously refused
  (`clone tree hash does not match... removed: docs/ai/STATE.yaml`) —
  caught by running this ride's own ceremony against itself (measurement:
  reproduced live, before the fix, while producing TEST-494's record) and
  fixed in the same commit (`buildIsolatedClone` now reproduces
  `RUNTIME_ALLOWLIST` paths the same way it reproduces an ordinary untracked
  file). TEST-497.
- **NB-7 (Spec-AC-05, `mutation-gate.mjs`).** No exemption existed for a Test
  Plan row whose Status cell is a terminal-not-green value (`deferred`,
  `dropped`, `rejected`) — a ride that truthfully deferred or dropped a row
  could only satisfy the gate by fabricating a RED record or deleting the
  row. Fixed at cause (disclosed inline in D8 above): such a row is now
  EXEMPT, named `EXEMPT <TEST-id>: status <value>` in the output, excluded
  from the satisfied count. TEST-498.
- **NB-8 (CHANGELOG.md).** The shipped release note claimed "all 21 rows
  RED-recorded"; the delivered gate already reported 24 (remediation round 2
  added TEST-491/492/493). Corrected in place to name the CURRENT row count
  this round's own gate run reports (35, after TEST-494..504) — see
  `## Evidence contract` / `gate-close.txt`.
- **NB1-r3 (Spec-AC-01, mutation-free survivor).** Round 2's own claim ("BOTH
  the normal-run D7 self-check and `--replay`'s own D7 self-check now diff
  the before/after maps and name the changed path(s)") was true in code but
  only the `--replay` half had a test (TEST-481 arm 5) — the NORMAL-run half
  was delivered but unguarded. TEST-499 closes it: a concurrent editor of a
  tracked file during a normal (non-replay) slow-selector run is caught
  (exit 6) and the message names the changed path, exactly like `--replay`'s.
- **NB2-r3 / NB3-r3 (Spec-AC-04 / Spec-AC-11, `rotateExisting`).** Two
  residual shapes in the D2/D14 rotation mechanics, both measured by
  validation round 3's own probes and both fixed at cause here. First
  (NB2-r3): `rotatedFileName`/`rotatedPatchFileName` keyed only on
  `run_at_utc` (ISO to the SECOND), so two rotations sharing one second would
  silently overwrite the earlier archive — `rotatedFileName` now accepts an
  optional monotonic `suffix` (`.1`, `.2`, ...), and `rotateExisting` probes
  for the first free name before writing. TEST-500. Second (NB3-r3):
  `rotateExisting`'s pointer-rewrite used `prevText.replace(re, string)` — a
  STRING replacement, so `$&`/`` $` ``/`$'` inside the rotated path (built
  from the spec's frontmatter `id`, read with no validation) would be
  re-interpreted rather than inserted literally, this repository's own
  LEARNED rule (`js-replace-dollar-quote-corrupts`) naming the exact trap.
  Fixed by passing a FUNCTION replacement instead. TEST-501.
- **NB5-r3 (Spec-AC-04, `lib/mutation-record.mjs` `parseRecord`).**
  `parseRecord`'s tolerance of an unrecognized header key is load-bearing —
  it is what let `selector_honoured` (NB6-r2) ship without regenerating every
  live record — but no test proved it; only the GATE would have caught a
  regression, no SUITE would have. TEST-502 closes it with a hand-built
  record carrying an extra header key, asserting the gate still passes it.
  No code change: the property was already correct.
- **NB6-r3 (Spec-AC-03, `mutation-run.mjs` `stripHeredocs`).** NB4-r2 (round
  2) fixed the case where NO heredoc terminator exists anywhere; it did not
  fix the case where a heredoc opener mentioned inside a full-line COMMENT
  (this repository's own house style: `# example: cat <<EOS`) shares its
  marker with a LATER, legitimate heredoc — the commented mention would
  consume everything up to that later heredoc's own terminator, swallowing
  every selector defined in between (fail-CLOSED: a false "unknown selector"
  refusal, never a silent wrong verdict; not reachable on the live corpus per
  validation's own sweep S2). Fixed at cause: a full-line comment is no
  longer recognized as a heredoc opener. TEST-503.
- **NB4-r3 (Spec-AC-03, `mutation-run.mjs` `POSITIONAL_DISPATCH_PATTERNS`).**
  The Node copy of the six selector-dispatch idioms used `[ \t]` where the
  bash twin (`hp_scan_selector_suites`) matches POSIX `[[:space:]]` (vertical
  tab and form feed included) — measured to be unreachable on the LIVE
  corpus (both scanners agree on every real suite, validation's own sweep
  S1) but real on synthetic input. Fixed at cause: the Node regexes are
  rebuilt from a shared `[ \t\v\f]` class. TEST-504 (in
  `test-aai-hygiene-pack.sh`, alongside its scanner) covers both the corpus
  agreement (the regression guard NB4-r3 itself asks for) and a synthetic
  vertical-tab fixture proving the widened class is load-bearing.
- **NB7-r3 (`rotateExisting`, disclosed design — no test, per the finding's
  own disposition).** `rotateExisting` moved from a single atomic
  `renameSync` of the live record to a `writeFileSync`+`rmSync` pair when the
  D2/D14 pointer-rewrite landed (round 2). Fixed at cause, disclosed here
  rather than tested: the rotated copy is now written to a `.tmp-<pid>-<ts>`
  sibling and `renameSync`'d into place (atomic on the same filesystem, the
  same discipline `spec-freeze.mjs`'s own atomic write uses) BEFORE the live
  record is removed — the worst case after an interruption is both the live
  and the rotated record surviving (a harmless duplicate), never a truncated
  archive and never the live record vanishing before its replacement exists.
  Not tested: reliably simulating a process interruption strictly BETWEEN the
  `renameSync` and the `rmSync` (as opposed to blocking the whole write, which
  old and new code both handle identically) needs process-kill timing this
  ride judged not worth the flake risk — named as a LIMIT rather than
  asserted by a fixture, per the finding's own "if not testable cheaply,
  prose + name the limit" disposition.

FILED, not fixed in this round (own scope, or the finding's own disposition
asked for a registry item): `fu-replay-vanished-target-counter` (NB-4 —
`--replay`'s summary arithmetic disagrees with its own printed INCONCLUSIVE
line for a vanished target; `replay()`'s two-counter split, not this round's
D7/D8/D2 surface); `fu-amend-record-lacks-from-to-hash` (NB-6 — the
`spec_amendment` record carries no `from`/`to` anchor hashes and
`restampSpecAnchor` writes without a tmp+rename; `spec-amend.mjs`'s OWN write
path, adjacent to but distinct from this round's `list --strict` scan fix);
`fu-tdd-block-needs-fail-line-grammar` (NB-9 — `.aai/SKILL_TDD.prompt.md`'s
new BLOCK line is unconditional, but the FAIL-line grammar it depends on is
an AAI-suite convention, not a property of test runners in general; a canon
prose fix, not this round's code surface).

`SPEC-FROZEN: true` is preserved; nothing above moves or deletes an existing
AC's or Test Plan row's text — eleven new rows (TEST-494 through TEST-504)
are added for properties this round newly covers, and D7/D8 each gain one
inline amendment paragraph disclosing the narrowing/exemption their own
prose did not yet state.

Authority: `docs/ai/decisions.jsonl`, `type: spec_amendment`,
`ref_id: mutation-gate-for-tests`, `--signoff none`.

### Validation round 4 — rotation collision probe covers the patch sibling

- NB5-r4: `rotateExisting`'s free-name probe looked only at the rotated
  RECORD name; a rotated `.patch` sitting alone at the next slot (its `.txt`
  gone, or planted by hand) was silently overwritten. The probe now considers
  both names for every suffix and the pair moves together. TEST-500 gained
  the arm (a decoy at the `.1` patch name survives; record and patch land at
  `.2` together; the rotated record's `mutation:` names its own `.2` patch);
  a record-only probe reddens it (observed). TEST-500's recorded mutation now
  names the new loop head (`while \(taken\(suffix\)\) {` → `while (false) {` in the runner's ERE sed, the
  same "drop the suffix" mutation on the renamed condition); the Test Plan
  cell says so.
- NB1/NB2/NB3/NB4-r4 filed as `fu-testplan-fallback-wrong-cell`,
  `fu-deferred-row-empty-mutation-cell`, `fu-test439-single-line-guard-grep`,
  `fu-runmain-runs-main-on-import` (P3). NB6-r4: the 95/95 sweep on 4c766047
  is committed with this change.

Authority: `docs/ai/decisions.jsonl`, `type: spec_amendment`,
`ref_id: mutation-gate-for-tests`, `--signoff none`.

### Validation round 5 — the sed dialect is named

- `mutation-run.mjs --help` (and its header) now say that `--sed`'s pattern is
  a JavaScript RegExp, not sed BRE/ERE: `(` groups, `\(` is a literal
  parenthesis, the replacement is literal except JS `$`-patterns, and a no-op
  is refused (NB2-r5). Test Plan Mutation cells name the mutation as the
  runner applies it (TEST-500's escaped form is that convention; NB1-r5).
- TEST-500's cell prose describes the `.2` pair landing (NB3-r5).

Authority: `docs/ai/decisions.jsonl`, `type: spec_amendment`,
`ref_id: mutation-gate-for-tests`, `--signoff none`.

### Remediation round 4 (2026-09-14 — code review round 2 PASS, non-blocking findings folded in)

Code review round 2 (`docs/ai/reviews/review-mutation-gate-for-tests-20260914T213131Z.md`)
PASSED with nine non-blocking findings. Per the review's own H6 disposition
table, this round remediates-in-tree the two with a live operational bite
(NB-1, NB-2), fixes-at-cause a third with a disclosed design limit (NB-3),
and corrects one sentence additively (NB-9). NB-5 is filed, not fixed, per
its own recommended disposition. NB-4, NB-6, NB-7, NB-8 are addressed below
without new code.

- **NB-1 (`lib/tree-hash.mjs`/`mutation-run.mjs`, D4/D7).** See the D7
  amendment above for the full account. Summary: `RUNTIME_ALLOWLIST` stays
  inside the D4 clone-fidelity comparison (`buildIsolatedClone`) but is now
  excluded from the D7 before/after tripwire (`withoutRuntimeAllowlist`,
  both the normal-run self-check and `--replay`'s own copy) — a
  canon-permitted concurrent ceremony write to `docs/ai/STATE.yaml` or
  `docs/ai/LOOP_TICKS.jsonl` no longer downgrades a genuine verdict. The
  second window the review named (`buildIsolatedClone`'s allowlist copy
  reading the source a second time, later, than the hash that judges it) is
  closed by hashing the bytes actually copied into the clone, not a second
  read. TEST-497 adjusts: it previously asserted the OPPOSITE outcome (a
  concurrent `docs/ai/STATE.yaml` write must trip the tripwire, INCONCLUSIVE,
  exit 6) — that assertion is now the documented LIMIT, not the tested
  behavior, and is superseded rather than duplicated. Arm 1 covers
  `docs/ai/STATE.yaml`, arm 2 (new) covers `docs/ai/LOOP_TICKS.jsonl`; both
  must stay RED (exit 0) under a concurrent write to their path, and TEST-499
  (a concurrent editor of a TRACKED file) is unchanged and still proves the
  tripwire fires for everything the allowlist does NOT cover. Mutation:
  `withoutRuntimeAllowlist`'s deletion loop disabled (`for (const rel of
  RUNTIME_ALLOWLIST) filtered.delete(rel);` -> `for (const rel of [])
  filtered.delete(rel);`) — both arms redden, the allowlist write downgrading
  the verdict to INCONCLUSIVE again. Record: `docs/ai/tdd/spec-mutation-gate-for-tests/mutation-TEST-497.txt`, verdict RED.

- **NB-2 (`mutation-gate.mjs`, D8; `close-work-item.mjs` `evaluateMutationGate`,
  D12).** See the D8 amendment above for the full account. Summary: an
  all-exempt Test Plan (`exempt.length > 0 && satisfied === 0`) is now its own
  named DEGRADE class, `DEGRADED: every row exempt (n) degraded=n exempt=n`,
  exit 0 unchanged. `evaluateMutationGate` no longer `continue`s past every
  exit-0 gate result unexamined: it reads the gate's own summary line for
  EVERY resolved spec doc and, whenever `exempt=n` is non-zero (an ordinary
  partial-exempt PASS or the new all-exempt DEGRADE class alike), prints a
  WARNING naming the counts — under `mutation_gate: enforce` exactly as under
  `report-only`, since this is never a refusal (the gate did not fail).
  Deliberately NOT widened to D9's own degrade classes (`pre-change spec`,
  `evidence tree absent`, which carry `degraded=n` but never `exempt=n`):
  those stay exactly as silent at the close as they were before this fix — an
  existing, intentional contract this finding was never about (TEST-477 arm
  C proves it still holds). TEST-498 gains arm D (multiple all-exempt rows,
  proving the count is the real row count, not a hardcoded 1) and arm A's
  assertion is corrected to expect the new DEGRADE line instead of the old
  vacuous `GATE PASS: 0 row(s) satisfied`. TEST-477's test function
  (`test_067_mutation_gate_close_wiring`) gains arm E, recorded as its OWN
  Test Plan row, TEST-505 (a distinct mutation from TEST-477's own
  dial-default property, sharing the same selector). Mutations: (gate side,
  TEST-498) the round-4 DEGRADE branch disabled (`if (exempt.length > 0 &&
  satisfied === 0) {` -> `if (false) {`); arms A and D redden. (close side,
  TEST-505) the exit-0 notices surfacing disabled (`if (notices.length === 0)
  return { severity: 'none' };` -> `if (true) return { severity: 'none' };`);
  arm E reddens. TEST-498's LIVE record now targets the round-4 branch
  specifically (the round-3 `EXEMPT_STATUSES` mutation is preserved as a
  rotated record per D2 — never deleted — and remains provable: arms A-C
  still require the exemption to hold). Records:
  `docs/ai/tdd/spec-mutation-gate-for-tests/mutation-TEST-498.txt` and
  `mutation-TEST-505.txt`, both verdict RED.

- **NB-3 (`mutation-run.mjs` `rotateExisting`, disclosed design — no
  mutation-recorded test, per the finding's own disposition).** The patch
  sibling was renamed AFTER the live record was removed (`rmSync(live)` then
  `renameSync(livePatch, rotatedPatchAbs)`), leaving a window where a process
  death between the two left a rotated record on disk naming a rotated patch
  that did not exist yet, and an orphan live patch the NEXT run's
  `storePatchCopy` would silently overwrite — the rotated archive
  permanently unreproducible. Fixed at cause: the patch sibling now moves to
  its rotated location FIRST, before the record is rotated and before the
  live record is removed, so by the time any rotated record can exist on
  disk its named rotated patch already does too. Not mutation-tested, same as
  NB7-r3's own sibling ordering claim: the property is only observable by
  interrupting the process strictly between two syscalls, which this ride
  again judges not worth the flake risk of simulating reliably — a normal
  (uninterrupted) run produces the identical FINAL on-disk state regardless
  of which order the two renames happen in, so no mutation of the ordering
  itself can redden a test that only checks final state. Documented instead
  as an invariant, checked via final state: TEST-492 gains an assertion that
  the rotated `.patch` sibling exists, BY NAMING CONVENTION (independent of
  what the rotated record's own `mutation:` pointer claims), whenever the
  rotated `.txt` does — the existing TEST-492 mutation (disabling the
  pointer rewrite) still reddens the row.

- **NB-9 (spec `:1649`).** The round-4 (rotation-collision) amendment's own
  prose called the `--sed` dialect "the runner's ERE sed"; round 5's
  amendment and the tool itself (`mutation-run.mjs --help`, `:16`) say
  JavaScript RegExp, not sed BRE/ERE. Corrected additively, per this spec's
  own convention (the frozen sentence at `:1649` is left in place, never
  edited): that sentence was WRONG about the dialect name — the escaped
  `\(` form it quotes is correct either way (a literal parenthesis reads
  identically in both dialects), which is why the recorded mutation still
  applies and TEST-500 stays green — but "the runner's ERE sed" should read
  "the runner's JavaScript RegExp `--sed`", exactly as round 5 already
  corrected everywhere else in this document and in the tool's own `--help`.

FILED, not fixed in this round (own disposition asked for a registry item,
not a rushed edit): `fu-sed-replacement-dollar-trap` (NB-5 — `applySedExpr`,
mutation-run.mjs:324, still uses the STRING form of `String.replace`, the
same trap NB3-r3 already fixed 210 lines below it in `rotateExisting`; a
Mutation cell containing `$'`-shaped text would splice corrupted bytes into
the clone's target and record a FALSE RED that replays forever; fix is a
design question — function replacement vs. escaping the parsed replacement —
left for a dedicated round, not this one).

ACCEPTED RESIDUALS, no action (per the review's own H6 disposition): NB-6
(`tests/skills/test-aai-mutation-gate.sh` TEST-497/TEST-499 are
timing-tuned against a `sleep 1`/`sleep 3` margin; a CI-only red on a
correct product — exit 3 instead of exit 6, both refusals — costs less to
re-run than the synchronization machinery to eliminate it would cost to
build); NB-7 (`mutation-run.mjs:106`'s imported `isRotatedFileName` is
unused — replay's two inline regexes are correct today and nothing is
misclassified; a future drift risk, not a live defect). NB-8 (19 Spec-AC
rows still `planned` at 225a1284) is the orchestrator's own close step
(`## Acceptance Criteria Status` reconciliation before `close-work-item.mjs`
runs) — no remediation action.

`SPEC-FROZEN: true` is preserved; nothing above moves or deletes an existing
AC's or Test Plan row's text outside the disclosed in-place edits to
TEST-497, TEST-498 and TEST-477's Description cells (naming the changed
behavior/new sibling row, never changing what property each row tests at
its core) — ONE new row, TEST-505, is added.

Authority: `docs/ai/decisions.jsonl`, `type: spec_amendment`,
`ref_id: mutation-gate-for-tests`, `--signoff none`.

### Remediation round 5 (2026-09-15 — validation round 6 FAIL, BLOCKING-1 + NB1-r6..NB6-r6)

Validation round 6 (`docs/ai/tdd/spec-mutation-gate-for-tests/validation-round6.txt`)
FAILED: BLOCKING-1 — TEST-490's recorded mutation went stale the moment the
round-4 re-pin (`17f97f15… -> e5c3fd39…`) added a NEW live allowlist entry;
the record's sed still nulled the now-HISTORICAL `17f97f15…` line, so the
LIVE entry stayed unaffected and the mutated tree kept asserting OK —
`--replay` was 35/36 rc 1 while `mutation-gate.mjs --spec` still read `GATE
PASS 36/36`, because the gate re-READS records and never re-RUNS them
(NB8-r2's own disclosed limit, now a live escape rather than a theoretical
one). Six findings, fixed at cause, each with a TEST a mutation reddens:

- **D8 amendment — stale records are visible to the gate.** Every NEW
  mutation record now carries an OPTIONAL `target_sha256: <sha256 of the
  target file at record time>` header field (`lib/mutation-record.mjs`,
  the same optional-field precedent `selector_honoured` set — an older
  record without it still parses as v1). `mutation-gate.mjs`: when the field
  is present and the LIVE target's sha256 differs from it, the row is
  OFFENDING with the class `STALE <id>: target <path> changed since the
  record — re-run mutation-run.mjs (or --replay) for this row`; when the
  field is absent, the record is counted in a named `unstamped=n` degrade
  (a `NOTE:` line, never blocking, exit 0 unchanged) — both `GATE PASS` and
  `GATE FAIL` summary lines now always carry `unstamped=<n>` alongside
  `degraded=<n>`. `close-work-item.mjs`'s `evaluateMutationGate` needs no
  change for this half: an OFFENDING STALE row is exactly the same shape as
  any other offending row, so it already refuses under `mutation_gate:
  enforce` through the existing offending-path logic. `mutation-run.mjs
  --replay` also names `(target changed since the record)` beside a STAYED
  GREEN result whenever the record's `target_sha256` no longer matches the
  live target, so the stale-vs-genuinely-fixed distinction is visible there
  too, not only at the gate. New row TEST-506
  (`tests/skills/test-aai-mutation-gate.sh`): an unchanged target's record
  satisfies the gate (`unstamped=0`); editing the target turns the row
  OFFENDING (exit 5, STALE, naming the path and the remedy); re-stamping
  `target_sha256` restores `GATE PASS`; a legacy record with no
  `target_sha256` field is `unstamped=1`, never mistaken for stale, exit 0.
  Mutation: drop the comparison (`if (liveSha256 !== f.target_sha256) {` ->
  `if (false) {`) — the changed-target arm must redden. Record:
  `docs/ai/tdd/spec-mutation-gate-for-tests/mutation-TEST-506.txt`, verdict
  RED. Every record of this spec is then REGENERATED with the runner so all
  37 rows (the 36 existing plus TEST-506 itself) carry the field: final
  state is `mutation-gate.mjs --spec` `GATE PASS`, `unstamped=0`,
  `--replay` 37/37 RED, rc 0.

- **BLOCKING-1 — TEST-490's mutation is re-pin-proof.** The recorded
  mutation no longer nulls one hard-coded historical allowlist hash (which
  the NEXT re-pin can silently strand, exactly as happened here); it instead
  disables `close_work_item_pin_assert` itself, regardless of which entry is
  currently live: `sed:s/close_work_item_pin_assert() {/close_work_item_pin_assert()
  { return 1;/` on `tests/skills/lib/close-work-item-pin.sh` (no `^` anchor —
  the runner's single-line sed emulator has no multiline flag, and the
  substring is unique in the file; the replacement stays on the SAME source
  line as the opening brace, so the unchanged body below is unreachable but
  still syntactically valid bash — confirmed with `bash -n` on the mutated
  file). Verified by hand (sourcing the mutated file directly and calling the
  function) that TEST-490 reds under it: `close_work_item_pin_assert` returns
  1 with empty stdout before it ever reads a hash, so
  `test_034_mutation_gate_pin_recut`'s own assertion
  (`result="$(close_work_item_pin_assert "$PROJECT_ROOT")" || log_fail ...`)
  fails on the non-zero exit and the empty `$result`. The Test Plan's
  TEST-490 Mutation cell is updated
  in-place (additively disclosed, the row's own core property —
  `close_work_item_pin_assert` must accept the live, edited
  `close-work-item.mjs` — unchanged); the record is regenerated.

- **NB3-r6 — the OFFENDING path's reason silently dropped notices.**
  `close-work-item.mjs` ~`:1216`: `evaluateMutationGate`'s refuse/warn
  `reason` on the offending path was built from `offending` alone, so a
  spec carrying BOTH offending rows and a non-zero `exempt` count printed
  only the offending rows and lost the `exempt=n` the D8 amendment
  (`:548-553`) says the close prints "whenever exempt is non-zero" — the
  exit-0 (no offending) path already appended `notices` to its own reason;
  only the offending path diverged. Fixed by appending the SAME
  notices-derived text to the offending-path reason when `notices.length`
  is non-zero. TEST-505 (see below) gains arm B: a MIXED offending+exempt
  spec refuses under `enforce`, and the REFUSED reason names both the
  offending row and `exempt=1`. Mutation: drop `notices` from the reason
  (reverting the `notices.length ? … : offendingReason` join back to
  `offendingReason` alone) — arm B must redden, the mixed-spec refusal
  losing its `exempt=1` mention. `close-work-item.mjs` is then RE-PINNED
  LAST, after this edit, in `tests/skills/lib/close-work-item-pin.sh` — a
  new itemized entry re-affirming both frozen invariants (the exit contract
  0-8 unchanged; the D6 snapshot/rollback transaction and its four
  best-effort regen calls untouched).

- **NB1-r6 — the D4 second window is now load-tested, not only
  mutation-tested.** `docs/specs/…md:493-497`'s own citation of TEST-497 for
  the D4 second-window fix (`buildIsolatedClone` hashing the bytes it
  ACTUALLY copies into the clone rather than trusting the earlier
  `computeTreeFileHashes(ROOT)` snapshot) was accurate about what the code
  does but not about what the test covers — round 4's own mutation (deleting
  the `sourceTreeFiles.set(rel, createHash…)` line) left TEST-497 fully
  GREEN, a mutation-free survivor exactly like NB-3's disclosed rotation
  ordering. Closed with a THIRD arm on TEST-497: a rapid (~50ms interval)
  appender writes to the SOURCE `docs/ai/STATE.yaml` for the WHOLE run
  (clone build through suite exit), not one well-timed write. Verified by
  hand, run 5 times: shipped code records RED (exit 0) five times out of
  five; the mutant (reverting the D4 fix) throws `TreeMismatchError …
  changed: docs/ai/STATE.yaml` (exit 3) five times out of five — not flaky
  at this density, so the interval was left at 50ms. The D7 section above
  (`:493-497` citation) is corrected in place to name arm 3 and the
  "Remediation round 5" section.

- **NB6-r6 — TEST-505 gets its own selector.** Round 4 recorded TEST-505 as
  arm E of TEST-477's own `test_067_mutation_gate_close_wiring`, sharing
  that function's selector — a drift risk: a future edit to arm A-D's FAIL
  text that happened to mention "TEST-505" (or vice versa) could silently
  swap which record a red run is attributed to. TEST-505 now has its own
  test function, `test_068_mutation_gate_all_exempt_notice`
  (`tests/skills/test-aai-close-work-item.sh`), covering the all-exempt
  vacuous-pass WARNING (arm A, unchanged property) and the new mixed-arm
  refusal reason (arm B, NB3-r6 above). TEST-477's own function keeps only
  arms A-D. Record regenerated against the new selector.

`SPEC-FROZEN: true` is preserved; nothing above moves or deletes an existing
AC's or Test Plan row's core property outside the disclosed in-place edits
to TEST-490's and TEST-505's Description/Mutation cells (naming the changed
mutation/selector, never changing what property each row tests at its
core), the D7/D8 sections' evidence citations, and TEST-497's own
Description cell (naming the new arm 3) — ONE new row, TEST-506, is added.

Authority: `docs/ai/decisions.jsonl`, `type: spec_amendment`,
`ref_id: mutation-gate-for-tests`, `--signoff none`.

### Remediation round 6 (2026-09-15 — validation round 7 PASS, NB1-r7..NB6-r7)

Validation round 7
(`docs/ai/tdd/spec-mutation-gate-for-tests/validation-round7.txt`) PASSED —
0 BLOCKING — with six non-blocking findings, all "future-regression coverage
/ diagnostic wording" class. Each is fixed at cause, each with a TEST a
mutation reddens:

- **NB1-r7 — the PRODUCER half of the D8 amendment had no test.** Only
  TEST-506's hand-built record exercised the CONSUMER side (`mutation-gate.mjs`
  reading `target_sha256`); nothing anywhere asserted that a record PRODUCED
  by `mutation-run.mjs` (`:691,794`) actually carries the field, so a producer
  regression (e.g. deleting the stamping line) restored the exact round-6
  blind spot with no red anywhere — a mutation confirmed this (M7,
  validation round 7). New row TEST-507
  (`tests/skills/test-aai-mutation-gate.sh`, `test_506_gate_detects_stale_target`):
  drives the REAL runner against an isolated git fixture and asserts a
  freshly produced record's `target_sha256` equals `shasum -a 256` of its own
  target at record time, and that editing the target afterward turns the row
  OFFENDING/STALE at the gate — reached through the producer, never a
  hand-built record. Mutation: delete `target_sha256: targetSha256,` from the
  producer's record fields.

- **NB2-r7 — `--replay`'s OTHER stale symptom printed no note.**
  `mutation-run.mjs:896-900`: when the recorded mutation no longer CHANGES
  the target (`before === after`) replay prints `FAIL … replayed mutation no
  longer changes <target>` and `continue`s — before ever reaching the
  `target_sha256` comparison the D8 amendment added only to the "no longer
  reddens" branch. A target edited after the record was produced is the more
  common way a recorded sed pattern stops matching, so the branch that most
  often means "stale record" carried no hint. Fixed by adding the identical
  `target_sha256` comparison to this branch, appending
  `(target changed since the record)` when it fires. New row TEST-508
  (`tests/skills/test-aai-mutation-gate.sh`, `test_481_replay` arm 6):
  a record whose target is edited so the recorded sed no longer matches
  must carry the note on replay. Mutation: disable the new comparison
  (`if (liveSha256 !== fields.target_sha256) beforeAfterStaleNote` ->
  `if (false) beforeAfterStaleNote`).

- **NB3-r7 — a MISSING target was reported with the CHANGED wording.**
  `mutation-gate.mjs:302-312`: the `try { readFileSync(targetAbs) } catch`
  branch (a DELETED or renamed target) pushed the identical `STALE <id>:
  target <path> changed since the record …` reason used for a genuine hash
  mismatch — naming a cause the gate did not observe. Fixed by giving the
  catch branch its own wording, `target <path> missing`. New row TEST-509
  (`tests/skills/test-aai-mutation-gate.sh`, `test_506_gate_detects_stale_target`):
  a deleted target's record is OFFENDING, named `missing`, never `changed
  since the record`. Mutation: revert the wording back to `changed since the
  record`.

- **NB4-r7 — `unstamped=<n>` never reached the close.** The identical shape
  round 4's NB-2 fixed for `exempt=<n>`:
  `close-work-item.mjs:1186-1203`'s `evaluateMutationGate` captured ONLY
  `exempt=`/`degraded=` from the gate's summary line and pushed a WARNING
  notice only when `exempt` was non-zero — a spec closing with, say, `GATE
  PASS: … unstamped=37` closed with complete silence about it. Fixed by also
  parsing `unstamped=(\d+)` and triggering the same WARNING notice whenever
  either count is non-zero. New row TEST-511
  (`tests/skills/test-aai-close-work-item.sh`,
  `test_068_mutation_gate_all_exempt_notice` arm C): a spec whose only
  record is a LEGACY one (no `target_sha256`) still passes the gate
  (`unstamped=1`, never a refusal), and the close now surfaces that count
  as a WARNING. Mutation: drop the new OR-condition (`if (exemptN > 0 ||
  unstampedN > 0) {` -> `if (exemptN > 0) {`).

- **NB5-r7 — D8's own section text was not amended in place.** Rounds 3 and
  4 each added an inline amendment paragraph inside `### D8`; round 5 added
  none, leaving the "it requires ALL of" list at five conditions, the Exit
  codes paragraph silent about the STALE class, and D9's closing sentence
  silent about `unstamped=<n>`. Fixed in place above (D8 gains a sixth
  bulleted condition and an Exit-codes clause naming STALE; D9 gains a
  closing-sentence amendment naming `unstamped=<n>`) — placement only, the
  property was already specified (via the round-5 section), tested and
  mutation-proven.

- **NB6-r7 — the `NOTE: unstamped=` line's own wording was a mutation-free
  survivor.** `mutation-gate.mjs:195-197`'s NOTE line was never observed by
  any test — only the summary line's shared `unstamped=<n>` substring was
  asserted, so a mutation renaming the NOTE's own token
  (`NOTE: unstamped=` -> `NOTE: skipped=`) stayed GREEN. New row TEST-510
  (`tests/skills/test-aai-mutation-gate.sh`, `test_506_gate_detects_stale_target`):
  asserts the NOTE line's full text, not only the shared substring.
  Mutation: rename the token as above. The three DEGRADE summary lines'
  `unstamped=` omission is left as-is (disclosed, not fixed): the spec
  scopes the token to `GATE PASS`/`GATE FAIL` only (D9's closing-sentence
  amendment above), and every DEGRADE class exits before any row is ever
  read as unstamped, so the count is genuinely, not merely apparently, zero
  there.

All five new rows (TEST-507..TEST-511) are added to the Test Plan, each
mapped to the Spec-AC its property already belongs to (Spec-AC-05 for the
gate-side findings, Spec-AC-11 for the replay-side one, Spec-AC-07 for the
close-side one) — no existing row's core property changes. Every record of
this spec whose target is `mutation-run.mjs`, `mutation-gate.mjs` or
`close-work-item.mjs` (20 of the prior 37, per the D8 amendment's own
`target_sha256` mechanism) is REGENERATED with the runner alongside the five
new ones: final state is `mutation-gate.mjs --spec` `GATE PASS`,
`unstamped=0`, `--replay` 42/42 RED, rc 0.

`SPEC-FROZEN: true` is preserved; nothing above moves or deletes an existing
AC's or Test Plan row's core property outside the disclosed in-place
amendments to D8/D9 (naming the new sixth condition and `unstamped=<n>`,
never changing what any existing row tests at its core) — five new rows,
TEST-507 through TEST-511, are added.

Authority: `docs/ai/decisions.jsonl`, `type: spec_amendment`,
`ref_id: mutation-gate-for-tests`, `--signoff none`.

### Numbering at the PR — the allocator rewrote this spec's own references

- `allocate-doc-number.mjs` numbered the intake (CHANGE-0187) and this spec
  (SPEC-0181) at the PR ceremony and rewrote the draft paths inside this
  frozen body (the `requirement:` link, the Links list, the Isolation file
  list, one sentence naming the spec file). That is a post-freeze body edit by
  a tool, and the strict amendment gate this ride delivered (D11) refused it as
  `undisclosed-amendment` — correctly. This record discloses it; the anchor is
  re-stamped by the `add`. `fu-allocator-rewrites-frozen-spec-body` (P2) tracks
  the structural fix (the allocator is an L3 surface: it should record or
  re-stamp itself, or the contract projection should be invariant to a
  DRAFT → number path rewrite).

Authority: `docs/ai/decisions.jsonl`, `type: spec_amendment`,
`ref_id: mutation-gate-for-tests`, `--signoff none`.

### PR ceremony — the usage-capture gate did not know the field its own canon writes

- `close-work-item.mjs` refused this ride's close under `usage_capture_gate:
  enforce`: all 21 runs "with no usage capture". Every run carries
  `tokens_total` — the FIELD `state.mjs append-run --tokens-total` has written
  since SPEC-0178 (telemetry-fields-not-prose) — but the gate's
  `usageCaptured` read only the prose marker, the decomposed pair and the
  sentinel. `scanAgentRuns` now parses `tokens_total:` and a non-negative
  total is usage capture; null and negative totals are still gaps. TEST-512
  (own function, `test_069_usage_gate_tokens_total_field_passes`); the file is
  re-pinned last; the four records whose targets moved (TEST-477/505/511 on
  `close-work-item.mjs`, TEST-490 on the pin file) were regenerated by the
  runner because the gate called them STALE.

Authority: `docs/ai/decisions.jsonl`, `type: spec_amendment`,
`ref_id: mutation-gate-for-tests`, `--signoff none`.

### Correction to the PR-ceremony amendment (validation round 9 NB3)

- The PR-ceremony paragraph above and its ledger record say four records were
  STALE. Three were: TEST-505 and TEST-511 (target `close-work-item.mjs`) and
  TEST-490 (target the pin file). TEST-477's target is `lib/guard-config.mjs`,
  which did not change; its record was regenerated unnecessarily and its
  `target_sha256` is identical before and after.
- The allocator also rewrote the draft paths inside two historical review
  reports (`docs/ai/reviews/review-mutation-gate-for-tests-*.md`), so one
  quoted command now names SPEC-0181 though the reviewer ran it against the
  draft (NB8). Tracked by `fu-allocator-rewrites-history-docs` (P3).

Authority: `docs/ai/decisions.jsonl`, `type: spec_amendment`,
`ref_id: mutation-gate-for-tests`, `--signoff none`.

### PR #384 bot findings — remediation round 7

Six external bot findings on PR #384 (Codex four, Copilot two), each fixed AT
CAUSE with its own new Test Plan row (TEST-513..TEST-519, one finding —
value-taking-flag usage errors — split across two rows because it touches
two different target files) and a RED mutation record produced by the real
`mutation-run.mjs`:

1. **Codex P1 — a `--patch` could edit files besides `--target`.**
   `mutation-run.mjs`'s `applyMutation` applied a `--patch` file WHOLE, so an
   extra hunk touching the SUITE (or a dependency) could fake a matching FAIL
   line and produce a false RED — the strongest possible evidence for a
   mutation that never actually challenged `--target`. Fixed by parsing the
   patch's own file headers (`diff --git`, `--- a/…`/`--- /dev/null`,
   `+++ b/…`/`+++ /dev/null`, renames) and refusing (exit 2, naming the
   offending path, no record, no clone left) any patch touching a path other
   than `--target`; `--replay` applies the identical check on a stored patch
   (INCONCLUSIVE, named, never silently re-applied). TEST-513.
2. **Codex P1 — an anchor could outlive its own freeze marker.**
   `spec-amend.mjs`'s `scanSpecAnchors` skipped a spec entirely before ever
   comparing its `frozen_sha256` anchor when the body's `SPEC-FROZEN: true`
   marker was absent — so deleting that ONE line silently disabled the
   undisclosed-amendment gate for that spec, forever, with the anchor still
   sitting unread in its frontmatter. A spec carrying `frozen_sha256` is now
   ALWAYS scanned; a carried anchor with no marker is itself a STRICT
   violation (`anchor-without-freeze-marker`), printed with a runnable remedy
   (restore the marker line). TEST-514.
3. **Codex P1 — an escaped pipe inside a Mutation cell shifted table
   columns.** `lib/spec-contract-hash.mjs`'s `blankTableSection` split Test
   Plan/AC rows on a plain `split('|')`; SPEC-0181's OWN TEST-511 row carries
   an escaped `\|` inside its Mutation cell (`if (exemptN > 0 \|\|
   unstampedN > 0) {`), which the plain split miscounted as two extra column
   boundaries — a routine Status flip on that row then changed the CONTRACT
   hash, a false `undisclosed-amendment`. Fixed by reusing
   `lib/docs-model.mjs`'s `splitRawTableCells` — the SAME escaping primitive
   `splitTableCells` (the Test Plan reader) already builds on — rather than a
   second hand-rolled splitter. TEST-515. **This fix changes THIS spec's own
   contract projection** (TEST-511's row is exactly the row it fixes), so
   `frozen_sha256` no longer matches after this round; disclosed by the
   `spec-amend.mjs add` at the foot of this section, which re-stamps it.
4. **Codex P2 — an unreadable spec was silently omitted from the strict
   scan.** A bare `catch { continue; }` in `scanSpecAnchors` meant a spec
   this scanner could not read (a permission change, a race) contributed
   NOTHING to the scan — indistinguishable from a spec that was never there.
   Fixed to fail CLOSED: reported as its own STRICT violation bucket
   (`unreadable-spec`) naming the file, never silently skipped. TEST-516.
5. **Copilot — `--spec` (and siblings) accepted a following flag as their
   own value.** `mutation-gate.mjs --spec --json` swallowed `--json` as the
   (nonexistent) spec path and fell through to a confusing exit 3 "cannot
   read" instead of naming the real defect: the invocation itself. A missing
   value, or a value starting with `--`, is now a usage error (exit 2) in
   BOTH `mutation-gate.mjs` (TEST-517) and every value-taking flag of
   `mutation-run.mjs` — `--spec`, `--test-id`, `--suite`, `--selector`,
   `--target`, `--sed`, `--patch` (TEST-519, same shape, different target
   file, so its own row).
6. **Copilot — a byte-correctness check that could not catch a wrong
   hash.** `tests/skills/test-aai-spec-tools.sh`'s `test_freeze_004_no_h1`
   (the TEST-009(freeze) minimal-fixture arm) read `frozen_sha256` back OUT
   of the file `spec-freeze.mjs` had just written, then built its OWN
   expected output FROM that same value — tautological about the hash's
   VALUE, provably only its byte POSITION. A `spec-freeze.mjs` that wrote the
   hash of the empty string would still have "passed". Fixed by recomputing
   the contract-projection hash INDEPENDENTLY, via `lib/spec-contract-hash.mjs`'s
   own `contractHash()` on the frozen file's bytes, and asserting the stored
   anchor equals it — proved by mutating `spec-freeze.mjs` to write
   `contractHash('')` instead of `contractHash(out)`. TEST-518 (shares
   `test_freeze_004_no_h1`'s own selector; its FAIL line is now dual-labeled
   `TEST-009(freeze) / TEST-518` so `mutation-run.mjs`'s FAIL-line grammar
   can attribute a redden to it).

**Regeneration.** Every current record whose `target` is one of the five
edited files (`mutation-run.mjs`, `spec-amend.mjs`, `mutation-gate.mjs`,
`lib/spec-contract-hash.mjs`, `lib/docs-model.mjs`) went STALE the moment
this round's edits landed and was regenerated by the real runner, re-running
each row's OWN previously-recorded mutation (never re-authored) — 29 rows
across those five targets, plus the 7 new rows above, for 36 fresh RED
records in this round. `spec-freeze.mjs`, `close-work-item.mjs` and the pin
file were NOT edited, so TEST-489 and every `close-work-item.mjs`-targeted
row (TEST-477, TEST-505, TEST-511, TEST-512) needed no regeneration. Two
transient non-RED results surfaced mid-batch and were root-caused, not
papered over: TEST-494's first regeneration attempt tripped its OWN D7
tripwire on a concurrent edit to THIS spec file (made by this same round,
mid-batch) and was re-run clean; TEST-497 (the round-5 "rapid ~50ms
appender" arm, already documented as timing-sensitive) landed STAYED GREEN
once under load and RED on an immediate re-run with the byte-identical
mutation — a flake, not a regression, left as-is.

`node .aai/scripts/mutation-gate.mjs --spec
docs/specs/SPEC-0181-spec-mutation-gate-for-tests.md` now reads `GATE PASS:
50 row(s) satisfied degraded=0 unstamped=0`.

Authority: `docs/ai/decisions.jsonl`, `type: spec_amendment`,
`ref_id: mutation-gate-for-tests`, `--signoff none`.

### Validation round 10 (FAIL) — the patch-scope guard asks git, not a parser

- BLOCKING-1: round 7's `patchTouchedPaths` read only `a/`-`b/` headers.
  `git apply` strips ANY first path component, accepts C-quoted names and CRLF
  header lines, so a second hunk spelled any of those ways was applied unseen
  — the validator forged a RED end to end through the fixture suite, and
  `--replay` re-affirmed it. The hand parser is gone: the touched paths now
  come from `git apply --numstat -z` in the clone (the parser that then
  applies the patch), and any path other than `--target` is refused (exit 2,
  named, no record, no clone left; a named INCONCLUSIVE under `--replay`).
  TEST-513 gained arms C (another prefix, the forged-suite attack verbatim),
  D (C-quoted, TAB in the name) and E (CRLF headers) and a private `TMPDIR`
  for its leftover-clone count. A before/after tree hash of the clone was
  tried as a second guard and dropped: it never fired where numstat had not,
  and it does not see a path git quotes (`fu-tree-hash-blind-to-quoted-paths`).
- NB1: TEST-516's root guard degrades by name instead of `log_skip` (exit 42
  voided the whole spec-amend suite on a root host). NB2: CHANGELOG names the
  re-filed follow-up id. NB3 (TEST-497 arm 3 reddens deterministically when
  unloaded and can stay green under heavy load — fail-closed for the gate,
  noisy for `--replay`), NB4–NB7: recorded in validation-round10.txt, no
  change in this ride.

Authority: `docs/ai/decisions.jsonl`, `type: spec_amendment`,
`ref_id: mutation-gate-for-tests`, `--signoff none`.

### Validation round 11 (FAIL) — numstat names only the post-image; the tree diff is back

- BLOCKING-1: `git apply --numstat -z` prints one record per item with the
  POST-image path only (the round-10 comment described `git diff --numstat
  -z`). A rename whose destination is `--target` therefore read as the target
  three times while deleting `lib/extra.txt`, the file the fixture suite
  checks — a forged RED again, re-affirmed by `--replay`. The before/after
  tree hash of the clone, tried and dropped in round 10, names exactly that
  path; it is restored. The two guards are now each load-bearing: TEST-513
  arm F (rename source) is caught only by the tree diff, arm G (a creation
  under a gitignored path, which the tree hash does not list) only by
  numstat — disabling either guard alone reddens its arm (observed).
- `lib/tree-hash.mjs` lists with `git ls-files -z`: a git-quoted name (TAB,
  quote, non-ASCII) used to drop out of the hash, so the D4/D7 tripwire could
  not see it. `fu-tree-hash-blind-to-quoted-paths` closed by this change
  (arm D is now seen by the tree diff as well as by numstat).
- TEST-513's Description cell is rewritten to describe the shipped mechanism
  (its first sentence still described the deleted parser — round 11 NB2).
- Rounds 10 and 11 both failed in the `--patch` seam. Disclosed here rather
  than split into a new ride: the fix restores a guard the validator asked
  for, and the seam now has one arm per known class (seven).

Authority: `docs/ai/decisions.jsonl`, `type: spec_amendment`,
`ref_id: mutation-gate-for-tests`, `--signoff none`.

