```yaml
review:
  scope: "git diff origin/main..HEAD (0eea891b..8352be61), branch change/roadmap-serves-downstream-projects, 32 paths = STATE code_review.scope"
  spec: docs/specs/SPEC-0202-spec-roadmap-serves-downstream-projects.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/lib/roadmap-model.mjs:49-55; TEST-1301/1302/718 PASS; live validate prints 'roadmap OK: 11 pair(s), 4 wave-2 item(s)'" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/scripts/ride-select.mjs:206-215 noBudgetGate, :357 dispatch after done-ref refusal; TEST-1303/1304/1305 PASS" }
      - { ac: Spec-AC-03, call: compliant, citation: ".aai/scripts/ride-select.mjs nextNoBudget/pickNext (+path in both walkers); TEST-1306/1307/1308 PASS" }
      - { ac: Spec-AC-04, call: compliant, citation: ".aai/scripts/ride-select.mjs cmdShow; TEST-1309 PASS" }
      - { ac: Spec-AC-05, call: compliant, citation: ".aai/scripts/roadmap-edit.mjs:173-304; TEST-1311..1316 PASS; probe: drop of last pair refused exit 1, bytes restored" }
      - { ac: Spec-AC-06, call: compliant, citation: ".aai/scripts/roadmap-edit.mjs:212-228; TEST-1317/1318/1319 PASS" }
      - { ac: Spec-AC-07, call: compliant, citation: ".aai/scripts/roadmap-edit.mjs:290-304; TEST-1320/1321 PASS" }
      - { ac: Spec-AC-08, call: compliant, citation: "TEST-1322 PASS; close-work-item.mjs absent from the diff; test-aai-close-work-item.sh rc=0" }
      - { ac: Spec-AC-09, call: compliant, citation: "TEST-1323 PASS; orchestration-dispatch.mjs untouched; test-aai-orchestration-dispatch.sh rc=0" }
      - { ac: Spec-AC-10, call: compliant, citation: ".aai/scripts/nothing-left-behind.mjs:196-210; TEST-1324 PASS" }
      - { ac: Spec-AC-11, call: compliant, citation: ".aai/scripts/roadmap-propose.mjs buildWriteContent; TEST-1310 PASS" }
      - { ac: Spec-AC-12, call: compliant, citation: ".claude/skills/aai-roadmap/SKILL.md (8 lines) + 3 mirrors; sync --check rc=0; PROFILES core entries; suite-map aai-roadmap row; TEST-1325..1328 PASS; layer-profiles + hygiene-pack rc=0" }
      - { ac: Spec-AC-13, call: compliant, citation: ".aai/SKILL_ROADMAP.prompt.md:15-50; TEST-1329/1330/1340 PASS" }
      - { ac: Spec-AC-14, call: compliant, citation: ".aai/SKILL_SHIP.prompt.md INPUT/1a/step 6; .aai/SKILL_PR.prompt.md 4c bullet; TEST-1331/1332/1338 PASS; downstream-autopilot + golden-flow rc=0" }
      - { ac: Spec-AC-15, call: compliant, citation: "docs/USER_GUIDE.md '## Roadmap: when and how' + TOC; README.md Orientation link; docs/product/roadmap.md; .aai/AGENTS.md rule 4; TEST-1333/1334/1335/1339 PASS" }
      - { ac: Spec-AC-16, call: compliant, citation: "tests/skills/lib/prompt-diet-ledger.sh 4349 B entry; test-aai-prompt-diet.sh rc=0; TEST-1337 PASS (ORCHESTRATION blob = merge-base)" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: docs/USER_GUIDE.md, line: 2169,
          issue: "Mutation records for TEST-1328, TEST-1333 and TEST-1339 are STALE: commit 27c22aa3 (validation NB-A/NB-B fix) changed docs/USER_GUIDE.md after the round-2 replay; mutation-gate.mjs --spec now prints GATE FAIL (3 offending rows)",
          failure_scenario: "SKILL_PR step 4c runs close-work-item.mjs, whose close-time mutation gate spawns the real mutation-gate.mjs; with 3 STALE rows the close refuses and the ride stalls at the PR ceremony" }
      - { rank: NON-BLOCKING, file: .aai/scripts/roadmap-edit.mjs, line: 146,
          issue: "docStatus() reads document status through parseFrontmatter (strips quotes, whole frontmatter) while ride-select.mjs findDoc() reads the raw first-30-line value; the two disagree on what 'done' is",
          failure_scenario: "Reproduced: capability doc with status: \"done\" (quoted). advance flips the pair to done; ride-select next --json (findDoc sees the literal '\"done\"') still names that capability, and gate refuses it only because the pair is now done. The D2 one-parser intent does not cover document status" }
      - { rank: NON-BLOCKING, file: .aai/scripts/roadmap-edit.mjs, line: 175,
          issue: "add on a --roadmap path whose parent is a regular file: roadmapAbsent() treats ENOTDIR as absent, then fs.mkdirSync throws an uncaught exception (stack trace, exit 1) instead of a named usage exit 2",
          failure_scenario: "Reproduced: roadmap-edit.mjs add --ref gamma --roadmap docs/issues/a.md/roadmap.yaml -> node:fs mkdir stack trace; nothing written. Operator-typo path only" }
  cannot_verify:
    - { claim: "S4/R1: the ship-append edit at SKILL_SHIP 1a reaches the close commit via SKILL_PR 4c staging", closes_with: "a real /aai-ship ride on a budget-free downstream project whose PR diff carries docs/ai/roadmap.yaml" }
    - { claim: "D16 id carve (an intake filed for a file-intake ref uses id: <ref>) is followed by an LLM, not only by TEST-1338's ship_noarg model", closes_with: "a live no-argument /aai-ship ride against a roadmap item with no document" }
    - { claim: "CI legs (Ubuntu skill-suite, Windows Pester) are green at 8352be61", closes_with: "gh run conclusions for the PR head" }
    - { claim: "full sweep at HEAD (validation's 98/101 sweep predates 25feb99b, 27c22aa3 and the 8352be61 merge; this review ran 10 selected suites)", closes_with: "one full sweep with AAI_TEST_TIMEOUT=3000 at 8352be61" }
    - { claim: "the dispatch's prompt hash f9761094... matches what this reviewer read", closes_with: "the hashing rule: the instruction file read hashes to 5ef4697a..., so the stated hash is presumably over the assembled payload with the scope section substituted" }
  overall: pass
```

# Code review — roadmap-serves-downstream-projects (round 1 of 2)

- Scope: `git diff origin/main..HEAD`, base 0eea891b, head 8352be61. The 32 changed paths match STATE `code_review.scope` exactly. `git status --porcelain` was clean at start.
- Spec: docs/specs/SPEC-0202-spec-roadmap-serves-downstream-projects.md (frozen, `spec-lint --path` PASS). D16 is an additive amendment, disclosed, recorded with `--signoff none`, and tracked by open `fu-amend-roadmap-serves-downstrea-bc77da` (`spec-amend list --strict`: unsigned-tracked).
- Intake: docs/issues/CHANGE-0201-roadmap-serves-downstream-projects.md. Validation round 2 PASS: docs/ai/reports/VALIDATION-20261001T100543Z-roadmap-serves-downstream-projects.md.
- Dispatch coaching check: the dispatch did not pre-rate findings and did not exclude any area from scope. Nothing to record.

## AC table walk
All 16 Spec-AC rows are compliant (see the YAML above). All 40 TEST rows (TEST-1301..1340) exist. Each has a `verdict: RED` mutation record under docs/ai/tdd/spec-roadmap-serves-downstream-projects/, and both owning suites pass at HEAD.

Suites run by this reviewer at HEAD (all `env -u AAI_ROLE`, rc=0):
- roadmap
- ride-select
- prompt-diet
- layer-profiles
- close-work-item
- downstream-autopilot
- golden-flow
- hygiene-pack
- orchestration-dispatch
- unattended

Other checks run, all clean:
- `ride-select.mjs validate` printed `roadmap OK: 11 pair(s), 4 wave-2 item(s)`.
- `sync-harness-skills --check` rc=0.
- `check-vendored-script-deps` CLEAN.
- `docs-audit --strict` rc=0, with 0 orphans, 0 drifted, 0 stale and 0 false-open.
- All three ledgers keep current origin/main as an exact byte prefix, so validation NB-C is resolved by the 8352be61 merge.

Deviations from the frozen text are listed here even though each one is reasonable:
- The `aai-roadmap` row in suite-map has more globs than Implementation plan item 11. It also lists SHIP, PR, AGENTS, PROFILES, USER_GUIDE, the product doc and README, which are the prose the suite asserts. It is still exactly one row, so Spec-AC-12 holds.
- The Verification section still says "a RED record for each of the 37 rows", but D16 added TEST-1338..1340, so there are 40. All 40 have records.
- The AC Status table still reads `planned` for every row. That is expected: SKILL_PR's "FLIP THE AC TABLE FIRST" step does it.
- D12 asks the prompt to contain `never hand-edit`. The prompt has it only as part of the word "hand-edited" (".aai/SKILL_ROADMAP.prompt.md:4"). TEST-1329 accepts that.

## Findings (code_quality: pass, 0 BLOCKING, 3 NON-BLOCKING)

1. **NB — stale mutation evidence (docs/USER_GUIDE.md:2169).**
   - What is wrong: commit 27c22aa3 edited USER_GUIDE after the round-2 replay. `mutation-gate.mjs --spec` now prints GATE FAIL, with STALE on TEST-1328, TEST-1333 and TEST-1339.
   - How it bites: close-work-item.mjs runs the real mutation gate at close time, so the close ceremony would refuse.
   - Recommended disposition: (a) fix in-tree before the PR step with `node .aai/scripts/mutation-run.mjs --replay --spec docs/specs/SPEC-0202-spec-roadmap-serves-downstream-projects.md`. A replay that still turns these tests red re-stamps the records.
   - Why the reviewer did not run it: it would mutate a tracked file, and HAZ-RESTORE plus the reviewer's read-only status rule that out.
2. **NB — two parsers for document status (.aai/scripts/roadmap-edit.mjs:146).**
   - What is wrong: `docStatus` reads status through `parseFrontmatter`, while ride-select uses the line scan in `findDoc`.
   - How it bites: reproduced with a quoted `status: "done"`. `advance` flips the pair, but `next` still names the capability as unfinished.
   - Severity: P3. No real document in the corpus is known to quote `status`.
   - Recommended disposition: (b) file follow-up `suggested: fu-roadmap-docstatus-two-parsers`. Move `findDoc`/`docStatus` into lib/roadmap-model.mjs so `advance`, `next` and `gate` share one status reader.
3. **NB — uncaught exception on an ENOTDIR roadmap path (.aai/scripts/roadmap-edit.mjs:175).**
   - What is wrong: the absent-file branch of `add` lets `mkdirSync` throw.
   - How it bites: the user gets a stack trace, and the exit code is 1 instead of the documented 2. Nothing is written.
   - Recommended disposition: (d) `accepted residual: P3 operator-typo path, no write, no false record; error surface only.`

INFO (does not gate): `move` and `drop` keep a comment that sits between two pair blocks with the block above it. In a probe, a `# note about beta` comment ended up under `alpha` after `move beta --to 1`. This is covered by disclosed residual R5.

## cannot_verify
See the YAML block: five items.
- S4/R1 is a prose seam.
- The D16 id carve is carried only by prose.
- The CI legs were not checked.
- No full sweep has run at HEAD.
- The prompt hash could not be matched.

## Side effect disclosed
Running `docs-audit.mjs --strict` appended one `docs_audit` telemetry line to `docs/ai/EVENTS.jsonl` (ts 2026-10-01T10:44:36Z, payload all zeros). It is an append-only line and was left in place: HAZ-LEDGER and HAZ-RESTORE forbid reverting it. The orchestrator should commit it with the review-response or close commit, or keep it uncommitted. It must never be restored away.

## Next steps
1. Replay the 3 stale mutation rows (NB-1) before SKILL_PR.
2. Record the dispositions for NB-2 (follow-up) and NB-3 (accepted residual) in `code_review.notes`.
3. Run one full sweep at HEAD before the close ceremony.
4. Owner sign-off on D16 is still owed at the merge checkpoint (`fu-amend-roadmap-serves-downstrea-bc77da`).
