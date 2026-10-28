```yaml
review:
  scope: "working tree vs main f8614f67 (inline): .aai/scripts/lib/codex-rollout.mjs .aai/scripts/codex-usage.mjs .aai/scripts/live-parsers/codex.mjs .aai/SKILL_LOOP.prompt.md .aai/SUBAGENT_PROTOCOL.md .aai/system/PROFILES.yaml tests/skills/test-aai-codex-usage.sh tests/skills/test-aai-token-capture.sh tests/skills/test-aai-live-status.sh tests/skills/test-aai-hygiene-pack.sh tests/skills/test-aai-merge-cleanup.sh tests/skills/test-aai-pr-preflight.sh tests/skills/suite-map.yaml tests/skills/suite-weights.tsv tests/skills/lib/cd-subshell-leak-baseline.tsv tests/skills/lib/prompt-diet-ledger.sh tests/skills/test-aai-prompt-diet.sh docs/specs/SPEC-0258-spec-codex-usage-missing-from-run-budgets.md docs/issues/ISSUE-0106-codex-usage-missing-from-run-budgets.md CHANGELOG.md"
  spec: docs/specs/SPEC-0258-spec-codex-usage-missing-from-run-budgets.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "codex-rollout.mjs:241-259 (inWindow half-open, response_id dedupe across files, conflicting_duplicate), :148-166 (subsets only as _subset, inconsistent_total); TEST-3101..3103 green" }
      - { ac: Spec-AC-02, call: compliant, citation: "codex-rollout.mjs:168-198 (baseline before A, reset segments, Math.max(0) no negative, compaction flag); readFile:127-129 skips info:null; TEST-3104/3105 green" }
      - { ac: Spec-AC-03, call: compliant, citation: "codex-rollout.mjs:138-146 null not 0 + missing_field, :116-118 partial_tail/malformed, unavailable() reasons :219/:265/:336/:341; codex-usage.mjs:82 exit 4; TEST-3106/3107 green" }
      - { ac: Spec-AC-04, call: compliant, citation: "codex-rollout.mjs:12 ROLLOUT_DIRS, :73-104 firstMeta, :124 first meta only, :232 own thread_id filter; TEST-3108/3109 green" }
      - { ac: Spec-AC-05, call: compliant, citation: "codex-rollout.mjs:296-308 treeIds each id once, :254 cross-file dedupe; TEST-3110 green" }
      - { ac: Spec-AC-06, call: compliant, citation: "codex-usage.mjs:53-78 attachFlags; TEST-3111 (real append-run + real metrics-flush), TEST-3112 (real log-tick) green" }
      - { ac: Spec-AC-07, call: compliant, citation: "codex-usage.mjs:89-113 (exhausted = cumulative >= limit, exit 3/0/2/4, NOT enforced line without 'within'); TEST-3113/3114 green incl. real unattended-gate park" }
      - { ac: Spec-AC-08, call: compliant, citation: "codex-rollout.mjs:353-370 closed D8 rule; TEST-3115 green" }
      - { ac: Spec-AC-09, call: compliant, citation: "META_KEYS pick :65-69, no write path; TEST-3116 green (sentinel, fixture listing, git status, empty HOME)" }
      - { ac: Spec-AC-10, call: compliant, citation: "codex-usage.mjs:116-129 probe, app_server_token_events constant not_integrated; TEST-3117 green" }
      - { ac: Spec-AC-11, call: compliant, citation: "SKILL_LOOP.prompt.md step 2f diff; SUBAGENT_PROTOCOL.md:235 Codex bullet; PROFILES.yaml:123-125; suite-map aai-codex-usage row; live-parsers/codex.mjs imports codexHome; ledger +407 and TEST-012 pin 64324; state.mjs/metrics-flush.mjs/usage-note.mjs git diff --quiet f8614f67 rc 0 (reviewer re-run); TEST-3118/3119 green, TEST-3120 per validation round 2 full sweep 117/117" }
      - { ac: Spec-AC-12, call: compliant, citation: "TEST-3121 opt-in; docs/ai/reports/codex-usage-smoke-codex-usage-missing-from-run-budgets.md present (metadata-only, 11 lines); validation round 1 recorded rc 0 total 2240404 == last record. Reviewer did not re-run against the real CODEX_HOME." }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/codex-rollout.mjs, line: 236,
          issue: "Cumulative basis: an untimed token_count snapshot is silently dropped when the thread's meta timestamp parses (s.ts >= metaTs is false for NaN), and silently counted in-window when it does not (validation NB-8). Either way no missing_field:timestamp reason; the records path got this guard in round 2, the snapshot path did not.",
          failure_scenario: "Reviewer probe h-untimed: snapshot 100 at 10:01 then an untimed snapshot 500; observe reports total 100, degraded [], budget prints enforcement=active. 400 tokens vanish with an 'active' verdict." }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/codex-rollout.mjs, line: 250,
          issue: "Records without a response_id are never deduplicated, so a thread file present in both sessions/ and archived_sessions/ is counted twice with no degraded reason.",
          failure_scenario: "Reviewer probe h-noresp: identical file in both dirs, one record 100/10 with no response_id; observe reports 200/20/220, degraded [], and the printed append_run_flags would write a doubled METRICS record." }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/codex-rollout.mjs, line: 117,
          issue: "A newline-terminated but malformed LAST line is classified partial_tail (not degraded) although D5 reserves that for a truncated write in progress; readFile pops the trailing empty line before testing i === lines.length - 1, so a complete corrupt line and an unterminated one are indistinguishable.",
          failure_scenario: "Reviewer probe h-lastmal: last line '{...payload:{BROKEN}}\\n' — observe total 110, degraded [], partial_tail true, budget enforcement=active; the corrupt record's tokens are silently missing." }
      - { rank: NON-BLOCKING, file: .aai/SUBAGENT_PROTOCOL.md, line: 235,
          issue: "The Codex bullet tells the orchestrator to capture a role run with 'observe --thread auto --from <role start> --to <role end> --descendants' in the zero/multi-child case; codex-usage.mjs:147 labels every observe result usage_attribution=run, while D8 defines that case as attribution interval (it contains orchestration work). The METRICS note then carries a false attribution label.",
          failure_scenario: "A role that ran inline in the orchestrator thread is captured per the bullet via observe; METRICS note says usage_attribution=run instead of interval, so a later per-role cost analysis treats an interval slice that includes orchestration as a clean run. 'attribute --parent' gives the same numbers with the correct label." }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/codex-rollout.mjs, line: 218,
          issue: "Each observeThread call re-runs findThreadFiles over every rollout file, and observe(--descendants) additionally builds threadIndex over every file: O(threads x files) firstMeta reads (each up to 50 lines, first line often tens of KB) on every budget call, which step 2f runs before each dispatch; readFile also loads each thread file whole.",
          failure_scenario: "A CODEX_HOME that has accumulated ~1000 rollout files and a ride tree of ~30 threads does ~30k file opens/reads per tick. Today's machine has 60 files / 261 MB, so not observed; cost grows linearly with history." }
      - { rank: NON-BLOCKING, file: docs/ai/STATE.yaml, line: 597,
          issue: "code_review.scope omits tests/skills/test-aai-merge-cleanup.sh and tests/skills/test-aai-pr-preflight.sh, which this ride modified (both carry the +407 B prompt-diet pin arithmetic).",
          failure_scenario: "aai-pr stages only the recorded scope: the PR would ship the moved TEST-012 pin without the matching pr-preflight want_growth term and TEST-2923 later-credit fix, and both suites go red in CI." }
  cannot_verify:
    - { claim: "CODEX_THREAD_ID is exported by the Codex host, so 'budget --thread auto' ever reaches enforcement=active in a real ride", closes_with: "probe output from inside a real Codex orchestrator session (D6 says unverified; smoke records only whether it was set on this machine)" }
    - { claim: "A real Codex orchestrator actually runs step 2f before each dispatch and passes the printed flags verbatim", closes_with: "telemetry from one real Codex ride: RUN BUDGET lines per tick and METRICS notes with usage_source=codex_rollout" }
    - { claim: "Role subagents on Codex are thread_spawn children sharing the root session_id; a role launched as a separate 'codex exec' process (no parent_thread_id) would be silently outside the budget tree with enforcement=active", closes_with: "rollout metadata from a real AAI Codex ride showing every role thread under the root's parent chain" }
    - { claim: "Threads started on an older CLI (snapshots only) and resumed on a newer CLI (records) are measured correctly; D1 by design ignores snapshots once any record exists, so the pre-upgrade part of the window is dropped without a degraded reason (reviewer probe h-mixed: snapshot 1000 then record 110 -> total 110)", closes_with: "a check that no in-window snapshot predates the thread's first record, or a measured statement that resumed cross-version threads do not occur" }
    - { claim: "TEST-3121 real smoke equality (2240404) still holds on the current tree", closes_with: "AAI_CODEX_SMOKE=1 re-run of TEST-3121; reviewer did not read the real CODEX_HOME beyond counting files" }
    - { claim: "Budget latency on a large CODEX_HOME is acceptable per tick", closes_with: "timed budget run over a CODEX_HOME with >=1000 rollout files" }
  overall: pass
```

# Code Review — codex-usage-missing-from-run-budgets

security_relevant: false

- Scope: inline working tree on `main` vs HEAD f8614f67, paths above (the STATE `code_review.scope` plus the two test files the dispatch named and STATE omits). `docs/ai/overview-data.json`, `docs/ai/overview.html` excluded as not this ride's (dispatch statement; their 1-line diffs are a generated timestamp/data refresh). Ledgers (`EVENTS.jsonl`, `decisions.jsonl`, `test-runs.jsonl`) are append-only telemetry, not reviewed as code.
- Spec: docs/specs/SPEC-0258-spec-codex-usage-missing-from-run-budgets.md (frozen, spec-lint PASS on re-run).
- Dispatch note (anti-gaming): the dispatch listed validation's known NB items and invited re-classification. Recorded; the full scope was reviewed independently and the NB items were re-derived by probe rather than taken as given.

## Evidence the reviewer ran

- `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-codex-usage.sh` — all TEST-3101..3119 PASS, TEST-3121 SKIP (opt-in), "All aai-codex-usage tests passed".
- `git diff --quiet f8614f67 -- .aai/scripts/state.mjs .aai/scripts/metrics-flush.mjs .aai/scripts/lib/usage-note.mjs` — rc 0.
- `node .aai/scripts/spec-lint.mjs --path <spec>` — LINT PASS.
- Line caps: lib 370 / 420, CLI 150 / 260.
- Four scratch-fixture probes (h-noresp, h-lastmal, h-untimed, h-mixed) under the session scratchpad with `CODEX_HOME` pointed there; outputs quoted in the findings.
- Real CODEX_HOME: file count and sizes only (60 files, 61 MB sessions + 200 MB archived); no content read.

## AC table walk

All twelve Spec-AC rows are compliant; citations in the YAML block. The one deviation from the spec text: D12 says the reader "parses only lines whose type is ...", while `readFile` JSON-parses every line and then keeps only the metadata fields (validation NB-3). Output privacy holds (TEST-3116), so it is a wording deviation, not a behavioral one. Also: the spec's Acceptance Criteria Status column still says `planned` for every row while the Test Plan says `green`; the close ceremony should flip it.

## Findings

No BLOCKING finding. Re-classification check against the intake contract ("missing is not zero; never claim enforcement without data"): findings 1-3 each produce `enforcement=active` on an incomplete or inflated number, which is that contract's failure class. They stay NON-BLOCKING because each needs a log shape that the measured Codex CLI (0.163-0.165) does not write: every line is timestamped, every record has a response_id, and lines are newline-terminated whole. They are still cheap to close, so the recommended disposition is to fix them in the tree.

1. NB-A (= validation NB-8, extended): untimed snapshot dropped or counted silently. Lib :236 and :175/:182. Fix: in observeThread, give snapshots the same `missing_field:timestamp` guard the records path got.
2. NB-B: records without response_id are not deduplicated. Lib :250. Fix: degrade `missing_field:response_id` (or dedupe on a file-content key) when a record lacks one.
3. NB-C: a malformed last line that ends in a newline is treated as partial_tail. Lib :110/:117. Fix: decide partial_tail on whether the text ends with '\n', not on the line's position after the pop.
4. NB-D: the SUBAGENT_PROTOCOL bullet routes the interval case through `observe`, which labels it `usage_attribution=run`. Fix (prose): always use `attribute`, which covers both D8 branches.
5. NB-E: O(threads x files) meta scans on every budget call. Fix: build the file-to-meta index once per observe and pass it down.
6. NB-F: the recorded code_review.scope is missing two modified test files. Fixed by the scope string in the returned `set-code-review` command below.

Carried validation items NB-2 (descendant provenance thread id), NB-3 (D12 wording), NB-4 (TEST-3121 replay needs the opt-in), NB-5 (seam by convention), NB-6 (RED_CLASS re-capture): reviewer agrees they are NON-BLOCKING.

## Warning dispositions (H6, named by the reviewer; the orchestrator records them)

- NB-A, NB-B, NB-C: remediate in tree (P2: each can leave a false METRICS record or a false `active` verdict). If deferred instead, file them as a single follow-up, e.g. `fu-codex-usage-silent-shapes`. That follow-up is suggested, not filed.
- NB-D: remediate in tree (P2: leaves a false attribution label). SUBAGENT_PROTOCOL.md is outside the prompt-diet glob, so the change costs no ledger work.
- NB-E: promote to a follow-up (P3, performance), suggested id `fu-codex-usage-meta-index-once`.
- NB-F: remediated by the returned `set-code-review --scope`.
- NB-2..NB-6 (validation): dispositions as validation recorded them; NB-2 can ride with the NB-A..C fix.

## Next steps

Orchestrator: record the dispositions above. If NB-A..D are remediated in tree, a re-review or a delta re-check of codex-rollout.mjs, codex-usage.mjs and SUBAGENT_PROTOCOL.md follows, and so does the TEST-3118 pin if the bullet text changes.
