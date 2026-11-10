# Code Review (post-open, REVIEWER-FALLBACK) — release-corpus-hermetic, PR #544

```yaml
review:
  scope: "PR #544, git diff origin/main...HEAD (base 1d2e163c5a1cbfeb99328c9e7d0f63813d266b91, head e7cc1e5247bdc1f63c2f1c5e0fc9047fa4effca3), all 16 files"
  spec: docs/specs/SPEC-0280-spec-release-corpus-hermetic.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "tests/skills/aai-win-dispatch.Tests.ps1:102-108 (TEST-001 CLEAR/RESTORE), :931-937 (TEST-013), :68 caller capture, :1254-1265 TEST-002; expectations unchanged (:109, :940); reviewer run via canonical wrapper with 4500 inherited: 107 passed 0 failed, PRE=POST=4500; CI native 5.1 + pwsh 7 + WSL1 legs SUCCESS at e7cc1e52" }
      - { ac: Spec-AC-02, call: compliant, citation: "rejected (superseded) per Amendment 7 + DECISION-release-corpus-hermetic-scope-20261109.md; #543 commit c4706b80 is an ancestor of HEAD; tracked digest sha256 e98c6a22…545f3 re-hashed and matches; no corpus claim in diff" }
      - { ac: Spec-AC-03, call: compliant, citation: "rejected (superseded); SPEC-0257 blob at HEAD 2d63ab07… and git diff --quiet origin/main HEAD on it (together with .aai .github) rc 0; spec-amend list --strict rc 0" }
      - { ac: Spec-AC-04, call: compliant, citation: "tests/skills/aai-update.Tests.ps1:81-119: disposable TestDrive targets with explicit origins, real updater via Invoke-NativeCaptured/Start-Process (inherits Push-Location cwd), exit 2 + REFUSED, acme/foo control exit 0 + dry-run (dry-run path takes no network for a slug Repo, aai-update.ps1:76-79,118), caller location and RepoRoot origin preserved; .aai/scripts/aai-update.ps1 identical to origin/main" }
  code_quality:
    verdict: pass
    findings: []
  cannot_verify:
    - { claim: "External bot review (Copilot/Codex) of PR #544", closes_with: "a bot review on the head; the API shows 0 inline comments and 0 reviews at this review's time. That absence is NOT a no-findings statement; this report is the fallback reviewer" }
    - { claim: "Fixtures stay hermetic when an inherited GIT_DIR/GIT_WORK_TREE is present (for example Pester launched from inside a git hook); then `git -C $dir init`/`remote add` would act on the inherited repository", closes_with: "a run with GIT_DIR exported, or confirmation that no caller does that; no repo hook runs Pester today (grep of hook dirs empty), so no path is known" }
    - { claim: "SPEC-0046 manual real-Windows MV2/MV3 protocol", closes_with: "owner manual execution by 2026-11-17; green CI Windows legs do not close the full protocol" }
    - { claim: "Hosted timing and fit within shipped 540/1080 defaults beyond this one CI run", closes_with: "a hosted executor timing label in the raw CI artifact; it stays unverified (the CI job SUCCESS proves only that job)" }
    - { claim: "Full framework sweep 131/130 PASS/1 skip", closes_with: "VALIDATION-20261109T0925Z-release-corpus-hermetic.md (not re-run here; the test bytes are unchanged since then per R2 hashes, and CI at e7cc1e52 is green)" }
  overall: pass
```

security_relevant: false

## Scope and preflight

- The worktree is `/private/tmp/aai-release-corpus-hermetic`, branch `fix/release-corpus-hermetic`, HEAD `e7cc1e52` (equal to the PR headRefOid). `git status --porcelain` was clean at the start. The scope is `git diff origin/main...HEAD`: 16 files, +710/-11. All 16 were reviewed, including the ledgers, the generated pages and the earlier review reports, not only the two Pester files.
- Coaching check: the dispatch supplied evidence pointers and constraints. It did not pre-rate severity, predict findings or exclude any area. No coaching was recorded.
- Post-open state: PR #544 is OPEN and MERGEABLE. Its 16 checks are 14 SUCCESS and 2 SKIPPED. Those are the gated full-framework and unsharded selected legs, so the skips are intentional. reviewDecision is empty, and there are 0 inline comments and 0 reviews.

## Spec walk

See the YAML above. Other checks:
- Protected paths: `git diff --quiet origin/main HEAD -- SPEC-0257 .aai .github` returned rc 0. No production code changed.
- Append-only ledgers: on each of EVENTS (+37), METRICS (+1), decisions (+23) and tests/test-runs (+7), origin/main is a byte-exact prefix of HEAD, and every appended line parses as JSON.
- `spec-lint --path SPEC-0280` LINT PASS (rc 0). `spec-amend list --strict` rc 0. `docs-audit` reports CLEAN with no SCOPE row (the 8 unreadable AC tables are pre-existing, in other docs). The NUL-byte scan of both test files and the spec returned 0.
- `git ls-files -ci --exclude-standard` is empty, so no gitignored artifact is tracked.
- `links.pr: []` on the spec and issue matches the pre-merge convention seen on SPEC-0279/0281, so this is not a false record.

## Findings

No BLOCKING or NON-BLOCKING findings. The checks behind that:
- Start-Process has no `-WorkingDirectory`, so it uses the current PowerShell location. Push-Location therefore really does move the updater's `$Target`. The TEST-005 mutation RED in the evidence and the native Windows legs both confirm this.
- Env restore uses the file's own two-state idiom, inside `finally`.
- TEST-002 relies on file-order execution. A filtered run that skips it is harmless, because it only asserts a negative after the other blocks.
- The control case's dry-run reaches `exit 0` before any clone.

INFO (non-gating, no failure mode):
- The spec's Implementation plan steps are numbered 1-5, 7, 6, and "Base ref: origin/main at 3e6b52d5" is historical (the real base is 1d2e163c). Both are cosmetic.
- In the appended EVENTS there are two `check_dispatched` records without a matching verdict: 2026-11-08T08:47:17Z validation, and 2026-11-09T10:47:21Z validation, which was followed at once by a code_review dispatch. This is telemetry only and append-only. Nothing in it claims a verdict.

## Warning dispositions

None (no WARNINGs).

## Reviewer side effect (disclosed)

Running `node .aai/scripts/docs-audit.mjs` appended one telemetry line to the worktree `docs/ai/EVENTS.jsonl`: `{"ts":"2026-11-09T17:03:39Z","event":"docs_audit","ref":"docs-audit/full",...}`. It is uncommitted, and I did not restore it (HAZ-RESTORE/HAZ-LEDGER). The root decides whether to keep it and should keep the append order in mind before the pr_sweep record. No other file was written besides this report. The Pester run used the canonical wrapper and a private XDG cache; its log is at `/private/tmp/release-corpus-hermetic-postopen-review-scratch/pester-4500.log`.

## Next steps

The root records usage and the post-open ledger entries, then the pr_sweep after the last ledger write. Merge stays an operator decision.
