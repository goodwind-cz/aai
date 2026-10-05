# Code Review — configurable-merge-policy-lanes

```yaml
review:
  scope: "git diff 64f2595f..f47f8861 (branch feat/configurable-merge-policy-lanes, 16 commits, 28 files)"
  spec: docs/specs/SPEC-0207-spec-configurable-merge-policy-lanes.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/merge-policy.mjs:1280-1283, :1374-1376; TEST-1501 green" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/scripts/claude-hook-gate.sh merge_deny_article7 (verdict line only when LANE_VERDICT set); TEST-1502 green" }
      - { ac: Spec-AC-03, call: compliant, citation: "merge-policy.mjs:1276 readAtBase(root, base, POLICY_PATH), :1295 decisions at base; TEST-1503/1504/1505 green" }
      - { ac: Spec-AC-04, call: compliant, citation: "merge-policy.mjs:52-70 GUARD_PATHS, :1267 guard runs before no_policy; TEST-1506/1507 green" }
      - { ac: Spec-AC-05, call: compliant, citation: "merge-policy.mjs classifyFiles (architecture before kinds); TEST-1508 green" }
      - { ac: Spec-AC-06, call: compliant, citation: "merge-policy.mjs globToRegExp + runClassify; TEST-1509 green" }
      - { ac: Spec-AC-07, call: compliant, citation: "merge-policy.mjs requesterApproved; TEST-1510 green" }
      - { ac: Spec-AC-08, call: compliant, citation: "merge-policy.mjs ciGreen; TEST-1511 green" }
      - { ac: Spec-AC-09, call: compliant, citation: "merge-policy.mjs:1019 (exit 5 maps to sweep_check_failed), ALLOWED_REQUIRES_KEYS; TEST-1512 green. See BLOCKING B1: other failure modes of the spawned check are allowed through" }
      - { ac: Spec-AC-10, call: compliant, citation: "validatePolicy needsOptIn; TEST-1513 green" }
      - { ac: Spec-AC-11, call: compliant, citation: "readRideCeremony, DEFAULT_MAX_CEREMONY; TEST-1514/1515/1533/1540 green" }
      - { ac: Spec-AC-12, call: compliant, citation: "parsePolicy textual canonical form, validatePolicy; TEST-1516..1518, 1534..1539, 1545, 1547, 1548, 1552, 1553, 1555..1557 green" }
      - { ac: Spec-AC-13, call: compliant, citation: "MARKER_RE + duplicate_marker, parseStrictScalar; TEST-1519/1550 green" }
      - { ac: Spec-AC-14, call: compliant, citation: "claude-hook-gate.sh lane_path / lane_check_merge_shape; TEST-1520/1541/1542/1549/1551 green" }
      - { ac: Spec-AC-15, call: compliant, citation: "evaluateLane requires checks, parseRequiredList; TEST-1521/1543/1544/1546/1554 green" }
      - { ac: Spec-AC-16, call: compliant, citation: "runCheck pr_not_open/api_unavailable/base_unavailable, getPrJson; TEST-1522/1523 green" }
      - { ac: Spec-AC-17, call: compliant, citation: "runCheck lane loop + output; TEST-1524 green" }
      - { ac: Spec-AC-18, call: compliant, citation: "docs/ai/merge-policy.yaml; --validate prints VALID lanes=1 (rerun here); TEST-1525/1526 green" }
      - { ac: Spec-AC-19, call: compliant, citation: ".aai/SKILL_PR.prompt.md step 6, .aai/AGENTS.md closeout, .aai/SKILL_SHIP.prompt.md step 6; TEST-1527 green" }
      - { ac: Spec-AC-20, call: compliant, citation: ".aai/scripts/aai-doctor.mjs catMergePolicy; TEST-1528/1558 green (test-aai-doctor.sh rc 0)" }
      - { ac: Spec-AC-21, call: compliant, citation: "docs/CONSTITUTION.md article 7 + v2, 2026-10-03; TEST-1529 green" }
      - { ac: Spec-AC-22, call: compliant, citation: "PROFILES.yaml core, DOCS_AI_CANON.list, suite-map aai-merge-policy, prompt-diet ledger; TEST-1530/1531 green, layer-profiles + prompt-diet rc 0" }
      - { ac: Spec-AC-23, call: compliant, citation: "CHANGELOG.md [unreleased] heading for this capability; TEST-1532 green" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/merge-policy.mjs, line: 1019,
          issue: "runSweepCheck treats every outcome other than exit 5 as a passed sweep. lane-gate.mjs --sweep-check exits 0 from its runMain onError handler on any internal error (it prints 'LANE heavy reason=internal-error'), and readPrSweepRecords deliberately throws on an unreadable EVENTS.jsonl so that it reaches that handler. The function's own comment (lines 999-1003) promises the opposite: 'any other nonzero exit ... must fail the same way (deny), never silently allow a merge nothing actually swept'.",
          failure_scenario: "Reproduced in a scratch fixture with a valid base policy, green CI, a qualifying intake and NO pr_sweep record. With docs/ai/EVENTS.jsonl absent the result is 'denied reason=sweep_check_failed' (rc 3). With docs/ai/EVENTS.jsonl unreadable (made a directory, EISDIR) the result is 'MERGE-POLICY allowed pr=7 lane=a ...' (rc 0). The hook's gate 2b then runs the same lane-gate call, gets the same rc 0 and allows too. A lane merge therefore lands with no sweep verified. The same happens on any other lane-gate exception, or on a crash or signal kill whose status is not 5. This breaks P9 ('never turns today's deny into an allow on error') and the Notes mapping, which says the sweep check is mandatory and not configurable. Fix: count the sweep as passed only when rc === 0 AND stdout carries 'SWEEP-CHECK allowed pr=<n>'; anything else is sweep_check_failed. Add a regression test with an unreadable EVENTS.jsonl." }
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-policy.mjs, line: 1331,
          issue: "Nothing ties the ride inputs (ceremony, intake type and ref from STATE current_focus, plus last_validation and code_review status) to the PR being judged. The evaluator never checks the PR number, the head branch or last_validation.ref_id against the ride. In the hook the inputs come from $ROOT's STATE, while the cwd check accepts any linked worktree.",
          failure_scenario: "The main checkout's STATE focuses on ride A (a change intake, ceremony 2, validation and review pass). The agent runs the lane merge for PR B, an RFC-capability ride at ceremony 3 opened from a worktree, from that checkout. --check reads ride A's inputs and allows PR B under internal-standing, provided B has a pr_sweep record. Several sessions sharing one checkout is a documented local condition. P8 mandates the current_focus default and R4 accepts agent-written inputs, so this is a spec-level gap, not non-compliance. Recommended disposition: (b)/(c) promote to a follow-up (bind the ride to the PR, e.g. last_validation.ref_id equals the ride ref and the PR head branch or body names it)." }
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-policy.mjs, line: 1076,
          issue: "exclude_roadmap_capability fails open. A base roadmap.yaml that is absent or has a structural error returns null, and so does an intake with no 'id:' line (rideRef null), and in each case no deny follows. Elsewhere this evaluator fails closed on unresolvable inputs (for example, an unresolved ceremony counts as 3).",
          failure_scenario: "A lane that declares exclude_roadmap_capability without intake_types, judging a capability ride whose intake lacks 'id:', is allowed. Likewise, after any merge that leaves docs/ai/roadmap.yaml unparseable at base, every capability ride passes the exclusion. This repo's own lane is partly covered because intake_types also denies an unresolved intake. Recommended disposition: (a) remediate in tree (deny roadmap_capability when the key is declared and either the base roadmap or the ride ref cannot be resolved), or (b) promote to a follow-up at P3." }
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-policy.mjs, line: 1213,
          issue: "A zero-file PR is represented as the sentinel path '-'. The spec's Implementation plan says 'a PR touching zero files gets unclassified with path -', but '-' goes through the globs like a real path and matches '**' (this repo's only kind).",
          failure_scenario: "Probe: classifyFiles(['-'], live policy) returns kinds {repo}. A PR with an empty net diff is therefore classified and can be lane-merged instead of denied unclassified. The impact is low (no file content lands) but it departs from the frozen spec's edge-case text. Recommended disposition: (a) remediate in tree (return unclassified path=- when the diff is empty, before any glob match), or (d) accepted residual at P3." }
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-policy.mjs, line: 683,
          issue: "An empty decision_match (decision_match: \"\") parses, is canonical, and matches every record at the same ref@ts, because ''.includes('') is true. The spec already rejects the same shape for pr_body_contains for exactly this reason.",
          failure_scenario: "Probe: a lane with decision_match \"\" bound to a unique owner-signed record whose text has nothing to do with merging ('approve RFC X') validates {ok:true}. The binding then proves only that some owner decision exists at that ts, not that it authorizes this lane. This needs a policy edit, which GUARD_PATHS sends to the operator. Recommended disposition: (a) remediate in tree (parse_error on an empty decision_match, mirroring pr_body_contains), or (d) accepted residual at P3." }
      - { rank: NON-BLOCKING, file: .aai/scripts/claude-hook-gate.sh, line: 402,
          issue: "The hook resolves the PR head (LANE_HEAD) with one gh call, and the evaluator resolves headRefOid with a second, independent call. The allowed line does not name the head it judged, so the hook cannot confirm the evaluator judged the same head that --match-head-commit pins.",
          failure_scenario: "The PR head is force-pushed between the two calls, from H1 to H2 and back to H1. The evaluator judges H2, and gh then merges H1 because it matches --match-head-commit. This needs a deliberate race inside a sub-second window, and the hook is a guardrail, not a security boundary (R3). Recommended disposition: (d) accepted residual at P3, or (a) add head=<oid> to the allowed line and compare it in the hook." }
  cannot_verify:
    - { claim: "The real `gh pr view --json reviews,statusCheckRollup` shapes (reviews[].commit.oid, CheckRun vs StatusContext fields) match the fixtures; gh's reviews list is not truncated for PRs with many reviews", closes_with: "One live --check against a real PR with a review and mixed checks (spec R1)" }
    - { claim: "A real lane merge from this repository's main checkout passes lane-gate --sweep-check: its stale-head comparison uses the local HEAD of --repo-root, not the PR's headRefOid", closes_with: "A live dry-run of the hook lane path on a real PR from the checkout where merges are run" }
    - { claim: "Server-side branch protection and GitHub's --match-head-commit enforcement behave as P9 assumes", closes_with: "A live merge attempt with a stale --match-head-commit, refused by GitHub" }
  overall: fail
```

## Scope and preflight

- Diff: `git diff 64f2595f..f47f8861`, worktree `/Users/ales/Projects/aai-feat-configurable-merge-policy-lanes`, branch `feat/configurable-merge-policy-lanes`, HEAD f47f8861 (verified). The working tree's only extra changes are uncommitted appends to `docs/ai/EVENTS.jsonl` and `docs/ai/tests/test-runs.jsonl`, both telemetry and outside the reviewed range.
- Spec: frozen SPEC-0207-spec-configurable-merge-policy-lanes.md (ceremony 3) and accepted RFC-0015-configurable-merge-policy-lanes.md. The owner decisions for this ref are in decisions.jsonl: 2026-10-03T15:30:00Z, and the 2026-10-04 menu answers for rounds 4 and 5. All 12 spec amendments are disclosed under the additive-with-disclosure convention.
- Coaching check: the dispatch did not characterize findings, pre-rate severity or exclude any area.

## Evidence I ran myself (AAI_ROLE unset for suites)

| command | rc |
|---|---|
| `bash tests/skills/test-aai-merge-policy.sh` (48 PASS) | 0 |
| `bash tests/skills/test-aai-hooks-overlay.sh` (26 PASS) | 0 |
| `bash tests/skills/test-aai-doctor.sh` | 0 |
| `bash tests/skills/test-aai-constitution.sh` | 0 |
| `bash tests/skills/test-aai-prompt-diet.sh` | 0 |
| `bash tests/skills/test-aai-layer-profiles.sh` | 0 |
| `bash tests/skills/test-aai-ride-select.sh` | 0 |
| `node .aai/scripts/merge-policy.mjs --validate` -> `VALID lanes=1` | 0 |
| `node .aai/scripts/spec-lint.mjs --path <spec>` -> LINT PASS | 0 |
| `node .aai/scripts/mutation-gate.mjs --spec <spec>` -> GATE PASS 58 rows | 0 |
| scratch probe: unreadable EVENTS.jsonl fixture -> `MERGE-POLICY allowed` (B1) | 0 |
| scratch probe: `lane-gate.mjs --sweep-check` with EVENTS.jsonl a directory -> `LANE heavy reason=internal-error` | 0 |
| scratch probe: `classifyFiles(['-'], live policy)` -> kinds {repo} | — |
| scratch probe: empty decision_match lane validates ok | — |

Append-only ledgers: decisions.jsonl (+15/-0), EVENTS.jsonl (+13/-0) and test-runs.jsonl (+26/-0) are pure appends in the range (HAZ-LEDGER holds).

## Verdict 1 — spec_compliance: pass

All 23 Spec-AC rows are compliant, and every TEST-15xx named in the Test Plan exists and passes in the suites I re-ran. The mutation gate passes for all 58 rows.

Deviations from the frozen spec text:
- The Implementation-plan edge case for a zero-file PR is not met (NON-BLOCKING N3). No AC row names it, so it does not fail the AC walk.
- The `--debug-inputs` line prints before the `MERGE-POLICY` line, so with that flag stdout's first line is not the P10 verdict line. It is test-only and the hook never passes it (INFO).

## Verdict 2 — code_quality: fail

### BLOCKING
- **B1 — `.aai/scripts/merge-policy.mjs:1019` lets a failed sweep check through as a pass.** The "mandatory" sweep check is skipped whenever `lane-gate.mjs --sweep-check` fails internally. lane-gate's onError handler exits 0, and the evaluator only denies on exit 5. I reproduced this end to end: an unreadable EVENTS.jsonl with no sweep record gives `MERGE-POLICY allowed`, and the hook's gate 2b allows on the same rc 0. This contradicts P9, the Notes mapping ("every bot thread answered and resolved: mandatory sweep check") and the function's own comment. Fix: require `rc === 0` and a `SWEEP-CHECK allowed pr=<n>` first line, and add a RED-proofed regression test.

### NON-BLOCKING (WARNINGs, H6 disposition owed)
- **N1 — `:1331` does not bind the ride to the PR.** Recommended: promote to a follow-up (`suggested: fu-merge-policy-ride-pr-binding`, P2).
- **N2 — `:1076` makes `exclude_roadmap_capability` fail open** when the base roadmap is absent or malformed, or the ride ref is null. Recommended: remediate in tree, or `suggested: fu-merge-policy-roadmap-exclusion-fail-open` (P3).
- **N3 — `:1213` lets the zero-file sentinel `-` match `**`.** Recommended: remediate in tree (a one-line early return), or accepted residual at P3.
- **N4 — `:683` accepts an empty `decision_match`.** Recommended: remediate in tree (mirror the `pr_body_contains` rule), or accepted residual at P3.
- **N5 — `claude-hook-gate.sh:402` keeps the hook's head and the evaluator's judged head unbound.** Recommended: accepted residual at P3 (narrow deliberate race, R3 guardrail), or emit `head=` on the allowed line.

None of the suggested ids above are filed. The orchestrator records the dispositions.

INFO: the parser, textual canonical form, glob engine, requester-approval predicate, CI predicate and hook allow-list are carefully closed. I found no further misread-then-allow shape in parsePolicyLoose: tab indentation, quoted keys, `: ` inside values, leading zeros and comments after an apostrophe all fail closed through unknown_key, parse_error or noncanonical.

## cannot_verify

See the YAML block: live gh JSON shapes, a real-checkout sweep-check head comparison, and GitHub's server-side `--match-head-commit` enforcement.

## Next steps

1. Remediate B1 with a failing-first regression test (unreadable EVENTS.jsonl, or a lane-gate exiting 0 with no `SWEEP-CHECK allowed` line), then re-review.
2. Record a disposition for each of N1 to N5 per H6 in code_review.notes.
