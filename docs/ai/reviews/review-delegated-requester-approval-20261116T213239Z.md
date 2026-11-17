# Code review: delegated-requester-approval

```yaml
review:
  scope: "git diff origin/main...HEAD (c1a90930...043b713e) restricted to .aai/scripts/merge-policy.mjs, tests/skills/test-aai-merge-policy.sh, docs/product/configurable-merge-policy-lanes.md, docs/USER_GUIDE.md, CHANGELOG.md, docs/issues/CHANGE-0258-delegated-requester-approval.md, docs/specs/SPEC-0299-spec-delegated-requester-approval.md"
  spec: docs/specs/SPEC-0299-spec-delegated-requester-approval.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "merge-policy.mjs:1309-1312 delegatedList returns [] when absent; requesterVerdict:997-1019; TEST-3850 + TEST-1510 PASS; 200k-case old/new differential probe 0 diffs" }
      - { ac: Spec-AC-02, call: compliant, citation: "merge-policy.mjs:974-989 relayReference (LF split, one trailing CR); TEST-3851 alone/prose/crlf/crlf_alone assert exact allowed line" }
      - { ac: Spec-AC-03, call: compliant, citation: "merge-policy.mjs:985,1014-1018; runCheck:1715-1716 login suffix; TEST-3852 empty/prose_only/no_body/null_body + not_contains requester_approval_missing" }
      - { ac: Spec-AC-04, call: compliant, citation: "RELAY_LINE_RE merge-policy.mjs:976, m[1]!==m[3]:987, candidates>1:986; TEST-3853 ten bodies" }
      - { ac: Spec-AC-05, call: compliant, citation: "requesterVerdict returns ok on first satisfying login, relayFailure only after loop:1013-1019; atHead/state gate before relay:1009-1011; TEST-3854" }
      - { ac: Spec-AC-06, call: compliant, citation: "parse branch merge-policy.mjs:611; validatePolicy:803-816; TEST-3855 (incl. duplicate_key, no requesters, control)" }
      - { ac: Spec-AC-07, call: compliant, citation: "LANE_SCALAR_KEYS:381-385, LIST_KEYS:212; TEST-3856 position, swapped->noncanonical, absent->no line" }
      - { ac: Spec-AC-08, call: compliant, citation: "product doc section 'Requesters without GitHub', USER_GUIDE.md:2899, CHANGELOG.md:33; TEST-3857" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: docs/product/configurable-merge-policy-lanes.md, line: 120,
          issue: "'Other lines in the body are ignored' is false: every line whose trimmed text starts with aai-relay in any case is a candidate, and a second candidate makes the review malformed",
          failure_scenario: "gateway appends a footer 'AAI-Relay gateway v2' (or quotes the requester's chat text 'aai-relay ok') next to a valid relay line: the lane is denied relay_reference_malformed, while the doc told the operator that line would be ignored (fails closed; operator misled)" }
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-policy.mjs, line: 805,
          issue: "validatePolicy only checks delegated_approvers when it is an array, and delegatedList (1310) coerces a non-array to []; a non-array value is silently read as 'no delegation' (fail-open shape) instead of being refused",
          failure_scenario: "an in-process caller passes a hand-built lane { requester_logins: ['bot'], delegated_approvers: 'bot' }: validatePolicy reports no error and evaluateLane allows the bot's APPROVED review with an empty body (probe: requesterVerdict(..., 'bot') -> {ok:true}). Not reachable through the CLI today: parsePolicy stores only arrays (parseRequiredList) and the textual canonical check refuses a mistyped value" }
  cannot_verify:
    - { claim: "gh pr view --json reviews returns reviews[].body (and normalizes line ends to LF or CRLF only)", closes_with: "one --debug-inputs run against a real PR carrying a bot review with a multi-line body" }
    - { claim: "a GitHub App/bot reviewer appears in that payload under the login spelling the doc example implies (content-gateway, not content-gateway[bot])", closes_with: "a real gh pr view --json reviews payload for an App-submitted review; if the [bot] form appears, the doc should say which spelling to list (a wrong spelling fails closed forever)" }
    - { claim: "the trust assumption (bot credential unreachable from agent tools) holds in any deployment", closes_with: "deployment-side review of the gateway host; out of the evaluator's reach by design (spec D4, R1)" }
  overall: pass
```

security_relevant: true

## Scope and spec

- Scope: `git diff origin/main...HEAD` (base c1a90930, head 043b713e) restricted to the seven paths named in the spec's review scope. Other paths in the range (docs/INDEX.md, EVENTS/decisions/roadmap ledgers) were not reviewed.
- Spec: docs/specs/SPEC-0299-spec-delegated-requester-approval.md (frozen, one disclosed amendment to the TEST-3853 mutation cell).
- Coaching note (anti-gaming contract): the dispatch prompt pre-characterized expected findings (the product doc's "Other lines in the body are ignored" sentence, the `delegatedList` placement) and pointed at areas to examine. Recorded here; the full scope was reviewed regardless, and both points were re-derived from code (NB-1 by probe, the placement as INFO only).

## Evidence run by this reviewer

- `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-merge-policy.sh` rc 0; TEST-1510 and TEST-3850..3857 PASS, "All tests passed!".
- `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-hook-gate.sh` rc 0 ("All aai-hook-gate tests passed").
- `.aai/scripts/hook-gate.mjs:88` LANE_ALLOWED_RE unchanged; the diff changes only the `lane=... reason=...` denial lines (`login=` suffix), never the `MERGE-POLICY allowed` line. TEST-3851 asserts the exact allowed line.
- Differential probe (`$TMPDIR/review-delegated-probe/probe.mjs`, log `probe.log`): origin/main merge-policy.mjs vs HEAD, 200,000 random review lists over 3 logins, 5 states, head/base/missing commits, null authors and bodies: `requesterApproved` and `evaluateLane` (lane with no `delegated_approvers`) produced 0 differences. Back-compat holds.
- relayReference probes: CR-only separator, `\r\r`, U+2028 prefix, markdown quote, HTML comment, dotted-I lookalike, `aai-relayed` prose next to a valid line all fail (missing or malformed); a line inside a code fence and a trailing LF pass. Ids such as `::` or `../..` pass the charset (by D2 design; the evaluator never dereferences them).
- requesterVerdict precedence probes: a failing delegated login listed first does not shadow a later human approval; an older valid relay superseded by a newer APPROVED without a line denies relay_reference_missing; a newer COMMENTED review carrying the line does not rescue an older APPROVED without one; on an equal submittedAt the first review in payload order wins (pre-existing P6 tie rule).

## AC table walk

| Spec-AC | Call | Citation |
|---|---|---|
| Spec-AC-01 | compliant | delegatedList → [] when absent; requesterVerdict with an empty delegated set returns ok exactly where the old predicate did (differential 0 diffs); TEST-3850 empty and absent body; TEST-1510 green |
| Spec-AC-02 | compliant | relayReference splits on LF, strips one trailing CR; TEST-3851 four bodies, exact allowed line, rc 0 |
| Spec-AC-03 | compliant | zero candidates → RELAY_MISSING; lane line `login=<escaped>`; TEST-3852 four bodies and a not-contains on requester_approval_missing |
| Spec-AC-04 | compliant | regex matched whole, platform equality, >1 candidates malformed; TEST-3853 ten bodies |
| Spec-AC-05 | compliant | state/atHead gates run before the relay check, so stale or superseded approvals never yield a relay reason; human login wins; TEST-3854 |
| Spec-AC-06 | compliant | parseRequiredList branch, three validate codes, duplicate_key via seenLaneKeys; TEST-3855 incl. --check policy_invalid |
| Spec-AC-07 | compliant | key order and LIST_KEYS; TEST-3856 |
| Spec-AC-08 | compliant | all named strings present; TEST-3857 |

Deviations from the frozen spec (none change behaviour):
- The plan says `evaluateLane` passes `lane.delegated_approvers || []`; the code uses a `delegatedList` helper with `Array.isArray`, which also maps a non-array to [] (see NB-2).
- The plan's edge case "a login with characters that need escaping in the lane line" has no authored test. Such a login cannot pass the parser (control characters have no canonical spelling), so the escape is defence in depth only.

## Findings

### NON-BLOCKING

- NB-1 docs/product/configurable-merge-policy-lanes.md:120 — "Other lines in the body are ignored." Code (merge-policy.mjs:982-986) treats any line whose trimmed text starts with `aai-relay` in any case as a candidate, and two candidates are malformed. Scenario: a gateway footer `AAI-Relay gateway v2` beside a valid line denies relay_reference_malformed. Fails closed; only the doc misleads. Recommended disposition: remediate-in-tree (replace the sentence with "Other lines are ignored unless they start with `aai-relay` in any letter case; such a line counts as a second relay line and the review is malformed.").
- NB-2 .aai/scripts/merge-policy.mjs:805 and :1310 — a present but non-array `delegated_approvers` is neither refused by validatePolicy nor treated as delegated by evaluateLane; it reads as "no delegation", which is the permissive direction for this guard. Not reachable through `--check`/`--validate` today (parser stores arrays only; textual canonical check), so it bites only an in-process caller with a hand-built lane. Recommended disposition: remediate-in-tree (in validatePolicy, push `parse_error` when the key is present and not an array), or accepted residual as P3 assurance strength if the owner prefers not to widen the diff.

### INFO (no failure scenario, never gates)

- `delegatedList` and its comment (merge-policy.mjs:1309-1312) sit between evaluateLane's long header comment and `export function evaluateLane`, so that header now reads as documenting the helper. Move the helper above the comment block.
- The old `requesterApproved` header comment (merge-policy.mjs:957-961) now precedes `DECIDING_REVIEW_STATES` and `relayReference`, far from the wrapper it describes.
- TEST-3854 `relay_only` asserts the allowed line but not rc 0 (the other allow cases assert both).
- Spec R3 (an edited review body changes the verdict on the next `--check`) is not repeated in the product doc's trust paragraph.

## cannot_verify

1. `gh pr view --json reviews` carries `reviews[].body` for real PRs. Every test feeds the body through the gh stub. Closes with one `--debug-inputs` run against a real PR with a bot review.
2. The login spelling a GitHub App reviewer has in that payload (`name` vs `name[bot]`). The doc example implies the bare form; a wrong spelling fails closed, never open. Closes with a real payload.
3. The trust assumption (bot credential unreachable from agent tools) is a deployment property the evaluator cannot check (spec D4, R1).

## Warning dispositions (H6)

- NB-1: recommended remediate-in-tree (doc sentence).
- NB-2: recommended remediate-in-tree (one validatePolicy branch plus a TEST-3855 case), else `accepted residual: P3 assurance strength, unreachable through the CLI because the parser stores only arrays and the canonical check refuses a mistyped value; no observed bite, no false record`.
The orchestrator records the chosen artifact for each.

## Next steps

Both verdicts pass. Apply NB-1 (and NB-2 or record its residual), then open the PR. The ride is in merge-policy's own GUARD_PATHS, so the owner merges it.
