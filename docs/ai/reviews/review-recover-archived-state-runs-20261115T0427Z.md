# Code Review — recover-archived-state-runs (PR #559), reviewer-fallback pass

Scope: `git diff origin/main...HEAD` on fix/recover-archived-state-runs at aae2469c. The focus is the two commits the earlier reviews did not see: 31d27ece (close ceremony) and aae2469c (DEP0187 guard).
Spec: docs/specs/SPEC-0292-spec-recover-archived-state-runs.md (SPEC-FROZEN, status done).
Earlier reviews: review-recover-archived-state-runs-20261115T0142Z.md (full, ecac2cf9) and -20261115T0318Z.md (delta to 7a8e39c3), both pass.
Mode: SKILL_PR step 5d reviewer fallback. No external bot reviewed this PR.
Dispatch note: the dispatch prompt named the areas to check. It did not pre-rate findings and it did not exclude any part of the diff. The earlier reviews' coverage of the code paths was used as a baseline, not as a scope limit.

security_relevant: false

```yaml
review:
  scope: "origin/main...aae2469c (PR #559); focus 31d27ece + aae2469c"
  spec: docs/specs/SPEC-0292-spec-recover-archived-state-runs.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "TEST-3734/3735; test-aai-metrics.sh rc 0 on aae2469c (this review)" }
      - { ac: Spec-AC-02, call: compliant, citation: "TEST-3736/3737; suite rc 0" }
      - { ac: Spec-AC-03, call: compliant, citation: "TEST-3738 PASS on aae2469c; real --dry-run under node 26.12 --throw-deprecation rc 0, recovered=0" }
      - { ac: Spec-AC-04, call: compliant, citation: "TEST-3739; suite rc 0" }
      - { ac: Spec-AC-05, call: compliant, citation: "TEST-3740; suite rc 0" }
      - { ac: Spec-AC-06, call: compliant, citation: "TEST-3741 (validation-waiver suite, per 0256Z sweep)" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-3742 (docs-audit suite, per 0256Z sweep); docs-audit --strict CLEAN on head" }
      - { ac: Spec-AC-08, call: compliant, citation: "TEST-3743 (orchestration-dispatch suite, per 0256Z sweep)" }
      - { ac: Spec-AC-09, call: compliant, citation: "TEST-3744/3745 (ride-handoff, per 0256Z sweep)" }
      - { ac: Spec-AC-10, call: compliant, citation: "TEST-3746/3747 (golden-flow, factory-report, per 0256Z sweep)" }
      - { ac: Spec-AC-11, call: compliant, citation: "TEST-3748 (ride-handoff, per 0256Z sweep)" }
      - { ac: Spec-AC-12, call: compliant, citation: "TEST-3749 PASS on head; extracted body rc 0 on docs/ai/METRICS.jsonl; mutation test (ride line given the recovery stamp) fails as it should; a later recovery line with another stamp still passes" }
      - { ac: Spec-AC-13, call: compliant, citation: "TEST-3750 (per 0256Z sweep, mutation re-stamped)" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: docs/ai/METRICS.jsonl, line: 318,
          issue: "The ride's own flush line was written at close (~03:28Z), before the aae2469c code fix (03:59Z) and this fallback review. Neither has a recorded run on the line, and nothing re-validated after aae2469c. The line keeps verdict_after_last_implementer: true.",
          failure_scenario: "The factory report and golden-flow read 16 runs and about $15.82 for this ride. The post-close remediation run, which changed metrics-flush.mjs, and this review run are missing, so the ride's cost and run count are understated." }
      - { rank: NON-BLOCKING, file: docs/ai/decisions.jsonl, line: 3008,
          issue: "The close restamp is recorded as 'restamp of an UNVERIFIED cause' (contract lane, owner signature owed). The cause is in fact mechanical. Reversing BOTH allocator rewrites (SPEC-0292-spec-... to SPEC-DRAFT-... and ISSUE-0115-... to ISSUE-DRAFT-...) on the head spec reproduces the stored anchor f53446c9... exactly. spec-amend's candidate rule (.aai/scripts/spec-amend.mjs:1480-1499) misses the intake because the spec frontmatter names it as the slug links.requirement: recover-archived-state-runs, not as a numbered basename.",
          failure_scenario: "Every spec whose links.requirement is a bare slug (SPEC-0291 does the same) gets an 'UNVERIFIED cause' contract amendment at close. That leaves an owner-signature debt on a purely mechanical rename and blurs the signal for real unexplained drift." }
  cannot_verify:
    - { claim: "aae2469c fixes TEST-3738 on CI under Node 24 (DEP0187 on stderr)",
        closes_with: "The green CI run on aae2469c, which the caller reports. Locally, node 22 does not warn and node 26 --throw-deprecation on the real --dry-run passed (rc 0). No Node 24 binary was tested." }
    - { claim: "The cited VALIDATION reports back the AC evidence cells",
        closes_with: "docs/ai/reports/** is gitignored, so the three cited reports exist only in this local worktree and a PR reader cannot open them. 0055Z is a FAIL-round report and is cited for real-data observations (the cloudflare-share-on-node NOTE, the base and head counts). TEST-3748 and several other ids are covered by the 0140Z and 0256Z full sweeps and the 17/17 mutation gate, not by name." }
    - { claim: "Suites other than test-aai-metrics.sh are still green on aae2469c",
        closes_with: "The CI run on aae2469c. Only the metrics suite was rerun here. The only code change since the 0256Z sweep is the one-line guard in metrics-flush.mjs." }
  overall: pass
```

## What was checked

### aae2469c — `latestValidationEvent` guard (.aai/scripts/metrics-flush.mjs:495-498)
- The normal flush path always passes `path.resolve(process.cwd(), opts.events)`, which is always a string (metrics-flush.mjs:1897). For a string, `typeof eventsPath !== 'string'` is false, so the guard does nothing and control goes to the same `fs.existsSync(eventsPath)` as before. The normal path is unchanged.
- The only call that passes a non-string is the recovery `buildEntry` (`eventsPath: null`, :1860). It reaches the guard through `verdictAfterLastImplementer` → `lastVerdictInstant` → `latestValidationEvent` (:934/:736/:722). The other EVENTS readers (`closedRefs`, `scanCloseEvents`, `eventsAppendOnlyWarning`) are not reachable from the recovery branch, so `fs.existsSync(null)` has no other call site.
- Proof: `node@26.12 --throw-deprecation .aai/scripts/metrics-flush.mjs --recover-archives --dry-run` → rc 0, a valid JSON plan, recovered=0 (idempotent on the real archives). `fs.existsSync(null)` with `--throw-deprecation` throws on node 26 and returns false on node 22. That confirms the cause the commit names.

### 31d27ece — close ceremony
- **The ride's own flush line** (METRICS.jsonl:318) is valid JSON and is the last line, with a trailing newline. It has 16 runs with full per-run fields (model_id, requested and actual model, harness, cost bounds), verdict PASS and strategy tdd. It has no `reconstructed` and no `flush_segment`. None of its (ref, role, started_utc) keys appears in any of the 65 recovery lines, and none of the recovery lines is for this ref (the focus skip worked). The whole ledger has no new duplicate run keys. The only duplicate is an old one inside line 177, which is also on main.
- **TEST-3749 selection:** the diff adds 66 METRICS lines. 65 of them carry `reconstructed.recovered_utc = 2026-11-15T00:09:46Z` and the 66th is the ride line. The selector matches on both the reason and the stamp, so it picks exactly those 65. Pins hold: 280 runs, 79080170 tokens, 21/44 segment split, and the prefix sha256 over 866116 bytes. METRICS.jsonl is the same on 5bbc129e and origin/main, so the prefix pin holds after merge.
- **AC table:** all 13 rows read `done`, each with 8 cells. There are no `|` or `\|` characters inside the cells. Every cited report path exists (locally, see cannot_verify). `spec-lint --path` gives LINT PASS (mutation gate exempt, terminal). `spec-amend list --strict` gives rc 0. `docs-audit --strict` gives CLEAN.
- **Numbering:** ISSUE-0115 and SPEC-0292 do not collide on origin/main. INDEX counts moved as expected (Active 3→2, Done 654→656, Drafts 15→14). The 0142Z report's spec path was rewritten to the numbered name. `links.pr/commits: []` matches precedent (SPEC-0291).
- **USER_GUIDE.md:2819** picks up the #558 routing sentence. This is close-work-item's USER_GUIDE rollup regeneration (close-work-item.mjs:849) catching up with a product doc that already merged, not a hand edit. INFO only.

## Warning dispositions (recommended; the orchestrator records them)
- NB-1 (METRICS.jsonl:318): remediate in tree. Record the aae2469c fix run and this review run, then re-flush. A flush after a reopen writes a `flush_segment` continuation line (SPEC-0291), so line 318 stays untouched.
- NB-2 (decisions.jsonl:3008): promote to follow-up, P3. spec-amend's `allocatorRewriteCandidates` should resolve a slug `links.requirement` or `links.intake` to its numbered basename. Separately, the owner can sign the restamp cheaply because the cause is proven mechanical: reverse ISSUE-0115 and SPEC-0292 → f53446c9....

## Side effects of this review (not restored, per instructions)
- docs/ai/EVENTS.jsonl: two `docs_audit` telemetry lines from the `docs-audit --strict` runs (04:28:35Z, 04:28:37Z).
- docs/ai/overview-data.json and docs/ai/overview.html were regenerated by the targeted `tests/skills/test-aai-metrics.sh` run (rc 0, "All aai-metrics tests passed").

## Next steps
Merge-ready from the review's side. Neither finding blocks. Record dispositions for NB-1 and NB-2.
