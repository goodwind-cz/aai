# Code Review r2 — release-corpus-hermetic (re-review after the B1/NB1 remediation, 2026-11-09)

```yaml
review:
  scope: "working delta vs origin/main (1d2e163c, HEAD == origin/main) + untracked scope docs: tests/skills/aai-win-dispatch.Tests.ps1, tests/skills/aai-update.Tests.ps1, docs/issues/ISSUE-0111-release-corpus-hermetic.md, docs/specs/SPEC-0280-spec-release-corpus-hermetic.md, docs/decisions/DECISION-release-corpus-hermetic-resume-20261108.md, docs/decisions/DECISION-release-corpus-hermetic-scope-20261109.md, appended docs/ai/{decisions.jsonl,EVENTS.jsonl,tests/test-runs.jsonl}, generated docs/INDEX.md docs/ai/overview.html docs/ai/overview-data.json, review reports docs/ai/reviews/review-release-corpus-hermetic-{20261108T015810Z,20261109-final,20261109-r2}.md; plus the gitignored proof records the remediation touched (docs/ai/tdd/spec-release-corpus-hermetic/mutation-TEST-00{1,2}*.txt, docs/ai/tdd/release-corpus-hermetic-review-remediation-20261109-replay.log)"
  spec: docs/specs/SPEC-0280-spec-release-corpus-hermetic.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "tests/skills/aai-win-dispatch.Tests.ps1:103,107,932,937 (sha256 a60a009d… == Validation O1 identity); reviewer's own replay in /private/tmp/release-corpus-hermetic-final-review2-scratch: controls 97/97 under 4500 and absent with PRE==POST, CLEAR mutant (e7d41665…) 2 fail (TEST-001, TEST-013), RESTORE mutant (5c6934ec…) 1 fail and caller leak (POST=<absent>); fresh mutation-TEST-001/002.txt target_sha256 a60a009d…; mutation-gate rc 0" }
      - { ac: Spec-AC-02, call: compliant, citation: "rejected (superseded) per owner-signed Amendment 7 (decisions.jsonl 2026-11-09T09:22:35Z); Description cell unchanged; tracked #543 digest; no new corpus claimed; row untouched by this remediation" }
      - { ac: Spec-AC-03, call: compliant, citation: "rejected (superseded) per Amendment 7; git diff origin/main -- docs/specs/SPEC-0257-spec-release-passes-first-time.md empty (rc 0, re-verified); row untouched by this remediation" }
      - { ac: Spec-AC-04, call: compliant, citation: "tests/skills/aai-update.Tests.ps1 sha256 6a5f330f… == Validation O3 identity == mutation-TEST-005/006 target_sha256; .aai/.github identical to origin/main (rc 0); pester log sha256 c6b8c25b… == Validation O1 evidence_sha256" }
  code_quality:
    verdict: pass
    findings: []
  cannot_verify:
    - { claim: "Pester fixtures behave identically on Windows PowerShell 5.1 / the Windows CI leg (env-var restore, Push-Location propagation into the Start-Process child cwd)", closes_with: "green Windows Pester leg of ps1-quality.yml on the PR head" }
    - { claim: "Linux CI green on the PR head (hosted timing, shipped 540/1080 defaults)", closes_with: "observed current-head CI conclusion on the PR with headSha == pushed HEAD (PR does not exist yet)" }
    - { claim: "Full sweep 131 suites, 130 PASS, 1 SKIP, rc 0 at width 4 / timeout 4500", closes_with: "stored in VALIDATION-20261109T0925Z-release-corpus-hermetic.md (sweep log sha 4bb335aa…); not re-run here, per the dispatch, and the code bytes it observed are unchanged (hashes re-verified)" }
    - { claim: "The rotated old records (mutation-TEST-00{1,2}.2026-11-07T22:54:39Z.txt) are verbatim copies of the former live records", closes_with: "no pre-rotation copy exists to compare against (gitignored); consistent with this: the target_sha256 is the stale de49b396…, the mtime is preserved (Nov 7 23:54), and the sha256 values equal those recorded in the replay log header" }
  overall: pass
```

security_relevant: false

## Scope and preflight

- Worktree `/private/tmp/aai-release-corpus-hermetic`, branch `fix/release-corpus-hermetic`, HEAD `1d2e163c` == `origin/main`. `git status --porcelain` showed exactly the dispatch's file list. It was unchanged before and after every gate I ran (`STATUS-UNCHANGED`, diffed twice).
- This is the full-envelope re-review, not a delta recheck. The whole scope was re-checked, and the rows and bytes that the remediation did not touch were re-verified by hash, not re-read line by line.
- Coaching check: the dispatch summarised what the maker claimed and asked for explicit B1/NB1 dispositions. It did not pre-rate severity or exclude any area. Every maker claim below was re-observed, not taken on trust.

## B1 (prior BLOCKING): stale TEST-001/002 mutation records — FIXED

Observed this round:
- The live `mutation-TEST-001.txt` and `mutation-TEST-002.txt` carry `target_sha256: a60a009da0f2…`, which equals `shasum -a 256 tests/skills/aai-win-dispatch.Tests.ps1`. Each has a `method:` line that says the record is a manual v1 record that mutation-run.mjs did not produce (D18), and each points at the replay log.
- The old records were rotated to `mutation-TEST-00{1,2}.2026-11-07T22:54:39Z.txt`. They still carry `de49b396…`, and their sha256 (`9022ff25…`, `57d95405…`) matches the replay-log header. They are named as `isRotatedFileName` expects, so the gate reads only the live records.
- **Independent replay.** I ran this in my own `--no-local` clone at 1d2e163c, with origin disabled and the candidate file copied in. I used the same canonical wrapper and Pester 5.7.1 driver, with BSD `/usr/bin/sed -i ''`, and restored with `cp`:
  - controls: 97/97 under 4500 (PRE=POST=4500) and under absent (PRE=POST=<absent>);
  - CLEAR mutant: sha `e7d416650828…`, identical to the maker's. Under 4500, exactly TEST-001 and TEST-013 fail (3000 expected, 4500 received). Under absent, 97/97: the mutant bites only on the inherited-value side, which is the side the spec targets;
  - RESTORE mutant: sha `5c6934ec3ac0…`, identical to the maker's. Under 4500, exactly the TEST-002 caller-preservation case fails (`Expected '4500', but got $null`) and POST=<absent>, so the caller leak is observable. Under absent, 97/97;
  - after restore the sha is `a60a009d…` and the control is 97/97 again.
- `node .aai/scripts/mutation-gate.mjs --spec docs/specs/SPEC-0280-…`: `GATE PASS: 6 row(s) satisfied degraded=0 unstamped=0 uncomparable=0`, rc 0. It was rc 5 in the failed review.
- `close-work-item.mjs … --dry-run`: `mutationGate.severity: none`. It was `refuse`.

## NB1 (prior NON-BLOCKING): Evidence cells unreadable by the rescue tokenizer — FIXED (disposition (a), remediated in tree)

- The Spec-AC-01 and Spec-AC-04 Evidence cells (spec lines 83 and 85) now list one full path per file, with no braces and no bare names. Every cited file exists and is non-empty.
- The close dry run's `evidencePathGate.rescue` lists all 12 worktree-only tokens. It listed 3 before.
- The only unresolved token is `docs/decisions/DECISION-release-corpus-hermetic-scope-20261109.md`, cited by the superseded AC-02/03 rows. It gives a `warn` on a `report-only` dial because the file is untracked and resolves only from the main checkout. It resolves once the scope commit tracks it, so this DECISION doc and the other untracked scope docs must be staged with the scope commit.
- **The edit touched only the Evidence cells, and this is proven.** I swapped the two old Evidence cells (from the `release-corpus-hermetic-before-main` snapshot) back into the current spec and hashed the result. The hash is exactly `70c1a10e2f08…`, the spec sha256 that the Validation outcome block binds. So the spec has changed since Validation in those two cells and nothing else: no Description, Status or other byte.
- The amendment record was appended at 2026-11-09T10:57:09Z, class `measurement`, `owner_signoff: false`. `spec-amend list --strict` returns rc 0, with unsigned-tracked=1 (the existing 2026-11-08T03:28:28Z restamp, still open under `fu-amend-spec-release-corpus-hermetic`), unsigned-untracked=0 and unclassified=0. `spec-lint --path SPEC-0280` passes with 0 findings.
- Ledgers: `EVENTS.jsonl` (26 appended), `decisions.jsonl` (23) and `tests/test-runs.jsonl` (6) each keep the origin/main blob as a byte-exact prefix, and every appended line parses as JSON.

## Validation binding: what the canon requires before the PASS is used (not a code finding)

- `validation-outcome-check.mjs --report docs/ai/reports/VALIDATION-20261109T0925Z-release-corpus-hermetic.md --ref release-corpus-hermetic --since 2026-11-09T09:25:35Z --intake … --spec …` now refuses with rc 1: `source spec hash mismatch`. The report binds `70c1a10e…`, and the current spec is `2064bff9…`.
- **Canonical requirement.** `.aai/SKILL_LOOP.prompt.md` tick step 1, at about line 136, runs this check whenever a standing Validation PASS would be used to complete or to dispatch a later role. A refusal makes that PASS unusable: the loop sets `set-validation --status not_run` and dispatches a fresh Validation.
  - The check compares hashes exactly and has no carry-forward exception.
  - The PR gate (`SKILL_PR` step 0, `validation-waiver.mjs`) reads only `last_validation.status`. Its own AC flip edits Evidence cells after the loop has ended, so the edit is not re-checked there. That is the "Evidence changes by design at close" case.
  - Doing the Evidence edit mid-ride, before Review, rather than at the SKILL_PR flip step as the failed review recommended, is what brings the edit inside the loop's binding check.
- **Assessment of carry-forward.** The original PASS is still a true observation of its own snapshot, and the code bytes it observed are unchanged: the win-dispatch, update, pester-log and SPEC-0257 hashes all re-verified. The spec delta is provably only the two Evidence cells (reconstruction above).
  - What does not count: a reviewer's or orchestrator's artifact check relabelled as a Validation verdict. Code Review does not own the Validation verdict.
  - The canonical way to carry forward without faking anything is a focused Validation round under `.aai/RECHECK_DELTA.prompt.md`. Its rule 5 says not to repeat checks on bytes the delta did not touch, so the full sweep and the PS quality run are not repeated. The round must still re-observe each outcome against the current spec hash and write a new `VALIDATION-*.md` report whose `sources[]` bind `2064bff9…`.
  - That round should be independent and on a model other than the implementer's. It can cite this report's reconstruction and replay as inputs to check.
  - The other option is for the orchestrator to leave the loop and enter SKILL_PR on the standing PASS. This report does not recommend that: the loop's rule exists to stop a PASS bound to a superseded spec snapshot from being used.

## INFO (no failure mode, does not gate)

- In the new records, `run_at_utc: 2026-11-09T10:56:25Z` is when the record was written. The replay log shows the mutant runs themselves at 10:55:03Z (CLEAR) and 10:55:23Z (RESTORE). The gate does not read this field (`mutation-gate.mjs` has no `run_at` use), and the exact per-run times are in the cited replay log. A one-line correction is optional.
- The Spec-AC-04 Evidence cell cites the older `release-corpus-hermetic-ps1quality.log`, not the final `release-corpus-hermetic-final-20261109-ps1quality.log`. The final log is reachable through the cited Validation report and `last_validation.evidence_paths`. No claim is lost.
- PR body disclosures, carried over and still owed:
  - the out-of-order foreign `hitl_decision` line (ref `test-wrapper-windows-fallback`, SPEC-0046 manual Windows decision, ts 2026-11-07T20:00:48Z) ships in this decisions.jsonl delta;
  - the 2026-11-08T03:28:28Z restamp stays unsigned-tracked under the open `fu-amend-spec-release-corpus-hermetic`. This review grants no owner sign-off;
  - the TEST-006 paired-preservation note: the control alone does not assert propagation, but the paired refusal case covers it. There is no counterexample, so it is not a finding.
- The rotated records' filenames contain colons, which fail the evidence tokenizer's charset. They are local history only and correctly not cited. They are gitignored and must not be force-added.

## Warning dispositions (H6)

| Finding | Rank | Disposition |
|---|---|---|
| B1 stale TEST-001/002 mutation records → close refuses | BLOCKING (prior round) | (a) remediated; verified by independent replay, mutation-gate rc 0 and close dry run `mutationGate: none` |
| NB1 Evidence cells not tokenizable for rescue | NON-BLOCKING (prior round) | (a) remediated in tree; verified by 12/12 rescue tokens and the hash reconstruction showing that only the Evidence cells changed |

This round raises no new BLOCKING or NON-BLOCKING finding, so it bears no findings and nothing remains to dispose of.

## Next steps

1. Orchestrator: run `state.mjs set-code-review` with this report (command returned in the result block).
2. Before the standing Validation PASS is used, re-establish it on the current spec hash through a focused independent Validation round (RECHECK_DELTA, a different model from the implementer's, new `VALIDATION-*.md` bound to `2064bff9…`), as the canonical loop check requires. Do not relabel this review as Validation.
3. Stage the scope commit with all untracked scope docs and the three review reports. Do not stage gitignored proof (`git ls-files -ci` must be empty).
4. PR: make the disclosures above, then observe current-head Linux CI and the Windows Pester leg.
