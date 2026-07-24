```yaml
review:
  scope: "git diff main (working tree; HEAD==main) -- .aai/scripts/metrics-flush.mjs tests/skills/test-aai-metrics.sh"
  spec: docs/specs/SPEC-DRAFT-spec-retire-stranded-nonworkitem-metric.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/metrics-flush.mjs:632-635 (guard 2a) + tests/skills/test-aai-metrics.sh:147-162 (test_111) — reproduced independently, exit 1, byte-unchanged" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/scripts/metrics-flush.mjs:636-641 (guard 2b, closedRefs() called unconditionally) + tests/skills/test-aai-metrics.sh:164-179 (test_112) — reproduced independently" }
      - { ac: Spec-AC-03, call: compliant, citation: ".aai/scripts/metrics-flush.mjs:623-627 (existence guard) + tests/skills/test-aai-metrics.sh:181-195 (test_113)" }
      - { ac: Spec-AC-04, call: compliant, citation: ".aai/scripts/metrics-flush.mjs:676-698 (mutate+append) + tests/skills/test-aai-metrics.sh:108-145 (test_110)" }
      - { ac: Spec-AC-05, call: compliant, citation: ".aai/scripts/metrics-flush.mjs:645-657 (discardedRuns/event payload) + tests/skills/test-aai-metrics.sh:125-139 (field-exact node assertion inside test_110)" }
      - { ac: Spec-AC-06, call: compliant, citation: ".aai/scripts/metrics-flush.mjs:629-674 (both guards before the dry-run branch) + tests/skills/test-aai-metrics.sh:197-232 (test_114, both directions)" }
      - { ac: Spec-AC-07, call: compliant, citation: "diff hunk .aai/scripts/metrics-flush.mjs:765-774 (retire branch inserted, no reordering of surrounding lines) — independently reproduced via git-stash A/B on a synthetic fixture: STATE + stdout byte-identical modulo scratch-dir path text; full metrics suite 27/27 green locally" }
      - { ac: Spec-AC-08, call: compliant, citation: ".aai/scripts/metrics-flush.mjs:67-84 (header) + :160 (usage string) + tests/skills/test-aai-metrics.sh:234-253 (test_116); .aai/METRICS_FLUSH.prompt.md diff is empty (git diff main -- .aai/METRICS_FLUSH.prompt.md)" }
  code_quality:
    verdict: pass
    findings: []
  cannot_verify:
    - { claim: "retire's ledger-before-STATE ordering survives a genuine process crash between the EVENTS append and the STATE commit (the same guarantee TEST-013 crash-fault-injects for the default flush path)", closes_with: "an AAI_FLUSH_INJECT_CRASH-style hook inside handleRetire() plus a regression test; the current evidence for retire is static code order (verified by reading .aai/scripts/metrics-flush.mjs:692-698, event write strictly precedes writeState()), which the spec's own Constraints section treats as sufficient — not a gap against the frozen spec, just an unexercised failure mode" }
    - { claim: "actorSlug() behavior when the git binary itself is absent/unexecutable on a CI runner (spawnSync throwing rather than returning a non-zero status)", closes_with: "a test that PATH-hides git before invoking --retire; existing coverage only exercises the no-.git-repo case (git config exits non-zero, falls back to unknown), not a spawnSync throw" }
    - { claim: "full tests/skills/test-framework.sh (42-skill) suite green, cited in STATE.yaml's validation notes as CI-authoritative", closes_with: "CI run output (dispatch explicitly scoped this review to the two named files; I ran tests/skills/test-aai-metrics.sh directly — 27/27 green locally — not the full suite)" }
  overall: pass
```

# Code Review — retire-stranded-nonworkitem-metric

## Scope

Working-tree diff against `main` (HEAD == main, no commits yet), restricted per
dispatch to:
- `.aai/scripts/metrics-flush.mjs` (+162/-7)
- `tests/skills/test-aai-metrics.sh` (+247/-0)

Note: the dispatch cited `git diff main...HEAD`, which is empty because HEAD
currently equals `main` — the actual changes are uncommitted working-tree
diffs. Used `git diff main -- <paths>` instead, which is exactly the same
byte content the branch will produce once committed. Recorded here rather
than silently substituted.

## Spec compliance — PASS

Read `docs/specs/SPEC-DRAFT-spec-retire-stranded-nonworkitem-metric.md`
(SPEC-FROZEN: true, ceremony_level 1) in full, then the diff. All 8 Spec-AC
rows walked above; every row independently reproduced against synthetic
fixtures I built myself (not the implementer's fixtures, not the real
`pr-67-post-merge-review` STATE entry) — see Verification below. No deviation
from the frozen spec found. AC Status table rows are all terminal (`done`)
with non-empty evidence; `Review-By` empty is consistent with an in-progress
code_review phase.

## Code quality — PASS

### Truth-gate cannot be bypassed — confirmed, no bypass found

Traced `handleRetire()` (`.aai/scripts/metrics-flush.mjs:617-711`):
1. Existence guard (line 624-627) — exact match, no mutation on absence.
2. Guard 2a (line 632-635) — `vStatus === 'pass' && refMatches(vRef, ref)`,
   the *exact expression* used at line 788 in the default flush loop (same
   `vStatus`/`vRef` variables, same `refMatches` function — not a
   reimplementation).
3. Guard 2b (line 638-641) — `closedRefs(eventsPath).has(ref)`, the same
   `closedRefs()` function the `--sweep` gate uses (line 807), called here
   **unconditionally** regardless of whether `--sweep` was also passed.
4. Both guards run before the `--dry-run` branch (line 665), confirmed by
   source order and independently reproduced (see below) — a dry-run on a
   flushable ref refuses identically to a non-dry-run attempt, no plan
   printed.

I independently proved both guards are *supersets* of true flushability
(never under-refuse): for guard (a), the full default-flush eligibility
requires `vStatus==='pass' && refMatches(vRef,ref)` AND code-review-ok AND
`runs.length>0` — guard (a) checks only the first conjunct, so it fires
whenever the entry *would* flush by default, and additionally fires in some
cases where the entry would NOT yet flush (e.g. code review still pending)
— i.e. it only ever over-refuses, never under-refuses. Same reasoning holds
for guard (b) vs. full `--sweep` eligibility (`closedRefs.has(ref)` is a
necessary condition of sweep-flushability, checked alone). This is
structurally why reusing the narrower boolean expressions (rather than the
full multi-gate eligibility chain) is safe and matches the spec's explicit
Design section.

Bypass hunt performed with my own synthetic fixtures (all reproduced,
none succeeded):
- `--sweep --retire <flushable-by-default ref>` → still refused, exit 1,
  zero mutation.
- `--ref <other> --retire <stranded ref>` → `--retire` ignores `--ref`
  entirely and retires the named ref (confirms `--retire` takes the branch
  unconditionally, per spec's documented "inert combination" note).
- Composite slash ref in both directions (`vRef="a/b"`, target `"b"` →
  refused via the loose `refMatches` split-match; `vRef="a"`, entry ref
  `"a/b"` → retired, but independently confirmed this exact case would
  *also* not flush under the default loop's own `refMatches` call — no
  divergence between retire's guard and the actual default-flush verdict).
- `--dry-run --retire <sweep-predicate-flushable ref>` (committed
  `work_item_closed` event, no `--sweep` flag) — **not covered by the
  existing test suite** (TEST-006/`test_114` only exercises dry-run against
  a *default*-predicate-flushable ref) — I reproduced it manually and it
  refuses correctly (exit 1, zero mutation, no plan printed). Code is
  correct; test coverage has a gap here. NON-BLOCKING (see disposition
  below) — the guard-order property that makes this case safe (both guards
  run before the dry-run branch) is the same property `test_114`(b) already
  pins for the other predicate, so the residual risk of regression is low,
  but the gap is real.

### Ledger-before-STATE + rollback — confirmed

`fs.appendFileSync(eventsPath, ...)` (line 695) executes strictly before
`writeState(statePath, ...)` (line 698) — verified by source order, and the
ordering claim is structural (synchronous Node.js, no async gap between the
two calls, so no interleaving is possible within one process invocation).
Pre-write validation (`duplicateKeys`/`inlineChildConflicts`, lines 684-690)
runs before the EVENTS append, so a structurally-invalid planned STATE never
reaches the ledger-write step. Post-commit `check-state.mjs` failure (line
702-706) writes a `.pre-flush-<ts>` recovery snapshot exactly as the default
flush path does — the appended `metric_retired` event is already durable on
disk by that point regardless of the STATE-side outcome, satisfying "no
half-state that loses telemetry AND keeps the entry."

### Default path byte-unchanged — confirmed independently

Diff-hunk inspection shows the retire branch (line 768-774) is inserted
*after* all pre-existing reads (`entries`, `vStatus`, `vRef`, `rRequired`,
`rStatus`, `focusRef`, `strategy`) and *before* the flush loop starts, with
`return` immediately after `handleRetire()` (which itself always
`process.exit()`s). No existing line in `main()` was reordered or edited
except the necessary additive changes to `parseArgs`'s `valueFlags` map and
the unknown-flag usage string (both required to accept the new flags at
all, not touching default-path *logic*).

Independently reproduced via `git stash` A/B: built a synthetic
`metrics.work_items` entry, ran the new script and the stashed (pre-change)
script against separate copies of the identical fixture with `--now` pinned
— resulting `STATE.yaml` files are byte-identical; stdout differs only in
the scratch-directory path text embedded in the relative-path report line.

### Event shape — confirmed

`metric_retired` payload carries `reason` (defaults to `null` via
`reason ?? null`, line 656) and `discarded_runs` (compact
`{role, model_id, duration_seconds}` per run, read verbatim off the parsed
entry, no re-derivation — matches the spec's explicit "no `trustedDuration`
re-validation" design choice). Confirmed the write path never calls
`append-event.mjs`: `EVENT_TYPES` in `.aai/scripts/append-event.mjs:26` does
not list `metric_retired` and is untouched by this diff (`git diff main --
.aai/scripts/append-event.mjs` empty) — irrelevant here since the retire
path never invokes that script at all (direct `fs.appendFileSync`, mirroring
the script's own `METRICS.jsonl` append idiom: `fs.mkdirSync` +
`fs.appendFileSync`, one JSON object + `\n` per line, no partial line
possible since the string is fully built before the single synchronous
write call).

### actorSlug() — confirmed

`.aai/scripts/metrics-flush.mjs:122-130` mirrors
`.aai/scripts/append-event.mjs:40-47`'s `actorSlug()`: git `user.email` →
lowercase → `[^a-z0-9._-]` stripped → `unknown` fallback on any failure
(empty result, non-zero exit, or thrown exception — wrapped in try/catch,
never propagates). The metrics-flush version uses `spawnSync` (already
imported) with an explicit `status !== 0` check instead of `execSync`'s
throw-on-nonzero, but the observable fallback behavior is equivalent.

### Read-only otherwise / fail-closed — confirmed

Reproduced independently: missing STATE file → exit 2 (usage-class,
pre-existing check, line 727); STATE with a duplicate top-level key → exit 1
integrity refusal before entries are even parsed (line 732-735, applies to
both default and retire paths identically); missing EVENTS.jsonl directory
under `--retire` on a genuinely stranded ref → `fs.mkdirSync(..., {
recursive: true })` creates it cleanly, no crash, entry retired successfully
on the first call and correctly reports "not present" on a re-run against
the now-empty state (idempotent, no double-retire).

## Test quality

Synthetic fixtures throughout (`write_retire_state()`,
`.aai/scripts/test-aai-metrics.sh` — reuses the existing `mk_repo()`/
`run_flush()` harness, no new `mktemp` template introduced). None of the new
tests depend on the real `pr-67-post-merge-review` entry (confirmed by
reading the fixture builder and grepping the new test bodies).

Coverage confirmed present: stranded-retire success (`test_110`), all three
refusal classes (`test_111`/`test_112`/`test_113`), dry-run-no-write +
dry-run-still-refuses (`test_114`, both branches), payload-carries-telemetry
(field-exact `node -e` assertion inside `test_110`), default-byte-unchanged
(pre-existing, unmodified `test_006_flush_golden`, correctly *not*
duplicated as a new function per the spec's own RED-proof carve-out for
non-discriminating regression pins).

Gap (NON-BLOCKING, test-quality dimension): no automated test for
`--dry-run --retire <ref>` where the ref is flushable specifically via the
**sweep** predicate (committed `work_item_closed` event, no `--sweep` flag)
— `test_114` only exercises the dry-run/no-bypass combination against the
*default* predicate. I reproduced this combination manually above and it
behaves correctly; the gap is in the regression net, not the code. See
disposition below.

Ran `bash tests/skills/test-aai-metrics.sh` directly: **27/27 tests green**,
including all 6 new `test_11N_*`/`test_116_*` functions. Ran twice for
determinism; identical output.

## Findings

None BLOCKING. Zero code-quality defects found across the truth-gate,
ledger-ordering, byte-unchanged, event-shape, actor, and fail-closed
dimensions specified in the dispatch.

One NON-BLOCKING test-coverage gap (not a code defect — the guarded
behavior was independently verified correct by hand):
- **NON-BLOCKING**: `tests/skills/test-aai-metrics.sh` has no automated
  case for `--dry-run --retire <ref>` where `<ref>` is flushable via the
  sweep predicate only (committed `work_item_closed`, `--sweep` absent).
  Disposition recommendation: remediate-in-tree (a 4th assertion appended to
  `test_114_retire_dry_run`, or a `test_115_retire_dry_run_sweep_flushable`
  filling the numbering gap already left between `test_114` and `test_116`)
  — small, mechanical, same fixture shape as `test_112`. Not a merge
  blocker; low risk given the shared "both guards precede dry-run" code
  path is already pinned for the other predicate.

## Verification

```
bash tests/skills/test-aai-metrics.sh          # 27/27 PASS (2 runs, deterministic)
node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-DRAFT-spec-retire-stranded-nonworkitem-metric.md   # LINT PASS
node .aai/scripts/docs-audit.mjs --gate spec-retire-stranded-nonworkitem-metric                            # GATE PASS
git diff main -- .aai/METRICS_FLUSH.prompt.md   # empty
git diff main -- .aai/scripts/append-event.mjs  # empty
grep metrics-flush.mjs .aai/system/PROFILES.yaml  # present under core (line 113)
node .aai/scripts/metrics-flush.mjs --dry-run --retire pr-67-post-merge-review   # real-repo, read-only, plan printed, git status clean after
```

Own-fixture bypass hunt (all refused / zero-mutation except the intended
stranded-retire success case): `--sweep --retire` on default-flushable;
`--ref X --retire Y` (inert composition, confirmed); composite `a/b` refs
both directions; `--dry-run --retire` on sweep-predicate-flushable (manual,
uncovered by the suite — see NON-BLOCKING finding); missing STATE; duplicate
top-level key; missing EVENTS directory.

git-stash A/B on a synthetic single-entry fixture: default (no-`--retire`)
`STATE.yaml` output byte-identical between pre-change and post-change
script.

## Companion obligations

N/A, confirmed. This spec touches no `.aai/*.prompt.md`/`.aai/AGENTS.md`
bytes (prompt file diff is empty) and adds no new `.aai/**` file
(`metrics-flush.mjs` and `test-aai-metrics.sh` both pre-exist and are
already classified `core` in `.aai/system/PROFILES.yaml`) — the spec's own
"Companion obligations" section states NEITHER of the two closed obligations
applies, and I confirmed both underlying facts independently rather than
taking the spec's self-assessment on faith.

## Protected paths

Confirmed `.aai/scripts/metrics-flush.mjs` is absent from
`protected_paths_l3` in `docs/ai/docs-audit.yaml` (the 8-entry list checked
by name), and no file in that list appears in this diff's file list.

## Next steps

- Overall: PASS. No BLOCKING findings on either dimension.
- One NON-BLOCKING test-coverage gap recorded above; needs a disposition
  (remediate-in-tree / decision / follow-up ref) per H6 before closeout —
  left to the orchestrator per the anti-gaming contract (a read-only
  reviewer names the recommended disposition, does not file it).
