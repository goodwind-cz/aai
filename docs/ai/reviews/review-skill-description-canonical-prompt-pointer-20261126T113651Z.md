# Code review (round 3): skill-description-canonical-prompt-pointer

```yaml
review:
  scope: "c511d47e..c03c93c2 (A7 remediation of three Codex inline findings on PR #596) + cf099af3 (ledger) + merge 8e734e3c (origin/main 9da38865, PR #595); AC table re-walked on the merged tree 8e734e3c"
  spec: docs/specs/SPEC-0318-spec-skill-description-canonical-prompt-pointer.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "live --check at 8e734e3c: rc 0, 'OK: 42 wrapper description(s) name their canonical source'; TEST-4130 PASS (reviewer run)" }
      - { ac: Spec-AC-02, call: compliant, citation: "sync-harness-skills.mjs:365-380 D4 order kept, the duplicate-key test is prepended; TEST-4131 PASS" }
      - { ac: Spec-AC-03, call: compliant, citation: "sync-harness-skills.mjs:312-318 unchanged; TEST-4132 PASS incl. the new duplicate-key case (test-aai-harness-shims.sh:1221-1222)" }
      - { ac: Spec-AC-04, call: compliant, citation: "sync-harness-skills.mjs:369-372 unchanged; TEST-4133 PASS" }
      - { ac: Spec-AC-05, call: compliant, citation: "loadPointerRule unchanged; TEST-4134 PASS" }
      - { ac: Spec-AC-06, call: compliant, citation: "sync-harness-skills.mjs:381-389 (A7 name test + SKIPPED line, marker SKIPPED kept); TEST-4135 PASS incl. deploy-notes and aai-project-deploy SKIPPED cases and the OK 42 count (test-aai-harness-shims.sh:1297-1304)" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-4136 PASS (reviewer run)" }
      - { ac: Spec-AC-08, call: compliant, citation: "SKILL_SHIP unchanged since round 2; TEST-4137 (test-aai-downstream-autopilot.sh) not re-run this round, last green in the 09:37Z sweep; deviation 'three legal endings' disclosed by A6 (round 2)" }
      - { ac: Spec-AC-09, call: compliant, citation: "unchanged since round 2; TEST-4138" }
      - { ac: Spec-AC-10, call: compliant, citation: "TEST-4139 PASS; docs/skill-catalog-data.json regenerates byte-equal except generatedAt (reviewer scratch clone)" }
      - { ac: Spec-AC-11, call: compliant, citation: "CHANGELOG.md:33 heading kept on top of main's onboarding entry; TEST-4140 PASS" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/sync-harness-skills.mjs, line: 309,
          issue: "isAaiWrapperName copies the name test of aai-sync.mjs isRetiredSkillWrapper (aai-sync.mjs:667) by hand (A7 chooses this on purpose); no test pins the two equal",
          failure_scenario: "a later change widens the layer-owned rule in aai-sync.mjs (e.g. a second project-owned prefix) without touching sync-harness-skills.mjs; consumer skills under the new prefix get 'DIVERGE pointer ... lacks the canonical pointer' again, the NB-4 class, and no suite turns red" }
  cannot_verify:
    - { claim: "A model running /aai-ship obeys the END-OF-TURN INVARIANT so #593 does not recur (carried from rounds 1-2)", closes_with: "a recorded /aai-ship ride per harness that ends a turn on a background dispatch and resumes on its notification" }
    - { claim: "Non-Claude harnesses surface the suffix pointer; Codex listing truncation keeps it; Windows leg of the harness-shims tests (carried)", closes_with: "per-harness listing captures and the hosted skill-suite Windows leg on the PR head" }
    - { claim: "Suites touched only by the merge (bootstrap-node, doctor, pr-preflight, suite-reuse, sync-node, downstream-autopilot) pass on the merged tree 8e734e3c; this round re-ran only harness-shims and prompt-diet", closes_with: "CI on the pushed head or a selected+CORE run on 8e734e3c" }
  overall: pass
```

security_relevant: false

## Scope

Round 3, re-review after external-review remediation (A7) and a main integration (A8). Reviewed:

1. `git diff c511d47e..c03c93c2`: `.aai/scripts/sync-harness-skills.mjs`, `tests/skills/test-aai-harness-shims.sh`, `CHANGELOG.md`, `docs/ai/decisions.jsonl`, SPEC-0318 A7. Plus `cf099af3` (one `follow_up_status` line closing `fu-pointer-scope-aai-project`).
2. Merge `8e734e3c` (parents `cf099af3`, `9da38865`; merge base `5f02b0e5`).

Spec: `docs/specs/SPEC-0318-spec-skill-description-canonical-prompt-pointer.md`. Worktree `git status --porcelain` was clean before and after the review.

Dispatch handoff check: the dispatch listed what to verify and gave expected values (69585, +575 +836, "rh_now -836 still right"). It did not rank any finding. I treated the values as claims and checked each one myself (below). It asked me to judge the TEST id collision as a defect or a follow-up. That is a question, not a ruling. No coaching recorded.

## 1. The three Codex findings (A7)

Fetched read-only with `gh api repos/goodwind-cz/aai/pulls/596/comments`: three `chatgpt-codex-connector[bot]` threads (P1 4707323501, P2 4707323523, P2 4707323536).

- **(a) SKIPPED line for non-aai skills (P1 thread): fixed, complete.** `checkPointers` now adds `SKIPPED pointer <skill>: not an AAI wrapper` for every name that fails `isAaiWrapperName` (sync-harness-skills.mjs:382-385). The `--check` path prints these lines on stdout before the drift/OK lines (:684). They are not counted. No caller parses this output: the only `sync-harness-skills` references in `.aai/scripts` are comments.
- **(b) aai-project-* excluded (P2 thread): fixed, complete.** `isAaiWrapperName` (:309) is `^aai-[a-z0-9-]+$` and not `aai-project-`. This is the same name test `aai-sync.mjs:667` applies before any file-system call. The name keys come from the source directory names (`sourceModels`, :525-533), the same keys aai-sync tests. All 42 shipped wrappers match, so the count stays 42.
- **(c) duplicate `description:` keys refused (P2 thread): fixed for the shape in the finding.** `firstFailure` counts `^description:\s*` frontmatter lines and refuses more than one before any other check (:366-367), as `description is declared <n> times, want exactly one`. `extractDescription`, which feeds the catalog and README, still takes the first key, and `--write` still mirrors verbatim. A7 states both, so they match the code. INFO, not a finding: a key spelled `description :` (space before the colon) or `"description":` is not counted. No merge or edit path in this repo produces those spellings.

**RED proof.** `docs/ai/tdd/skill-description-canonical-prompt-pointer/red/a7-red.log` shows the pre-fix suite failing at TEST-4132's new duplicate-key case (`--check must exit 1 for aai-ship, got 0`). `log_fail` in this suite runs `exit 1` (test-aai-harness-shims.sh:54), so the log stops there. It does not show the two new TEST-4135 cases (a, b) going RED. I closed that gap in a scratch copy of the HEAD tree: I added `deploy-notes` and `aai-project-deploy`, then ran both script versions.
- `c511d47e` script: `DIVERGE pointer aai-project-deploy: description lacks the canonical pointer`, rc 1, no SKIPPED line. Both new TEST-4135 assertions would fail.
- HEAD script: two `SKIPPED pointer ... not an AAI wrapper` lines and `OK: 42`, rc 0.

All three fixes now have RED evidence. One caveat: (a) and (b) are proved only by this report, not by the ride's own log.

**A7 against the code.** Every claim checks out:
- The SKIPPED wording matches the code.
- The ownership test matches the code.
- Skipped skills are left out of `OK: <n>`, and the test asserts `OK: 42` with both skips present.
- The duplicate-key wording matches the code.
- `--write` stays verbatim.
- The script is 716 lines, under the 720 cap.
- The name test is repeated in the script, not imported.

The amendment record exists (decisions.jsonl, ts 2026-11-26T11:10:31Z). `spec-amend list --strict` exits 0: A7 and A8 are `unsigned-tracked` under `fu-amend-skill-description-canoni-b4901e`, which is open and still owes an owner signature. `mutation-gate --spec SPEC-0318`: `GATE PASS: 11 row(s) satisfied degraded=0 unstamped=0 uncomparable=0`. The TEST-4132 plan-row mutation (`isYamlSafeScalar` returns true) still bites, because the colon-space case runs before the new duplicate-key case.

Suite re-run on 8e734e3c (`env -u AAI_ROLE`, fresh `XDG_CACHE_HOME`): `tests/skills/test-aai-harness-shims.sh` rc 0, `=== All aai-harness-shims tests passed ===`, TEST-4130..4140 all PASS.

## 2. Merge 8e734e3c

- **Append-only ledgers.** For EVENTS, METRICS, decisions and test-runs, main's `9da38865` blob is a byte-exact prefix of the merged blob (`head -c <main size> | cmp`). For EVENTS (29 lines), METRICS (1) and test-runs (3), the remaining tail is byte-equal to the branch's own appends since the merge base. decisions.jsonl has the branch's 9 own lines plus one line appended in the merge itself: the A8 `spec_amendment` (ts 11:15:51Z), a legitimate new append at the end. `sort | uniq -d` finds no duplicate lines in any of the four. Each file ends in `\n`. HAZ-LEDGER holds.
- **tests/skills/test-aai-sync-node.sh** is identical to main's blob (`git diff --quiet 9da38865 8e734e3c` holds). The A5 skip is gone. Main's TEST-4019 compares the corpus at `077ee649` with `0ff18d63` (:944-947), a property of history, so the SKILL_SHIP edit cannot break it. The A8 text says exactly this.
- **Prompt-corpus pins:**
  - `prompt-diet-ledger.sh`: the onboarding `575` entry comes before this ride's `836` entry.
  - TEST-012 `want_growth=69585`, which is 68174 + 575 + 836.
  - pr-preflight case 008 adds `+575` and `+836`.
  - suite-reuse TEST-3278 adds `+ 575 + 836`.
  - `rh_now` sums only SKILL_WORKTREE and SKILL_SHIP (test-aai-prompt-diet.sh:1082-1089). Onboarding touched neither, so `-836` alone stays right.
  - Corpus is 377582 B, which is 376171 + 575 + 836, so main's TEST-4134 subtraction of later entries resolves to 575.
  - `tests/skills/test-aai-prompt-diet.sh` re-run: rc 0, `PASS TEST-012 ... == 69585`, `PASS TEST-4134: corpus growth 575 B credited 1:1`.
- **CHANGELOG.** The merged file is main's file plus this branch's entry inserted directly under the `## [unreleased]` scaffold. The onboarding and mutation entries are byte-identical to main's. **USER_GUIDE** keeps both sections, this branch's first.
- **One-sided files.** Every file only main changed equals main's blob. Every file only the branch changed equals the branch's blob, except SPEC-0318, which gains A8 and a restamp. The mutation gate shows the restamp is consistent.
- **Generated pages** were regenerated, not hand-merged. In a scratch clone at 8e734e3c I re-ran generate-docs-index, generate-overview, generate-factory-report and generate-docs-hub. INDEX.md and SKILL_CATALOG.html came out byte-equal. The overview, factory-report and skill-catalog-data files differ only in `generatedAt`, `project` (derived from the clone's directory name) and `age_days` (+1 day). Those are run-time fields; no content drifted. `docs-audit --check --no-event`: `Verdict: CLEAN`.

### TEST-4130..4135 shared with SPEC-0317

SPEC-0317 also uses TEST-4130..4135, in `test-aai-bootstrap-node.sh` and `test-aai-doctor.sh`. **This is not a defect of this PR, and it does not need a follow-up.** TEST ids in this repository are suite-local by long practice: by `log_pass` ids alone, 80 ids are reused across suites (TEST-001..039 appear in up to 43 suites). The tooling that binds evidence to an id keys it with the suite and the spec: `mutation-run.mjs --spec --test-id --suite`, and the mutation gate reads per-spec Test Plan rows. The same id in another suite under another spec therefore resolves to a different record. A global id allocator would be a separate capability, not a fix for this ride.

## Code quality findings

### NB-7 (P3): copied ownership predicate, no equality pin (sync-harness-skills.mjs:309)

See the YAML block. A7 chose to repeat the predicate, to keep `aai-sync.mjs` out of the generator's imports, and that is a reasonable trade. The finding is only that nothing turns red if the two copies drift apart.

Recommended disposition: **accepted residual (d)**. Alternative: a one-line TEST-4135 assertion that compares `isRetiredSkillWrapper`'s name gate with `isAaiWrapperName` on a small name list, folded into `fu-consumer-pointer-check-after-sync` when it is built.

accepted residual: NB-7 — isAaiWrapperName repeats the aai-sync.mjs:667 name test by design (A7) with no equality pin; P3 maintenance/assurance, no observed bite, both copies agree today.

## Prior findings

- NB-4 (round 2): **closed** by c03c93c2 (b above). `fu-pointer-scope-aai-project` is marked done in cf099af3.
- NB-5 (round 2): **closed** by c03c93c2 (a above). The accepted-residual line from round 2 is superseded.
- NB-6 (round 2) and NB-3 (round 1): unchanged. Their accepted residuals stand.

## Warning dispositions

| Finding | Sev | Recommended disposition |
|---|---|---|
| NB-7 copied ownership predicate, no pin | P3 | accepted residual (line above) |
| NB-6 (round 2) | P3 | accepted residual, unchanged |
| NB-3 (round 1) | P3 | accepted residual, unchanged |

## Next steps

- The orchestrator stages this report with the next commit and records NB-7's disposition.
- Before merge, CI on the pushed head 8e734e3c should cover the suites that only the merge touched (the cannot_verify entry above).
- Optionally, reply to the three Codex threads citing c03c93c2 and TEST-4132/TEST-4135, then resolve them (the external-review response flow).
