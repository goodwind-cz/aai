# Code Review: configurable-merge-policy-lanes (re-review after remediation round 8)

```yaml
review:
  scope: "git diff 64f2595f..74805d63 (branch feat/configurable-merge-policy-lanes, 22 commits, 31 files)"
  spec: docs/specs/SPEC-0207-spec-configurable-merge-policy-lanes.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "merge-policy.mjs runCheck no_policy path (:1456); TEST-1501 green" }
      - { ac: Spec-AC-02, call: compliant, citation: "claude-hook-gate.sh merge_deny_article7 (verdict line only when LANE_VERDICT set); TEST-1502 green" }
      - { ac: Spec-AC-03, call: compliant, citation: "merge-policy.mjs readAtBase (:819) for policy and decisions; TEST-1503/1504/1505 green" }
      - { ac: Spec-AC-04, call: compliant, citation: "GUARD_PATHS checked before no_policy (:1442-1446); TEST-1506/1507/1570 green" }
      - { ac: Spec-AC-05, call: compliant, citation: "globToRegExp now compiles with the dotAll flag (:888); classifyFiles (:905-937); getChangedFiles -z --no-renames (:1358-1364); TEST-1508/1569/1570/1572/1573 green; dotAll-drop mutation reddens TEST-1572 (re-run here)" }
      - { ac: Spec-AC-06, call: compliant, citation: "globToRegExp :844-889, runClassify :1584; TEST-1509 green" }
      - { ac: Spec-AC-07, call: compliant, citation: "requesterApproved :946; TEST-1510 green" }
      - { ac: Spec-AC-08, call: compliant, citation: "ciGreen :988; TEST-1511 green" }
      - { ac: Spec-AC-09, call: compliant, citation: "sweepCheckAllowed :1094 / runSweepCheck :1107; TEST-1512/1559/1568 green" }
      - { ac: Spec-AC-10, call: compliant, citation: "validatePolicy :758 needsOptIn; TEST-1513 green" }
      - { ac: Spec-AC-11, call: compliant, citation: "readRideCeremony :1055; TEST-1514/1515/1533/1540 green" }
      - { ac: Spec-AC-12, call: compliant, citation: "parsePolicy :674 textual canonical form, validatePolicy; TEST-1516..1518, 1534..1539, 1545, 1547, 1548, 1552, 1553, 1555..1557, 1562, 1565, 1566 green" }
      - { ac: Spec-AC-13, call: compliant, citation: "MARKER_RE + duplicate_marker, lane-id shape; TEST-1519/1550/1563 green" }
      - { ac: Spec-AC-14, call: compliant, citation: "claude-hook-gate.sh lane path / lane_check_merge_shape / field-exact LANE_ALLOWED_ERE; TEST-1520/1541/1542/1549/1551/1564 green" }
      - { ac: Spec-AC-15, call: compliant, citation: "evaluateLane :1248-1305 (per-path coverage), parseRequiredList :370; TEST-1521/1543/1544/1546/1554/1560/1567/1569 green" }
      - { ac: Spec-AC-16, call: compliant, citation: "runCheck pr_not_open / api_unavailable / base_unavailable; TEST-1522/1523 green" }
      - { ac: Spec-AC-17, call: compliant, citation: "runCheck lane loop :1538-1552 (kind_not_in_lane path= suffix now escaped, one physical line per lane); TEST-1524/1573 green" }
      - { ac: Spec-AC-18, call: compliant, citation: "docs/ai/merge-policy.yaml; --validate prints VALID lanes=1 (re-run here); TEST-1525/1526 green" }
      - { ac: Spec-AC-19, call: compliant, citation: ".aai/SKILL_PR.prompt.md step 6 `gh pr merge <n> --squash --match-head-commit <headRefOid>`; TEST-1527/1571 green" }
      - { ac: Spec-AC-20, call: compliant, citation: "aai-doctor.mjs catMergePolicy; TEST-1528/1558 green; test-aai-doctor.sh rc 0" }
      - { ac: Spec-AC-21, call: compliant, citation: "docs/CONSTITUTION.md article 7 + v2; TEST-1529 green; test-aai-constitution.sh rc 0" }
      - { ac: Spec-AC-22, call: compliant, citation: "PROFILES.yaml core, DOCS_AI_CANON.list, suite-map, prompt-diet ledger; TEST-1530/1531 green; prompt-diet, layer-profiles, hygiene-pack rc 0" }
      - { ac: Spec-AC-23, call: compliant, citation: "CHANGELOG.md [unreleased] heading; TEST-1532 green" }
  code_quality:
    verdict: pass
    findings: []
  cannot_verify:
    - { claim: "The real `gh pr view --json reviews,statusCheckRollup` shapes (reviews[].commit.oid; CheckRun vs StatusContext) match the fixtures, and gh's reviews list is not truncated on PRs with many reviews", closes_with: "One live --check against a real PR with an approval and mixed check types (spec R1)" }
    - { claim: "A real lane merge from the checkout where merges run passes lane-gate --sweep-check (its stale-head comparison uses the local HEAD of --repo-root, not the PR headRefOid)", closes_with: "A live dry-run of the hook lane path on a real PR" }
    - { claim: "GitHub enforces --match-head-commit server-side as P9 assumes, and server-side branch protection is the boundary R3 names", closes_with: "A live merge attempt with a stale --match-head-commit, refused by GitHub" }
  overall: pass
```

## Scope and preflight

- Worktree `/Users/ales/Projects/aai-feat-configurable-merge-policy-lanes`, branch `feat/configurable-merge-policy-lanes`, HEAD `74805d63` (verified), `git status --porcelain` clean before and after. STATE `worktree.user_decision: worktree`. Range `git diff 64f2595f..74805d63`, run myself.
- Spec: the frozen SPEC-DRAFT (ceremony 3, 23 Spec-ACs, 73 Test Plan rows after round 8) and the accepted RFC. Prior reviews: 20261004T175939Z, 20261005T000837Z, 20261005T014832Z. Latest validation read: VALIDATION-20261005T0135Z (round 8, FAIL on V8-B1, the same defect as my prior B1).
- Coaching check: the dispatch did not characterize findings, pre-rate severity, or exclude any area. I re-walked every AC row over the full range. Adversarial probing concentrated on the round-8 delta (`5d21d126..74805d63`: the dotAll flag, `escapeForLine`, TEST-1572/1573, two spec_amendment records), since rounds 1-7 have been reviewed in full three times.

## Evidence I ran myself (suites with AAI_ROLE unset)

| command | rc |
|---|---|
| `bash tests/skills/test-aai-merge-policy.sh` (62 PASS, "All tests passed!") | 0 |
| `bash tests/skills/test-aai-{hooks-overlay,prompt-diet,doctor,constitution,ride-select,hygiene-pack,layer-profiles}.sh` | 0 each |
| `node .aai/scripts/merge-policy.mjs --validate` -> `VALID lanes=1` | 0 |
| `node .aai/scripts/spec-lint.mjs --path <spec>` -> LINT PASS | 0 |
| `node .aai/scripts/spec-amend.mjs list --strict` (4 contract amendments unsigned-tracked by fu-amend-configurable-merge-policy-lanes, none untracked) | 0 |
| `node .aai/scripts/mutation-gate.mjs --spec <spec>` -> GATE PASS 73 rows | 0 |
| `node .aai/scripts/docs-audit.mjs --gate spec-configurable-merge-policy-lanes` -> GATE PASS | 0 |
| `tdd-evidence-check.mjs --red` on red-TEST-1572.log / red-TEST-1573.log | ACCEPTED (product_red) each |
| scratch worktree at 74805d63: drop the `'s'` flag, run TEST-1572 alone | 1 (bites: lf/cr/ls/ps allowed rc 0) |
| same scratch, flag restored, un-escape the classification-deny path (`:1490`), TEST-1572 alone | 1 (bites: raw LF splits the line) |
| unit probe `classifyFiles`: LF, CR, U+2028, U+2029, TAB, NUL, U+0085, U+FFFD, `é` inside segments under `.github/**`, `migrations/**`, `infra/*` | all `architecture`; the same byte inside the directory name (`.github<LF>/x.yml`) correctly classifies as a kind, since it is a different directory |
| HAZ-LEDGER: base EVENTS.jsonl, decisions.jsonl, tests/test-runs.jsonl are byte prefixes at HEAD | ok (3/3) |

The scratch worktree was removed with a targeted `git worktree remove --force <path>`.

## Verdict 1: spec_compliance is pass

- **Spec-AC-05 is compliant again.** Prior B1 / V8-B1 is closed: `globToRegExp` returns `new RegExp(\`^${re}$\`, 's')` (`merge-policy.mjs:888`), so `.` (from `**`) and `[^/]` (from `*`/`?`) now agree on every line terminator. TEST-1572 covers the four terminators under `.github/**` + `**/*.yml` and the RFC's own `migrations/**` + content example. The recorded mutation and my own probe both redden it.
- **Spec-AC-17** gains TEST-1573: a path carrying LF plus a forged `MERGE-POLICY allowed` payload prints on exactly one lane line. Previously that was an INFO-level gap against "exactly one `lane=<id> reason=<code>` line per lane". All three `path=` sites are escaped (`:1444`, `:1490`, `:1545`). The lane-line site is pinned by the TEST-1573 mutation. The classification-deny site is pinned by TEST-1572's exact-line assertion, which my probe confirmed. The policy_touched site can only print an exact GUARD_PATHS string, so it can never carry a control byte.
- **Prior NB-1 is closed.** The contract-class correction at decisions.jsonl 2026-10-05T03:51:33Z names the AC-05 criterion additions (per-path coverage, `-z`) and the AC-19 PR-number addition. It is tracked by `fu-amend-configurable-merge-policy-lanes`, and `spec-amend list --strict` lists it as unsigned-tracked. I checked the 03:51:26Z measurement record against the diff: its claim that "no AC criterion text changed in this round" is true. Only the evidence and notes columns of the AC-05 row changed.
- Deviations (INFO, no failure mode):
  - The TEST-1573 Test Plan row maps to Spec-AC-05. The test's own name says Spec-AC-05/Spec-AC-17, and what it asserts is P10/AC-17.
  - The `path=<p>` encoding (JSON-style escaping of C0/C1/DEL/U+2028/U+2029) is a new representation of `<p>`, and P10 does not spell it out. It enforces AC-17's one-line promise rather than changing it.

## Verdict 2: code_quality is pass

No BLOCKING and no NON-BLOCKING findings in this round.

INFO (no failure scenario that gates anything):
- `escapeForLine` does not escape a backslash. A path containing a literal backslash followed by `n` therefore prints the same as a path containing an LF. This is display-only: the hook takes the first line and the exit code, and every such path is denied in both readings. The comment at `:1373-1388` says this is deliberate, to keep TEST-1570's real-bytes rendering.
- The `getChangedFiles` comment (`:1341-1357`) is now accurate. The prior overclaim is corrected.

### Dispositions carried from previous reviews (checked in tree)
- **Prior B1 (dotAll):** closed, see above.
- **Prior NB-1 (understated amendment):** closed by the 03:51:33Z contract-class correction, tracked by `fu-amend-configurable-merge-policy-lanes` (owner sign-off still pending, as for the three earlier contract amendments).
- **Prior N5:** accepted residual: the hook resolves LANE_HEAD and the evaluator resolves headRefOid in two separate gh calls. A force-push race inside that window could land a head the evaluator did not judge. P3, it needs a deliberate race, the hook is a guardrail not a boundary (R3), and it has not been observed. (Unchanged.)
- `fu-merge-policy-ride-pr-binding` and `fu-merge-policy-decision-ref-frac-ts` remain filed (both present in decisions.jsonl).

## cannot_verify

See the YAML block: live gh JSON shapes and review truncation, the sweep-check head comparison in a real checkout, and GitHub's server-side `--match-head-commit` enforcement. All three need a live PR. The prior entry about the real-world consumer effect of a line-terminator file name is dropped, because the deny now holds whatever that effect is.

## Next steps

1. Validation round 9 (pending) re-runs on HEAD 74805d63. Nothing in this review blocks it.
2. Before close: the owner signs off, or explicitly accepts, the four unsigned contract amendments tracked by `fu-amend-configurable-merge-policy-lanes`.
3. Optional, at the orchestrator's discretion (INFO): re-map TEST-1573's Test Plan row to Spec-AC-17 in the next measurement amendment.
