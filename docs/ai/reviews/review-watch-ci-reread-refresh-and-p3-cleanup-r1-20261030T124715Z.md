# Code Review r1 — watch-ci-reread-refresh-and-p3-cleanup

```yaml
review:
  scope: git diff 7d38415a...HEAD (HEAD 659cc859, branch fix/watch-ci-reread-refresh-and-p3-cleanup)
  spec: docs/specs/SPEC-DRAFT-spec-watch-ci-reread-refresh-and-p3-cleanup.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/lib/github-checks.mjs:169-201; TEST-2931 (current-head-ci.test.mjs) green locally" }
      - { ac: Spec-AC-02, call: compliant, citation: "github-checks.mjs:186-188; TEST-2932 three arms green locally" }
      - { ac: Spec-AC-03, call: compliant, citation: "github-checks.mjs:93-125 (refresh, fetched set, identity check :119-120); TEST-2933, TEST-2934 green locally" }
      - { ac: Spec-AC-04, call: compliant, citation: "TEST-2711 code unchanged; full test-aai-current-head-ci.sh rc=0 locally" }
      - { ac: Spec-AC-05, call: compliant, citation: ".aai/SKILL_PR.prompt.md:163 (+72 B, 0 lines); TEST-2935 green locally" }
      - { ac: Spec-AC-06, call: compliant, citation: "tests/skills/lib/prompt-diet-ledger.sh:266; test-aai-prompt-diet.sh want_growth 64396 and TEST-2936; validation r2 prompt-diet PASS" }
      - { ac: Spec-AC-07, call: compliant, citation: "decisions.jsonl +2 process_finding records, 0 removed lines (measured); facts checked against SPEC-0261/0260 file lists and reviews; TEST-2937 passes on macOS only, see BLOCKING B-1" }
      - { ac: Spec-AC-08, call: compliant, citation: "decisions.jsonl four follow_up_status done records; TEST-2938; validation r2 verify-closures --strict 0" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: tests/skills/test-aai-spec-amend.sh, line: 5570,
          issue: "TEST-2937 passes the two full spec-amend list --json outputs (488,395 B each) as argv to node -e",
          failure_scenario: "Linux caps one argv string at 128 KiB (MAX_ARG_STRLEN); on the ubuntu CI leg node fails to exec with E2BIG, the || branch runs log_fail, and aai-spec-amend goes red. The diff triggers FULL_RUN (shared-lib github-checks.mjs), so the suite runs. Reproduced in node:22-slim: 'node: Argument list too long', rc=126. Fix: write both outputs to files in $scratch and pass paths (or stdin)." }
      - { rank: NON-BLOCKING, file: tests/skills/lib/current-head-ci.test.mjs, line: 431,
          issue: "D3 (run cancelled on read 1 and re-run by read 2 judged by its own checks) is a spec Decision and a named edge case, but no test exercises it",
          failure_scenario: "a later edit that builds nowCancelled from the first-read set again (or unions the two) would supersede a re-run's live checks and no test would redden; behavior today is never-green (traced by reading), but unguarded" }
  cannot_verify:
    - { claim: "Real GitHub ordering between run cancellation, the check-run conclusion, the run-level conclusion and the run list matches the stub's sequencing", closes_with: "a live observation of a cancel-in-progress pair on a real PR (SPEC-0261 r2 cannot_verify, unchanged)" }
    - { claim: "A re-run (same run id, new run_attempt) between the two reads produces check-runs whose ids order after attempt 1 under filter=all", closes_with: "a live re-run observation or GitHub API documentation of check-run id monotonicity across attempts" }
    - { claim: "TEST-2937 and the rest of the branch pass in CI", closes_with: "green skill-suite run on the PR after B-1 is fixed" }
  overall: fail
```

security_relevant: false

## Scope

- Diff: `git diff 7d38415a...HEAD`, 17 files, HEAD 659cc859. STATE `worktree.user_decision: worktree`; working tree carries only telemetry changes (EVENTS.jsonl, test-runs.jsonl), outside the review scope.
- Spec: docs/specs/SPEC-DRAFT-spec-watch-ci-reread-refresh-and-p3-cleanup.md (frozen, amendments A1, A2).
- Dispatch note (anti-gaming): the dispatch named focus areas without pre-rating severity or excluding areas; the full scope was reviewed.

## Reader change (github-checks.mjs) — false-green analysis

Interleavings traced against the new code (lines 93-201):

- Read 1 in progress, cancelled on re-read, sibling in run list unfinished: pending (TEST-2931). Completed with its own copy: the copy governs by creation order. Completed without the check: dropped; required mode refuses `required context missing` (TEST-2932 arm 3).
- Newly cancelled with no qualifying sibling (sibling created after the run list, other event): refuses `workflow state moved during observation` (TEST-2932 arms 1-2). Never pass.
- Cancelled on read 1, re-run by re-read: dropped from the cancelled set (D3); attempt-1 checks keep bucket cancel, attempt-2 checks (newer id) pending. Not green unless a newer attempt or newer run actually passed.
- Run first seen on read 2 and cancelled: same rule as newly cancelled (D4/D5).
- Stale map entries (a run present on read 1 but absent on re-read) can enter nowCancelled but touch no observation.
- Non-required mode: a newly cancelled run's completed failure can now be dropped when its completed sibling lacks the check. That is SPEC-0261 D1 semantics applied to the newly cancelled set, exactly as spec D4 decides; the newest run of the workflow governs. INFO, not a finding.
- Identity refusal: compares created (ms), workflow_id, event on refresh only; unreachable on read 1; refuses closed if a field appears or disappears. Correct.
- Extra API calls only on the re-read path: `refresh` is true only at :169, which runs only when read 1 saw a cancelled run; `fetched` bounds it to one call per run per re-read (TEST-2933 calm arm: one per run, zero run lists). The Map is per readCurrentChecks call, so watch-ci polls do not share stale state.
- Shared consumers: watch-ci.mjs:128 and release-finish.mjs:478 both call readCurrentChecks; tests drive both as subprocesses. watch-ci.mjs header (:38) still true; not edited, consistent with the spec's conditional.

No new path to PASS found.

## SKILL_PR 3b wording

New sentence matches release-notes-gate.mjs `isShipped` (:12-16: the six root md files, docs/USER_GUIDE.md, docs/product/) and docs/product/release-notes-gate.md:16 ("All other docs paths stay exempt, as do tests and evidence-only changes"). Byte growth 72 B, no new line; ledger entry, TEST-012 pin and TEST-008 pins (A1) all move by +72.

## Ledger

- `git diff 7d38415a...HEAD -- docs/ai/decisions.jsonl | grep -c '^-[^-]'` = 0.
- D8a facts verified: SPEC-0261 "Files Implementation touches" lists github-checks.mjs, current-head-ci.test.mjs and test-aai-current-head-ci.sh; USER_GUIDE.md is absent; the spec's Amendment line 365 quotes exactly; review r1 NB-1 and NB-3 exist as cited.
- D8b facts verified: SPEC-0260 list contains tests/skills/suite-map.yaml; A1-n (line 498) says otherwise; review r2 has "NB-2 (new): content-only globs left on the engine row"; record 2541 `why` begins "Validation r2 NB-2".
- Four follow_up_status closes carry resolved_by and source as D9 requires.
- Amendments: A1 (TEST-008 pin, +72 both pins) and A2 (AC-01/AC-07 wording, Validation r1 F2/F3 exist in the r1 report) are accurate. INFO: A1 prose says "Implementation" while its ledger record has actor orchestrator.

## Test quality

- TEST-2931..2934: drive watch-ci CLI and the release reader against a sequenced stub; mutations listed in the Test Plan redden them (validation r2 replay 9/9). Suite passes locally (rc=0).
- TEST-2935: slices step 3b to the next numbered step; asserts absence of the old sentence and presence of the list pointer.
- TEST-2936: `wc -c < file | tr -d ' '` (tr reads to EOF, no early-closing reader); prompt-diet suite runs `set -uo pipefail`.
- TEST-2937: `set -euo pipefail` safe locally, but see B-1 (argv size on Linux). Also `pick` compares `items` and `counts`, which exist in the JSON (586 items), so the comparison is not vacuous.
- TEST-2938: `printf | node` with node consuming all stdin; safe under pipefail.

## Findings and dispositions

- B-1 BLOCKING, tests/skills/test-aai-spec-amend.sh:5570 — remediate in tree (pass the JSON by file or stdin; also :5564-5565 can write straight to files). Re-run aai-spec-amend, ideally under Linux (`docker run node:22-slim`).
- NB-1 NON-BLOCKING, tests/skills/lib/current-head-ci.test.mjs (no D3 case) — recommended disposition: remediate in tree with a TEST-2931-shaped arm where run A's workflowSeq goes cancelled -> in_progress and its attempt-2 check is pending, asserting pending and no drop; alternative promote to follow-up `fu-current-head-ci-rerun-between-reads` (P3).
- INFO: CHANGELOG.md entry (D10, plan step 6) not yet in the diff; D10 assigns it to the PR ceremony, where release-notes-gate enforces it.

## Next steps

1. Remediation fixes B-1 (and NB-1 if remediated in tree), re-runs aai-spec-amend and aai-current-head-ci.
2. Re-review r2.
