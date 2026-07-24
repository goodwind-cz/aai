---
id: test-018-legacy-spare-attribution
number: 30
type: issue
status: done
links:
  pr:
    - 139
  commits:
    - 8c8c2ea04e988fa9eb096d9fc689df78c3c1d6e6
  github_issues: []
---

# TEST-018 spare-fresh blames the reaper for a fresh proc's death it may not have caused; the "reaped: 1" flake is not derivable from the local model

# Summary
- `tests/skills/test-aai-run-tests.sh` TEST-018 spare-fresh direction
  intermittently fails on Ubuntu CI with `fail-safe broken (case='<future>'):
  legacy MIN_AGE=60 must still spare the fresh match (reaper output: reaped: 1)`.
  It has recurred AFTER both prior fixes: PR #123 (split-direction margins,
  SPEC-0064) and PR #128 (per-case workspace isolation, SPEC-0069). Two fixes
  reduced but did NOT eliminate it (most recently on PR #132, a telemetry-only
  diff).
- The failure is NOT derivable from the test + reaper logic:
  - The spare-fresh reap runs legacy mode with `MIN_AGE=60`. Legacy reaps a
    process iff `etime_secs >= MIN_AGE`. The fresh proc is spawned ~0s before the
    reap, and `old_pid` was already reaped in direction 1, so no process in the
    workspace has `etime >= 60`. `reaped: 1` therefore requires a process to pass
    the workspace + vitest + `age >= 60` guards — impossible for the two procs the
    test spawns.
  - All six invalid `STEP_START` cases (UNSET/EMPTY/abc/-5/0/future) are correctly
    coerced to empty by the reaper, so epoch mode never activates (epoch mode with
    a future STEP_START would reap everything — but the reaper rejects `> SNAP_NOW`).
  - Empirical: a load repro (180 iterations of the exact reap-old→spare-fresh
    sequence in a fresh workspace, under 8 CPU hogs on 16 cores, macOS) produced
    **0 / 180** failures. The flake does not reproduce locally even under load.
- Leading hypothesis (NOT proven): a Linux `ps etime` read race under CI load
  transiently reports a large elapsed time for the just-spawned fresh proc, so it
  passes the legacy `age >= 60` guard and is reaped. macOS BSD `ps` does not
  exhibit this (0/180). A secondary hypothesis is a coincidental argv-substring
  match by an unrelated process on the shared runner. Either way, the fresh proc
  is killed by a signal the TEST cannot currently attribute.

# Type
- bug

# Impact
- `aai-run-tests` is a REQUIRED CI check; this flake intermittently BLOCKS merges
  on unrelated PRs, each costing a ~8-min re-run (hit on #122, #127, #132). It is
  the third correction to the same test, and the prior two chased margins/isolation
  without removing the mechanism. Severity: medium — no product impact, but
  standing CI friction and a test that fails on evidence it does not actually have
  (it blames the reaper for a death it cannot prove the reaper caused).

# Current Behavior
- The spare-fresh assertion is `if ! alive "$fresh_pid"; then log_fail "... must
  still spare the fresh match (reaper output: $out)"`. It concludes "the reaper
  reaped the fresh proc" from `fresh_pid` being dead, but the reaper only reports a
  COUNT (`reaped: N`), never WHICH pids. So a fresh proc killed by ANY cause (a
  transient `ps` misread inside the reaper, an unrelated runner process the reaper
  matched, external interference) is attributed to a reaper spare-failure. The test
  measures a proxy (fresh_pid liveness) instead of the property it claims (the
  reaper, in legacy mode, does not reap a young proc).

# Expected Behavior
- The spare-fresh direction proves its property in an ATTRIBUTABLE, load-immune
  way: it fails ONLY when the reaper itself demonstrably reaped the test's own
  fresh proc, not when the fresh proc dies for a reason outside the reaper
  invocation. If a transient `ps` misread inside the reaper is the real cause, that
  is surfaced with enough captured evidence (the `ps` snapshot the reaper acted on)
  to finally root-cause it, rather than a bare `reaped: 1`.

# Steps to Reproduce (if applicable)
- Only observed on Ubuntu CI under load; does NOT reproduce on macOS (0/180 under
  8 CPU hogs). CI is the authoritative environment.

# Verification
- The spare-fresh assertion is made ATTRIBUTABLE: the reaper reports the pids it
  reaped (an additive diagnostic on `.aai/scripts/aai-reap-tests.sh` — a `reaped
  pids: ...` line alongside `reaped: N`; NOT a behavior change), and the test
  asserts `fresh_pid` is NOT in the reaped list (immune to an external kill of
  fresh_pid) AND, on any `reaped > 0`, dumps the `ps` snapshot the reaper matched
  on plus each matched pid's parsed etime — so a Linux `ps etime` read race (the
  leading hypothesis) is captured with evidence the next time it fires.
- The split-direction margins are NOT widened again (that is explicitly the
  anti-pattern the prior two fixes fell into); the fix changes ATTRIBUTION and
  OBSERVABILITY, not thresholds.
- Local: `bash tests/skills/test-aai-run-tests.sh` exits 0 on macOS across repeated
  runs (it already does — 0/180). CI: the `skill-suite` job is green on Ubuntu
  across repeated runs; because the flake is CI-only and rare, CI is the sole
  authoritative signal for the fix (like SPEC-0072 Spec-AC-05) — a local pass is
  NOT flake-fix evidence.
- If, after attribution, CI still shows the reaper genuinely reaping the fresh proc
  (its own pid in the reaped list with a misread etime), that is captured as a
  distinct, now-evidenced finding for a follow-up on the reaper's legacy age guard
  — not silently margin-patched here.

# Constraints / Risks
- `.aai/scripts/aai-reap-tests.sh` is the PRODUCTION reaper — an additive
  diagnostic line (reaped pids) is acceptable and useful, but its epoch/legacy
  DECISION logic must stay byte-behaviour-identical (TEST-006/013/015/016/017
  must still pass). Do NOT change what it reaps; only report what it reaped. It is
  NOT `protected_paths_l3`, but treat it with the care its safety-critical role
  warrants.
- No retry / loop-until-pass — that hides the mechanism (the anti-pattern that made
  #123/#128 incomplete). The fix removes the mis-attribution and captures evidence.
- Honesty: the root cause is NOT proven; the fix's job is to stop the
  false-attribution failures AND capture the data to prove the mechanism if it
  persists. Do NOT claim the flake is "fixed" — claim it is de-flaked by
  attribution + CI-validated, with the underlying ps-race hypothesis instrumented.
- Portability (LEARNED 2026-07-19): the reaper runs under `sh`/`dash`; the new
  diagnostic must be POSIX-safe, add no bashisms, and not perturb the existing
  `reaped: N` line other tests grep for (`grep -qiE "reaped: *[1-9]"`). Full
  `mktemp` templates in any test additions.
- Companion obligations (PLANNING step 3a): the touched files are a script + the
  test (not prompt corpus, not a new `.aai/**` file) — expect no prompt-diet ledger
  true-up and no PROFILES classification.
- No secret referenced — SECRETS PREFLIGHT skipped.

# Notes
- This is the third and (intended) final correction to TEST-018's spare-fresh
  direction. The lesson from #123/#128 is explicit: margins and isolation treated
  SYMPTOMS. This item changes what the test MEASURES — attribution over a liveness
  proxy — and instruments the reaper so the CI-only mechanism can finally be seen.
  Sibling epoch-mode case TEST-017 was root-caused by boundary arithmetic
  (SPEC-0072); this legacy case cannot be, because the failing behaviour is not
  reproducible in the local model — hence the instrument-and-attribute approach.
