# Code Review: configurable-merge-policy-lanes (re-review after remediation round 7)

```yaml
review:
  scope: "git diff 64f2595f..5d21d126 (branch feat/configurable-merge-policy-lanes, 21 commits, 30 files)"
  spec: docs/specs/SPEC-0207-spec-configurable-merge-policy-lanes.md
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "merge-policy.mjs runCheck no_policy path; TEST-1501 green" }
      - { ac: Spec-AC-02, call: compliant, citation: "claude-hook-gate.sh merge_deny_article7 (verdict line only when LANE_VERDICT set); TEST-1502 green" }
      - { ac: Spec-AC-03, call: compliant, citation: "merge-policy.mjs readAtBase for policy and decisions; TEST-1503/1504/1505 green" }
      - { ac: Spec-AC-04, call: compliant, citation: "GUARD_PATHS checked before no_policy (merge-policy.mjs:1396-1400); TEST-1506/1507 green; TEST-1570 guard_with_nonascii_sibling green" }
      - { ac: Spec-AC-05, call: non-compliant, citation: "merge-policy.mjs:873 globToRegExp builds RegExp without the dotAll flag; with round 7's -z (:1338) a changed path carrying a line terminator (LF, CR, U+2028, U+2029) under an architecture glob escapes the architecture deny and is allowed via a [^/]*-based kind glob (reproduced end to end, rc 0). See BLOCKING B1. TEST-1508/1569/1570 green but cover no line-terminator path" }
      - { ac: Spec-AC-06, call: compliant, citation: "globToRegExp :844-874, runClassify; TEST-1509 green" }
      - { ac: Spec-AC-07, call: compliant, citation: "requesterApproved; TEST-1510 green" }
      - { ac: Spec-AC-08, call: compliant, citation: "ciGreen; TEST-1511 green" }
      - { ac: Spec-AC-09, call: compliant, citation: "sweepCheckAllowed; TEST-1512/1559/1568 green" }
      - { ac: Spec-AC-10, call: compliant, citation: "validatePolicy needsOptIn; TEST-1513 green" }
      - { ac: Spec-AC-11, call: compliant, citation: "readRideCeremony, DEFAULT_MAX_CEREMONY; TEST-1514/1515/1533/1540 green" }
      - { ac: Spec-AC-12, call: compliant, citation: "parsePolicy textual canonical form, validatePolicy; TEST-1516..1518, 1534..1539, 1545, 1547, 1548, 1552, 1553, 1555..1557, 1562, 1565, 1566 green" }
      - { ac: Spec-AC-13, call: compliant, citation: "MARKER_RE + duplicate_marker, lane-id shape; TEST-1519/1550/1563 green" }
      - { ac: Spec-AC-14, call: compliant, citation: "claude-hook-gate.sh lane_path / lane_check_merge_shape / field-exact LANE_ALLOWED_ERE (:200, :439-451); TEST-1520/1541/1542/1549/1551/1564 green" }
      - { ac: Spec-AC-15, call: compliant, citation: "evaluateLane :1233-1290 (per-path coverage :1236-1242), parseRequiredList; TEST-1521/1543/1544/1546/1554/1560/1567/1569 green" }
      - { ac: Spec-AC-16, call: compliant, citation: "runCheck pr_not_open / api_unavailable / base_unavailable; TEST-1522/1523 green" }
      - { ac: Spec-AC-17, call: compliant, citation: "runCheck lane loop :1493-1501 (kind_not_in_lane path= suffix per amended P10); TEST-1524 green" }
      - { ac: Spec-AC-18, call: compliant, citation: "docs/ai/merge-policy.yaml; --validate prints VALID lanes=1 (re-run here); TEST-1525/1526 green" }
      - { ac: Spec-AC-19, call: compliant, citation: ".aai/SKILL_PR.prompt.md:500 now `gh pr merge <n> --squash --match-head-commit <headRefOid>`; TEST-1527/1571 green (prior N7 closed)" }
      - { ac: Spec-AC-20, call: compliant, citation: "aai-doctor.mjs catMergePolicy; TEST-1528/1558 green" }
      - { ac: Spec-AC-21, call: compliant, citation: "docs/CONSTITUTION.md article 7 + v2, 2026-10-03; TEST-1529 green" }
      - { ac: Spec-AC-22, call: compliant, citation: "PROFILES.yaml core, DOCS_AI_CANON.list, suite-map, prompt-diet ledger (+121 B SKILL_PR, TEST-012 pin 50754); TEST-1530/1531 green; test-aai-prompt-diet.sh rc 0" }
      - { ac: Spec-AC-23, call: compliant, citation: "CHANGELOG.md [unreleased] heading; TEST-1532 green" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/merge-policy.mjs, line: 873,
          issue: "globToRegExp compiles `new RegExp(`^${re}$`)` without the `s` (dotAll) flag. `**` becomes `.*`, which does not match a JS line terminator (LF, CR, U+2028, U+2029), while `*` and `?` become `[^/]*` / `[^/]`, which DO match one. So an architecture glob written with `**` misses a path whose tail contains a line terminator, while a kind glob written with `*` still matches it. Round 7's B2 fix (`git diff -z`, :1338) now hands those real bytes to the classifier (pre-fix they arrived C-quoted with a leading `\"`, which matched neither). The code comment at :1325-1336 claims a newline inside a path 'can never be misread'; it is misread one layer later.",
          failure_scenario: "Reproduced end to end in a scratch worktree with the suite's own helpers (write_sweep_record, gh stub): policy architecture consumer-facing [.github/**], kind config [**/*.yml] (and separately [.github/*/*.yml]), lane lane-x kinds [config]. A PR adds `.github/workflows/de<LF>ploy.yml` via `git update-index --cacheinfo`. `--check` prints 'MERGE-POLICY allowed pr=80 lane=lane-x marker=AAI_PROBE_MERGE ...', rc 0, for both kind globs. Unit probe of classifyFiles with the same policy: LF, CR, U+2028 and U+2029 each classify as kind cfg; the control `é` classifies as architecture. The absolute architecture deny (P5/D3, HITL-2's stand-in for 'visible to downstream consumers') is bypassed; U+2028/U+2029 are valid UTF-8 path characters, so a control-character refusal alone would not close it. This repository's live policy (single catch-all `**` kind) is not exposed: `**` also fails, giving unclassified. Fix: compile with `new RegExp(`^${re}$`, 's')` so every glob token treats a line terminator as an ordinary non-slash character (optionally also deny any path carrying a C0 control or U+2028/U+2029 as unclassified). RED test: architecture [.github/**] + kind [**/*.yml]; paths with LF and U+2028 must deny reason=architecture; control: the same names outside .github classify as config. Add a mutation row dropping the flag." }
      - { rank: NON-BLOCKING, file: docs/ai/decisions.jsonl, line: 1528,
          issue: "The round-7 `spec_amendment` at 2026-10-05T00:49:44Z is classed `measurement` and says only that 'Spec-AC-05/Spec-AC-19's own evidence citations now list the new RED/GREEN logs and TEST ids'. The same commit also changed the CRITERION text of both rows: Spec-AC-05 gained 'a lane is eligible only when it covers EVERY changed path' and 'getChangedFiles reads git's real path bytes via -z', and Spec-AC-19 gained the PR-number requirement. The 00:27:31Z contract record discloses P5/P10 only, not those AC-text clauses.",
          failure_scenario: "A reader of `spec-amend list` (or the owner signing off fu-amend-configurable-merge-policy-lanes) sees two AC criteria widened under a measurement-class record that claims citations only, so the contract change to the acceptance table carries no contract-class disclosure: a false record in an append-only ledger. Recommended disposition: (a) remediate in tree by appending a corrective contract-class spec_amendment (tracked_by fu-amend-configurable-merge-policy-lanes) that names the AC-05 and AC-19 criterion additions; fold it into the amendment B1's fix will need anyway." }
  cannot_verify:
    - { claim: "The real `gh pr view --json reviews,statusCheckRollup` shapes (reviews[].commit.oid; CheckRun vs StatusContext) match the fixtures, and gh's reviews list is not truncated on PRs with many reviews", closes_with: "One live --check against a real PR with an approval and mixed check types (spec R1)" }
    - { claim: "A real lane merge from the checkout where merges run passes lane-gate --sweep-check (its stale-head comparison uses the local HEAD of --repo-root, not the PR headRefOid)", closes_with: "A live dry-run of the hook lane path on a real PR" }
    - { claim: "GitHub enforces --match-head-commit server-side as P9 assumes, and server-side branch protection is the boundary R3 names", closes_with: "A live merge attempt with a stale --match-head-commit, refused by GitHub" }
    - { claim: "GitHub Actions (or any consumer) actually executes or publishes a file whose name carries a line terminator, i.e. the real-world blast radius of B1 beyond 'architecture deny bypassed'", closes_with: "Not needed to gate: the architecture deny is absolute by spec, so B1 stands on the classifier result alone" }
  overall: fail
```

## Scope and preflight

- Worktree `/Users/ales/Projects/aai-feat-configurable-merge-policy-lanes`, branch `feat/configurable-merge-policy-lanes`, HEAD `5d21d126` (verified), `git status --porcelain` clean. Range `git diff 64f2595f..5d21d126`, read myself.
- Spec: the frozen SPEC-DRAFT (ceremony 3, 23 Spec-ACs, 71 Test Plan rows after the round-7 amendment) and the accepted RFC. Prior reviews: 20261004T175939Z and 20261005T000837Z.
- Coaching check: the dispatch did not characterize findings, pre-rate severity, or exclude any area. I re-walked every AC row over the full range and concentrated adversarial probing on the round-7 delta (`5d21d126`) and on the classification input path it changed, since rounds 1-6 were reviewed in full twice already.

## Evidence I ran myself (suites with AAI_ROLE unset)

| command | rc |
|---|---|
| `bash tests/skills/test-aai-merge-policy.sh` (60 PASS, "All tests passed!") | 0 |
| `bash tests/skills/test-aai-hooks-overlay.sh` / `-prompt-diet` / `-doctor` / `-constitution` / `-layer-profiles` / `-ride-select` | 0 each |
| `node .aai/scripts/merge-policy.mjs --validate` -> `VALID lanes=1` | 0 |
| `node .aai/scripts/spec-lint.mjs --path <spec>` -> LINT PASS | 0 |
| `node .aai/scripts/spec-amend.mjs list --strict` (no unsigned-untracked) | 0 |
| `node .aai/scripts/mutation-gate.mjs --spec <spec>` -> GATE PASS 71 rows | 0 |
| scratch worktree: TEST-1569 mutation (`if (false)` on the coverage deny) | 1 (bites: mixed PR allowed) |
| scratch: classifyFiles reverted to break-on-first-match | 1 (bites: dual_kind_allowed denied) |
| scratch: TEST-1570 row mutation (drop `-z`, keep NUL split) | 1 (bites, but by collapsing the list into one bogus path) |
| scratch: TRUE pre-fix form (no `-z`, split on LF + trim) | 1 (bites: non-ASCII and quote paths allowed) |
| scratch: TEST-1571 mutation (old SKILL_PR text) and a misplaced `<n>` variant | 1 each |
| scratch end-to-end `--check`, LF in `.github/workflows/` path, kind `**/*.yml` (B1) | 0 (allowed) |
| same with kind `.github/*/*.yml` (B1) | 0 (allowed) |
| unit probe classifyFiles: LF, CR, U+2028, U+2029 -> kind; `é` -> architecture | — |

The scratch worktree was removed with a targeted `git worktree remove`. Append-only ledgers in the range only grew (round 7 adds +1 EVENTS, +2 decisions).

## Verdict 1: spec_compliance is fail

- **Spec-AC-05 is non-compliant** (B1): "WHEN a changed path matches an architecture glob THEN `--check` exits 3 with reason=architecture even if a kind glob also matches". A path under `.github/**` whose name carries a line terminator exits 0.
- Round-7 amendments checked against the text: P5 per-path rule, P10 `path=<p>` field and `roadmap_unreadable` are present in the spec and match the code (`evaluateLane` :1236-1242, runCheck :1496-1500). The prior P5 deviation and the P10 listing gap are closed.
- **Disclosure gap (NB-1 below):** the AC-05/AC-19 criterion-text additions are recorded under a measurement-class amendment that describes citations only.
- INFO deviations, no failure mode: `--classify` prints only the first matched kind for a multi-kind path (`:1559`), which is enough for an authoring aid; the TEST-1570 mutation cell is weaker than the regression it guards (it also breaks the NUL split), though my probe confirms the true pre-fix form is caught.

## Verdict 2: code_quality is fail

### BLOCKING
- **B1: `merge-policy.mjs:873` glob regex without dotAll lets a line-terminator path escape the architecture deny.** Newly reachable through round 7's `-z` for LF/CR; U+2028/U+2029 too. Same misread-then-allow class as the prior B2. Fix: the `s` flag in `globToRegExp`, a RED test (LF and U+2028 under `.github/**` with a `**/*.yml` kind), and a mutation row. Correct the `getChangedFiles` comment (:1325-1336) so it no longer claims a newline "can never be misread".

### NON-BLOCKING (WARNINGs; H6 disposition owed)
- **NB-1: `decisions.jsonl` 2026-10-05T00:49:44Z measurement amendment understates an AC-text contract change.** Recommended: (a) append a corrective contract-class `spec_amendment` tracked by `fu-amend-configurable-merge-policy-lanes`, folded into the B1 amendment.

### Dispositions carried from the previous review (checked in tree)
- **Prior B1 (per-PR coverage) is closed.** `classifyFiles` returns per-path kind sets (:902-915); `evaluateLane` denies on the first uncovered path (:1236-1242). TEST-1569 green, and both mutations I tried bite.
- **Prior B2 (C-quoted paths) is closed for quoting.** `-z` + NUL split (:1338-1341); TEST-1570 green and bites on the true pre-fix form. The residual line-terminator shape is the new B1 above, a downstream glob-engine defect, not a reopening of the quoting fix.
- **Prior N7 is remediated.** SKILL_PR.prompt.md:500 carries `<n>`; TEST-1571 parses the prompt and runs the hook's own `lane_check_merge_shape`; it bites.
- **Prior N5:** accepted residual: the hook resolves LANE_HEAD and the evaluator resolves headRefOid in two separate gh calls. A force-push race inside that window could land a head the evaluator did not judge. P3, needs a deliberate race, hook is a guardrail not a boundary (R3), not observed. (Unchanged.)
- `fu-merge-policy-ride-pr-binding` (prior N1) and `fu-merge-policy-decision-ref-frac-ts` (round 7 NB-A) remain filed.

INFO: with `-z`, a newline-bearing path is printed raw in the deny output, so a deny can carry extra lines beyond P10's one-line-per-lane shape. It cannot flip a verdict: the hook takes only the first line and also requires rc 0 (claude-hook-gate.sh:441-443), and every deny exits 3. Closing B1 by also refusing such paths would remove this too.

## cannot_verify

See the YAML block: live gh JSON shapes and review truncation, the sweep-check head comparison in a real checkout, GitHub's server-side `--match-head-commit` enforcement, and the real-world consumer effect of a line-terminator file name (not needed to gate B1).

## Next steps

1. Remediate B1 failing-first: add the `s` flag to `globToRegExp`, add a TEST row with LF and U+2028 paths under `.github/**` and a `**/*.yml` kind (deny architecture) plus controls outside `.github` (classify config), and a mutation dropping the flag. Fix the `getChangedFiles` comment.
2. Disclose the B1 spec touch and the AC-05/AC-19 criterion additions (NB-1) in one contract-class amendment tracked by `fu-amend-configurable-merge-policy-lanes`.
3. Re-validate and re-review.
