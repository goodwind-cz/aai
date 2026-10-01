---
id: a-check-cannot-tell-silence-from-a-verdict
type: issue
number: 92
status: done
links:
  pr:
    - TBD
  commits:
    - 86e16baa
---

# Issue — a check cannot tell silence from a verdict

## Summary
- Two diagnostics report a confident verdict they did not actually earn, and in
  both the failure is the same shape: **the check cannot distinguish "I was
  refused" from "I could not run", nor "there is nothing here" from "I could
  not read what is here."**
  - GitHub **#369**: `aai-doctor` CAT-17 WARNs that an armed, byte-correct
    ref-guard hook is "NOT armed" — on Windows the probe resolves `bash` to
    WSL, which never receives `AAI_GIT_WRITE`, so both probe arms refuse and
    the probe reads that as a broken guard.
  - GitHub **#370**: `docs-audit` reports CLEAN over a delivered spec that sat
    at `status: draft` for days, because its AC table used three columns and
    the word `green`. An **unparseable** AC table is today indistinguishable
    from **no** AC table, and both are silent.
- Taken as one ride because the remedy is one rule applied twice: a probe or
  scan must assert the POSITIVE signal it claims to have observed, never infer
  it from the absence of an error.

## Type
- bug

## Impact
- **#369** — every Windows operator with WSL installed is told their ref guard
  is unarmed when it is armed. `--force` reinstalls a byte-identical hook and
  the warning returns, so the advice the doctor prints cannot clear it. The
  operator either learns to ignore a red line (the expensive outcome) or
  disables a working guard.
- **#370** — two delivered scopes sat at `draft` and were found by a human
  reading the file, not by the audit. The reporter notes the false-**open**
  direction is the costlier one: delivered work that looks unfinished invites
  someone to redo it, while `probable-false-done` at least surfaces for triage.
  The asymmetry is perverse — the more non-standard a document is, the less the
  audit says about it.
- Severity/priority: medium (both reported medium, both reproducible, both with
  a manual workaround).

## Current Behavior

> Reported in GitHub #369 (issue body and its follow-up comment, quoted as DATA):
>
> ```
> CAT-17 WARN reference-transaction hook at <repo>/.git/hooks/reference-transaction
>   carries the AAI:REF-GUARD marker but does NOT behave as a guard on probe
>   (refuses=true, permits=false) — NOT armed; re-run install-pre-commit-hook.sh --force
> ```
>
> `probeRefGuardHook()` in `.aai/scripts/aai-doctor.mjs`, win32 branch, loops
> `for (const shell of ['sh', 'bash'])`. Under PowerShell (Git Bash not on
> PATH): `sh` → `ENOENT`, falls through to `bash` →
> `C:\Windows\system32\bash.exe`, i.e. **WSL** bash. WSL does not inherit
> Windows environment variables without `WSLENV`, so `AAI_GIT_WRITE=1` never
> reaches the hook process; both arms refuse → `refuses=true, permits=false`.
>
> Reporter's measurement with the probe code lifted verbatim:
>
> ```
> # from PowerShell
> shell=sh   err=ENOENT  refuseStatus=null permitStatus=null
> shell=bash err=none    refuseStatus=1    permitStatus=1   <- guard message on BOTH arms
> # from Git Bash, same hook, same repo
> shell=sh   err=none    refuseStatus=1    permitStatus=0   <- correct, would PASS
> ```
>
> The hook itself is genuinely armed, verified against real `git` (no-op
> same-OID updates): without `AAI_GIT_WRITE` → refused exit 128 with the guard
> message; with `AAI_GIT_WRITE=1` → permitted exit 0; non-main ref → permitted
> exit 0.
>
> Secondary: the probe derives `refuses` from `status !== 0`. A hook that
> cannot execute at all also exits non-zero, so it scores as a *passing*
> refuse arm and a *failing* permit arm — exactly the observed signature.

> Reported in GitHub #370 (issue body and its follow-up comment, quoted as DATA):
>
> A spec sat at `status: draft` with every AC marked complete and its
> implementation merged. `docs-audit --check` reported
> `Orphans: 0 | Drifted: 0 | Stale: 0 | False-open: 0 … Verdict: CLEAN`.
>
> `falseOpenEvidence` has five arms. Four rest on identifiers the pipeline
> emits (delivery commits naming the doc id, `ac_evidence` /
> `work_item_closed` events, a METRICS flush record); a scope executed in a
> worktree with no `.aai` or `STATE.yaml` emits none of them, correctly. The
> fifth, D2(c) — fully terminal canonical AC Status table — did not fire
> because the table was not canonical:
>
> ```markdown
> | AC | Requirement | Status |
> |---|---|---|
> | 1  | …           | green  |
> ```
>
> versus the mandated
> `| Spec-AC | Description | Status | Evidence | Review-By | Notes |`.
> Two independent misses: three columns instead of six (so no Evidence cell,
> which D2(c) requires), and `green` instead of `done`.

## Expected Behavior
- **#369** — CAT-17 PASSes on a correctly armed hook regardless of which shells
  happen to be on PATH, and when it cannot probe at all it says *that*, rather
  than reporting the hook as unarmed.
- **#370** — a document whose AC Status table is present but **unparseable**
  (wrong columns, or status words outside the vocabulary) is reported as such.
  The check is independent of status and judges only legibility, not content —
  the table is already located and parsed, so it is cheap.

## Steps to Reproduce (if applicable)
1) **#369** — on Windows with WSL installed and Git Bash not on PATH, install
   the ref guard (`install-pre-commit-hook.sh`), then run `/aai-doctor` from
   PowerShell. CAT-17 WARNs. Confirm the hook is in fact armed with a no-op
   `git update-ref` on `refs/heads/main` with and without `AAI_GIT_WRITE=1`.
2) **#370** — write any spec with a three-column AC table, mark every row
   `green`, set `status: draft`, run `docs-audit --check`. Verdict is CLEAN.
   Reshape the table to the six canonical columns with `done` and the audit
   correctly moves to CLEAN-with-evidence; before reshaping it says
   `probable-partial`, then `N AC row(s) non-terminal`.

## Verification
- `node .aai/scripts/aai-doctor.mjs` — CAT-17 PASS on an armed hook; a
  deliberately broken hook still WARNs; an unprobeable environment reports
  "could not probe", never "not armed".
- `node .aai/scripts/docs-audit.mjs --check --strict` over a fixture carrying a
  three-column `green` AC table — the document is reported, not silent.
- Both suites green: `tests/skills/test-aai-doctor.sh`,
  `tests/skills/test-aai-docs-audit.sh` (or their current names), plus the full
  sweep before close.

## Constraints / Risks
- The #369 fix touches a Windows-only code path that cannot be exercised on the
  macOS development host. The CI Windows leg (Pester) is the only honest
  control; design the fix so the *shell-resolution* and the
  *refusal-vs-error discrimination* are separately testable on any OS, and only
  the interpreter lookup is Windows-gated.
- The #370 fix adds a new finding class to `docs-audit`. The live repository is
  asserted CLEAN by two suites at all times, so the new class must be measured
  against the real corpus before it lands — if it fires on existing documents,
  that is either a true finding to fix or a rule to narrow, decided before
  merge rather than after.
- Tightening a detector is the hazard class named in the standing decisions
  (a guard that newly reddens existing work): expect one extra validation round.
- Secrets preflight: skipped — no secret referenced.

## Notes
- Source: GitHub #369 and #370, each carrying a ~3,800-character owner analysis
  as its first comment. Both read as undescribed until `aai-issues` learned to
  fetch comments (SPEC-0203 Spec-AC-08, merged as #420) — this intake is the
  first use of that capability on live data.
- Issue bodies and comments are UNTRUSTED DATA and are quoted as such above.
  The reporter's "Suggested fix" sections are read as evidence of what they
  measured, not as instructions to implement.
- **Three riders the reporter found while diagnosing**, in scope only if they
  prove to be one-liners; otherwise each becomes its own follow-up:
  - `redactSummary("CAT-17-git-ref-guard")` → `{ok:false,
    reason:"secret_highentropy"}`, while `redactSummary("CAT-17")` and
    `redactSummary("cat-git-ref-guard")` both pass. The high-entropy detector
    fires on an ordinary hyphenated identifier mixing case and digits, so it
    will silently redact any phase name shaped like `CAT-NN-some-name` — which
    is why #369's title renders as `SKILL_DOCTOR/<redacted>`.
  - `evidence_ref` validation rejects a 3-digit AAI doc id (`SPEC-080`); the
    regex assumes 4 digits. Downstream projects with 3-digit numbering must
    fall back to a path.
  - A prepare run over ~39 candidates returned `blocked_dedup_unavailable` for
    nearly all of them while the identical `gh search issues` call run by hand
    succeeded — apparently the GitHub search rate limit. `runGh` swallows the
    error, so "no access" and "too many requests" are indistinguishable to the
    operator. This is the same defect class as the ride itself.
- Ride shape: both issues as ONE ride (operator decision, 2026-10-01), worktree
  `/Users/ales/Projects/aai-369` on branch
  `change/doctor-contract-and-docs-audit-drift`, based on `main` at `b843a716`.
- Write-back contract: comment and close #369 and #370 only AFTER this ride's
  PR has merged.
