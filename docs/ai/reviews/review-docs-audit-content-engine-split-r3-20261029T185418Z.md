# Code review r3: docs-audit-content-engine-split (delta 85f9ab6e)

```yaml
review:
  scope: "git show 85f9ab6e (dc25add4..85f9ab6e), plus what it touches in git diff main...85f9ab6e"
  spec: docs/specs/SPEC-0260-spec-docs-audit-content-engine-split.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "not touched by the delta; r2 pass stands" }
      - { ac: Spec-AC-02, call: compliant, citation: "TEST-2302 and TEST-2302b pass (aai-suite-select rc 0, this round); the doc-only probe still prints CORE aai-docs-content and no aai-docs-audit line" }
      - { ac: Spec-AC-03, call: compliant, citation: "not touched by the delta; r2 pass stands" }
      - { ac: Spec-AC-04, call: compliant, citation: "none of the four removed globs is in the AC-04 engine-input list; reviewer grep finds no real-tree read of them by any engine case; TEST-2306 (validation r4 rc 0) also covers $PROJECT_ROOT/<any> literal reads" }
      - { ac: Spec-AC-05, call: compliant, citation: "not touched by the delta; r2 pass stands" }
      - { ac: Spec-AC-06, call: compliant, citation: "not touched by the delta; r2 pass stands" }
      - { ac: Spec-AC-07, call: compliant, citation: "not touched by the delta; r2 pass stands" }
      - { ac: Spec-AC-08, call: compliant, citation: "suite-map.yaml:41-56 core list unchanged by the delta" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0260-spec-docs-audit-content-engine-split.md, line: 498,
          issue: "A1-n states two false facts. (1) It says suite-map.yaml 'was edited outside the original file list', but the file list at line 363 names tests/skills/suite-map.yaml. (2) It attributes the change to 'Validation r2 finding NB-2'. Validation r2 has no NB-2 (only F-R2-N1). The source is code review r2 NB-2. The decisions.jsonl record at 2026-10-29T18:07:55Z has the same misattribution ('Validation r2 NB-2').",
          failure_scenario: "The owner reads Amendment 1 at merge to decide whether to accept it. They look for NB-2 in VALIDATION-...-r2.md and do not find it. They also read A1-n as disclosing a file-list breach that never happened. The append-only ledger now holds the wrong source, so this is a false record." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-suite-select.sh, line: 2183,
          issue: "TEST-2302b has no Test Plan row, so mutation-gate (GATE PASS 12 rows) does not cover it. It is also negative-only: an empty selector output with rc 0 would pass it.",
          failure_scenario: "A future selector regression prints nothing and exits 0. TEST-2302b still passes. That regression is caught elsewhere in the same suite (TEST-2302 asserts the positive CORE line), so this TEST adds no protection for that case. The RED replay against the dc25add4 map was reproduced only by validation r4 (red-2302b-old.txt), not by a mutation record." }
  cannot_verify:
    - { claim: "No engine case reads CHANGELOG.md, README.md, docs/TECHNOLOGY.md or docs/project-sessions through an indirect path (a script that builds the path at runtime)",
        closes_with: "a runtime file-access trace of the engine suite. Literal grep and TEST-2306 cover only literal paths. Scripts the engine runs (docs-audit.mjs, docs-audit-core.mjs, generate-docs-index.mjs, spec-lint.mjs, check-test-registration.mjs, check-state.mjs) contain none of the four names, and docs-audit-core.mjs:43 excludes project-sessions." }
  overall: pass
```

security_relevant: false

## Scope

- Delta: commit 85f9ab6e on chore/docs-audit-content-engine-split. It changes suite-map.yaml, test-aai-suite-select.sh (TEST-2302b), spec A1-n plus the freeze re-stamp, the decisions.jsonl record, the INDEX regeneration, and adds the r2 review file to the commit.
- Interactions checked against the rest of main...HEAD: the core list, the aai-docs-content row, TEST-2302, TEST-2305 and TEST-2306, and the other suites that map or read the four paths.
- Coaching note: the dispatch pointed me at specific checks. It did not pre-rate any finding. The full delta was reviewed.
- Excluded on instruction (unrelated refresh): docs/ai/overview-data.json, docs/ai/overview.html.

## Checks performed

1. **Under-selection hole: none found.**
   - Grepping the six engine-suite files (test-aai-docs-audit.sh, lib/docs-audit-{body,closeout,gate}.test.mjs, docs-audit-live.sh) and test-aai-docs-content.sh for CHANGELOG, README, project-sessions and TECHNOLOGY finds one hit: test-aai-docs-audit.sh:7862. It is a `br_write` into a temporary fixture repository, so it is not a real-tree read.
   - The engine scripts these suites call also contain none of the four names. docs-audit-core.mjs:43 explicitly excludes project-sessions.
   - TEST-2306's `root_re` catches any `$PROJECT_ROOT/<path>` literal, including top-level files, and it passes (validation r4).
2. **Selection after the move:**
   - The four paths, run through the real selector this round:
     - project-sessions selects only core plus a companion, no FULL_RUN.
     - CHANGELOG.md selects aai-release.
     - README.md selects aai-roadmap.
     - docs/TECHNOLOGY.md selects aai-win-fallback.
   - None selects aai-docs-audit or FULL_RUN.
   - aai-docs-content is in `core:`, so the new project-sessions glob changes nothing about that suite's selection. It only keeps the path mapped, so the path does not fall to an unmapped FULL_RUN.
   - The one real-tree reader of project-sessions outside the engine is hygiene-pack test_091, and that suite is core. golden-flow and doc-number-reservation use the path only in fixtures.
   - Before this ride, project-sessions on main selected only the docs-audit row (which was core then). So no suite lost a selection it had on main.
3. **TEST-2302b under `set -euo pipefail`:**
   - `out="$(...)"` exits the suite loudly if node exits non-zero, so that path fails closed. This matches the TEST-2305 pattern.
   - There is no pipe into an early-closing reader.
   - The matcher is a `[[ =~ ]]` loop, so it cannot die on its own payload.
   - Anchoring:
     - `'SELECTED aai-docs-audit'` is unanchored. That can only over-match (stricter), and no other suite name starts with that prefix.
     - `^FULL_RUN` is anchored per line.
     - A `CORE aai-docs-audit` line would escape TEST-2302b, but TEST-2302 catches it (any line naming aai-docs-audit).
   - The test's name and log line claim only the four listed paths, so the universal-negative naming rule is not triggered.
4. **Amendment versus ledger:**
   - The A1-n text and the 18:07:55Z record agree on what changed: four globs dropped, project-sessions moved, TEST-2302b added.
   - The lead count went from thirteen to fourteen.
   - frozen_sha256 was re-stamped and mutation-gate reports GATE PASS with 12 rows.
   - Both the text and the record carry the misattribution in finding NB-1 below. The A1-n file-list claim is also false.
5. **D3 deviation:** D3 says "aai-docs-audit keeps every engine glob". A1-n discloses the removal of the four globs, and Amendment 1 governs where it differs from D3. Spec-AC-04's engine-input list never named these paths.

## Evidence (this round)

| Command | rc | Result |
|---|---|---|
| `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-suite-select.sh` | 0 | "PASS: shared docs paths skip the engine without FULL_RUN (TEST-2302b)"; "All aai-suite-select tests passed" |
| select-suites.mjs on each of the four paths | 0 | no aai-docs-audit, no FULL_RUN (see check 2) |
| `node .aai/scripts/mutation-gate.mjs --spec <spec>` | 0 | GATE PASS: 12 row(s) satisfied |
| `node .aai/scripts/spec-amend.mjs list --strict` | 0 | A1-n record listed as unsigned-tracked under fu-amend-docs-audit-content-engine-split |
| `node .aai/scripts/spec-lint.mjs --path <spec>` | 0 | LINT PASS |

Other suites: I rely on validation r4 (29/29 rc 0) at 85f9ab6e and did not re-run them.

## Warning dispositions (H6)

- **NB-1** (false facts in A1-n and the ledger). Recommended disposition: (a) remediate in the tree at close, or (b) file a follow-up. Disposition (d) is not allowed because the finding leaves a false record.
  - Fix the A1-n wording:
    - drop the "outside the original file list" claim;
    - change "Validation r2 finding NB-2" to "code review r2 finding NB-2".
  - Append a correction spec_amendment record for the ref. Do not rewrite the ledger (HAZ-LEDGER).
  - Re-stamp the freeze afterwards.
  - Folding this under the existing `fu-amend-docs-audit-content-engine-split` is acceptable, provided the owner's merge read of Amendment 1 includes the correction.
  - Not filed: `suggested: fu-docs-split-a1n-attribution` (P3).
- **NB-2** (TEST-2302b has no Test Plan row and is negative-only). Disposition (d):

accepted residual: NB-2, TEST-2302b has no Test Plan row and asserts only negatives. P3 assurance strength. TEST-2302 in the same suite carries the positive CORE assertion, validation r4 reproduced RED on the dc25add4 map, there is no observed bite and nothing false is recorded.

- Carried from r2, unchanged: NB-1 (allowlist header, owner decision) and NB-3 (accepted residual).

## Next steps

1. The orchestrator applies the NB-1 correction (text edit plus an appended correction record) or files the suggested follow-up.
2. The owner decides on Amendment 1 at merge.
3. Run one full sweep before close, as validation scheduled.
