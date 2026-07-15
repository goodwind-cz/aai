# Code Review (re-review) — CHANGE doctor-vendored-layer-drift

- Scope: worktree `feat/doctor-layer-drift` (uncommitted) @ /Users/ales/Projects/aai-feat-layer-drift
- Base ref: main
- Head ref: WORKTREE (uncommitted)
- Reviewer model: claude-sonnet-5 (independent re-review role; fresh session, no
  memory of the prior review)
- Reviewed: 2026-07-15T23:38:13Z
- Prior review: `docs/ai/reviews/review-doctor-layer-drift-20260715T233145Z.md`
  — **FAIL** on one BLOCKING finding (B1: main-guard compared decoded argv vs
  percent-encoded `import.meta.url` pathname, so a path with a space made the
  CLI silently exit 0 — doctor CAT-13 would read that as up-to-date).
- Verdict: **PASS** — B1 remediated, no regression.

## What changed since the prior (FAIL) review
`git diff --stat main` for the previously-modified tracked files is byte-for-byte
consistent with the prior review's Stage-1 characterization (still purely
additive, same line counts):
- `.aai/SKILL_DOCTOR.prompt.md`  +24/-0
- `.aai/scripts/aai-sync.sh`     +8/-0
- `.aai/scripts/aai-sync.ps1`    +10/-0
- `.aai/scripts/aai-update.sh`   +1/-1
- `.aai/system/AAI_PIN.md`       +10/-0

`.aai/scripts/layer-drift.mjs` is untracked (new-file diff vs main), so it was
read in full (293 L, up from the 283 L the prior review quoted) and compared
line-by-line against the prior review's excerpts of `decide`, `probeCanonical`,
`parseArgs`, `parsePin`, `git`, and `verdict`. All of that logic is byte-for-byte
unchanged. The only delta is:
1. `import { fileURLToPath } from 'node:url';` added (line 47).
2. The main-guard block (was line 281, one-liner using
   `path.resolve(new URL(import.meta.url).pathname)`) replaced with a
   `realOrResolve()` helper + comment explaining the two stacked causes, and the
   guard now compares `realOrResolve(process.argv[1])` against
   `realOrResolve(fileURLToPath(import.meta.url))`.

`tests/skills/test-aai-layer-drift.sh` gained one new test function,
`test_space_in_path` (TEST-014), wired into `main()`. No existing test body was
altered (diffed against the prior review's TEST-001..011 descriptions — all
still match).

`docs/specs/SPEC-DRAFT-doctor-vendored-layer-drift.md` gained a "Review finding
dispositions (2026-07-16)" section addressing B1 (REMEDIATED) and N1-N3
(ACCEPTED, no action) — no other spec content changed.

**Conclusion: the fix touched only the guard block + one import line + the new
regression test + the spec disposition section. No other behavior changed.**

## Fix verification — read

```js
function realOrResolve(p) {
  try { return fs.realpathSync(p); } catch { return path.resolve(p); }
}
if (process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url))) {
  main();
}
```

- `fileURLToPath` decodes the percent-encoding B1 flagged (`%20` -> ` `),
  fixing failure layer 1.
- `realpathSync` on both sides resolves symlinks (macOS `/tmp` ->
  `/private/tmp`), fixing failure layer 2 that the prior review's own fix
  suggestion (`fileURLToPath` alone) would NOT have caught — this
  worktree correctly went further than the minimum prior-review ask.
- Guarded by `try/catch` with a `path.resolve` fallback: `fs.realpathSync`
  throws ENOENT if the path doesn't exist, so this can never crash the guard
  even in degenerate invocations (e.g. a deleted script path). Confirmed by
  reading — this exact shape is exercised implicitly by every test run;
  argv[1] always exists in practice, so this is a defensive fallback, not a
  code path with its own test, and reading confirms it's structurally safe
  (no unguarded throw can propagate out of `realOrResolve`).
- `process.argv[1] &&` guard also prevents a crash if argv[1] is ever
  undefined (e.g. certain REPL/stdin invocations).

## Suite re-run

`bash tests/skills/test-aai-layer-drift.sh` — 14/14 test functions PASS
(TEST-001, 002, 003, 004a, 004b, 005, 006, 007, 008, 009, 010, 010b, 011,
no-real-network self-check, 014), exit 0:

```
=== AAI Skill Test: aai-layer-drift ===
...
PASS: TEST-014 main-guard fires from a space-containing path (B1)
=== ALL TESTS PASSED: aai-layer-drift ===
```

## Independent probes (raw output, not just test-suite trust)

**Probe (a) — space-in-path AND symlink layer (macOS `/tmp` -> `/private/tmp`,
confirmed: `readlink /tmp` = `private/tmp`), missing pin:**
```
$ node "/tmp/layer drift probe <pid>/.aai/scripts/layer-drift.mjs" \
    --pin "/tmp/layer drift probe <pid>/nope/AAI_PIN.md"
layer drift unverifiable (no .aai/system/AAI_PIN.md — not a vendored project, or never synced)
EXIT=4
```
This is the exact double-failure scenario the disposition describes (space +
symlink-resolved /tmp). Pre-fix this produced empty stdout and exit 0
(per the prior review's own reproduction). Post-fix: correct message, exit 4.

**Probe (b) — no-space, non-symlinked absolute path under `$HOME`, missing pin
(control case — confirms the fix didn't regress the common path):**
```
$ node "$HOME/aai_probe_<pid>/scripts_no_space/layer-drift.mjs" \
    --pin "$HOME/aai_probe_<pid>/nope/AAI_PIN.md"
layer drift unverifiable (no .aai/system/AAI_PIN.md — not a vendored project, or never synced)
EXIT=4
```
Matches probe (a)'s output — the fix is path-shape-invariant, as required.

**Probe (c) — import-only path must not execute `main()`:**
```
$ node --input-type=module -e "import('<abs>/.aai/scripts/layer-drift.mjs').then(()=>console.log('import ok, no CLI run'))"
import ok, no CLI run
EXIT=0
```
No verdict/message line was printed — confirms `import { parsePin, decide }`
(used by future unit tests / other tooling) remains side-effect-free and the
guard does not fire on `import()`.

**Probe (d) — try/catch shape verified by reading (see "Fix verification"
above): `fs.realpathSync` throwing on a nonexistent path is caught and falls
back to `path.resolve`, so the guard cannot crash. No separate executable
reproduction is possible/needed here since `process.argv[1]` always refers to
the actually-invoked script path in a real `node` invocation; the shape is
confirmed structurally.**

## Regression sanity

- `node .aai/scripts/docs-audit.mjs --strict` → **Verdict: CLEAN** (only the
  two DRAFT docs for this change flagged as "pending commit", which is
  expected for an uncommitted worktree; no orphan/false-done/stale findings).
- `node .aai/scripts/check-state.mjs` → `OK: docs/ai/STATE.yaml has exactly
  one of every top-level key.`
- Diff-scan (above) confirms the remediation is scoped to the guard block,
  the one import line, the new TEST-014, and the spec disposition section —
  no other file's behavior changed since the prior (FAIL) review.

## N1-N3 (prior review's non-blocking findings)
Re-confirmed as accepted-with-disposition in the spec (lines 273-276):
N1 (garbage pin sha -> drift not unverifiable) matches D3 by design; N2
(quoted URL) / N3 (case-sensitive marker) are dead paths because the sync
scripts never emit either form. No action required; no change requested here.

## Overall: PASS
B1 is remediated at both failure layers (decode + symlink-resolve), verified
by direct execution from a real space+symlink path (not just the packaged
test), a control case, and an import-safety probe. No other file's behavior
changed since the prior FAIL review. Regression sweep (docs-audit --strict,
check-state) is clean.
