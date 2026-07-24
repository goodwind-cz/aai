---
id: spec-test-canon-drift-detection
type: spec
number: 77
status: draft
ceremony_level: 1
links:
  requirement: docs/issues/ISSUE-0031-test-canon-drift-detection.md
  rfc: null
  pr: []
  commits: []
---

# Implementation Spec — TEST-006 (test-canon) drift-detection attribution + complete measurement

SPEC-FROZEN: true

Ceremony justification: the scope touches exactly one file —
`tests/skills/test-aai-test-canon.sh` (the `test_006` function body rewritten
from an inferred, position-dependent byte-diff to an attributed, isolated,
order-stable, self-proving check) — a single test-infra file, no production
code. Confirmed not in `protected_paths_l3` (docs/ai/docs-audit.yaml):
`.aai/scripts/state.mjs`, `.aai/scripts/lib/state-engine.mjs`,
`.aai/scripts/lib/state-core.mjs`, `.aai/scripts/allocate-doc-number.mjs`,
`.aai/scripts/pre-commit-checks.sh`, `.aai/scripts/pre-commit-checks.ps1`,
`.aai/workflow/WORKFLOW.md`, `docs/CONSTITUTION.md` — none match
`.aai/scripts/test-canon.mjs`, `.aai/scripts/lib/test-canon-core.mjs`, or
`tests/skills/test-aai-test-canon.sh` (grep confirmed zero matches). Single
reviewable, additive-in-intent, reversible, single-surface, test-only change
-> Level 1.

## Links
- Requirement: docs/issues/ISSUE-0031-test-canon-drift-detection.md
- Prior art (same family — CI-only, locally-unreproducible flake fixed by
  attribution + complete measurement, not thresholds):
  docs/specs/SPEC-0076-spec-test-018-legacy-spare-attribution.md (PR #139),
  docs/specs/SPEC-0072-spec-reaper-epoch-survivor-robustness.md (the
  anti-pattern this scope must also not repeat: margin-widening instead of
  fixing what is measured).
- Technology contract: docs/TECHNOLOGY.md
- Learned rules: docs/knowledge/LEARNED.md (Session 2026-07-19 —
  CI-authoritative-when-only-CI-reproduces; POSIX/portability discipline for
  test-infra).

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: see template semantics

## Problem (verified against the code)

`tests/skills/test-aai-test-canon.sh::test_006` (lines 445-493, read in full):
after establishing idempotency on an unchanged re-run, it modifies an
archived source (`tests/_archive/skills/test-canon-1.sh`), commits, re-runs
`--phase2`, and asserts:

```
before_mod=$(sha256sum tests/canonical/* 2>/dev/null | head -c 40 || echo "no-canonical")
if run_script --phase2 2>/dev/null; then
  after_mod=$(sha256sum tests/canonical/* 2>/dev/null | head -c 40 || echo "no-canonical")
  if [[ "$before_mod" != "$after_mod" ]]; then
    log_fail "Phase 2 silently overwrote canonical tests despite drift — should report drift"
  fi
fi
```

Confirmed defects, by direct read and reproduction:
1. `head -c 40` truncates the piped `sha256sum` output (`<64-hex-char
   hash>  <filename>\n` per line) to its first 40 bytes — this is not even
   one complete hash (sha256 hex digest is 64 characters), let alone the
   whole multi-file listing. It is glob-order-dependent (only the
   alphabetically-first canonical file's hash is even partially covered) and
   silently ignores every other file.
2. The test infers "the drifted domain was overwritten" from "any canonical
   byte changed anywhere in `tests/canonical/`," conflating the specific
   per-domain contract with a whole-directory proxy. It never consults Phase
   2's own authoritative report line, confirmed present verbatim in
   `.aai/scripts/test-canon.mjs:89`:
   `` `- DRIFT (changed since synthesis, NOT rewritten): ${result.drifted.length} (${result.drifted.join(', ') || '—'})` ``
   — confirmed zero occurrences of the string `DRIFT (changed since
   synthesis, NOT rewritten)` anywhere in `tests/skills/test-aai-test-canon.sh`
   today (`grep -c` = 0): the test never reads this line.
3. `runPhase2` / `hashTestSources` (`.aai/scripts/lib/test-canon-core.mjs`
   lines 509-756, 758-782, read in full) are pure file-read + `sha256`
   hashing with no clock, no timestamp embedded in rendered canonical
   content (`renderCanonicalTest`/`renderStubFile`, lines 321-419, read in
   full — confirmed no `Date`/`Math.random` in either renderer; the only
   `new Date()` calls in the file are in Phase-1's proposal/report writers,
   `docs/ai/test-canon.proposal.json` and the coverage report, never
   `tests/canonical/*`), and no git dependency beyond reading committed
   file bytes. A domain found in the `recorded` vs. re-hashed comparison to
   have drifted is pushed to `result.drifted` and `continue`d (line 548)
   — skipped — before any `fs.writeFileSync` for that domain. This
   confirms the comparator itself is deterministic; the flake is not
   reproduced by static analysis, matching the intake's empirical result
   (0/40 under 8-CPU-hog load on macOS).

NEW finding from this planning pass (direct reproduction in a throwaway
fixture, mirroring `setup_fixture "test-canon" 2 2 "with-canonical"`):
a content-NEUTRAL drift marker (e.g. appending an unrelated comment line to
the archived source) changes the source's `sha256` hash — enough to trigger
drift detection — but does **not** change the rendered
`tests/canonical/test-canon.sh` bytes even when Phase 2 is later re-run
with `--resync` (verified: `--resync` on that marker produced a
byte-identical `test-canon.sh`), because the renderer never embeds source
body text, only file paths, dispatch metadata, and uncovered-criterion stub
tags. A marker that instead **references the domain's own AC tag**
(`AC-<domain>-1`, matching `findCoveredCriteria`'s
`sc.content.includes(criterionTag)` predicate, `test-canon-core.mjs:99-101`)
flips that criterion from uncovered to covered, which DOES change the
rendered `test-canon.sh` bytes under `--resync` (verified: differing
`sha256sum`) while leaving the no-resync (drift-skip) path byte-identical
(also verified). This means a byte-diff check alone is not automatically
discriminating — the DRIFT MARKER used by the fixture matters, and this
spec's discriminating check (Spec-AC-04) depends on using an AC-tag-bearing
marker, not an arbitrary content edit.

## Honesty requirements (binding on this spec and on Validation)

- Do NOT claim the CI flake is "fixed." It does not reproduce locally (0/40
  under load per the intake) and this spec does not change the production
  comparator (`test-canon-core.mjs`) at all — no root cause in Phase 2 is
  claimed or found.
- Frame the acceptance criteria as: (i) ATTRIBUTION — the test asserts on
  Phase 2's own drift report, not an inferred byte-diff; (ii) ISOLATION —
  the drifted domain's own canonical file is checked separately from
  non-drifted domains Phase 2 legitimately rewrites; (iii) COMPLETENESS /
  DIAGNOSABILITY — the whole-layer measurement is order-stable and complete,
  and dumps evidence on mismatch; (iv) NOT WEAKENED — a discriminating
  sub-check proves the isolated assertion would catch a real silent
  overwrite. A local pass is NOT evidence the CI flake is resolved — the
  CI-green AC (Spec-AC-06) is `deferred` with Review-By >= 14 days out
  (2026-08-10), same posture as SPEC-0076 Spec-AC-06.
- If CI recurs post-fix, the new attribution + instrumentation gives a
  diagnosable failure (which file, what diff) instead of a bare "silently
  overwrote" — any such recurrence is a NEW, now-evidenced finding, not
  something this spec claims to have pre-empted.

## Scope
- In scope:
  1. `tests/skills/test-aai-test-canon.sh::test_006` — rewrite the
     post-drift assertion block only (the idempotent-rerun check above it,
     lines 445-471, is unchanged). New behavior:
     - Modify the archived source with an AC-tag-bearing marker (not an
       arbitrary comment) so the discriminating check (below) is meaningful.
     - Snapshot `tests/canonical/` before the drift-triggering re-run.
     - Capture the drift-triggering `--phase2` re-run's STDOUT and assert
       the `DRIFT (changed since synthesis, NOT rewritten)` line names the
       fixture's domain (attribution).
     - Assert the drifted domain's own canonical file
       (`tests/canonical/<domain>.sh`) is byte-identical to the snapshot
       (isolation).
     - Assert a complete, order-stable whole-layer digest
       (`sha256sum tests/canonical/* \| sort \| sha256sum`) is unchanged;
       on any mismatch, dump per-file `diff` output against the snapshot
       before failing (completeness + diagnosability).
     - Discriminating check: run `--phase2 --resync` on the same drifted
       domain and assert (a) the domain's canonical file DOES now differ
       from the pre-drift snapshot, and (b) Phase 2's report reclassifies
       the domain into `Re-synced (drift resolved)` — proving the isolated
       byte-identical assertion above is sensitive, not vacuous.
  2. This spec document.
- Out of scope: `.aai/scripts/test-canon.mjs` and
  `.aai/scripts/lib/test-canon-core.mjs` (the drift comparator/decision
  logic) — not changed; no real race was proven (repro: 0/40 under load,
  and the comparator is pure-hash/no-clock per the Problem section above).
  `test_007` (`--drift`/`--resync` semantics) — not changed, must stay
  green unmodified. Any retry/loop-until-pass wrapper (explicitly
  forbidden — hides the mechanism, and there is no mechanism proven to
  exist locally to retry around). Any other `test_0NN` function in the
  same file.
- Protected paths touched: none (verified directly against
  `docs/ai/docs-audit.yaml:protected_paths_l3` — see Ceremony
  justification above).

## Design — mechanism decision

Per the intake's explicit instruction and the Honesty requirements: change
WHAT is measured (attribution + completeness), not thresholds, and stay
test-only unless a real Phase 2 race is proven. This planning pass did not
find one (Problem section, point 3) — CHOSEN: test-only fix, matching the
intake's preferred direction and the same-family precedent (SPEC-0076).

The four sub-checks map 1:1 to the intake's four numbered design-direction
bullets:
1. Attribution: grep the captured `--phase2` STDOUT for the exact line
   Phase 2 already prints (`test-canon.mjs:89`) rather than inferring intent
   from a hash.
2. Isolation: compare only the drifted domain's own
   `tests/canonical/<domain>.sh` before/after, not the whole directory —
   this stays correct even in a future multi-domain fixture where Phase 2
   legitimately rewrites OTHER (non-drifted) domains' files on the same
   run.
3. Completeness: `sha256sum tests/canonical/* \| sort \| sha256sum` hashes
   every file, sorted (order-stable regardless of glob/locale ordering),
   into one digest — no truncation, no first-file bias. A pre-drift
   directory snapshot (`cp -R tests/canonical <snapshot>`) is taken so a
   mismatch can be diagnosed with a real `diff`, not just "hash changed."
4. Not weakened: the discriminating sub-check (`--phase2 --resync`) proves
   the isolated byte-identical assertion in point 2 is discriminating.
   This directly answers the intake's "DO NOT WEAKEN THE TEST" requirement
   — it demonstrates, empirically and in the same test run, that a genuine
   drifted-domain overwrite (the `--resync` path) WOULD be caught by the
   same mechanism that just passed on the drift-skip path.

### Discriminating fixture (proves the check catches a real overwrite)

Per the intake's mandatory discriminating-row requirement and the Test Plan
quality bar:
- The archived source is modified with a marker referencing the domain's
  own AC tag (`# drift-marker covers AC-<domain>-1`), not an arbitrary
  comment. Verified by direct reproduction (Problem section): this choice
  is necessary — a content-neutral marker triggers drift detection (hash
  changed) but does NOT change the rendered canonical bytes even under
  `--resync` (the renderer never embeds source body text), which would make
  the discriminating check vacuously pass regardless of correctness. The
  AC-tag marker flips stub coverage, which DOES change the rendered bytes
  under `--resync`.
- PRE-CHECK (drift, no resync): Phase 2 reports the domain under `DRIFT
  ... NOT rewritten`; the domain's canonical file is byte-identical to the
  pre-drift snapshot. This is the passing case Spec-AC-01..03 assert.
- DISCRIMINATING STEP (`--resync` on the same drifted domain): Phase 2
  reports the domain under `Re-synced (drift resolved)`; the domain's
  canonical file NOW DIFFERS from the pre-drift snapshot (verified by
  direct reproduction: `test-canon.sh` sha256 changes because the
  previously-uncovered AC-1 stub is dropped from the header/stub list).
  If the byte content had stayed identical here, that would mean the
  isolated-file assertion in Spec-AC-02 could never fail — i.e. it would
  be structurally incapable of catching a real silent overwrite. Asserting
  it DOES differ here is what proves Spec-AC-02 is a real check, not a
  tautology.

This is the row that behaviorally discriminates a correct implementation
(catches the resync-caused byte change, while still passing the normal
drift-skip path) from a broken/vacuous one, independent of whether the
CI-only race ever reproduces.

### Seam analysis (step 6a)

`tests/canonical/*` and `docs/ai/test-canon.map.json` are written only by
`runPhase2`; this scope adds no new writer and no new reader — the only
consumer of the new assertions is `test_006` itself, in its own isolated
`mktemp` fixture directory (`setup_fixture`, confirmed each `test_0NN`
function gets an independent `TEST_DIR` via `mktemp -d`, no shared state
across test functions in the same run). No other feature or screen reads
`tests/canonical/` output as data (it is a test suite, consumed only by
being executed). No cross-feature seam was found; no residual risk to
record.

## Companion obligations check (PLANNING step 3a)

Closed list, two entries, evaluated against this scope's actual file list
(`tests/skills/test-aai-test-canon.sh`, this spec doc, the ISSUE-DRAFT
intake doc, the regenerated work-item brief):

1. Adds bytes to the prompt corpus (`.aai/*.prompt.md`, `.aai/AGENTS.md`)?
   **NO** — no prompt-corpus file is touched. Prompt-diet ledger true-up
   (`tests/skills/lib/prompt-diet-ledger.sh` + TEST-012 checkpoint bump)
   does **NOT** apply.
2. Adds a NEW `.aai/**` file? **NO** — no file under `.aai/` is created;
   the only edited file is under `tests/skills/`. PROFILES.yaml
   classification does **NOT** apply.

OUTCOME: neither companion obligation applies. No prompt-diet ledger
true-up, no PROFILES.yaml classification entry required. (Structurally
pinned by Spec-AC-05 / TEST-005 below.)

## Constitution deviations

None. (Article 2 "Simplicity" governs the test-only, no-core-change
decision; Article 1 "Evidence before claims" governs the Honesty
requirements section above.)

## Acceptance Criteria Mapping

- Maps to: intake "Expected Behavior" + "Verification" sections.
- Spec-AC-01: `test_006` asserts on Phase 2's own drift report — the
  `DRIFT (changed since synthesis, NOT rewritten)` line naming the
  fixture's domain — as the authoritative signal that drift was detected
  for that domain, replacing pure byte-diff inference.
  - Verification: `bash tests/skills/test-aai-test-canon.sh 006`
    (TEST-001).
- Spec-AC-02: `test_006` isolates the DRIFTED domain's own canonical file
  (`tests/canonical/<domain>.sh`) and asserts it is byte-identical to a
  pre-drift snapshot, separated from any other (non-drifted) domain's
  files that Phase 2 legitimately rewrites every run.
  - Verification: `bash tests/skills/test-aai-test-canon.sh 006`
    (TEST-002).
- Spec-AC-03: `test_006` replaces `sha256sum tests/canonical/* \| head -c
  40` with a complete, order-stable whole-layer digest
  (`sha256sum tests/canonical/* \| sort \| sha256sum`), and on any mismatch
  dumps a per-file `diff` against a pre-drift snapshot before failing.
  - Verification: `grep -c "head -c 40" tests/skills/test-aai-test-canon.sh`
    = 0 post-fix; `bash tests/skills/test-aai-test-canon.sh 006` (TEST-003).
- Spec-AC-04: `test_006` proves its own Spec-AC-02 assertion is
  discriminating (not weakened / not vacuous) — running `--phase2
  --resync` on the same drifted domain afterward changes the domain's
  canonical file bytes AND Phase 2 reclassifies it from `DRIFT ... NOT
  rewritten` to `Re-synced (drift resolved)`; the preceding no-resync path
  (Spec-AC-01..03) still passes.
  - Verification: `bash tests/skills/test-aai-test-canon.sh 006`
    (TEST-004).
- Spec-AC-05: Companion obligations check (step 3a) run and recorded;
  neither companion applies to this scope's own file list; `test_007` and
  the rest of the suite stay green, unmodified.
  - Verification: `git diff --name-only` contains exactly one path
    (`tests/skills/test-aai-test-canon.sh`), no prompt-corpus path, no new
    `.aai/**` path (TEST-005); `git diff -- tests/skills/test-aai-test-canon.sh`
    shows zero changed lines outside the `test_006` function body
    (TEST-006); `bash tests/skills/test-aai-test-canon.sh` exits 0,
    19/19 passed (TEST-007).
- Spec-AC-06 (deferred, CI-authoritative): the `skill-suite` CI job is
  green on Ubuntu across repeated runs post-fix, with no recurrence of the
  TEST-006 flake — CI is the sole authoritative environment for this
  CI-only, load-dependent flake (does not reproduce locally); a local pass
  is NOT sufficient evidence (Honesty requirements section).
  - Verification: `gh run list --workflow skill-suite.yml --branch
    fix/test-canon-drift-detection` / `gh run view <id>`, repeated
    (TEST-008).

## Acceptance Criteria Status

| Spec-AC    | Description                                                         | Status    | Evidence | Review-By  | Notes |
|------------|----------------------------------------------------------------------|-----------|----------|------------|-------|
| Spec-AC-01 | test_006 asserts on Phase 2's own DRIFT report line (attribution)     | done      | docs/ai/tdd/green-20260724T154813Z-test006-attribution-isolation.log | — | GREEN: `bash tests/skills/test-aai-test-canon.sh 006` exit 0 — asserts `DRIFT (changed since synthesis, NOT rewritten): [1-9]… (test-canon)` from captured `--phase2` STDOUT. RED-by-absence confirmed pre-fix (grep=0). |
| Spec-AC-02 | test_006 isolates the drifted domain's own canonical file (isolation) | done      | docs/ai/tdd/green-20260724T154813Z-test006-attribution-isolation.log | — | GREEN: `cmp -s tests/canonical/test-canon.sh` vs pre-drift snapshot = identical on no-resync. Non-vacuity proven by mutation test (simulated silent overwrite => FAIL, exit 1). |
| Spec-AC-03 | Complete, order-stable digest replaces `head -c 40`; dumps diff on mismatch | done | docs/ai/tdd/green-20260724T154813Z-test006-attribution-isolation.log | — | GREEN: `grep -c "head -c 40"` = 0 post-fix; a complete sorted per-file `sha256sum` digest replaces the truncating proxy, with a per-file `diff` dump on mismatch. RED-by-presence (2) confirmed pre-fix. |
| Spec-AC-04 | Discriminating check proves Spec-AC-02 is not vacuous (resync catches overwrite) | done | docs/ai/tdd/green-20260724T154813Z-test006-attribution-isolation.log | — | GREEN: `--phase2 --resync` on the AC-tag-marked drifted domain => canonical bytes DIFFER from snapshot AND report flips to `Re-synced (drift resolved): 1 (test-canon)`. RED-by-absence confirmed pre-fix (grep=0). |
| Spec-AC-05 | Companion obligations recorded; test_007 + suite stay green, scope stays single-file | done | git diff main...HEAD --name-only = tests/skills/test-aai-test-canon.sh (+ docs) | — | Post-fix full-file run: 19/19 passed, exit 0; test_007 unmodified + green standalone. Baseline (pre-fix) also 19/19. Neither companion applies. |
| Spec-AC-06 | CI skill-suite green on Ubuntu across repeated runs post-fix           | deferred  | —        | 2026-08-10 | CI-authoritative for this CI-only flake; local pass is not sufficient evidence (Honesty requirements). Owned by Validation after push. |

## Implementation plan
- Components/modules affected: `tests/skills/test-aai-test-canon.sh`
  (`test_006` function body, lines 445-493, only the post-idempotency block
  from the archived-source modification onward; the idempotent-rerun
  check above it, lines 445-471, is untouched).
- Data flows: none (test-infra only; no production code, no runtime
  state).
- Edge cases:
  - The `sha256sum tests/canonical/*` glob must still degrade gracefully
    if `tests/canonical/` is ever empty/absent (preserve the existing
    `2>/dev/null` / `|| echo ...` fallback idiom used by the current code,
    applied to both the snapshot step and the digest recomputation).
  - The AC-tag drift marker must reference the SAME domain the fixture
    uses (`test-canon`, the `setup_fixture` first argument), not a
    hardcoded literal, so the fixture stays self-consistent if the domain
    name is ever changed.
  - The whole-layer digest and the isolated-file check must both run
    against the SAME pre-drift snapshot, taken once, before the
    drift-triggering `--phase2` call — not two independent `sha256sum`
    calls that could observe different states under CI load (this is the
    same "capture once, compare against the capture" discipline the
    intake's design direction implies by asking for a snapshot-based
    diff on mismatch).
  - `run_script --phase2` after modifying the archived source must still
    be captured (STDOUT+STDERR) even though its exit code is 0 with drift
    present (confirmed by direct reproduction: `phase2` never calls
    `process.exit` on drift, only `--drift` mode does) — do not treat
    reaching the report-line grep as conditional on exit code the way the
    pre-fix `if run_script --phase2 ...; then` gate did.

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected)                          | Description | Status |
|----------|------------|------|------------------------------------------------|--------------|--------|
| TEST-001 | Spec-AC-01 | int  | tests/skills/test-aai-test-canon.sh (test_006) | Attribution: after modifying the archived source and re-running `--phase2` (no resync), the captured STDOUT contains a line matching `DRIFT (changed since synthesis, NOT rewritten): [1-9][0-9]* (...test-canon...)`. Cmd: `bash tests/skills/test-aai-test-canon.sh 006`. Pre-fix value: the current test_006 never inspects Phase 2's STDOUT at all (`run_script --phase2 2>/dev/null` discards it) — `grep -c "DRIFT (changed since synthesis, NOT rewritten)" tests/skills/test-aai-test-canon.sh` = 0 (RED by absence, confirmed today). Post-fix value: the grep count is >=1 and the behavioral assertion passes against a real `--phase2` run. | green |
| TEST-002 | Spec-AC-02 | int  | tests/skills/test-aai-test-canon.sh (test_006) | Isolation: `tests/canonical/test-canon.sh` (the drifted domain's own canonical file) is byte-identical (via `cmp`/`diff`) to its pre-drift snapshot after the no-resync `--phase2` re-run. Cmd: `bash tests/skills/test-aai-test-canon.sh 006`. Pre-fix value: no per-domain isolated comparison exists in the file today (only the whole-glob `head -c 40` proxy at lines 483/486) — structurally RED by absence. Post-fix value: `cmp -s` reports identical, assertion passes. | green |
| TEST-003 | Spec-AC-03 | int  | tests/skills/test-aai-test-canon.sh (test_006) | Completeness/diagnosability: `sha256sum tests/canonical/* \| head -c 40` no longer appears in the file; a complete, order-stable digest (`sha256sum tests/canonical/* \| sort \| sha256sum`) is computed before and after, and on any mismatch a per-file diff against the pre-drift snapshot is printed before `log_fail`. Cmd: `grep -c "head -c 40" tests/skills/test-aai-test-canon.sh` expect `0`; `bash tests/skills/test-aai-test-canon.sh 006`. Pre-fix value: `grep -c "head -c 40"` = 2 today (both `before_mod` and `after_mod` lines) — RED by presence (must reach 0). Post-fix value: `0`; digest-based assertion passes on the normal (no-drift-rewrite) path. | green |
| TEST-004 | Spec-AC-04 | int  | tests/skills/test-aai-test-canon.sh (test_006) | THE DISCRIMINATING ROW. After the no-resync checks (TEST-001..003) pass, run `--phase2 --resync` on the same drifted domain (marker: `# drift-marker covers AC-test-canon-1`, appended to `tests/_archive/skills/test-canon-1.sh`) and assert BOTH (a) `tests/canonical/test-canon.sh` now DIFFERS from the pre-drift snapshot, and (b) the captured STDOUT contains `Re-synced (drift resolved): [1-9][0-9]* (...test-canon...)`. Cmd: `bash tests/skills/test-aai-test-canon.sh 006`. Pre-fix value: no `--resync` step exists in test_006 today — `grep -c "Re-synced (drift resolved)" tests/skills/test-aai-test-canon.sh` = 0 (RED by absence); additionally, direct reproduction during planning showed that a content-NEUTRAL marker (not this fixture's AC-tag marker) produces byte-IDENTICAL `test-canon.sh` even under `--resync`, which would make a naive discriminating check vacuously fail to discriminate — the AC-tag marker is required and is what this row exercises. Post-fix value: `test-canon.sh` differs from the snapshot AND the `Re-synced` line is present — both must hold for the row to pass. | green |
| TEST-005 | Spec-AC-05 | int  | (scope diff, not a test file)                  | Scope-conformance guard: the diff touches exactly one file, `tests/skills/test-aai-test-canon.sh`, no prompt-corpus path, no new `.aai/**` path. Cmd: `git diff --name-only <base>...HEAD`. Pre-fix value: N/A at plan time (no diff exists yet) — fails FAST if implementation strays into a companion-trigger path or a second file. Post-fix value: exactly `tests/skills/test-aai-test-canon.sh`. | green |
| TEST-006 | Spec-AC-05 | int  | tests/skills/test-aai-test-canon.sh (diff, not runtime) | Regression pin: only `test_006`'s body changes — `test_007` and every other `test_0NN` function stay byte-unchanged. Cmd: `git diff <base>...HEAD -- tests/skills/test-aai-test-canon.sh` inspected for the changed line range; `bash tests/skills/test-aai-test-canon.sh 007` run standalone. Pre-fix value: N/A at plan time — scope-conformance guard, fails fast if the diff touches `test_007` or another function. Post-fix value: `test_007` unmodified and green. | green |
| TEST-007 | Spec-AC-05 | int  | tests/skills/test-aai-test-canon.sh (full suite) | Full-suite regression pin. Cmd: `bash tests/skills/test-aai-test-canon.sh`. Pre-fix (baseline, recorded this planning pass): `19/19 passed, 0 failed`, exit 0. Post-fix value: still `19/19 passed, 0 failed`, exit 0 (test_006 rewritten but still passing, nothing else regressed). | green |
| TEST-008 | Spec-AC-06 | e2e  | .github/workflows/skill-suite.yml (CI)         | AUTHORITATIVE evidence: `skill-suite` job green on Ubuntu across a REPEATED run (>=2 consecutive runs on the branch, or one run re-run at least once), with no recurrence of the TEST-006 mis-measurement failure. Cmd: `gh run list --workflow skill-suite.yml --branch fix/test-canon-drift-detection` + `gh run view <id>` (repeat). Pre-fix value: the intermittent `"Phase 2 silently overwrote canonical tests despite drift — should report drift"` failure observed on PR #137 (a branch-guard-only diff, per the intake). Post-fix value: no recurrence across repeated CI runs — this row is the sole authoritative evidence; TEST-001..007 are explicitly NOT substitutable for it (Honesty requirements). | pending (CI — owned by Validation after push) |

Notes:
- Every Spec-AC has >=1 TEST-xxx. Test IDs are stable post-freeze.
- RED-proof obligation: TEST-001/002/004 RED-proof by absence (the
  respective grep patterns return 0 matches in the current, unedited file
  — directly reproducible today). TEST-003 RED-proofs by presence (`head -c
  40` currently occurs 2 times and must reach 0). TEST-004 additionally
  carries an empirical RED-proof from direct reproduction during this
  planning pass (see Problem/Design sections): a content-neutral marker
  does not discriminate; the AC-tag marker does — this was verified by
  actually running Phase 2 with and without `--resync` against both marker
  styles in a throwaway fixture before writing the implementation. TEST-005/
  006/007 are regression/scope-conformance guards with no independently
  discriminating pre/post state of their own — TEST-007's baseline
  (19/19 passed) is recorded now so a post-fix re-run has a concrete
  number to match, not just "still green."
- CI (Ubuntu, under load) is the authoritative environment for the CI-only
  flake this scope addresses; a green local run (TEST-001..007) is
  necessary but never sufficient to claim the flake is de-flaked, and must
  not be reported as standalone evidence for Spec-AC-06.

## Verification
- Commands: the eight rows above (TEST-001..008).
- Evidence artifacts: RED/GREEN grep + assertion output for TEST-001..004;
  `git diff --name-only` / `--name-status` output for TEST-005; diff-range
  inspection + standalone `test_007` run output for TEST-006; full-suite
  run output (`19/19 passed, 0 failed` baseline, then post-fix re-run) for
  TEST-007; `gh run` output/URLs for TEST-008.
- PASS criteria (local, non-CI rows): TEST-001..007 green AND all Spec-AC
  except Spec-AC-06 in status `done`. Spec-AC-06 stays `deferred` with
  Review-By 2026-08-10 until TEST-008's repeated-CI-green evidence
  arrives — per the Honesty requirements, this deferral is NOT itself a
  blocker for reporting the local fix, but a merge/PR-ready claim must not
  assert the CI flake is resolved until Spec-AC-06 is flipped to `done`
  with real CI evidence.

## Evidence contract
For each implementation / validation / TDD / code-review artifact record:
- ref_id: test-canon-drift-detection
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path
- commit SHA or diff range when available

## Implementation strategy
- Strategy: tdd
- Rationale: the entire scope is one function (`test_006`) in one file,
  and its central purpose IS the discriminating RED/GREEN proof the intake
  mandates (Spec-AC-04 — the check must be shown to actually catch a
  drifted-domain overwrite, not just added). RED-GREEN-REFACTOR per
  TEST-xxx is directly observable and cheap here: every one of TEST-001..
  004 has a concrete, already-confirmed RED state (grep counts / absent
  patterns, verified above) to observe before editing, and a single
  cohesive edit produces GREEN across all four. A `loop`/`hybrid` split
  would be artificial for a single-function, single-file change where the
  "mechanical" pieces (digest replacement, snapshot) and the "risky" piece
  (the discriminating resync check) are not separable into independent
  commits without breaking the function's internal ordering (snapshot must
  precede both the no-resync and resync checks). TDD for the whole scope
  keeps the RED-proof discipline uniform and matches the bug-fix /
  regression-proof criterion from `.aai/PLANNING.prompt.md` step 7.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: one non-protected test file, small, reversible,
  single-function change; already on its own dedicated branch
  `fix/test-canon-drift-detection` off `main` per the one-branch-per-
  work-item convention.
- User decision: undecided (Implementation Preparation gate; `not_needed`
  does not require a user decision before proceeding, per
  `.aai/AGENTS.md` worktree policy).
- Base ref: main
- Worktree branch/path: n/a (inline)
- Inline review scope: `tests/skills/test-aai-test-canon.sh`

Allowed worktree recommendation values:
- not_needed: small, low-risk, clearly scoped change
- optional: useful but not important for safety
- recommended: larger, experimental, PR-bound, or parallelizable work
- required: protected workflow/state/schema, migration, or high-risk work; user may still explicitly override inline

Allowed user decision values:
- undecided: no implementation may start when recommendation is recommended or required
- worktree: create/use a git worktree before implementation
- inline: continue in the current working tree with a clean explicit review scope
- waived: user explicitly accepts the risk of ambiguous isolation or review scope

## Code review
- Required: true (test-infra behavioral change).
- Scope: `tests/skills/test-aai-test-canon.sh` only (inline diff scope, no
  worktree/PR base-ref yet). `.aai/scripts/test-canon.mjs` and
  `.aai/scripts/lib/test-canon-core.mjs` are explicitly OUT of scope — no
  real Phase 2 race was proven during this planning pass (Problem section,
  point 3), so the comparator is not touched and is not part of the review
  scope.

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
Use plain Markdown headings and body text. Do not add emoji or decorative
icons unless there is a strong domain-specific reason.
