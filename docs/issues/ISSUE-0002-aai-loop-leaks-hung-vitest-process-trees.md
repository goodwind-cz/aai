---
id: ISSUE-0002
type: issue
status: done
links:
  pr: []
  commits: []
---

# Issue: aai-loop leaks ~40 hung vitest process trees (~5.6 GB) per long run

## Summary
During a long `/aai-loop` run, every subagent test invocation that runs `vitest`
can orphan a hung `vitest` process tree. After a 17+ tick run (~25 test
invocations) the host held **~40 orphaned vitest trees holding ~5.6 GB RSS**,
4–15+ minutes old — long after their tests finished and the subagent reported
results. Nothing reaps the spawned process group, so hung runs accumulate and
host memory grows unbounded.

## Type
- bug

## Impact
- Who/what is affected? Any long autonomous `/aai-loop` run on a project whose
  test command is `vitest` (the dynamic `aai-test-unit` / `aai-test-e2e` skills
  + the project vitest config). Each test-running tick can leak one tree;
  fork-pool workers are sized to CPU count (~150 MB each), so memory multiplies.
- Severity/priority: **High** for long runs — unbounded host-memory growth; can
  OOM the machine or slow every subsequent subagent. Silent (no error surfaced).

## Current Behavior
`vitest run` does NOT exit after tests pass when a suite leaves open handles /
unhandled rejections (timers, unclosed mock clients, dangling promises). Vitest
(unlike Jest's `--forceExit`) waits on the event loop. When a suite keeps the
loop alive, `vitest run` hangs; the agent's `Bash` call returns/times out with
output captured, and the hung tree is **orphaned, not reaped**. Observed tree:

```
npm exec vitest run            (~43 MB)     <- never returned to the agent's shell
└─ node vitest.mjs run         (~65–98 MB)  <- hung after tests finished
   ├─ node .../vitest/dist/workers/forks.js   (~110–190 MB)  ×N fork workers
   └─ esbuild --service=… --ping              (~12 MB)
```

Two compounding factors:
1. **No guaranteed teardown** — nothing kills the spawned process group when the
   test command's output is captured; a hung `vitest` survives the launching agent.
2. **Unbounded fork workers** — default fork pool = CPU-count workers at ~150 MB
   each, multiplied across concurrent subagents.

## Expected Behavior
- A test run launched by the loop / `aai-test-*` skills can NEVER outlive the
  step that launched it: on success, failure, or timeout the entire process
  group is killed (no orphaned `vitest`/`esbuild` survivors).
- A single vitest run is memory-bounded (a few hundred MB), not CPU×~150 MB.
- A leak is visible (logged proc/memory accounting), never silent.

## Steps to Reproduce (if applicable)
1) Run `/aai-loop` for many ticks (17+) on a project using `vitest` whose suites
   have open-handle / unhandled-rejection teardown noise.
2) After the run, on the host: `ps axo pid,etime,rss,command | grep -E 'vitest|esbuild'`
   → many minutes-old `vitest`/`esbuild` trees still resident, summing to GBs.

## Verification
- Wrapper: a `vitest` suite that deliberately leaves an open handle (e.g. a
  dangling `setInterval`) is launched via the wrapper → the wrapper returns the
  test exit code AND no `vitest`/`esbuild` child survives (assert empty
  `pgrep -f "vitest\.mjs.*$PWD"` after the wrapper exits). RED before the
  wrapper exists (tree survives), GREEN after.
- Timeout path: a suite that never exits is killed at `AAI_TEST_TIMEOUT`; wrapper
  exits non-zero; no survivors.
- Bounded forks: a loop run caps a single vitest run at ~300–400 MB (maxForks=2),
  not ~1.5 GB.
- Reaper/accounting: after a test-running tick, scoped reap removes only
  this-workspace stale trees; tick log records lingering-proc / free-memory count.

## Constraints / Risks
- POSIX, macOS + Linux: macOS has no GNU `timeout`; use an inline watchdog.
- `kill -TERM -<pgid>` signals the whole group — MUST scope by workspace path and
  (under concurrent subagents) by start-time/etime so a sibling's in-flight run
  is never killed. Never reap globally.
- Fixes #1–#4 live in THIS AAI-framework repo (the loop + `aai-test-*` skills +
  bootstrap config). Fix #5 is target-project-specific (this repo has no vitest).

## Notes
Prescribed fix (priority: ship 1+2 first — they stop the bleeding and are
cheap/safe; 3–4 are loop hardening; 5 is the durable cure):

**1. Wrap every test run so the process GROUP is always killed (load-bearing).**
The loop / `aai-test-*` skills must never launch `vitest`/`tsc` directly. Route
through a wrapper that runs in its own process group, enforces a hard wall-clock
timeout, and kills the whole group on exit (success/failure/timeout):

```bash
# scripts/aai-run-tests.sh  (POSIX; macOS + Linux)
set -m                                  # new process group
timeout_secs="${AAI_TEST_TIMEOUT:-300}"
( "$@" ) & cmd_pgid=$!
( sleep "$timeout_secs"; kill -TERM -"$cmd_pgid" 2>/dev/null ) & watchdog=$!
wait "$cmd_pgid"; status=$?
kill "$watchdog" 2>/dev/null
kill -TERM -"$cmd_pgid" 2>/dev/null      # reap survivors (hung vitest workers/esbuild)
exit "$status"
```

**2. Bound vitest memory + leak surface** (vitest config, per app + root), e.g.
`pool: 'forks'`, `poolOptions.forks.maxForks: 2, minForks: 1`, `teardownTimeout:
10_000`; or `--no-file-parallelism` / `--maxWorkers=2` on the CLI for loop runs.
Caps a single run at ~300–400 MB instead of ~1.5 GB.

**3. Reaper after each test-running role (defence in depth).** At the end of every
Implementation/Validation/Remediation tick that ran tests, scoped reap of
this-workspace survivors only:
```bash
pkill -f "vitest\.mjs.*$PWD"        2>/dev/null || true
pkill -f "esbuild --service.*$PWD"  2>/dev/null || true
```
Scope by `$PWD`; under concurrent subagents only reap trees older than the
step's start time (record a timestamp; kill by etime) so siblings are untouched.

**4. Pre-flight + post-run accounting in the loop.** At loop start, count
`vitest`/`esbuild` procs for this workspace; if > threshold (e.g. 5), `log()` a
warning and reap stale ones (a previous run's leak must not compound). Record
host free-memory / lingering-proc count in the tick log (mirrors the existing
token-cost discipline) so a leak is visible, not silent.

**5. Fix the open-handle suites (root cause; TARGET-PROJECT repo, not this one).**
The real cure is `vitest run` exiting on its own. Fix the leaking suites (e.g. a
Supabase mock that throws `.order is not a function` at teardown → give it a
chainable `.order`; `issue019`/`prefill` unhandled rejections via `useAgeRules`).
Consider `test.dangerouslyIgnoreUnhandledErrors=false` so these FAIL loudly
instead of leaking.

LEARNED-rule candidate: "a `vitest run` that doesn't exit on its own is a
test-leak bug, not just noise — fix the open handle." (Add to
docs/knowledge/LEARNED.md when fix #5 lands in a target project.)

Immediate one-off operator cleanup (when no test run is in flight): `pkill -f
"vitest\.mjs"; pkill -f "esbuild --service"; pkill -f "npm exec vitest"` (freed
~5.6 GB on the reporting host).

Related: dynamic test skills `aai-test-unit`/`aai-test-e2e`
(`.aai/system/DYNAMIC_SKILLS.md`), `.aai/SKILL_BOOTSTRAP.prompt.md`,
`.aai/SKILL_LOOP.prompt.md`, `.aai/VALIDATION.prompt.md`.
