---
review_of: reaper-deterministic-age-guard
spec: docs/specs/SPEC-DRAFT-spec-reaper-deterministic-age-guard.md
scope: main...HEAD (fix/reaper-deterministic-etime @ fdff86b)
reviewer_role: Code Review
reviewed_utc: 2026-07-20T12:52:16Z
---

```yaml
review:
  scope: main...HEAD (branch fix/reaper-deterministic-etime, HEAD fdff86b; commits d45fe4e + fdff86b)
  spec: docs/specs/SPEC-DRAFT-spec-reaper-deterministic-age-guard.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/aai-reap-tests.sh:236-243 (start_epoch=SNAP_NOW-age; reap iff start_epoch < STEP_START-GRACE, else spare) + TEST-006/TEST-017 GREEN (green-20260720T120138Z log)" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "TEST-016 delay 0 AND 7 both spare (green log) + RED red-20260720T114129Z-test016.log: pre-change reaper KILLS fresh sibling at delay=7s (reaped: 1) — flake reproduced" }
      - { ac: Spec-AC-03, call: compliant,
          citation: ".aai/scripts/aai-reap-tests.sh:180-196 (STEP_START valid iff digits>0 and <=SNAP_NOW; else legacy age>=MIN_AGE) + TEST-018 6 invalid shapes GREEN" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "strip_lz octal-safe (sh:86-93); no lstart / date -d / date -j in code + TEST-013 dash epoch path + TEST-019 static guard GREEN; `pwsh` n/a — .sh dash-clean" }
      - { ac: Spec-AC-05, call: compliant,
          citation: ".aai/scripts/aai-reap-tests.ps1 Get-ReapCandidates -StepStart + Get-StepStartFromEpoch; Pester re-run ON THIS HOST: 38 passed / 0 failed" }
      - { ac: Spec-AC-06, call: compliant,
          citation: ".aai/SKILL_LOOP.prompt.md POST-TICK REAP + .aai/VALIDATION.prompt.md step 8c capture AAI_REAP_STEP_START_EPOCH=$(date +%s) + TEST-020 GREEN" }
      - { ac: Spec-AC-07, call: compliant,
          citation: "gh run 29742208991 (headSha fdff86b == HEAD) success + 29741627562 (d45fe4e) success — two consecutive green skill-suite Ubuntu runs" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: docs/INDEX.md, line: 176,
          issue: "Auto-generated index (regenerated 12:16Z) still lists Spec-AC-07 as a per-AC Deferred item (Review-By 2026-07-27) while the spec table marks it done (flipped at 12:48Z by Validation).",
          failure_scenario: "A docs-audit run reading INDEX.md would see AC-07 deferred and could surface stale-drift; refreshes on next `node docs/*index*` regen. Disposition: regenerate INDEX at close (advisory)." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-run-tests.sh, line: 528,
          issue: "TEST-017 reaps a survivor spawned 3s before step_start with default GRACE=2 (~1s nominal margin).",
          failure_scenario: "Only fails in the SAFE direction (a survivor not reaped = test red, never a wrongful kill); determinism makes reaper overhead push start_epoch OLDER (toward reap), and CI passed 2x. Note only — no action needed." }
  cannot_verify:
    - { claim: "Native Windows process enumeration + Stop-ProcessTree kill semantics of the .ps1 reaper",
        closes_with: "SPEC-0046 MV-1..MV-3 manual verification on a real Windows host (off-CI, unchanged posture; Pester covers the pure candidate-selection logic with injected $Now + fixture snapshots)" }
    - { claim: "Absence of the flake across MANY future CI runs (probabilistic)",
        closes_with: "The spec's bar is two consecutive green Ubuntu runs — met (29742208991 + 29741627562); local delay-injection (TEST-016) proves overhead-independence deterministically without needing real CI load" }
  overall: pass
```

# Code Review — reaper-deterministic-age-guard

**Scope:** `git diff main...HEAD` on `fix/reaper-deterministic-etime` (HEAD `fdff86b`; commits `d45fe4e` fix + `fdff86b` Pester `$args`→`$argv` rename).
**Spec:** `docs/specs/SPEC-DRAFT-spec-reaper-deterministic-age-guard.md` (SPEC-FROZEN, L2).
**Verdict: PASS** (both verdicts pass; no BLOCKING findings). SAFETY-CRITICAL process-killing code — scrutinized per dispatch.

## Diff scope (obtained by reviewer)
7 declared files + 3 coherent companions: `.aai/scripts/aai-reap-tests.sh`, `.aai/scripts/aai-reap-tests.ps1`, `tests/skills/test-aai-run-tests.sh`, `tests/skills/aai-win-dispatch.Tests.ps1`, `.aai/SKILL_LOOP.prompt.md`, `.aai/VALIDATION.prompt.md`, `docs/TECHNOLOGY.md`; plus `docs/INDEX.md` (auto-regen), `tests/skills/lib/prompt-diet-ledger.sh` + `tests/skills/test-aai-prompt-diet.sh` (prompt-diet ledger credit for the prose growth — arithmetic checks: 12339 + 825 = **13164**, correct).

## Safety scrutiny (the dispatch's specific asks)

**Guard rewrite — same-snapshot cancellation:** `SNAP_NOW=$(date +%s)` is captured on line 174, IMMEDIATELY after `ps axo pid=,etime=,args= > "$SNAP"` (line 169) and BEFORE the read-loop walk — so overhead between step-start and the sweep inflates `SNAP_NOW` and every sampled `etime` by the same amount. `start_epoch=$((SNAP_NOW - age))` (line 239) is therefore invariant to reaper overhead. **Correct.**

**Reap condition, both directions:** `threshold=$((STEP_START - GRACE))`; reap iff `[ "$start_epoch" -lt "$threshold" ]`, else `continue` (spare). Strict `<` means a proc exactly at the boundary is SPARED — the safe direction. Fresh post-step sibling: `start_epoch ≈ SNAP_NOW ≥ STEP_START > threshold` → spared. Genuine pre-step survivor: `start_epoch < STEP_START - GRACE` → reaped. **No off-by-one/sign error.**

**Fail-safe — traced every branch:** `STEP_START` is set ONLY when `_step_start_raw` is all-digits (`case '' | *[!0-9]*`), normalized via `strip_lz` (leading-zeros stripped so `$(())` never treats it as octal — the dash `10#` alternative errors, W1), `> 0`, AND `<= SNAP_NOW`. Unset / empty / `abc` / `-5` / `0` / future all leave `STEP_START=""` → the `else` branch runs the **byte-exact legacy** `[ "$age" -ge "$MIN_AGE" ]`. TEST-018 exercises all six shapes GREEN. Legacy `MIN_AGE` default is 0, but the kill is still Guard-1 (token) + Guard-2 (workspace) scoped — **never a global kill**. Epoch mode can only ever SPARE MORE than legacy (it reaps strictly the procs predating the step); no input makes it reap MORE than legacy. Failed arithmetic tests fall through `2>/dev/null || continue` → spare (safe).

**Guards 1 & 2 unchanged:** Confirmed byte-identical — token `case *vitest*|*esbuild*` and workspace `case *"${WORKSPACE}/"*` (path-separator-anchored, glob-safe) are untouched context lines. The real safety boundary is not weakened.

**Portability:** Only `ps etime` + `date +%s`. No `lstart`, no `date -d`/`date -j` string parsing (TEST-019 static guard on comment-stripped source). `strip_lz` uses POSIX `${var#"${var%%[!0]*}"}` + `${_v:-0}` + `printf` — dash-safe. TEST-013 extended to run the epoch spare/reap path under `dash` with no shell errors. **Clean.**

**Tests genuinely assert (not hollowed):**
- RED `red-20260720T114129Z-test016.log` (`RED_CLASS: product_red`): the pre-change fixed-threshold reaper **KILLS** the fresh sibling at injected delay=7s (`reaped: 1`) — the flake deterministically reproduced. GREEN: TEST-016 spares identically at delay 0 AND 7.
- RED test017: old reaper spares the survivor (`reaped: 0`); GREEN: epoch mode reaps it even at `MIN_AGE=999`.
- RED test020: prompt docs lacked the wiring.
- All fixtures are throwaway `spawn_marked` sleeps in isolated `mktemp -d` workspaces; each spawned pid is tracked to a FILE (the diff fixes a real bug — `track()` under `$(...)` command-substitution ran in a subshell so the trap never saw the pids) and reaped by `cleanup()`. No real process is touched.

**ps1 parity + producer wiring:** `Get-ReapCandidates` gains `-StepStart [datetime]` / `-GraceSeconds` (spare `CreationDate >= StepStart - Grace`, reap older; absent → byte-identical `-MinAgeSeconds` path). `Get-StepStartFromEpoch` mirrors the .sh validity rule (digits, `>0`, not future → else `$null` fallback). WSL delegation forwards `AAI_REAP_STEP_START_EPOCH`/`AAI_REAP_GRACE_SECS` **raw/unvalidated** so the .sh side owns validation (no double-format). Pester **re-run on this host: 38 passed / 0 failed.** SKILL_LOOP + VALIDATION both document capturing `AAI_REAP_STEP_START_EPOCH=$(date +%s)` at step start and passing it to the reaper (TEST-020 grep-asserts both).

## AC table walk
See the YAML `ac_walk` above — all 7 Spec-AC **compliant**. Every TEST-001..008 mapped test exists and is GREEN (green-20260720T120138Z log, 20/20) and Pester 38/38; CI green 2× at HEAD.

## Findings
- **NON-BLOCKING** `docs/INDEX.md` — stale auto-generated per-AC "Deferred" row for Spec-AC-07 (generated 12:16Z, before AC-07 flipped to done at 12:48Z). Disposition: **regenerate INDEX at close** (advisory; auto-generated, self-heals on next regen).
- **NON-BLOCKING** `tests/skills/test-aai-run-tests.sh` TEST-017 — ~1s nominal reap margin; fails only in the safe direction and overhead pushes toward reap. Disposition: **note only, no action** (green 2× in CI).
- **INFO** — three files exceed the declared `inline_review_scope` but are correct, coherent companions of this change (auto-regen index + prompt-diet ledger credit with verified arithmetic). No action.

## cannot_verify
1. Native Windows process kill semantics — off-CI, SPEC-0046 MV protocol (unchanged posture; Pester covers pure selection logic).
2. Flake absence across many future runs (probabilistic) — spec bar of 2 consecutive green Ubuntu runs is met; local delay-injection proves determinism.

## Next steps
Merge-ready from a code-review standpoint. Before close: regenerate `docs/INDEX.md` so the Spec-AC-07 row reflects `done` (advisory, non-blocking). The two NON-BLOCKING items carry disposition notes above; neither requires a follow-up ref.
