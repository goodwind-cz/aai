# Code Review: configurable-merge-policy-lanes (re-review after remediation rounds 5-7)

```yaml
review:
  scope: "git diff 64f2595f..ed87965c (branch feat/configurable-merge-policy-lanes, 20 commits, 29 files)"
  spec: docs/specs/SPEC-0207-spec-configurable-merge-policy-lanes.md
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/merge-policy.mjs:1371-1374, :1475-1477; TEST-1501 green" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/scripts/claude-hook-gate.sh merge_deny_article7 (verdict line only when LANE_VERDICT set); TEST-1502 green" }
      - { ac: Spec-AC-03, call: compliant, citation: "merge-policy.mjs:1366, :1386 (base reads); TEST-1503/1504/1505 green" }
      - { ac: Spec-AC-04, call: compliant, citation: "merge-policy.mjs:54-72 GUARD_PATHS, :1358-1362 before no_policy; TEST-1506/1507 green" }
      - { ac: Spec-AC-05, call: non-compliant, citation: "merge-policy.mjs:1299-1305 getChangedFiles reads git's C-quoted --name-only output; a changed path that matches an architecture glob is allowed when its name has a non-ASCII byte (reproduced: .github/workflows/déploy.yml under .github/** gives MERGE-POLICY allowed, rc 0). See BLOCKING B2. TEST-1508 green, but it covers ASCII names only" }
      - { ac: Spec-AC-06, call: compliant, citation: "globToRegExp :844-874, runClassify :1496-1521; TEST-1509 green" }
      - { ac: Spec-AC-07, call: compliant, citation: "requesterApproved :922-938; TEST-1510 green" }
      - { ac: Spec-AC-08, call: compliant, citation: "ciGreen :964-973; TEST-1511 green" }
      - { ac: Spec-AC-09, call: compliant, citation: "sweepCheckAllowed :1070-1081 (rc 0 AND the first line names this pr), ALLOWED_REQUIRES_KEYS :407; TEST-1512/1559/1568 green (prior B1 closed)" }
      - { ac: Spec-AC-10, call: compliant, citation: "validatePolicy needsOptIn :789-793; TEST-1513 green" }
      - { ac: Spec-AC-11, call: compliant, citation: "readRideCeremony :1031-1048, DEFAULT_MAX_CEREMONY; TEST-1514/1515/1533/1540 green" }
      - { ac: Spec-AC-12, call: compliant, citation: "parsePolicy textual canonical form :674-694, validatePolicy; TEST-1516..1518, 1534..1539, 1545, 1547, 1548, 1552, 1553, 1555..1557, 1562, 1565, 1566 green" }
      - { ac: Spec-AC-13, call: compliant, citation: "MARKER_RE + duplicate_marker :778-784, lane-id shape :556; TEST-1519/1550/1563 green" }
      - { ac: Spec-AC-14, call: compliant, citation: "claude-hook-gate.sh lane_path / lane_check_merge_shape / field-exact LANE_ALLOWED_ERE; TEST-1520/1541/1542/1549/1551/1564 green" }
      - { ac: Spec-AC-15, call: compliant, citation: "evaluateLane :1212-1262, parseRequiredList; TEST-1521/1543/1544/1546/1554/1560/1567 green" }
      - { ac: Spec-AC-16, call: compliant, citation: "runCheck :1338-1343, :1399-1402, getChangedFiles; TEST-1522/1523 green" }
      - { ac: Spec-AC-17, call: compliant, citation: "runCheck lane loop :1455-1465; TEST-1524 green" }
      - { ac: Spec-AC-18, call: compliant, citation: "docs/ai/merge-policy.yaml; --validate prints VALID lanes=1 (re-run here); TEST-1525/1526 green" }
      - { ac: Spec-AC-19, call: compliant, citation: ".aai/SKILL_PR.prompt.md step 6, .aai/AGENTS.md closeout, .aai/SKILL_SHIP.prompt.md step 6; TEST-1527 green (see NON-BLOCKING N7 on the step-6 command text)" }
      - { ac: Spec-AC-20, call: compliant, citation: ".aai/scripts/aai-doctor.mjs catMergePolicy; TEST-1528/1558 green" }
      - { ac: Spec-AC-21, call: compliant, citation: "docs/CONSTITUTION.md article 7 + v2, 2026-10-03; TEST-1529 green" }
      - { ac: Spec-AC-22, call: compliant, citation: "PROFILES.yaml core, DOCS_AI_CANON.list, suite-map aai-merge-policy, prompt-diet ledger; TEST-1530/1531 green" }
      - { ac: Spec-AC-23, call: compliant, citation: "CHANGELOG.md [unreleased] heading; TEST-1532 green" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/merge-policy.mjs, line: 1214,
          issue: "Lane coverage is judged per PR, but P5 judges it per path. evaluateLane allows when ANY kind in the PR's union of kinds is in the lane's kinds (kinds.some(k => ctx.kinds.has(k))). P5 says 'A lane covers a path when at least one kind the path matches is listed in the lane's kinds', so every changed path must be covered. A related problem: classifyFiles (:902-904) records only the FIRST kind a path matches (break), so 'at least one kind the path matches' is not honoured either.",
          failure_scenario: "Reproduced end to end with a scratch repo, a gh stub and a real lane-gate sweep record. The policy has kinds content [content/**] and code [src/**], and lane content-lane has kinds [content] and merge_reaches nothing. A PR changes content/a.md AND src/app.js. Result: 'MERGE-POLICY allowed pr=9 lane=content-lane marker=AAI_CONTENT_MERGE ...', rc 0. Code merges through a content-only lane whenever it rides along with one content file. This is the exact downstream use case the RFC exists for ('content and design pull requests merge when CI is green and the requester approved them'). This repository's live policy has a single catch-all kind, so it is not exposed today. Fix: evaluateLane denies kind_not_in_lane unless EVERY changed path has at least one matched kind in lane.kinds; classifyFiles returns per-path kind sets (all matches, not the first). Add a mixed-PR RED test plus a multi-kind-path control." }
      - { rank: BLOCKING, file: .aai/scripts/merge-policy.mjs, line: 1300,
          issue: "getChangedFiles runs `git diff --name-only` without -z. Under git's default core.quotePath=true, a path with a byte >= 0x80 (and, whatever the setting, a path containing a double quote, backslash, tab or newline) comes back C-quoted and escaped (\".github/workflows/d\\303\\251ploy.yml\"). That string is not the repo-relative path. An anchored architecture glob therefore never matches it, while a catch-all `**` kind does.",
          failure_scenario: "Reproduced end to end. The policy has architecture consumer-facing [hooks/**, .github/**] and kind repo [**], the same shape as this repository's live docs/ai/merge-policy.yaml. A PR adds .github/workflows/déploy.yml (a live GitHub Actions workflow). Result: 'MERGE-POLICY allowed pr=9 lane=internal ...', rc 0. Control: with core.quotePath=false the same PR gives 'denied reason=architecture path=.github/workflows/déploy.yml', rc 3. So the architecture deny, which P5/D3 make absolute and which HITL-2 relies on as the stand-in for 'visible to downstream consumers', is bypassed by naming the file with a non-ASCII character. That is the misread-then-allow class the owner escalated in rounds 3-5. Fix: `git diff -z --name-only --no-renames` and split on NUL (or pass -c core.quotePath=false AND refuse any path containing a quote, backslash or control character). Add RED tests with a non-ASCII and a quote-bearing architecture path." }
      - { rank: NON-BLOCKING, file: .aai/SKILL_PR.prompt.md, line: 500,
          issue: "Step 6 tells the agent to run `gh pr merge --squash --match-head-commit <headRefOid>` with no PR number. The hook's lane allow-list refuses exactly that form ('a PR number is required on the merge-policy lane', claude-hook-gate.sh lane_check_merge_shape, TEST-1549).",
          failure_scenario: "An agent following SKILL_PR literally after an allowed verdict is refused by the hook every time, so the lane is unusable as documented. In a harness without the hook, the branch-implicit form merges whatever PR the cwd branch resolves to, which is not necessarily PR <n>, the one --check judged. --match-head-commit refuses most of these mismatches, but the evaluator is no longer what binds the merge target. Recommended disposition: (a) remediate in tree (write `gh pr merge <n> --squash --match-head-commit <headRefOid>`, then re-pin TEST-012 and the diet ledger)." }
  cannot_verify:
    - { claim: "The real `gh pr view --json reviews,statusCheckRollup` shapes (reviews[].commit.oid; CheckRun vs StatusContext) match the fixtures, and gh's reviews list is not truncated on PRs with many reviews", closes_with: "One live --check against a real PR with an approval and mixed check types (spec R1)" }
    - { claim: "A real lane merge from the checkout where merges run passes lane-gate --sweep-check (its stale-head comparison uses the local HEAD of --repo-root, not the PR headRefOid)", closes_with: "A live dry-run of the hook lane path on a real PR" }
    - { claim: "GitHub enforces --match-head-commit server-side as P9 assumes, and server-side branch protection is the boundary R3 names", closes_with: "A live merge attempt with a stale --match-head-commit, refused by GitHub" }
  overall: fail
```

## Scope and preflight

- Worktree `/Users/ales/Projects/aai-feat-configurable-merge-policy-lanes`, branch `feat/configurable-merge-policy-lanes`, HEAD `ed87965c` (verified). The range is `git diff 64f2595f..ed87965c`, which I read myself. Outside the range, the working tree has one uncommitted telemetry append to `docs/ai/EVENTS.jsonl`.
- Spec: the frozen SPEC-DRAFT (ceremony 3, 23 Spec-ACs, 68 Test Plan rows) and the accepted RFC. Owner decisions for this ref: 2026-10-03T15:30:00Z, and the 2026-10-04 menu answers that set up rounds 4 and 5.
- Coaching check: the dispatch did not characterize findings, pre-rate severity or exclude any area. I reviewed the full range, not only the delta since the previous review.

## Evidence I ran myself (suites with AAI_ROLE unset)

| command | rc |
|---|---|
| `bash tests/skills/test-aai-merge-policy.sh` (57 PASS) | 0 |
| `bash tests/skills/test-aai-hooks-overlay.sh` (27 PASS) | 0 |
| `bash tests/skills/test-aai-doctor.sh` / `-constitution.sh` / `-prompt-diet.sh` / `-layer-profiles.sh` / `-ride-select.sh` | 0 each |
| `node .aai/scripts/merge-policy.mjs --validate` -> `VALID lanes=1` | 0 |
| `node .aai/scripts/spec-lint.mjs --path <spec>` -> LINT PASS | 0 |
| `node .aai/scripts/mutation-gate.mjs --spec <spec>` -> GATE PASS 68 rows | 0 |
| scratch unit probe `classifyFiles` + `evaluateLane` on a two-kind PR (B1) | allowed (`{"ok":true}`) |
| scratch end-to-end `--check` on a mixed content+code PR, content-only lane (B1) | 0 (allowed) |
| scratch end-to-end `--check` on `.github/workflows/déploy.yml`, default quotePath (B2) | 0 (allowed) |
| same PR with `core.quotePath=false` (B2 control) | 3 (denied architecture) |

Append-only ledgers in the range: EVENTS.jsonl +21/-0, decisions.jsonl +20/-0, test-runs.jsonl +48/-0. HAZ-LEDGER holds.

## Verdict 1: spec_compliance is fail

- **Spec-AC-05 is non-compliant.**
  - The AC says: "WHEN a changed path matches an architecture glob THEN `--check` exits 3 with reason=architecture".
  - For any path git C-quotes, `--check` exits 0 instead (B2). TEST-1508 passes only because every fixture name is ASCII.
- **P5 deviation with no AC row.** No AC row pins it, but the frozen design text is explicit: a lane covers a path when one of that path's kinds is in the lane. The implementation judges coverage over the PR's union of kinds (B1). A well-written implementation of the wrong rule still fails this verdict.
- **Disclosed deviations (INFO, no failure mode):**
  - Lane-level deny code `roadmap_unreadable` (merge-policy.mjs:1237, code review N2 remediation) appears only in the TEST-1560 row. It is missing from P10's list of lane-level codes. Fold it into P10 in the next amendment.
  - `--debug-inputs` prints before the verdict line. Tests use it; the hook never passes it.
  - A non-string `decision_match` is now parse_error, which is stricter than P10 says (validation round 7 NB-B, fail-closed).

Every other row holds, and every TEST-15xx the Test Plan names exists and passes.

## Verdict 2: code_quality is fail

### BLOCKING
- **B1: `merge-policy.mjs:1214` judges lane coverage per PR, not per path.**
  - A mixed PR with one content file and one code file is allowed by a content-only lane (reproduced, rc 0).
  - classifyFiles also keeps only the first kind a path matches (`:902-904`).
  - Fix both together: per-path kind sets, and every path must have a kind in `lane.kinds`.
- **B2: `merge-policy.mjs:1300` reads C-quoted paths from `git diff --name-only`.**
  - A non-ASCII (or quote-bearing) path under an architecture glob escapes the architecture deny.
  - The live policy's catch-all `**` kind then classifies it, and the internal lane can merge a new `.github/workflows/*` file (reproduced, rc 0; the control is rc 3).
  - Fix: `-z` and split on NUL.

Each fix needs a RED-proofed regression test and a mutation row, per the spec's TDD evidence contract.

### NON-BLOCKING (WARNINGs; H6 disposition owed)
- **N7: `SKILL_PR.prompt.md:500` documents a merge command the hook refuses** (it has no PR number). Recommended: (a) remediate in tree. This needs a TEST-012 re-pin and a diet-ledger true-up.

### Dispositions carried from the previous review (checked in tree and ledger)
- **B1 (prior) is closed.** sweepCheckAllowed requires rc 0 and the allowed first line for this pr. TEST-1559 and TEST-1568 are green, and their mutations redden (gate PASS).
- **N1 is filed** as `fu-merge-policy-ride-pr-binding` (P2; decisions.jsonl 2026-10-04T18:01:15Z).
- **N2 is remediated.** `roadmap_unreadable` fails closed at `:1236`; TEST-1560 green.
- **N3 is remediated.** The zero-file sentinel is unclassified at `:890`; TEST-1561 green.
- **N4 is remediated.** An empty or whitespace-only `decision_match` is parse_error at `:624`; TEST-1562 and TEST-1566 green.
- **N5:** accepted residual: the hook resolves LANE_HEAD and the evaluator resolves headRefOid in two separate gh calls. A force-push race inside that sub-second window could let the merge land a head the evaluator did not judge. It is P3, it needs a deliberate race, the hook is a guardrail and not a boundary (R3), and it has not been observed.
- **Validation round 7 NB-A is filed** as `fu-merge-policy-decision-ref-frac-ts` (P3; decisions.jsonl 2026-10-04T23:55:41Z).

INFO: The textual canonical form, the parse-time shape rules, the hook's allow-list and field-exact ERE, and the sweep binding are closed. In this pass I found no further parser misread-then-allow shape. Both blocking defects are in classification inputs and lane coverage, not in the parser.

## cannot_verify

See the YAML block: the live gh JSON shapes and review truncation, the sweep-check head comparison in a real checkout, and GitHub's server-side `--match-head-commit` enforcement.

## Next steps

1. Remediate B1 and B2 with failing-first tests:
   - a mixed content+code PR under a content-only lane;
   - a path matching two kinds, as a control;
   - a non-ASCII architecture path and a quote-bearing architecture path under a catch-all kind.

   Then re-validate and re-review.
2. Record N7's disposition (remediating it in tree is recommended), and add `roadmap_unreadable` to P10 through a disclosed amendment.
