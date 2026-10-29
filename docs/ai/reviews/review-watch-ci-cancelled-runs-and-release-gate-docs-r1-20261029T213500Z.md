```yaml
review:
  scope: git diff main...HEAD (head e7290ba4, branch fix/watch-ci-cancelled-runs-and-release-gate-docs; STATE code_review.scope path list)
  spec: docs/specs/SPEC-0261-spec-watch-ci-cancelled-runs-and-release-gate-docs.md (SPEC-FROZEN)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/lib/github-checks.mjs:132-178; TEST-2701, TEST-2702 PASS (aai-current-head-ci, rc 0)" }
      - { ac: Spec-AC-02, call: compliant, citation: "github-checks.mjs:132 (only run-level cancelled), :160 (workflow_id and event); TEST-2703 four arms PASS" }
      - { ac: Spec-AC-03, call: compliant, citation: "github-checks.mjs:137-148 (pages, total_count, unique ids, head, identity), :174 drop then required-missing at :216; TEST-2704 seven arms PASS" }
      - { ac: Spec-AC-04, call: compliant, citation: "only github-checks.mjs:137 holds actions/runs?head_sha; lazy guard :133; TEST-2705 PASS (stub exits 91 on an unexpected run-list call)" }
      - { ac: Spec-AC-05, call: compliant, citation: ".aai/scripts/release-notes-gate.mjs:13-14; TEST-2706 PASS (staged and range, refuse, entry, no-notes)" }
      - { ac: Spec-AC-06, call: compliant, citation: "release-notes-gate.mjs:13 anchored full-name regex, :14 exact equality and ^docs/product/; TEST-2707 PASS" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-2708 parses aai-sync.sh:579 and aai-sync.ps1:578 plus README.md; PASS" }
      - { ac: Spec-AC-08, call: compliant, citation: "release-finish.mjs:187 uses the same isShipped; TEST-2709 PASS (with-notes prints #102 only; bare prints both)" }
      - { ac: Spec-AC-09, call: compliant, citation: "CHANGELOG.md preamble +23-27 and new unreleased entry; docs/product/release-notes-gate.md:16; docs/product/release-command-finish.md:68; TEST-2710 PASS" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/github-checks.mjs, line: 137,
          issue: "The workflow-run list is read after the check-run pages and the per-run fetches, with no re-read; a sibling that registers a check and completes between the two reads is seen as completed-without-the-name, so the superseded observation is dropped.",
          failure_scenario: "Non-required watch (SKILL_PR.prompt.md:301 runs watch-ci --pr <n> without --required): poll reads check-runs (sibling X not yet created), sibling creates X, X fails, sibling completes; run-list read shows completed; cancelled run's X is dropped (:174), X vanishes from the output and watch-ci can exit 0 while X failed. In --required mode the same race refuses closed (exit 3, spurious degrade), never pass. Window is the per-run fetches plus one list call, so seconds." }
      - { rank: NON-BLOCKING, file: CHANGELOG.md, line: 33,
          issue: "The new unreleased entry says 'the eight documentation paths named above'; the paths are in the preamble, which is not part of the rolled release section.",
          failure_scenario: "aai-release rolls this entry into a versioned section and the GitHub release body; the reader sees 'named above' with no list above it." }
      - { rank: NON-BLOCKING, file: docs/USER_GUIDE.md, line: 2909,
          issue: "The user guide still carries the old wholesale exemption sentence ('Documentation, tests, and evidence-only changes are exempt'), word for word what this scope removed from docs/product/release-notes-gate.md; line 810 says 'Docs and test-only changes are exempt'. USER_GUIDE.md is itself now a shipped path.",
          failure_scenario: "A contributor follows the user guide, edits docs/product/x.md without notes, and the CI release notes job refuses the PR; the guide contradicts the gate." }
      - { rank: NON-BLOCKING, file: .aai/SKILL_PR.prompt.md, line: 163,
          issue: "Step 3b still states 'Docs/test/evidence-only changes are exempt.' (not edited: D7 avoids prompt-corpus growth). The gate still runs unconditionally, so the agent is not misled into skipping it, only into expecting a pass.",
          failure_scenario: "An /aai-pr ride on a README-only change predicts exempt and is surprised by the refusal; also applies downstream, where the shipped SKILL_PR runs the same widened classifier over the downstream repository's own README.md and docs/product/**." }
      - { rank: NON-BLOCKING, file: .aai/scripts/release-notes-gate.mjs, line: 14,
          issue: "new RegExp('^docs/product/') exists only to keep the frozen TEST-2707 mutation applicable (validation F2) and has no comment saying so.",
          failure_scenario: "A later simplify pass rewrites it as a regex literal or startsWith; the TEST-2707 mutation record stops applying and the mutation gate refuses on an unrelated PR." }
  cannot_verify:
    - { claim: "Real GitHub timing: the newer run's jobs register after the cancelled run's checks exist, and run-level conclusion is 'cancelled' (not 'failure') for a concurrency cancel.",
        closes_with: "One live PR with an edited body watched by watch-ci --required at the branch head (spec Seams residual). Phase 1 of tests/fixtures/watch-ci-pr515.json is a reconstruction, its provenance says so." }
    - { claim: "GitHub's actions/runs?head_sha listing returns a total_count consistent with the pages and at most 1000 results for a filtered query; a head with more runs refuses closed (incomplete pagination) rather than passing.",
        closes_with: "API contract check or a live head with many runs; fail-closed direction verified by code reading (:140)." }
    - { claim: "Downstream effect of the widened classifier: in a downstream install the gate (SKILL_PR 3b, aai-release audit) now treats the downstream repo's own README.md, AGENTS.md, ..., docs/USER_GUIDE.md and docs/product/** as shipped, while README_AAI.md (the file aai-sync actually writes) stays exempt.",
        closes_with: "A scratch aai-sync install with a README-only PR through /aai-pr, and an owner statement that this downstream behavior is intended." }
    - { claim: "History stays green (D6): aai-release --dry-run prints Preconditions none.",
        closes_with: "Validation r1 measured it (release-dry-run.log); not re-run by this reviewer." }
  overall: pass
```

security_relevant: false

# Code review r1: watch-ci cancelled runs and release-gate docs

- Scope: `git diff main...HEAD`, head `e7290ba4`, worktree `/Users/ales/Projects/aai-wt-watch-ci-release-gate`, base `main`. Four commits (1096ee0d, 3707c1ce, 2a3cdbf7, e7290ba4). Working tree: `docs/ai/EVENTS.jsonl` and `docs/ai/tests/test-runs.jsonl` modified (runtime telemetry from the Validation run, not part of the reviewed diff).
- Spec: `docs/specs/SPEC-0261-spec-watch-ci-cancelled-runs-and-release-gate-docs.md` (frozen).
- Dispatch note: the dispatch named focus areas and relayed validation NB F1/F2. It did not rate severity or exclude areas. The full scope was reviewed.

## Evidence run by the reviewer

| Command | rc | Result |
|---|---|---|
| `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-current-head-ci.sh` | 0 | TEST-001..004, TEST-2701..2705 PASS |
| `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-release-notes.sh` | 0 | legacy TEST-001..005 and comment parser (34 assertions) PASS; TEST-2706..2710 PASS; failures=0 |
| Scratch probe of `readCurrentChecks` with an injected `run` transport (scratchpad `probe.mjs`) | 0 | chain of cancelled runs -> pending; intermediate cancelled run holding the check -> pending; completed cancelled sibling holding the check -> its own `cancel` stands; non-required completed sibling without the name -> observation dropped; cancelled success job with in-flight sibling -> pending; only an older sibling -> `fail` kept; cancelled run without `workflow_id` -> throws `malformed cancelled workflow identity`. Each run issued exactly one run-list call. |

## AC table walk

| Spec-AC | Call | Citation |
|---|---|---|
| Spec-AC-01 | compliant | Supersession block `github-checks.mjs:132-178`: the synthetic pending observation keeps name, provider, kind and orderKind and takes `[siblingTime, sibling.id, 0]` (spec plan step 1). TEST-2701 (two-phase hand fixture) and TEST-2702 (PR #515 replay) run both watch-ci (real CLI, fixture gh) and the release reader on one transport. |
| Spec-AC-02 | compliant | Only `conclusion==='cancelled'` (:132); sibling must match `workflow_id` and `event` and be newer by (`created_at`, id) (:149-163). TEST-2703: no sibling, other event, other workflow, failed older run. Each exits 5 naming `aggregate`, and the release bucket stays fail/cancel. |
| Spec-AC-03 | compliant | Malformed pages, total_count mismatch, duplicate id, foreign head, bad identity all `fail()` (:138-148); a completed sibling drops the observation and the required name refuses at :216. TEST-2704 covers 7 arms: watch-ci exit 3 + `degraded`, release reader throws (exit 20). |
| Spec-AC-04 | compliant | The tree walk finds exactly one file containing `actions/runs?head_sha`. watch-ci.mjs and release-finish.mjs import `readCurrentChecks` and contain no `actions/runs`. The all-success Actions fixture issues zero list calls, and the stub refuses an unexpected one with exit 91, so the lazy guard is proven by the stub and not only by the call log. |
| Spec-AC-05 | compliant | `release-notes-gate.mjs:13-14`. TEST-2706 covers each of the 8 paths alone, staged and range: REFUSED naming the path, PASS with a new entry, PASS with a no-notes reason. |
| Spec-AC-06 | compliant | Anchored `^(?:README\|...)\.md$`, exact `docs/USER_GUIDE.md`, `^docs/product/` prefix. TEST-2707 checks the 9 internal docs paths (exempt) plus near-misses (`docs/product-notes.md`, `sub/README.md`, `tests/README.md`, `docs/README.md`, `readme.md`, `docs/USER_GUIDE.md.bak`): all false. |
| Spec-AC-07 | compliant | TEST-2708 parses the shim loop out of both sync scripts (`aai-sync.sh:579`, `aai-sync.ps1:578`) and asserts that the parse found the loop, so a renamed loop fails rather than passing vacuously. |
| Spec-AC-08 | compliant | `release-finish.mjs:187` calls the same `isShipped`, unmocked, on a real git history. TEST-2709 also has a bite arm: without the rolled note, #101 is named too. |
| Spec-AC-09 | compliant | The preamble and the product page name all 8 paths plus "other docs paths stay exempt". The old sentence is gone from the product page. release-command-finish.md states the rule. The CHANGELOG entry exists. |

TEST-xxx entries: all 10 Test Plan rows exist, are registered as selectors in the suite scripts (each `run_case`/`run_docs_case` returns non-zero on failure, safe under `set -euo pipefail`; the no-argument run aggregates through `|| FAILURES=...`), and pass. Mutation replay 10/10 RED is recorded by Validation r1. Deviations from the frozen spec: none found. The spec's AC Status table still reads `planned`; the close ceremony flips it, so this is not a compliance gap.

## Focus answers

- **Can supersession turn a failure into a pass?** In `--required` mode, no. Every rewrite is either `pending` or a drop, and a dropped required name refuses at :216. A `failure` run is never superseded (:132). In non-required mode a drop removes the name from the output, as D1 specifies. Combined with the read-order race (NB-1), a real sibling failure can then go unseen for one poll. Narrow window; NON-BLOCKING.
- **Pagination and API cost:** the list call is lazy (:133). It is one paginated call per poll while any observed run is cancelled, validated like the check-run pages. A head with more than GitHub's filtered-list cap refuses closed (cannot_verify 2).
- **Error paths:** every malformed shape `fail()`s, and watch-ci turns a throw into exit 3 (watch-ci.mjs:128-146). A cancelled run with a malformed `workflow_id`/`event` now refuses even when no sibling exists. That is stricter than the baseline and in the fail-closed direction.
- **Node stdlib only:** yes. No new import in either script.
- **Gate exact matching:** anchored and case-sensitive. `-z --no-renames` raw parsing is unchanged, so both the old and new side of a rename or delete are classified.
- **Tests:** no live network (fixture `gh` on PATH; the PR #515 fixture has its repo slug retargeted). Temp dirs are cleaned up. Selectors exit non-zero on failure.

## Findings and dispositions (H6)

| # | Rank | Finding | Recommended disposition |
|---|---|---|---|
| NB-1 | NON-BLOCKING (P3) | Read-order race: `github-checks.mjs:137` reads the run list after the check-run snapshot. A sibling that completes in between makes the reader drop the observation. Non-required watch can then miss a sibling failure for one poll; required mode only refuses spuriously. | promote to follow-up. suggested: `fu-current-head-ci-drop-race` (when a drop happens, re-read the check-run pages and refuse if total_count moved). Not (d): it can leave a false green line. |
| NB-2 | NON-BLOCKING (P3) | `CHANGELOG.md:33` entry says "named above", which dangles once the entry is rolled into a release section. | remediate in tree now: list the eight paths inline in the entry (or say "listed in the CHANGELOG preamble"). |
| NB-3 | NON-BLOCKING (P3) | `docs/USER_GUIDE.md:2909` and `:810` still say docs are exempt, contradicting the gate. | remediate in tree now: two sentences mirroring the product page. This touches a path outside "Files Implementation touches", so record it as additive-with-disclosure. Alternative: suggested `fu-user-guide-release-notes-docs-wording`. |
| NB-4 | NON-BLOCKING (P3) | `.aai/SKILL_PR.prompt.md:163` keeps "Docs/test/evidence-only changes are exempt". Downstream installs also get the widened classifier over their own README/docs/product. | promote to follow-up. suggested: `fu-skill-pr-3b-shipped-docs-wording` (prompt-corpus governance: diet ledger, TEST-012, PROFILES), and the owner confirms the downstream semantics (cannot_verify 3). |
| NB-5 | NON-BLOCKING (P3) | `release-notes-gate.mjs:14`: `new RegExp('^docs/product/')` has no comment saying why it is written that way (validation F2). | remediate in tree now: one comment line ("kept as RegExp source text so the frozen TEST-2707 mutation applies"). |
| INFO | INFO | Validation F1: RED logs have no `RED_CLASS:` line. Evidence hygiene; RED-proof was re-established by the pre-change run and the mutation replay. | orchestrator records validation's suggested `fu-red-logs-missing-red-class`; no review gate. |
| INFO | INFO | release-command-finish.md:68 says the check "refuses closed if the newer run completes without registering it". That holds for required reads; a non-required watch drops it. | none required. |

Every finding has a named disposition: NB-1 and NB-4 are suggested follow-ups (not filed by this reviewer); NB-2, NB-3 and NB-5 are in-tree remediations. No `accepted residual:` lines.

## Next steps

1. Orchestrator: apply NB-2, NB-3 and NB-5 in tree (docs and comment only; re-run `aai-release-notes`, `aai-current-head-ci` and the docs content suites; mutation gate for the TEST-2707 anchor after NB-5), or file them as follow-ups.
2. File `fu-current-head-ci-drop-race` and `fu-skill-pr-3b-shipped-docs-wording` with `follow-ups.mjs add`.
3. Optional live evidence for cannot_verify 1 on the PR this branch opens (edit the body once while watch-ci --required runs).
