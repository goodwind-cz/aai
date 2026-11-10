# Code Review — release-corpus-hermetic (final scope, 2026-11-09)

```yaml
review:
  scope: "working delta vs origin/main (1d2e163c, HEAD == origin/main) + untracked scope docs: tests/skills/aai-win-dispatch.Tests.ps1, tests/skills/aai-update.Tests.ps1, docs/issues/ISSUE-0111-release-corpus-hermetic.md, docs/specs/SPEC-0280-spec-release-corpus-hermetic.md, docs/decisions/DECISION-release-corpus-hermetic-resume-20261108.md, docs/decisions/DECISION-release-corpus-hermetic-scope-20261109.md, appended docs/ai/{decisions.jsonl,EVENTS.jsonl,tests/test-runs.jsonl}, generated docs/INDEX.md docs/ai/overview.html docs/ai/overview-data.json, historical docs/ai/reviews/review-release-corpus-hermetic-20261108T015810Z.md"
  spec: docs/specs/SPEC-0280-spec-release-corpus-hermetic.md
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "tests/skills/aai-win-dispatch.Tests.ps1:31,102-108,931-938,1254-1265; docs/ai/tdd/release-corpus-hermetic-final-20261109-pester.log §1 (97/97 under 4500 and absent, PRE/POST preserved) and §3 (manual RED replays on current bytes); BUT required TEST-001/TEST-002 mutation records are stale — see BLOCKING B1" }
      - { ac: Spec-AC-02, call: compliant, citation: "rejected (superseded) per owner-signed Amendment 7 (decisions.jsonl 2026-11-09T09:22:35Z, DECISION-release-corpus-hermetic-scope-20261109.md); Description cell unchanged; #543 digest docs/ai/reviews/evidence-spec-0257-ac05-final-corpus-20261108.md is tracked on origin/main; no new corpus claimed" }
      - { ac: Spec-AC-03, call: compliant, citation: "rejected (superseded) per Amendment 7; git diff origin/main -- docs/specs/SPEC-0257-spec-release-passes-first-time.md empty (verified); closure + rollback measurement records 2026-11-08T00:39:45Z / 09:55:26Z retained append-only" }
      - { ac: Spec-AC-04, call: compliant, citation: "tests/skills/aai-update.Tests.ps1:74-120; .aai/scripts/aai-update.ps1 identical to origin/main (verified); pester.log §2 10/10 in canonical W and isolated clone; mutation-TEST-005/006 target_sha256 6a5f330f… == current file; ps1-quality 206/206 per VALIDATION-20261109T0925Z" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0280-spec-release-corpus-hermetic.md, line: 83,
          issue: "Spec-AC-01/04 Evidence cells cite paths the close ceremony's evidence tokenizer cannot see (brace form release-corpus-hermetic-{red,green}.log / -update-{red,green}.log, bare mutation-TEST-002.txt / mutation-TEST-006.txt) and omit the current authoritative evidence",
          failure_scenario: "close-work-item --dry-run (run in this review) plans rescue of only 3 tokens (mutation-TEST-001.txt, mutation-TEST-005.txt, release-corpus-hermetic-ps1quality.log); the 4 logs + 2 mutation records cited in the brace/bare form stay worktree-only and are lost when the worktree is removed, leaving Evidence cells naming files that exist nowhere" }
  cannot_verify:
    - { claim: "Pester fixtures behave identically on Windows PowerShell 5.1 / Windows CI (env-var restore, Push-Location propagation to Start-Process child cwd)", closes_with: "green Windows Pester leg of ps1-quality.yml on the PR head" }
    - { claim: "Linux CI green on the PR head (hosted timing, 540/1080 defaults)", closes_with: "observed current-head CI conclusion on the PR, headSha == pushed HEAD" }
    - { claim: "Full sweep 131 suites 130 PASS 1 skip rc 0 at width 4 / 4500", closes_with: "stored in VALIDATION-20261109T0925Z-release-corpus-hermetic.md; not re-run by this review (dispatch instructed assess stored proof)" }
  overall: fail
```

security_relevant: false

## Scope and preflight

- Worktree `/private/tmp/aai-release-corpus-hermetic`, branch `fix/release-corpus-hermetic`, HEAD `1d2e163c` == `origin/main`; no commit yet, so `origin/main...HEAD` is empty and the scope is the working delta plus the untracked scope docs (listed above). `git status --porcelain` showed exactly the dispatch's file list; no unrelated change.
- Production files untouched: `git diff --quiet origin/main -- docs/specs/SPEC-0257-spec-release-passes-first-time.md .aai .github` → exit 0.
- Ledgers: `docs/ai/EVENTS.jsonl`, `docs/ai/decisions.jsonl`, `docs/ai/tests/test-runs.jsonl` each keep the origin/main blob as an exact byte prefix (node byte compare: PREFIX-OK; single trailing hunk each); all appended lines parse as JSON (23 / 22 / 6).
- Coaching check: the dispatch described the prior validation results and the known amendment state, and asked that evidence-path defects be named. It did not pre-rate severity or exclude any area. Not treated as coaching; full scope reviewed.

## Verdict 1 — spec_compliance: FAIL (one gap, mechanical)

AC walk is in the YAML block. Spec-AC-01..04 behaviour is satisfied, and the two superseded rows are handled as Amendment 7 states: the Description cells are unchanged, the status reads `rejected (superseded)`, SPEC-0257 is byte-identical to main, and the #543 digest is tracked on main. The verdict fails on Test Plan evidence:

**B1 (BLOCKING, evidence contract / mutation_gate v1):** the spec's Evidence contract requires "mutation records for all four rows". `mutation-TEST-001.txt` and `mutation-TEST-002.txt` carry `target_sha256: de49b396…`, while the current `tests/skills/aai-win-dispatch.Tests.ps1` hashes to `a60a009d…` (upstream #542 removed the release Describe). Results:
- `node .aai/scripts/mutation-gate.mjs --spec docs/specs/SPEC-0280-…` → **rc 5**, `GATE FAIL: 2 offending row(s)`, STALE TEST-001 and TEST-002.
- `close-work-item.mjs --ref release-corpus-hermetic --spec spec-release-corpus-hermetic --pr TBD --review pass --dry-run` → `mutationGate.severity: "refuse"` (dial `mutation_gate: enforce` in `docs/ai/docs-audit.yaml:77`). The canonical close ceremony in SKILL_PR will therefore refuse deterministically.
- Validation replayed both mutations by hand on the current bytes (RED, pester.log §3) and said that this supersedes the old records. That is correct as evidence, but the records the gate reads were never refreshed. Amendment 7 discloses the staleness only for the TEST-007/TEST-482 records, not for TEST-001/002.

Remediation (must happen before close): write fresh MANUAL mutation records for TEST-001 and TEST-002 against the current target. Each record carries `target_sha256: a60a009da0f2e616892d4b1182600ddefb46d0de3c06455d7662ec00a188365e` and cites a real replay on the current bytes: either the validator's pester.log §3 output, or a fresh replay by Implementation. `mutation-run.mjs --replay` cannot drive Pester (spec residual D18), so the record follows the existing MANUAL record shape. Keep the old records as history, for example by moving them aside instead of overwriting them in place. Then re-run `mutation-gate.mjs` and expect rc 0. Base the record text on an actual run, not on this report.

## Verdict 2 — code_quality: PASS

Diff read in full.

- `aai-win-dispatch.Tests.ps1`: the clear and restore around the two default-timeout `Invoke-Dispatch` calls (lines 102-108, 931-938) restore both states correctly. A present value is reassigned; an absent value is removed again rather than set to an empty string. In TEST-013 the restore sits in the same `finally` as `[Console]::SetError($origErr)`, so a throwing dispatch cannot leak either one. The capture at file `BeforeAll` uses `$script:` scope, the same pattern as `$script:RepoRoot`. The final Describe relies on Pester v5 running Describes in file order, which it does. With a filtered run the Describe still passes, because nothing has mutated the variable by then.
- `aai-update.Tests.ps1`: `New-UpdateTarget` builds a `TestDrive` repo with an explicit origin. The updater reads `$Target = (Get-Location).Path` (aai-update.ps1:47), and `Invoke-NativeCaptured`'s `Start-Process` starts the child in the current PowerShell location. That is proven by the refusal case going RED, `Expected 2, but got 0`, when the origin line is mutated under an isolated checkout. The non-canonical dry-run exits before any clone (aai-update.ps1:79 `if (-not $DryRun)`), so the control makes no network access. The `try`/`finally` `Pop-Location` cannot leak the location.
- INFO (no failure mode, does not gate): on its own, TEST-006's control does not assert that the child's printed `Target:` equals `$target`. When the checkout's origin is non-canonical, it would also pass if the location did not propagate. The paired refusal case covers propagation, so nothing is lost.
- INFO: the `decisions.jsonl` delta includes a foreign record (`hitl_decision`, ref `test-wrapper-windows-fallback`, ts 2026-11-07T20:00:48Z, out of chronological order). It is valid JSON and a byte-prefix append, and the dispatch says the owner decision is real (SPEC-0046 AC-10, by 2026-11-17 on ISSUE-0009). Disclose it in the PR body as a cross-ref record that ships with this PR.

### NON-BLOCKING finding

**NB1 — Evidence cells unreadable by the rescue tokenizer** (`docs/specs/SPEC-0280-spec-release-corpus-hermetic.md:83,85`). `lib/evidence-paths.mjs` rule 3 (charset) drops `{red,green}` brace tokens, and rule 1 drops `mutation-TEST-002.txt` / `mutation-TEST-006.txt`, which have no `/`. The close dry run confirmed that only 3 tokens would be rescued. The cells also omit the current authoritative evidence: `docs/ai/tdd/release-corpus-hermetic-final-20261109-pester.log` and `docs/ai/reports/VALIDATION-20261109T0925Z-release-corpus-hermetic.md`.
Recommended disposition: **(a) remediate in tree** at the SKILL_PR "FLIP THE AC TABLE FIRST" step. Rewrite the Spec-AC-01/04 Evidence cells with one full path per file, no braces and no bare names. Include the fresh report, the final pester log, the RED logs (`docs/ai/tdd/release-corpus-hermetic-red.log`, `…-green.log`, `…-update-red.log`, `…-update-green.log`) and all four mutation records by full path. Then re-run `close-work-item --dry-run` and confirm that the rescue list covers every cited worktree-only file. No follow-up ref is needed.

## Amendment accounting (assessed, not a finding)

`spec-amend list --strict` → rc 0 (unsigned-tracked=1, unsigned-untracked=0, unclassified=0). The 2026-11-08T03:28:28Z restamp (cause unverified, contract class) stays `unsigned-tracked` under the open `fu-amend-spec-release-corpus-hermetic`. Per SKILL_PR's AMENDMENT GATE, exit 0 lets the PR proceed; an unsigned tracked amendment is disclosed by itself and does not forbid the PR. `nothing-left-behind.mjs` excludes `fu-amend-*` structurally. Amendment 7 is owner-signed (09:22:35Z). The classification at 09:22:49Z signs only the Spec-AC-04 fixture half of Amendment 3, and no wider signature is claimed. The PR body should state that the restamp sign-off remains owed.

## Warning dispositions (H6)

| Finding | Rank | Disposition |
|---|---|---|
| B1 stale TEST-001/002 mutation records → close refuses | BLOCKING | (a) remediate before close (fresh MANUAL records on current bytes; mutation-gate rc 0) |
| NB1 Evidence cells not tokenizable for rescue | NON-BLOCKING | (a) remediate in tree at the AC flip; verify with close-work-item --dry-run |

## Next steps

1. Implementation (or orchestrator under its ceremony role): refresh the TEST-001/002 mutation records against `a60a009d…` from a real replay and keep the old records as history. Expect `mutation-gate.mjs --spec …SPEC-0280…` to exit 0.
2. At the AC flip, rewrite the Spec-AC-01/04 Evidence cells with full, tokenizable paths. Then run `close-work-item --dry-run` and expect `mutationGate.severity` none and complete rescue coverage.
3. Re-review the delta (records plus Evidence cells only). The test code needs no change.
4. PR body: disclose the unsigned tracked restamp (`fu-amend-spec-release-corpus-hermetic` open), the foreign SPEC-0046 HITL record, and that hosted CI and the Windows leg are still to be observed.
