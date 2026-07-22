---
title: Code Review — ps1-native-stderr-guard
ref_id: ps1-native-stderr-guard
spec: docs/specs/SPEC-DRAFT-spec-ps1-native-stderr-guard.md
reviewer: code-review (single dual-verdict)
date: 2026-07-22T13:20:57Z
---

```yaml
review:
  scope: git diff main...HEAD (commit 8cc930b) — .aai/scripts/aai-release.ps1, tests/skills/aai-win-dispatch.Tests.ps1
  spec: docs/specs/SPEC-DRAFT-spec-ps1-native-stderr-guard.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/aai-release.ps1:39-67 (helper: local EAP=Continue L58, 2>&1 merge L59, $LASTEXITCODE gate L60/62, throw-with-text L64, return L66); TEST-002/TEST-003 green (Pester 52/52)" }
      - { ac: Spec-AC-02, call: compliant,
          citation: ".aai/scripts/aai-release.ps1:285-299 (add/commit/tag/rev-parse/push/push-tag/gh routed); probes untouched L221,L230,L95,L108,L235; TEST-004 green; PSScriptAnalyzer clean; ps1-quality CI success @HEAD 8cc930b" }
      - { ac: Spec-AC-03, call: compliant,
          citation: ".aai/scripts/aai-release.ps1:69 guard open, :310 guard close, helper above guard; TEST-006 (child-proc dot-source) + TEST-007 (-DryRun exit 0, plan header) green" }
  code_quality:
    verdict: pass
    findings:
      - { rank: INFO, file: .aai/scripts/aai-release.ps1, line: 61,
          issue: "Explicit $prevEap save/restore of $ErrorActionPreference is redundant — assigning $ErrorActionPreference inside a function creates a function-scoped copy that is discarded on return, so EAP cannot leak to the caller regardless. Also not wrapped in try/finally, but that is moot for the same scoping reason.",
          failure_scenario: "None — no leak path exists; belt-and-suspenders only." }
      - { rank: INFO, file: .aai/scripts/aai-release.ps1, line: 289,
          issue: "$shortSha uses Select-Object -Last 1 over merged 2>&1 output; if git ever emitted a stderr line AFTER the sha on a zero exit, -Last 1 could pick an ErrorRecord.",
          failure_scenario: "git rev-parse --short HEAD writes a trailing stderr warning on success — not observed for this subcommand; display-only value, no cut-path impact." }
  cannot_verify:
    - { claim: "The actual Windows PowerShell 5.1 stderr-promotion SUPPRESSION — a real `git push` writing 'To <remote>...' to stderr no longer aborts the cut under EAP=Stop.",
        closes_with: "Operator smoke MV-1/MV-2 on a native Windows PowerShell 5.1 host (RR-1). Not reproducible on this macOS/pwsh-7 host; pwsh 7 does not promote native stderr; no 5.1 runtime CI job exists." }
  overall: pass
```

## Scope and spec

- Scope: `git diff main...HEAD`, single commit `8cc930b` "fix(release-ps1): guard native git/gh against stderr-as-error on Windows PS 5.1".
- Files: `.aai/scripts/aai-release.ps1` (new `Invoke-NativeChecked` helper, cut-path calls routed, dot-source guard), `tests/skills/aai-win-dispatch.Tests.ps1` (new `Describe 'aai-release.ps1'` block, TEST-001..004/006/007).
- Spec: `SPEC-DRAFT-spec-ps1-native-stderr-guard.md` (SPEC-FROZEN: true, ceremony_level 2, code_review.required true).

## Anti-gaming note

Dispatch prompt scoped review attention to enumerated concerns (helper correctness, compat, routing, guard, honesty). Per the anti-gaming contract this is coaching; recorded here and the full diff was reviewed independently anyway. No severity was pre-rated and no area was scope-excluded, so the coaching is benign.

## Verdict 1 — spec_compliance: PASS (AC table walk)

- **Spec-AC-01 — diagnostics-preserving `Invoke-NativeChecked`: compliant.**
  (a) local `$ErrorActionPreference = 'Continue'` at L58 — and because the assignment is function-scoped it cannot leak to the caller; (b) merged capture `& $Exe @Arguments 2>&1` at L59; (c) `$LASTEXITCODE` captured on the immediately-following statement (L60) with nothing between it and the native call, returns `$out` on zero and never throws on success-stderr (L66); (d) on non-zero, throws a message that interpolates `$joined` = the captured stdout+stderr (L63-64). TEST-002 (stderr+exit0 -> no throw, output retains text) and TEST-003 (stderr+exit1 -> throws WITH text) both green. I confirmed TEST-003 is non-tautological: a naive `*> $null` swallow variant throws WITHOUT the stderr text (probe: `BAD_HELPER_MISSING_TEXT`), so the test genuinely discriminates the fix.

- **Spec-AC-02 — all cut-path calls routed; probes untouched; parse-clean: compliant.**
  add (L285), commit (L286), tag (L287), display rev-parse --short (L289), push branch (L296), push tag (L297), gh release create (L299) all go through `Invoke-NativeChecked`. No bare `git -C $Root push|add|commit|tag` and no bare `gh release create` statement remains. Tolerant probes correctly retain their existing handling: `rev-parse -q --verify` (L221 `*> $null`), `gh auth status` (L230 `*> $null`), `rev-parse --show-toplevel` (L95 `2>$null`), `status --porcelain` (L108 `2>$null`), `rev-parse --abbrev-ref HEAD` (L235 `2>$null`) — all read/tolerate `$LASTEXITCODE` themselves and are correctly out of scope. PSScriptAnalyzer (Warning+Error) ran clean on the file locally; ps1-quality CI = success at headSha 8cc930b (== HEAD).

- **Spec-AC-03 — dot-source guard; `-File`/plan unchanged: compliant.**
  `if ($MyInvocation.InvocationName -ne '.')` opens at L69, closes at L310; the helper is defined ABOVE the guard (L39-67) so dot-source defines it without running the body; `param()` and the function are the only top-level constructs outside the guard. Pattern matches the proven siblings `aai-run-tests.ps1:315` / `aai-reap-tests.ps1:348`. TEST-006 (child-process dot-source -> HELPER_DEFINED + DOTSOURCE_COMPLETED + exit 0) and TEST-007 (`pwsh -File ... -DryRun` in a throwaway git fixture -> exit 0, prints `aai-release (plan)`) both green.

TEST evidence: ran `Invoke-Pester tests/skills/aai-win-dispatch.Tests.ps1` locally on pwsh 7 — **52/52 passed, 0 failed**, including all 8 new `aai-release.ps1` rows. The claimed TEST-001..007 exist and pass.

## Verdict 2 — code_quality: PASS

No BLOCKING and no NON-BLOCKING findings. Two INFO notes (no failure scenario, do not gate):

1. **L57-61 EAP save/restore is redundant / not try-finally-wrapped.** Assigning `$ErrorActionPreference` inside a function shadows in function scope and is discarded on return, so neither a leak nor a missing-restore-on-throw path exists. Harmless belt-and-suspenders. INFO.
2. **L289 `Select-Object -Last 1` over merged `2>&1`.** Display-only `$shortSha`; only bites if `rev-parse --short HEAD` emitted a trailing success-stderr line (not observed for this subcommand). No cut-path impact. INFO.

Positive correctness confirmations against the dispatch checklist: `$LASTEXITCODE` is captured immediately (L60, no intervening statement); success-stderr is never treated as an error (gate is exit-code only); the throw preserves git/gh's own diagnostic (strictly better than `*> $null`); helper uses only 5.1+7-portable constructs (no `??`/ternary/`$PSNativeCommandUseErrorActionPreference`); function verb `Invoke` is approved and no automatic-variable assignment / unused-var / BOM warning is present; no `protected_paths_l3` file is touched.

## Verdict 3 — cannot_verify

- The real Windows PowerShell 5.1 stderr-promotion suppression (Seam B / RR-1). Not reproducible on this macOS/pwsh-7 host and no 5.1 runtime CI exists. Closes with operator smoke MV-1/MV-2. This is honestly quarantined in the spec (RR-1, Constitution Art. 1 note) and in the commit message ("HONEST LIMIT: pwsh7 is a proxy ... verified only by a documented manual smoke (RR-1), not this repo's CI"). No overclaim found: neither the spec nor the commit asserts CI proves the 5.1 runtime fix.

## Warning dispositions (H6)

No BLOCKING or NON-BLOCKING (WARNING) findings — nothing to remediate/promote. The two INFO notes carry no disposition duty. Recommended disposition for the INFO notes: leave as-is (optional cleanup, not tracked).

## Next steps

- Overall PASS — both verdicts pass. Ready for PR.
- RR-1 remains open until MV-1/MV-2 are executed on a native Windows PS 5.1 host; that execution tracks on the ISSUE, not this spec's PASS (as the spec states).
