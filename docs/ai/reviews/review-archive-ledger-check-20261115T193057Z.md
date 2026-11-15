# Code review: archive-ledger-check (round 3, the single standing-a extension round)

```yaml
review:
  scope: "git diff origin/main (822569b2) in /Users/ales/Projects/aai-worktrees/archive-ledger-check, plus untracked docs/issues/ISSUE-0116-archive-ledger-check.md and docs/specs/SPEC-0293-spec-archive-ledger-check.md; focus on the round-2 remediation delta"
  spec: docs/specs/SPEC-0293-spec-archive-ledger-check.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/metrics-flush.mjs:230,250,1848; TEST-3751 (validation round 4 PASS; round-2 delta does not touch this path)" }
      - { ac: Spec-AC-02, call: compliant, citation: "metrics-flush.mjs dry-run exit line unchanged; TEST-3752 (validation round 4 PASS)" }
      - { ac: Spec-AC-03, call: compliant, citation: ".aai/scripts/merge-cleanup.mjs:867-870, .aai/scripts/lib/metrics-flush-record.mjs:163-201; TEST-3753 PASS (this round)" }
      - { ac: Spec-AC-04, call: compliant, citation: "merge-cleanup.mjs:870; TEST-3754 PASS (this round)" }
      - { ac: Spec-AC-05, call: compliant, citation: "merge-cleanup.mjs:1281-1286; TEST-3755 PASS (this round)" }
      - { ac: Spec-AC-06, call: compliant, citation: "metrics-flush-record.mjs:185,196; merge-cleanup.mjs:869; merge-outcomes.mjs:80,118; TEST-3756 PASS (this round)" }
      - { ac: Spec-AC-07, call: compliant, citation: ".aai/SKILL_WORKTREE.prompt.md step 2 block; TEST-3757 (validation round 4 PASS; round-2 delta does not touch it)" }
      - { ac: Spec-AC-09, call: compliant, citation: "metrics-flush-record.mjs:167-172 (main working METRICS + refs/remotes/origin/<base> blob as --held-in), merge-cleanup.mjs:868,1284 (origin, base passed); TEST-3759, TEST-3760, TEST-3761 PASS (this round); round-2 repro3.sh TEST-R3 now prints 'bar Planning runs in main = 1'" }
      - { ac: Spec-AC-08, call: compliant, citation: "CHANGELOG.md:33-35; docs/product/telemetry.md:197-213; TEST-3758 (validation round 4 PASS)" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/metrics-flush-record.mjs, line: 169,
          issue: "a failed `git show` of the base ledger is silent: the base ledger is simply left out of --held-in, so the check falls back to the round-2 (B3-prone) behaviour without saying so",
          failure_scenario: "refs/remotes/origin/<base> exists (readAndGate fetched it) but `git show` fails for a reason other than the path being absent (object corruption, ENOBUFS above the 1 GiB maxBuffer); a run that only the base ledger holds is then written to the worktree ledger and, after the base sync, is twice in the main METRICS. Not reproduced; needs a broken repository." }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/metrics-flush-record.mjs, line: 171,
          issue: "the temp-file write sits before the try, outside the keep path: a throw from fs.writeFileSync escapes archiveRuntime, which the step runner rethrows (merge-cleanup.mjs:1399-1400) instead of keeping the step",
          failure_scenario: "os.tmpdir() unwritable or full: apply stops with an uncaught error after archive-runtime made the archive copy and before sync-base; every resume stops at the same point. No metrics are lost (the archive copy holds them) and no ledger is written; the cleanup does not progress until TMPDIR is fixed. Not reproduced." }
  cannot_verify:
    - { claim: "the D3 step 3 branch for a worktree NOT at the PR head (writable=false with a METRICS file present) behaves like the no-METRICS case", closes_with: "a merge-cleanup case with the ride worktree one commit past ctx.head and a late run (spec R2 names it untested)" }
    - { claim: "Windows: the child spawn, the --held-in absolute paths, the os.tmpdir() temp ledger and the printed fallback command on a native runner", closes_with: "the Windows Pester / native leg on the PR head" }
    - { claim: "the full suite stays green; only selected cases were run here", closes_with: "the one full sweep owed before close" }
    - { claim: "the kept ledger_runs_unchecked outcome is surfaced again after the worktree is gone (a later apply reports noop no_worktree)", closes_with: "a decision that the archive copy plus the default --recover-archives sweep is the accepted backstop, or a durable outcome record" }
  overall: pass
```

security_relevant: false

## Scope and spec

- Scope: `git diff origin/main` (base 822569b2) in the ride worktree (16 tracked files), plus the two untracked drafts. This round reviewed the whole diff once and read the round-2 remediation delta line by line: `recoverStateCopy` gains `origin`/`base` (default null) and materialises `refs/remotes/origin/<base>:docs/ai/METRICS.jsonl` to a temp file passed as a second `--held-in` (removed in `finally`); both merge-cleanup callers pass `origin: ctx.origin, base: ctx.base`; TEST-3761; the Spec-AC-09/D3 contract amendment; CHANGELOG and telemetry.md wording.
- Append-only check: the origin/main blobs of `docs/ai/EVENTS.jsonl` (772203 B) and `docs/ai/decisions.jsonl` (2030088 B) are byte-exact prefixes of the branch files. The new decisions line is the round-2 contract amendment, tracked by the open `fu-amend-spec-archive-ledger-check` (`spec-amend list --strict` rc 0: two `unsigned-tracked` contract records, signed at merge).
- Spec: docs/specs/SPEC-0293-spec-archive-ledger-check.md (frozen, ceremony 2, contract-amended twice for Spec-AC-09).
- Dispatch note (anti-gaming): the dispatch summarised the remediation, set the BLOCKING bar ("only for a real, reproduced defect that loses or duplicates metrics, breaks the cleanup, or makes a spec claim false") and pointed at the repro. It did not pre-rate findings or exclude areas. The full scope was reviewed.

## Round-2 findings: are they cured?

| Round-2 | Status | Evidence |
|---|---|---|
| B3 run merged on origin/main but not yet pulled written twice | cured | round-2 repro `/private/tmp/claude-501/-Users-ales-Projects-aai/2071b3a2-d378-409f-946d-cd8edb99948a/scratchpad/r2/repro3.sh --test TEST-R3` (ROOT pinned to this worktree) now prints `archive-runtime ... "1 archived"` (no recovery), `sync-base ... fast-forward`, `bar Planning runs in main = 1`, rc 0. TEST-3761 encodes the same world (bar's line committed on the bare main as `bar (#432)` before the squash `foo (#433)`, main checkout not pulled) and PASSes; its RED log (`docs/ai/tdd/archive-ledger-check/red-TEST-3761.log`) shows the pre-fix `1 run(s) recovered`; its mutation record (dropping `held.push(tmp)`) is RED with `target_sha256` equal to the current file (7eab55a7...). The held base ledger is the same ref the sync lands on: `readAndGate` fetches `+refs/heads/<base>:refs/remotes/origin/<base>` (merge-cleanup.mjs:293) before any step, and `syncGate` targets `refs/remotes/origin/<base>` (:432). |
| N2 heldIn had no default (spawned as the string `undefined`) | cured | `origin = null, base = null` defaults (metrics-flush-record.mjs:163); with no origin `held` is `[]` and `...held.flatMap(...)` adds no flag (:183). No caller can produce a literal `undefined` argument any more. |

Round-1 B1/B2/N1 stay cured: TEST-3759 and TEST-3760 PASS this round.

## AC walk (spec_compliance: pass)

| Spec-AC | Call | Citation |
|---|---|---|
| Spec-AC-01 | compliant | metrics-flush.mjs parse + exit-2 guard and focus skip; TEST-3751 green in validation round 4; untouched by the round-2 delta. |
| Spec-AC-02 | compliant | TEST-3752 green in validation round 4; untouched by the delta. |
| Spec-AC-03 | compliant | TEST-3753 PASS (this round). |
| Spec-AC-04 | compliant | TEST-3754 PASS (this round), including the stop-after resume arm. |
| Spec-AC-05 | compliant | TEST-3755 PASS (this round). Plan mode now also runs `git show` and writes/removes one temp file under `os.tmpdir()`; that is outside the fixture world and the digest stays equal. |
| Spec-AC-06 | compliant | TEST-3756 PASS (this round). |
| Spec-AC-07 | compliant | TEST-3757 green in validation round 4; untouched by the delta. |
| Spec-AC-09 | compliant | The amended AC names the base-branch case; the code passes both held ledgers (metrics-flush-record.mjs:167-172). TEST-3759, TEST-3760, TEST-3761 PASS (this round). |
| Spec-AC-08 | compliant | TEST-3758 green in validation round 4. Wording checked: CHANGELOG "the ride's ledger, the main checkout's or the base branch's (`--held-in`, also new)" and telemetry.md "the base branch's ledger it is about to sync to" are true of the code. |

Mutation gate: `node .aai/scripts/mutation-gate.mjs --spec docs/specs/SPEC-0293-spec-archive-ledger-check.md` -> `GATE PASS: 11 row(s) satisfied degraded=0`.

Deviation noted (not a failure): the spec's Implementation plan "Components" bullet still names `recoverStateCopy({ scriptDir, root, copy, rel, writable, dryRun })` without `origin`/`base`; D3 (the binding decision) names both. INFO only.

Tests run this round (all rc 0, logs in /private/tmp/claude-501/-Users-ales-Projects-aai/2071b3a2-d378-409f-946d-cd8edb99948a/scratchpad/r3/): merge-cleanup `--test` TEST-3761, 3760, 3759, 3753, 3754, 3755, 3756, 058 (1490 <= 1490), 2923; repro3.sh TEST-R3. No `aai-held-ledger-*` file left in `os.tmpdir()` afterwards.

## Findings (code_quality: pass)

No BLOCKING finding. I looked for a way the new base-ledger hold could lose a run (a run skipped because origin/<base> holds it while the main checkout never receives it): if sync-base is kept (dirty or diverged main), the run still lives on origin/<base>, the ledger of record, and arrives with the next pull, so nothing is lost. A later fetch on a resume only widens the held set. `flush_segment` takes the max line count over three ledgers, which can only number higher, never collide lower.

### N3 (NON-BLOCKING): a failed base-ledger read degrades silently

- Where: .aai/scripts/lib/metrics-flush-record.mjs:169-171. `blob.status !== 0` (or empty stdout, or ENOBUFS over the 1 GiB `maxBuffer`) just leaves the base ledger out.
- Scenario: the fetched ref exists but `git show` fails (corrupt object, a ledger above 1 GiB). A run that only the base ledger holds is then written and appears twice after the sync, the B3 duplicate. Absent path on the base (an untracked ledger) is the legitimate empty case and is fine.
- Recommended disposition: (d) accepted residual (P3 assurance strength, needs a broken repository, no observed bite). If remediated later: a non-zero `git show` that is not "path does not exist" should keep the step (`ledger_runs_unchecked`) instead of writing.

### N4 (NON-BLOCKING): the temp-file write can throw past the keep path

- Where: .aai/scripts/lib/metrics-flush-record.mjs:171 (`fs.writeFileSync(tmp, ...)` before the `try`); the step runner rethrows anything that is not `Keep` (merge-cleanup.mjs:1399-1400).
- Scenario: `os.tmpdir()` unwritable or full. apply stops with an uncaught error after archive-runtime made the archive copy and before sync-base, and every resume stops at the same point. Nothing is lost or duplicated (the archive copy holds the runs, no ledger is written), but the cleanup cannot progress until TMPDIR is fixed.
- Recommended disposition: (d) accepted residual (P3, environment failure, cleanup halts loudly rather than corrupting). A two-line fix if wanted now: move the write inside the `try` and turn its failure into a keep.

### INFO

- Plan mode spawns one `git show` per plan; cost is one blob read, acceptable.
- merge-cleanup.mjs stays at its 1490-line ceiling (TEST-058 PASS); the remediation lives in the helper as round 2 advised.
- Pre-existing, not introduced here (follow-up candidates only if wanted): none new found this round.

## Warning dispositions (H6)

- N3: recommended (d), `accepted residual: a failed git show of the base ledger silently drops the base hold; P3, needs a broken repository, no observed bite`.
- N4: recommended (d), `accepted residual: an unwritable os.tmpdir() stops archive-runtime with an uncaught error; P3, no metric lost or duplicated, cleanup halts loudly`.
- B3, N2 (round 2): cured in tree (above).

## Next steps

1. Orchestrator records the N3/N4 dispositions (quote the accepted-residual lines above in `code_review.notes`, or file follow-ups if preferred).
2. The full sweep owed before close (cannot_verify), then the PR; the two contract amendments sign at merge via `fu-amend-spec-archive-ledger-check`.
