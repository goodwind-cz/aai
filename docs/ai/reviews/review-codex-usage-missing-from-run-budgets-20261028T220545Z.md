```yaml
review:
  scope: "working tree vs main f8614f67 (inline), STATE code_review.scope: .aai/scripts/lib/codex-rollout.mjs .aai/scripts/codex-usage.mjs .aai/scripts/live-parsers/codex.mjs .aai/SKILL_LOOP.prompt.md .aai/SUBAGENT_PROTOCOL.md .aai/system/PROFILES.yaml tests/skills/test-aai-codex-usage.sh tests/skills/test-aai-token-capture.sh tests/skills/test-aai-live-status.sh tests/skills/test-aai-hygiene-pack.sh tests/skills/test-aai-merge-cleanup.sh tests/skills/test-aai-pr-preflight.sh tests/skills/suite-map.yaml tests/skills/suite-weights.tsv tests/skills/lib/cd-subshell-leak-baseline.tsv tests/skills/lib/prompt-diet-ledger.sh tests/skills/test-aai-prompt-diet.sh docs/specs/SPEC-0258-spec-codex-usage-missing-from-run-budgets.md docs/issues/ISSUE-0106-codex-usage-missing-from-run-budgets.md CHANGELOG.md"
  spec: docs/specs/SPEC-0258-spec-codex-usage-missing-from-run-budgets.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "codex-rollout.mjs:258 half-open inWindow, :260-266 response_id dedupe + conflicting_duplicate, :151-169 subsets only as _subset + inconsistent_total; TEST-3101..3103 green (reviewer run)" }
      - { ac: Spec-AC-02, call: compliant, citation: "codex-rollout.mjs:171-201 baseline before A, reset segments, Math.max(0), compaction flag; :131 skips info:null; TEST-3104/3105 green" }
      - { ac: Spec-AC-03, call: compliant, citation: "codex-rollout.mjs:25-29 null not 0, :141-149 missing_field, :111/:119 partial_tail only for an unterminated last line else malformed, :222/:277 + observe :348/:353 unavailable reasons; codex-usage.mjs:82 exit 4; TEST-3106/3107 green" }
      - { ac: Spec-AC-04, call: compliant, citation: "codex-rollout.mjs:13 ROLLOUT_DIRS, :74-105 firstMeta, :126 first meta only, :231/:238 own thread filter; TEST-3108/3109 green" }
      - { ac: Spec-AC-05, call: compliant, citation: "codex-rollout.mjs:308-320 treeIds each id once, :232 identical-copy digest skip, :264 cross-file response dedupe; TEST-3110 green" }
      - { ac: Spec-AC-06, call: compliant, citation: "codex-usage.mjs:53-78 attachFlags; TEST-3111 (real append-run + metrics-flush), TEST-3112 (real log-tick) green" }
      - { ac: Spec-AC-07, call: compliant, citation: "codex-usage.mjs:89-113 exit 3/0/2/4, NOT enforced line without 'within'; TEST-3113/3114 green incl. real unattended-gate park" }
      - { ac: Spec-AC-08, call: compliant, citation: "codex-rollout.mjs:365-382 D8 rule; TEST-3115 green" }
      - { ac: Spec-AC-09, call: compliant, citation: "META_KEYS pickMeta :66-70, no write path; TEST-3116 green" }
      - { ac: Spec-AC-10, call: compliant, citation: "codex-usage.mjs:116-129, app_server_token_events constant; TEST-3117 green" }
      - { ac: Spec-AC-11, call: compliant, citation: "SKILL_LOOP step 2f diff; SUBAGENT_PROTOCOL.md:235 Codex bullet (now attribute-first); PROFILES.yaml:123-125; suite-map aai-codex-usage; live-parsers/codex.mjs imports codexHome; ledger +407 / TEST-012 pin 64324; protected files git diff --quiet f8614f67 rc 0 (reviewer run); TEST-3118/3119 green; TEST-3120 neighbours per validation rounds 3-4 (full sweep 117/117)" }
      - { ac: Spec-AC-12, call: compliant, citation: "TEST-3121 opt-in SKIP in reviewer run; smoke report docs/ai/reports/codex-usage-smoke-codex-usage-missing-from-run-budgets.md and validation evidence; not re-run against the real CODEX_HOME by the reviewer (cannot_verify)" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/codex-rollout.mjs, line: 244,
          issue: "The NB-A guard for untimed snapshots fires before the basis is chosen, so a response_records thread that also carries an untimed token_count event is degraded with missing_field:timestamp although snapshots are not used on that basis.",
          failure_scenario: "Probe P1: one record 15 tokens plus an untimed token_count line; budget prints enforcement=degraded, degraded [missing_field:timestamp], and the METRICS note would carry usage_degraded=missing_field:timestamp. Conservative direction (never a false 'active'); shape not written by the measured CLI." }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/codex-rollout.mjs, line: 270,
          issue: "NB-B remediation flags differing copies without response ids as missing_field:response_id but still sums both copies, so the degraded number is inflated and budget can decide exhausted on it.",
          failure_scenario: "Probe P4: sessions/ copy (110) and a longer archived copy (110 + 2), no response ids; budget limit 200 -> 'exhausted cumulative=222 enforcement=degraded', exit 3, although real usage is 112. An unattended ride would park falsely; METRICS would carry 222 labelled degraded. Measured Codex writes response_id on every record." }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/codex-rollout.mjs, line: 335,
          issue: "Carried validation NB-2, still present: sumObservations spreads ok[0], so when the root has no usage events the observation's thread (and the note's codex_thread) is the first child's id, not the requested root.",
          failure_scenario: "Probe P5: observe --thread P --descendants, P with no records, child C 10 tokens -> codex_thread=C in append_run_flags; the METRICS note names the wrong thread for a parent-level run." }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/codex-rollout.mjs, line: 374,
          issue: "D8 under parallel (K>=2) dispatch: overlapping role windows make a sibling role's child count in two per-role runs. Spec-conformant (labelled interval), but per-role METRICS sums double count; budget is unaffected (root tree once).",
          failure_scenario: "Probe P3: children A (100) and B (1000) of P spawned 10:01 and 10:02; role A window [10:00:30,10:10) -> interval 1100, role B window [10:01:30,10:10) -> thread B 1000. B's 1000 tokens appear in both METRICS runs." }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/codex-rollout.mjs, line: 221,
          issue: "Carried round-1 NB-E: findThreadFiles per thread plus threadIndex re-read every rollout's first meta on every budget call; readFile loads each thread file whole.",
          failure_scenario: "~1000 rollout files and ~30 ride threads -> ~30k file opens per step-2f tick. Not observed at today's 60 files." }
  cannot_verify:
    - { claim: "CODEX_THREAD_ID is exported by the Codex host, so 'budget --thread auto' reaches enforcement=active in a real ride", closes_with: "probe output from inside a real Codex orchestrator session" }
    - { claim: "A real Codex orchestrator runs step 2f before each dispatch and passes the printed flags verbatim", closes_with: "telemetry from one real Codex ride (RUN BUDGET lines per tick, METRICS notes with usage_source=codex_rollout)" }
    - { claim: "Every Codex role is a thread_spawn descendant of the root; a role launched as a separate 'codex exec' process would sit outside the budget tree with enforcement=active", closes_with: "rollout metadata from a real AAI Codex ride" }
    - { claim: "Cumulative basis on a forked child: whether replayed parent token_count lines are stamped at or after the child's meta timestamp (then :245 keeps them and the child's delta absorbs the parent's cumulative total)", closes_with: "metadata-only inspection of a forked child rollout written by a snapshot-only (pre-record) CLI, or a statement that such CLIs never fork" }
    - { claim: "Threads resumed across CLI versions (snapshots then records) lose the pre-upgrade part of the window without a degraded reason (D1 by design)", closes_with: "a check that no in-window snapshot predates the first record, or a measured statement that cross-version resumes do not occur" }
    - { claim: "TEST-3121 real smoke equality still holds on the remediated tree", closes_with: "AAI_CODEX_SMOKE=1 re-run of TEST-3121 (reviewer did not read the real CODEX_HOME)" }
    - { claim: "Budget latency on a large CODEX_HOME is acceptable per tick", closes_with: "timed budget run over >=1000 rollout files" }
  overall: pass
```

# Code Review (round 2) — codex-usage-missing-from-run-budgets

security_relevant: false

- Scope: inline working tree on `main` vs HEAD f8614f67, exactly the STATE `code_review.scope` path list (round-1 NB-F is closed: merge-cleanup and pr-preflight suites are now in it). `docs/ai/overview-data.json` / `overview.html` excluded as not this ride's. Append-only ledgers not reviewed as code.
- Spec: docs/specs/SPEC-0258-spec-codex-usage-missing-from-run-budgets.md (frozen; spec-lint LINT PASS on reviewer re-run).
- Dispatch note (anti-gaming): the dispatch carried classification guidance (which shapes are BLOCKING vs NON-BLOCKING) and asked to focus on the remediation delta. That is pre-rating of severity; recorded here. The full scope was re-walked and every classification below rests on a probe or a cited line, not on the guidance.

## Evidence the reviewer ran

- `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-codex-usage.sh` — TEST-3101..3119 PASS, TEST-3121 SKIP (opt-in), "All aai-codex-usage tests passed".
- `git diff --quiet f8614f67 -- .aai/scripts/state.mjs .aai/scripts/metrics-flush.mjs .aai/scripts/lib/usage-note.mjs` — rc 0.
- `node .aai/scripts/mutation-gate.mjs --spec <spec>` — GATE PASS, 21 rows, degraded=0 unstamped=0.
- `node .aai/scripts/spec-lint.mjs --path <spec>` — LINT PASS.
- Line caps: lib 382 / 420, CLI 150 / 260.
- Five scratch-fixture probes (P1, P3, P4, P5 quoted in findings) under the session scratchpad with `CODEX_HOME` pointed there. Real CODEX_HOME not read.

## Remediation delta (round-1 NB-A..D, NB-F)

- NB-A (untimed snapshot): fixed. :244 degrades with `missing_field:timestamp` and skips; TEST-3104 extension pins observe and `budget enforcement=degraded`. Side effect: it also fires on record-basis threads (finding 1).
- NB-B (identical copies / no response id): fixed for identical copies by the whole-file sha1 digest skip at :232 (TEST-3109 `dup-file-total 110`); differing copies degrade at :270. The degrade does not remove the double count (finding 2).
- NB-C (terminated malformed last line): fixed. `terminated` at :111 decides partial_tail at :119; TEST-3106 `lastmal-*`.
- NB-D (protocol route): fixed. SUBAGENT_PROTOCOL.md:235 now leads with `attribute`, restricts `observe` to a known thread, and states both D8 labels; TEST-3118 pins it.
- NB-F: closed by the current STATE scope.
- No new silent-loss path found in the delta: every new skip (`continue`) either has a reason pushed on the same line or skips an exact byte-identical duplicate. Readability is fine; caps respected.

## AC table walk

All twelve rows compliant (citations in the YAML block). Deviations from the frozen text, carried from round 1 and unchanged: D12 says the reader "parses only lines whose type is ..." while `readFile` JSON-parses every line and keeps only metadata fields (privacy holds, TEST-3116); the AC Status column still reads `planned` (close ceremony flips it). Recorded spec amendments (mutation-cell re-anchors incl. TEST-3116) are open under `fu-amend-codex-usage-missing-from-909fcc` (owner sign-off owed).

## Findings

No BLOCKING finding. None of the five yields a false `active` verdict on a shape the measured Codex CLI writes; findings 1-2 err toward degraded/over-count, 3-4 are provenance labelling, 5 is cost.

1. Untimed-snapshot degrade fires on the records basis (lib :244). Fix: move the snapshot timestamp check into the `cumulative_snapshot` branch.
2. Differing no-response-id copies are degraded but summed (lib :270). Fix: when no response ids and >1 distinct copy, keep only the longest copy (prefix check) or return `enforcement` degraded with `usage` from one copy.
3. Root with no usage names the first child as the thread (lib :335) — validation NB-2, still open.
4. Parallel role windows double count a sibling child in per-role runs (lib :374, D8 design).
5. Meta re-scans per thread per tick (lib :221) — round-1 NB-E.

## Warning dispositions (H6, named by the reviewer; the orchestrator records them)

- Finding 1: remediate in tree (one-line move) or `accepted residual: P3 conservative over-degrade on an unwritten shape, never a false active`.
- Finding 2: promote, P3 — suggested `fu-codex-usage-noresp-copy-sum` (leaves an inflated, though labelled, number).
- Finding 3: per validation NB-2's existing disposition; if none recorded, promote P3 — suggested `fu-codex-usage-root-thread-label`.
- Finding 4: promote, P3 — suggested `fu-codex-attr-parallel-overlap` (D8 needs a parallel-dispatch rule; spec change).
- Finding 5: promote, P3 — suggested `fu-codex-usage-meta-index-once` (as in round 1).
All ids are suggested, not filed.

## Next steps

Orchestrator: record the dispositions above, then proceed to PR. Close ceremony flips the AC Status column; owner sign-off on the recorded amendments remains owed.
