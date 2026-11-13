# Code Review — routing-tables-have-an-owner-and-a-seam (round 1)

```yaml
review:
  scope: "git diff origin/main...HEAD (ba4d753a) over code_review.scope + tests/skills/test-aai-harness-shims.sh"
  spec: docs/specs/SPEC-0289-spec-routing-tables-have-an-owner-and-a-seam.md
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "MODEL_ROUTING.yaml:122-132 routing_meta; TEST-3660 green" }
      - { ac: Spec-AC-02, call: compliant, citation: "table-freshness.mjs:98-132,312-333; TEST-3661 green" }
      - { ac: Spec-AC-03, call: compliant, citation: "table-freshness.mjs:80-96,120-123; TEST-3662 green" }
      - { ac: Spec-AC-04, call: compliant, citation: "aai-doctor.mjs catRoutingTables + runDoctor; TEST-3663/3664 (sweep test-20261113-140700)" }
      - { ac: Spec-AC-05, call: non-compliant, citation: "table-freshness.mjs:186-187 uses readMarker only; a future head stamp (INVALID per D-READ) is not a VIOLATION. repro-cr1-future-stamp-passes-guard.sh" }
      - { ac: Spec-AC-06, call: compliant, citation: "test-aai-pricing.sh live_guard + TEST-3666; suite-map.yaml aai-pricing globs" }
      - { ac: Spec-AC-07, call: compliant, citation: "table-freshness.mjs:251-293; TEST-3667 green" }
      - { ac: Spec-AC-08, call: compliant, citation: "TEST-3668/3669 green; empty allow-stale list" }
      - { ac: Spec-AC-09, call: compliant, citation: "TEST-3670; dispatch suite pins TEST-020/026/038/057 moved; sweep green" }
      - { ac: Spec-AC-10, call: compliant, citation: "ROUTING_REFRESH.routine.md; TEST-3671" }
      - { ac: Spec-AC-11, call: compliant, citation: "universal-routines.md owner command; TEST-3672" }
      - { ac: Spec-AC-12, call: compliant, citation: "PROFILES.yaml core/extended entries; TEST-3673" }
      - { ac: Spec-AC-13, call: compliant, citation: "CHANGELOG.md:33; aai-doctor.md CAT-21; TEST-3675/3676" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/table-freshness.mjs, line: 186,
          issue: "stamp-guard validates the head marker with readMarker() only, skipping the D-READ future-stamp rule that checkTables() applies; guard and check disagree on the same marker",
          failure_scenario: "a refresh writes last_updated_utc 2027-11-13 (year typo). Live guard: CHANGED-STAMPED exit 0, PR merges; every doctor (here and downstream after /aai-update) prints CAT-21 WARN INVALID future for a year; the correcting PR lowers the stamp and the live guard (TEST-3666) refuses it as 'lowered' on every run, with no override" }
      - { rank: NON-BLOCKING, file: .aai/scripts/table-freshness.mjs, line: 167,
          issue: "gitShow() maps any `git show` failure to null, which stampGuard reads as 'base had no table' (contentChanged and stampAdvanced both true): fail-open",
          failure_scenario: "blobless clone with promisor unreachable: an unstamped routed change passes CHANGED-STAMPED exit 0 (full clone: VIOLATION exit 1). repro-cr1-gitshow-error-fails-open.sh" }
      - { rank: NON-BLOCKING, file: .aai/routines/ROUTING_REFRESH.routine.md, line: 61,
          issue: "Step 2 says to add an unverifiable id to 'the live test's --allow-stale list', but TEST-3668 has no such list, pins --since 2026-11-13, and fails on any ALLOWED line",
          failure_scenario: "December run cannot verify gemini-3-flash-preview and adds --allow-stale gemini-3-flash-preview: routed prints ALLOW-UNUSED (its last_verified 2026-11-13 is not before the pinned since) and exit 1, and TEST-3668 also refuses ALLOWED; the agent has to improvise a test edit the contract does not describe" }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-doctor.mjs, line: 666,
          issue: "catRoutingTables catches every checkTables exception as 'bad AAI_TABLES_HORIZON_DAYS', then calls checkTables again outside a try",
          failure_scenario: ".aai/system/PRICING.yaml unreadable or a directory: EISDIR/EACCES escapes the second call and the doctor crashes with a stack trace and no category output, where the spec says CAT-21 never FAILs" }
  cannot_verify:
    - { claim: "refreshed ids and list prices (claude 4/20, 2/10, 0.10/0.50; codex gpt-6*; gemini-3.1-pro-preview) match the vendor pages", closes_with: "an independent re-read of the URLs in refresh-record.md" }
    - { claim: "live stamp-guard (TEST-3666) is green on the PR merge-commit checkout and on push-to-main/nightly", closes_with: "green skill-suite run on the PR head and the first post-merge main run" }
    - { claim: "ROUTING_REFRESH run by a scheduled agent reads only primary sources and stops in a downstream install", closes_with: "the owner's TEST AT CREATION run (R2)" }
    - { claim: "aai-sync.ps1 core profile delivers table-freshness.mjs", closes_with: "pwsh run of TEST-3673 or the install-path parity suite (R7)" }
  overall: fail
```

security_relevant: false

## Scope

- Diff: `git diff origin/main...HEAD`, HEAD `ba4d753a` (2 commits; `ba4d753a` changes only the CHANGELOG text and EVENTS since sweep head `8bd88112`).
- Spec: frozen `SPEC-0289-spec-routing-tables-have-an-owner-and-a-seam.md`, one recorded measurement-only amendment (decisions.jsonl line 2964).
- Dispatch note: the dispatch listed focus areas, not expected findings or severities. I reviewed the full scope regardless.
- Ran: `test-aai-pricing.sh` at HEAD → exit 0, all 12 cases PASS. I did not re-run the full sweep, which was green at `8bd88112`.

## Findings

### B1 (BLOCKING): stamp-guard accepts a future head stamp
`backed-by: repro docs/ai/reports/routing-tables-have-an-owner-and-a-seam/repro-cr1-future-stamp-passes-guard.sh`. The script exits 1 when it reproduces the defect, and it did.

Under D-GUARD, an INVALID head marker is a VIOLATION. D-READ defines a stamp more than one day after now as INVALID. `stampGuard` (table-freshness.mjs:186) only calls `readMarker`, and the future rule lives in `checkTables` (:120). Measured:
- guard `CHANGED-STAMPED` exit 0.
- `check` `INVALID ... future last_updated_utc` exit 1.
- the correcting PR is refused with `VIOLATION ... lowered` exit 1.

The monthly writer of these stamps is an LLM-run routine, so a typo here is not hypothetical. The cost is a year of CAT-21 WARN for every consumer, plus a guard that blocks the fix.

Fix (in-tree): in `stampGuard`, treat `head.stamp > now + 1 day` as `VIOLATION invalid head marker: future last_updated_utc`, sharing the rule with `checkTables`. Add the case to TEST-3665 and a mutation. This adds wall-clock dependence only for stamps already in the future.

### NB1: git show errors fail open (P2)
The repro is `repro-cr1-gitshow-error-fails-open.sh`. Recommended disposition: remediate-in-tree. Separate "path absent at base" from other errors, for example `git cat-file -e <base>:<path>` or the `git show` stderr, and make the second case exit 2. The CI full clone is not affected, which is why this is NON-BLOCKING.

### NB2: the routine's allow-stale instruction contradicts the live test (P2)
Recommended disposition: remediate-in-tree. Either make TEST-3668 read `--since` from the routing_meta stamp date and take an explicit, commented allow-stale array (and allow ALLOWED lines for it), or reword Step 2 to say what the routine edits. Otherwise, promote it to a follow-up beside `fu-routing-pins-structural`.

### NB3: the doctor crashes on an unreadable table (P3)
Narrow the catch to the RangeError from the horizon check. Report any other error as `CAT-21 WARN <file> unreadable`. Disposition: remediate-in-tree, or `accepted residual: P3 edge, no observed bite` if the orchestrator prefers.

### INFO (never gates)
- MODEL_ROUTING.yaml (comment above `Validation@lightweight`) still says "With the CURRENT tier map (standard: claude-sonnet-5)". That comment is stale. The resolution is unaffected.

## Checked, no finding
- **What the stamp guard compares.** It compares every line `loadModelRouting` turns into a model id: two-space rows under `tiers`/`roles` (@h) and `validation_alternate` (@h). Its line set is a superset (any indentation). Moving effort sections, comments or routing_meta cannot hide a routed change. `lookup_rules`/`cost_blend` are excluded, as the spec states.
- **Live guard over time.** On push-to-main and nightly, merge-base = HEAD, so the result is UNCHANGED. On later rides that leave the tables alone it is UNCHANGED. On a PR merge commit, base = origin/main. A release cut only touches the CHANGELOG. Every skill-suite job checks out with `fetch-depth: 0`. A shallow clone fails closed (rc 3, explicit). It does not skip.
- **CAT-21 cannot turn a clean doctor into a failure.** It is WARN-only, and exit stays 0 without `--strict`. The self-hosting-smoke step accepts rc 0 or 1 and checks only CAT-20. TEST-015 asserts shape, not status. Every `--strict` fixture is table-less (TEST-3664). The update suite stubs or copies the doctor without the tables.
- **The routine never merges.** MERGE-GATES is empty, and TEST-3671 asserts the merge-authorised render has no merge command. The step-0 `git ls-files --error-unmatch` guard stops it in installs that gitignore `.aai/`.
- **Clock dependence of the new tests.** They pass `--now`, set `FRESH_H=100000`, or compute stamps relative to the clock (TEST-3663). TEST-3668 pins `--since 2026-11-13`, which later refreshes can only satisfy.
- **TEST-3012 narrowing.** Adding `/SPEC-0184-/` still selects exactly the two 2026-09 records (decisions.jsonl lines 1318 and 1319). The new SPEC-DRAFT amendment is excluded, before and after the allocator rename.

## Next steps
Remediate B1 (one round). Name a disposition for NB1–NB3. Then re-review with the same single pass.
