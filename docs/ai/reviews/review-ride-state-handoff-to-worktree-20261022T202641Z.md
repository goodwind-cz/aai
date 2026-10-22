# Code Review: ride-state-handoff-to-worktree

```yaml
review:
  scope: d2824419..HEAD (HEAD d3cf01b8, branch change/ride-state-handoff-to-worktree, 23 files)
  spec: docs/specs/SPEC-0244-spec-ride-state-handoff-to-worktree.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/ride-handoff.mjs:279-305,435-454; TEST-001 (2 node cases) green" }
      - { ac: Spec-AC-02, call: compliant, citation: "ride-handoff.mjs:311-322,520-548; TEST-002 green" }
      - { ac: Spec-AC-03, call: compliant, citation: "ride-handoff.mjs:492,537-548; TEST-003 (incl. zero-run, focus-only, item-only edges) green" }
      - { ac: Spec-AC-04, call: compliant, citation: "TEST-004 green (real check-state + dispatcher, symlinked worktree path)" }
      - { ac: Spec-AC-05, call: compliant, citation: "TEST-005 green (real metrics-flush default and --sweep, whole-copy negative control)" }
      - { ac: Spec-AC-06, call: compliant, citation: "ride-handoff.mjs:375-396,531-546; TEST-006 green" }
      - { ac: Spec-AC-07, call: compliant, citation: "ride-handoff.mjs:95-118,466-486; TEST-007 green (see NB-2 for the non-REFUSE engine failure path)" }
      - { ac: Spec-AC-08, call: compliant, citation: "ride-handoff.mjs:403-416,495-540; TEST-008 green" }
      - { ac: Spec-AC-09, call: compliant, citation: "ride-handoff.mjs:569-604; TEST-009 green" }
      - { ac: Spec-AC-10, call: compliant, citation: "ride-handoff.mjs:555-588; TEST-010 green (see NB-1 for the unparsed-run gap)" }
      - { ac: Spec-AC-11, call: compliant, citation: ".aai/scripts/merge-cleanup.mjs:69,728-750,1134,1158-1161,1223; merge-cleanup TEST-075 and TEST-013 green" }
      - { ac: Spec-AC-12, call: compliant, citation: ".aai/SKILL_WORKTREE.prompt.md:70,179-180,197; .aai/SKILL_SHIP.prompt.md:36; TEST-012 green" }
      - { ac: Spec-AC-13, call: compliant, citation: "prompt-diet-ledger.sh +577 entry, test-aai-prompt-diet.sh all green, PROFILES core row, suite-map row; TEST-014 green" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/ride-handoff.mjs, line: 236,
          issue: "NB-1 (confirmed): entryRuns only recognises run items whose first line is `        - role:`; any other run item counts as zero, so reconcile skips the ledger check for it and removes the entry",
          failure_scenario: "origin entry whose agent_runs items start with `- model_id:` (hand repair or non-canonical writer) and an EMPTY METRICS.jsonl: reconcile printed `RECONCILED ride-demo cleared=0` and deleted both unledgered runs (probe, scratch). Violates D7.2 'a run is never deleted unless the ledger already holds it'; only the archive copy keeps them." }
      - { rank: NON-BLOCKING, file: .aai/scripts/ride-handoff.mjs, line: 520,
          issue: "NB-2 (confirmed): an engine refusal on the worktree write happens after the archive directory, record.json status started and draft copies were written; exit 1 without a REFUSE line",
          failure_scenario: "fresh worktree STATE with `metrics: {}`: writeState refuses the inline-header splice, out exits 1, origin STATE unchanged, but docs/ai/archive/handoffs/<R>-<stamp>/record.json stays `started` forever and the next run opens a second archive dir (probe, scratch)." }
      - { rank: NON-BLOCKING, file: .aai/scripts/ride-handoff.mjs, line: 273,
          issue: "NB-3 (new): putEntry converts `work_items: {}|null|~` to block form but not `work_items: []`; the R entry is spliced under the inline list and invalid YAML is written to the worktree STATE without any refusal (inlineChildConflicts only checks top-level headers)",
          failure_scenario: "worktree STATE with `  work_items: []` (a shape state.mjs append-run explicitly tolerates and converts, state.mjs:1255): out prints HANDOFF rc=0 and PyYAML then fails to parse the worktree STATE at the spliced entry (probe, scratch)." }
      - { rank: NON-BLOCKING, file: docs/ai/STATE.yaml, line: 0,
          issue: "NB-4 (confirmed): code_review.scope lists .aai/SKILL_MERGE.prompt.md and CHANGELOG.md, which the diff does not touch, and omits touched files (test-aai-hygiene-pack.sh, test-aai-pr-preflight.sh, suite-weights.tsv, decisions.jsonl, docs/INDEX.md)",
          failure_scenario: "SKILL_PR derives the staged scope from STATE/spec: a scope naming untouched files and missing touched ones produces a staged-vs-scope audit mismatch at PR time." }
      - { rank: NON-BLOCKING, file: tests/skills/lib/ride-handoff.test.mjs, line: 235,
          issue: "NB-6 (new): no fixture exercises the inter-block gap (blank / column-0 comment lines) that replaceBlock and removeItem preserve, nor a CRLF origin or a prefix-sharing ref",
          failure_scenario: "mutation `const gap = old.slice(contentOf(old).length)` -> `const gap = []` (scratch copy, RIDE_HANDOFF_SCRIPT) survives all 13 node cases; a regression that drops comments between blocks would ship green." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-prompt-diet.sh, line: 1042,
          issue: "NB-7 (new): the TEST-013 arm compares the ledger entry with the LIVE size of SKILL_WORKTREE + SKILL_SHIP against d2824419 forever (same shape as the slim TEST-010 arm)",
          failure_scenario: "the next scope that edits SKILL_SHIP.prompt.md or SKILL_WORKTREE.prompt.md (with its own correct ledger entry) turns TEST-012 red until it also edits this arm." }
  cannot_verify:
    - { claim: "Windows behaviour of out/reconcile (realpath, rename over existing files, mixed separators from git worktree list)", closes_with: "a Windows CI run of tests/skills/lib/ride-handoff.test.mjs (spec R2: no Pester case)" }
    - { claim: "Behaviour against a real concurrent origin writer between load and the final origin write (resume then refuses worktree_state_not_fresh if R's origin entry grew)", closes_with: "a fixture using AAI_STATE_INJECT_CONCURRENT on the origin write" }
    - { claim: "Downstream installs (.aai gitignored, worktree-seed snapshot) run the canon command as written", closes_with: "a scratch aai-sync install plus the SKILL_WORKTREE bash block end to end" }
    - { claim: "reconcile-origin firing rate on real merges (spec R3)", closes_with: "merge-cleanup journals over the next merges" }
  overall: pass
```

## Scope and preflight

- Worktree `/private/tmp/aai-ride-state-handoff`, branch `change/ride-state-handoff-to-worktree`, STATE `worktree.user_decision: worktree`, base `main`.
- Diff `d2824419..HEAD`: commits 9a91fd19 and d3cf01b8, 23 files, +2256/-18.
- Uncommitted files outside the scope (EVENTS.jsonl, roadmap.yaml, tests/test-runs.jsonl) are telemetry; not reviewed.
- Dispatch note (anti-gaming contract): the dispatch listed four prior findings (NB-1, NB-2, NB-4, NB-5) and asked for each to be confirmed or refuted. I treated that as a request to verify them and reviewed the full scope anyway. Each one was checked independently with a probe.

## Spec compliance

All 13 Spec-AC rows are compliant (walk above). The spec deviations are already disclosed:
- Constitution Article 6 (STATE written through the engine, not state.mjs).
- The measurement amendment in decisions.jsonl: the TEST file-path cells and the escaping of mutation cells.

Other observations:
- D1 says the script imports `lib/state-core.mjs`. It does not, and needs nothing from it. No behavioural impact.
- D9: SKILL_MERGE has no step list, so it stays unchanged, as the spec allows.

## Code quality

Nothing is BLOCKING. Probe results (all in the scratch pad, never in the shipping tree):

- **Prefix refs.** `reconcile --ref ride` and `--ref ride-demo-x` against the fixture both print `NOOP no_trace`. Every lookup is an exact compare after unquoting: `findBlock`, `metricsEntrySpan`, `parseItems`, `ledgerKeys`, `record.ref`. No prefix bleed.
- **Multi-line values.** An R item with a `>-` note that contains a blank line moved whole. Both STATE files parse with PyYAML, and the foreign items are intact.
- **CRLF origin.** The handoff succeeds and both files parse. The origin is rewritten as LF, which matches the engine's normalisation and what the spec says.
- **Single-item origin.** It collapses to `active_work_items: []`, and the gap is kept.
- **Quoted metrics key in the worktree.** For example `'other':`. checkFresh calls `entrySpan` and gets null, which throws a TypeError. Because this happens before any write, no damage results (INFO).
- **merge-cleanup idempotency.** The step re-runs on every apply. The second run is `noop` (TEST-075 and TEST-013 green: 6 no-ops, world digest unchanged). A refusal or a child failure (including exit 3 under `AAI_ROLE=subagent`) maps to `retained` plus a `remaining` entry, and never stops the run. `mergedRefs` is limited to intake docs left `done` with `links.pr` set to this PR, so an unrelated active ride is never reconciled.
- **Atomicity.** The write order matches D3. A crash after the worktree write resumes correctly (TEST-008). Gaps are NB-2 (an engine refusal after the archive) and NB-3 (an inline `[]` is not refused).
- **Windows.** The code handles Windows paths:
  - archive names carry no colons;
  - `safeRel` splits on both separators;
  - `realOr` normalises the `C:/` paths that git prints;
  - `moveFile` falls back on EXDEV;
  - a `path:` value such as `C:\x` needs no quoting.

  This is still unverified at runtime (see cannot_verify).

### Prior findings, confirmed or refuted
- **NB-1: confirmed.** See the YAML block. The archive copy keeps the data, but D7.2's "never" guarantee does not hold for runs it cannot parse.
- **NB-2: confirmed.** Exit 1 is shared with REFUSE, so the claim "exit 1 means nothing was written" is wrong for this path.
- **NB-4: confirmed.** The scope also omits files the diff does touch.
- **NB-5: refuted as a defect (INFO).** In argument mode, PowerShell expands `$AaiSourceRoot/.aai/...` into a single argument and quotes it for the native `node` call when it contains spaces. The line is also only a comment. Using `Join-Path` would match the style of the surrounding lines, but this is style only.

### INFO
- `--ref` is not validated before `path.join(base, \`${ref}-...\`)` builds the archive path. A ref containing `..` could create directories outside the archive. Callers are the orchestrator and merge-cleanup, which pass slugs from frontmatter.
- The canonical `out` command omits `--base-ref`. It falls back to the origin's `worktree.base_ref`, which M3 shows can belong to another session. That value is usually `main`, and when it is null the command exits 2 before any write.

## Warning dispositions (H6)

Recommended dispositions. The orchestrator records them; this reviewer files nothing.

| Finding | Severity | Recommended disposition |
|---|---|---|
| NB-1 | P2 | (a) Remediate in the tree. In `entryRuns` or reconcile, fail closed: count every `^ {8}- ` item under `agent_runs:`. If any item has no parsed role and started_utc, refuse `origin_runs_not_in_ledger`. The same count should feed checkFresh. Add a node case with a `- model_id:`-first run and an empty ledger. Otherwise (b): `fu-reconcile-unparsed-runs-fail-closed`, P2. |
| NB-2 | P3 | (b) `fu-handoff-engine-refusal-leaves-started-record`, P3. Run `writeState`'s duplicate-key and inline-header checks on both candidates before `newArchiveDir`, or mark the record `aborted` in a try/finally. |
| NB-3 | P3 | (a) Remediate in the tree with a one-token fix: `/^ {2}work_items:\s*(\{\}\|\[\]\|null\|~)\s*$/` at ride-handoff.mjs:273, plus a case. Otherwise (b): `fu-handoff-inline-empty-work-items`. |
| NB-4 | P3 | (a) Remediate in the tree. The `set-code-review` command returned with this review records the actual diff scope. |
| NB-6 | P3 | (d) `accepted residual: inter-block gap preservation, CRLF and prefix-ref shapes are verified by reviewer probes only; no observed bite, and no false record.` |
| NB-7 | P3 | (b) `fu-prompt-diet-live-size-arms-time-bomb`, P3, covering both the slim TEST-010 arm and this one (the class). Pin the measured size at the scope's own head blob instead of the live file. |

## Evidence

- `env -u AAI_ROLE bash tests/skills/test-aai-ride-handoff.sh`: exit 0, all aai-ride-handoff tests passed (TEST-000..010, 012, 014).
- `env -u AAI_ROLE bash tests/skills/test-aai-merge-cleanup.sh TEST-075|TEST-013|TEST-010|TEST-058`: all PASS.
- `env -u AAI_ROLE bash tests/skills/test-aai-prompt-diet.sh`: "All tests passed!" (TEST-012 = 58478).
- `node .aai/scripts/spec-lint.mjs --path <spec>`: LINT PASS. `check-vendored-script-deps.mjs`: CLEAN.
- Reviewer mutations, run against a scratch copy of `.aai/scripts` through `RIDE_HANDOFF_SCRIPT`:
  - killed: drop the ledger check, skip freshness, no tdd reset, always reset the worktree block, no hitl check, keep the origin entry;
  - survived: dropping the gap (NB-6).

## Next steps

Merge readiness is not blocked. Before closeout, the orchestrator records the NB dispositions above. Remediating NB-1 and NB-3 in the tree is cheap and recommended.
