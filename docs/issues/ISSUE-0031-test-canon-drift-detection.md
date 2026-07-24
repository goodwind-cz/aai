---
id: test-canon-drift-detection
number: 31
type: issue
status: draft
links:
  pr: []
  commits: []
  github_issues: []
---

# TEST-006 (test-canon) checks drift with a fragile first-file-only hash, not phase2's own drift report

# Summary
- `tests/skills/test-aai-test-canon.sh` TEST-006 intermittently fails on Ubuntu CI
  with `Phase 2 silently overwrote canonical tests despite drift — should report
  drift` (hit on PR #137, a branch-guard-only diff). It does NOT reproduce locally
  on macOS: a load repro (40 iterations of TEST-006 under 8 CPU hogs on 16
  cores) produced 0/40 failures — CI-environment-specific, same class as TEST-018.
- The test modifies an archived source, commits, re-runs Phase 2 (which must DETECT
  drift and NOT rewrite the drifted domain), and asserts the canonical layer is
  unchanged via:
  `before=$(sha256sum tests/canonical/* 2>/dev/null | head -c 40 || echo ...)` then
  the same `after`, failing if `before != after`. This measurement is fragile in
  two ways:
  - `head -c 40` takes only the first 40 characters of the FIRST canonical file's
    hash and ignores every other file — it is position/glob-order dependent and
    both weak (misses a change in any non-first file) and noisy.
  - It infers "the drifted domain was overwritten" from "any canonical byte
    changed", conflating the specific contract (a DRIFTED domain must not be
    re-synthesized without `--resync`) with the whole-layer digest. Phase 2 legitimately
    REWRITES the non-drifted domains every run; the canonical render is deterministic
    (no timestamp), so that is normally byte-identical — but the test does not verify
    that assumption, and a single spurious diff (whatever its CI-load cause) is
    reported as a drift-detection failure.
- The authoritative signal the test ignores: Phase 2 already PRINTS its drift
  decision — `- DRIFT (changed since synthesis, NOT rewritten): N (<domains>)`
  (`.aai/scripts/test-canon.mjs`). The drift comparator (`test-canon-core.mjs`
  `runPhase2` -> `hashTestSources`) is pure file-read hashing with no clock or git
  dependency; a domain reported as drifted is `continue`d (skipped) before any
  write. Asserting on that report is what proves the contract.

# Type
- bug

# Impact
- `aai-test-canon` is part of the REQUIRED skill-suite; this flake intermittently
  BLOCKS merges on unrelated PRs (a re-run clears it). Its failure message accuses
  Phase 2 of a data-loss bug (silently overwriting the canonical layer) that the
  local model does not exhibit — a scary, misleading signal for a false alarm.
  Severity: low-medium — no product impact, standing CI friction, and a test that
  measures a proxy (first-file hash) instead of the property it claims (drifted
  domain not re-synthesized).

# Current Behavior
- TEST-006 derives pass/fail from `sha256sum tests/canonical/* | head -c 40` before
  and after a post-drift Phase 2 run. It neither consults Phase 2's own
  `DRIFT ... NOT rewritten` report nor isolates the drifted domain's file from the
  (legitimately) rewritten non-drifted ones.

# Expected Behavior
- TEST-006 proves the contract attributably: after modifying an archived source and
  re-running Phase 2 WITHOUT `--resync`, Phase 2 REPORTS the domain as drifted-and-
  not-rewritten, and the DRIFTED domain's canonical file is byte-unchanged. The
  measurement is complete and order-stable (all canonical files, not the first 40
  bytes of one), and any residual diff is captured with which file changed, so a CI
  recurrence is diagnosable instead of a bare "silently overwrote".

# Steps to Reproduce (if applicable)
- Observed only on Ubuntu CI (under suite-parallel load). Does not reproduce on
  macOS (8/8 quick + 0/40 under load; CI-only).

# Verification
- TEST-006 asserts on Phase 2's drift REPORT (the `DRIFT ... NOT rewritten` line
  names the modified domain) as the authoritative drift-detection signal, AND
  checks the DRIFTED domain's specific canonical file is byte-identical before/after
  (isolated from non-drifted domains that Phase 2 rewrites deterministically every
  run).
- The whole-layer measurement, if kept as a secondary guard, is order-stable and
  complete (e.g. a digest over `sha256sum tests/canonical/* | sort`, not `head -c
  40`), and on any mismatch dumps WHICH file changed + a diff, so a real CI
  recurrence is evidenced.
- The Phase 2 drift comparator (`test-canon-core.mjs`) is NOT changed unless the
  load repro proves a genuine race in it — this is expected to be a test-fixture
  robustness fix (like TEST-018), not a change to drift detection. If the repro DOES
  reproduce a real phase2 race, that is a distinct, now-evidenced finding.
- Local: `bash tests/skills/test-aai-test-canon.sh` exits 0 on macOS across repeated
  runs. CI: the `skill-suite` job is green on Ubuntu across repeated runs; because
  the flake is CI-only, CI is the authoritative signal (a local pass is not
  flake-fix evidence) — the CI-green AC is `deferred` with a Review-By >=14 days out.

# Constraints / Risks
- Prefer a TEST-ONLY fix. `.aai/scripts/test-canon.mjs` / `lib/test-canon-core.mjs`
  are the production skill; touch them ONLY if the load repro proves a real race
  there, and never change the drift DECISION logic without the same care the reaper
  got. Neither is `protected_paths_l3` (verify).
- No retry / loop-until-pass (the anti-pattern). The fix changes WHAT is measured
  (attribution to the drift report + complete measurement), not thresholds.
- Do NOT weaken the test — it must STILL fail if Phase 2 genuinely re-synthesizes a
  drifted domain without `--resync` (assert the drifted file unchanged AND the
  report names it). TEST-007 (--drift/--resync) semantics must stay green.
- Portability (LEARNED 2026-07-19): POSIX-safe shell, full `mktemp` templates, honor
  shebangs; green on Linux CI + macOS.
- Companion obligations (PLANNING step 3a): a test-file-only fix touches no prompt
  corpus and adds no new `.aai/**` file -> expect no ledger true-up, no PROFILES.
- No secret referenced — SECRETS PREFLIGHT skipped.

# Notes
- Same family as the TEST-018 reaper attribution fix (SPEC-0076): a CI-only,
  locally-unreproducible flake where the test measures a fragile proxy and blames
  the production tool. The fix is attribution (assert on the tool's own authoritative
  report) + a complete/order-stable measurement + instrumentation, with CI as the
  sole validator. `head -c 40` of one file is exactly the kind of proxy that reads
  as coverage while providing little.
