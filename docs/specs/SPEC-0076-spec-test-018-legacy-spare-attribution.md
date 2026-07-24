---
id: spec-test-018-legacy-spare-attribution
type: spec
number: 76
status: done
ceremony_level: 1
links:
  requirement: docs/issues/ISSUE-0030-test-018-legacy-spare-attribution.md
  rfc: null
  pr:
    - 139
  commits:
    - 8c8c2ea04e988fa9eb096d9fc689df78c3c1d6e6
---

# Implementation Spec — TEST-018 spare-fresh attribution + reaper observability

SPEC-FROZEN: true

Ceremony justification: the scope touches exactly two files —
`.aai/scripts/aai-reap-tests.sh` (one additive diagnostic print, no change to
existing lines) and `tests/skills/test-aai-run-tests.sh` (one test function's
assertion rewritten from a liveness proxy to an attribution check, plus an
evidence dump on the same function) — a script and its own test. Neither path
is in `protected_paths_l3` (docs/ai/docs-audit.yaml):
`.aai/scripts/state.mjs`, `.aai/scripts/lib/state-engine.mjs`,
`.aai/scripts/lib/state-core.mjs`, `.aai/scripts/allocate-doc-number.mjs`,
`.aai/scripts/pre-commit-checks.sh`, `.aai/scripts/pre-commit-checks.ps1`,
`.aai/workflow/WORKFLOW.md`, `docs/CONSTITUTION.md` — confirmed by direct
read of that file. Single reviewable, additive, reversible, single-surface
change -> Level 1.

## Links
- Requirement: docs/issues/ISSUE-0030-test-018-legacy-spare-attribution.md
- Prior art: docs/specs/SPEC-0064-spec-reaper-deterministic-age-guard.md (the
  epoch/legacy contract this test asserts against), SPEC-0069-spec-test-018-workspace-isolation.md
  (PR #123, per-case workspace isolation — the SECOND correction to this same
  test), SPEC-0072-spec-reaper-epoch-survivor-robustness.md (PR #128/#131,
  split-direction margins for TEST-017/006/013/015 — the anti-pattern this
  scope explicitly must NOT repeat: margins/isolation treated symptoms, not
  the mis-attribution mechanism).
- Technology contract: docs/TECHNOLOGY.md
- Learned rules: docs/knowledge/LEARNED.md (Session 2026-07-19 — reaper runs
  under sh/dash, POSIX-safe only; CI-authoritative-when-only-CI-reproduces).

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: see template semantics

## Problem (verified against the code)

`.aai/scripts/aai-reap-tests.sh` (read in full during this planning pass)
prints exactly one summary line, `reaped: N`, and never the pids it matched
and killed — confirmed: the only `echo` of reap results is `echo "reaped:
$REAPED"` at the end of the script; `MATCH_PIDS` (the space list of matched
top-level pids, accumulated in the match loop) is used internally for the
kill/subtree walk but never printed.

`tests/skills/test-aai-run-tests.sh::test_018` (lines 603-658), spare-fresh
direction (lines 644-651): spawns `fresh_pid`, runs the reaper in LEGACY mode
with `AAI_REAP_MIN_AGE_SECS=60` against a ~0s-old process, then asserts:

```sh
if ! alive "$fresh_pid"; then
  log_fail "fail-safe broken (case='$invalid'): legacy MIN_AGE=60 must still
    spare the fresh match (reaper output: $out)"
fi
```

This concludes "the reaper reaped the fresh proc" purely from `fresh_pid`
being dead. Verified against the reaper's own legacy-mode guard (age check
`[ "$age" -ge "$MIN_AGE" ]` against `etime_to_secs`, LEGACY MODE branch): for
this fixture, `old_pid` was already reaped in Direction 1 and `fresh_pid` is
~0s old at the moment of the `ps` snapshot, so `age >= 60` cannot legitimately
hold for either workspace process — `reaped: 1` under this fixture is not
derivable from the local guard model. The empirical repro cited in the intake
(180 iterations of the exact sequence under 8-CPU-hog load on macOS, 0/180
failures) corroborates that the mechanism is not reproducible in the local
model; the failure is CI-Linux-only. The test therefore measures a PROXY
(`fresh_pid` liveness) instead of the property it claims (the reaper itself,
in legacy mode, did not reap the young proc) — any external cause of
`fresh_pid`'s death (a Linux `ps etime` read race inside the reaper's own
snapshot, an unrelated runner process the reaper's workspace-substring match
happens to catch, or genuinely external interference) is mis-attributed to a
reaper spare-failure.

CONCLUSION (per the intake, verified by direct read of both files): the root
cause of the CI-only `reaped: 1` observation is NOT proven and is explicitly
NOT claimed to be proven by this spec (see Honesty section below). What IS
provably wrong, independent of the root cause, is the test's attribution
method — it cannot currently distinguish "the reaper reaped `fresh_pid`" from
"`fresh_pid` died for any other reason at any point during the reap window."
This spec fixes the attribution defect and adds the observability needed to
finally see the mechanism if CI reproduces it again.

## Honesty requirements (binding on this spec and on Validation)

- Do NOT claim the flake is "fixed." The mechanism is not reproduced locally
  (0/180) and is not proven by static analysis of either file alone.
- Frame the acceptance criteria as: (i) ATTRIBUTION — the test no longer
  fails on a fresh-proc death it cannot attribute to the reaper; (ii)
  INSTRUMENTATION — a recurrence in CI now captures the `ps` evidence needed
  to root-cause it; (iii) CI-AUTHORITATIVE — a local pass is NOT flake-fix
  evidence for this CI-Linux-only flake (same posture as
  SPEC-0072 Spec-AC-05), so the CI-repeated-run AC (Spec-AC-06) is `deferred`
  with Review-By >= 14 days out.
- If CI later shows the reaper's OWN reported reaped-pids list genuinely
  contains `fresh_pid` (i.e., the reaper itself, not an external cause,
  reaped it), that is a NEW, now-evidenced finding for a follow-up on the
  reaper's legacy age guard — explicitly NOT silently margin-patched inside
  this scope (constraint carried verbatim from the intake).

## Scope
- In scope:
  1. `.aai/scripts/aai-reap-tests.sh` — ONE additive diagnostic line, `reaped
     pids: <space-separated pid list>` (empty tail when nothing matched),
     printed immediately after the existing, byte-unchanged `reaped: N`
     line. Sourced from the SAME `MATCH_PIDS` accumulator the existing
     count/kill logic already uses (see Design below) — no new match
     computation, no change to any guard (workspace scope, vitest/esbuild
     token, legacy/epoch age decision). POSIX `sh`/`dash`-safe: no bashisms,
     no arrays, no `[[ ]]`.
  2. `tests/skills/test-aai-run-tests.sh::test_018` spare-fresh direction —
     rewrite the assertion from a liveness proxy (`! alive "$fresh_pid"`) to
     an attribution check (`fresh_pid` not present in the reaper's reported
     reaped-pids list), and add an evidence dump (workspace-scoped `ps`
     snapshot + each reported pid's parsed etime) that fires only when the
     reaper reports `reaped > 0` on this direction, so a recurrence captures
     the data needed to see the mechanism.
  3. This spec document.
- Out of scope: any change to the reaper's match/age/kill DECISION logic
  (workspace guard, vitest/esbuild token guard, epoch-vs-legacy branch, age
  threshold arithmetic); the split-direction margins already in place
  (`MIN_AGE=1` / `MIN_AGE=60`, `sleep 3`) — NOT widened, per the intake's
  explicit anti-pattern warning; any retry/loop-until-pass wrapper around the
  assertion (explicitly forbidden — hides the mechanism); `.aai/scripts/aai-reap-tests.ps1`
  (Windows twin — untouched, no related flake reported, not read by
  `test_018`); TEST-006/013/015/016/017/019/020/021 (unrelated directions,
  already deterministic per SPEC-0064/SPEC-0072 — this scope must not
  perturb their pass/fail); any `protected_paths_l3` file.
- Protected paths touched: none (verified against
  `docs/ai/docs-audit.yaml:protected_paths_l3` directly).

## Design — mechanism decision

Two levers were available: (a) widen `MIN_AGE=60` / the ~0s fresh-proc gap
further, chasing a bigger margin; (b) change WHAT the test measures, from a
liveness proxy to reaper-reported attribution, plus capture evidence for the
CI-only mechanism.

CHOSEN: **(b) only.** (a) is explicitly the anti-pattern of the two prior
fixes (SPEC-0069 / PR #123 workspace isolation, SPEC-0072-adjacent PR #128
margin widening) — both reduced but did not eliminate the recurrence, because
neither changed what the assertion actually proves. Widening `MIN_AGE=60`
again would be the THIRD margin patch on the same unproven mechanism.

Reaper-side change (additive only): the match loop already accumulates
`MATCH_PIDS="$MATCH_PIDS $pid"` for every top-level pid that clears all three
guards (token, workspace, age) — this is the exact same variable the existing
`REAPED` counter is derived from (one increment per loop iteration over
`MATCH_PIDS`). Printing `MATCH_PIDS` (trimmed of its leading separator) as a
new `reaped pids: ...` line therefore reports precisely the set the existing
`reaped: N` line already counts — no new decision surface, no new guard,
purely a report of an already-computed value. This is why the decision logic
stays provably byte-identical (Spec-AC-02 / TEST-005 below) rather than
merely "probably unaffected."

Test-side change: `test_018`'s spare-fresh block calls the reaper once and
captures `out`. Instead of concluding from `fresh_pid`'s liveness, the
assertion parses the `reaped pids:` line from `out` and checks `fresh_pid` is
NOT a token in it. This is immune to `fresh_pid` dying for a reason the
reaper's own report does not claim responsibility for. The evidence dump
(triggered only when the reaper's `reaped: N` on this direction is `> 0`,
which is itself already-failing/suspicious under the current fixture model)
prints a `ps` snapshot filtered to the case workspace plus the parsed etime
of each reported pid — giving the next CI recurrence enough data to
distinguish "reaper genuinely reaped fresh_pid via a misread etime" from
"reaper reaped 0 and something else killed fresh_pid."

### Discriminating fixture (proves the attribution fix, not just its existence)

Per the intake's verification section and the Test Plan quality bar: inject
an EXTERNAL kill of `fresh_pid` immediately before the assertion, while the
reaper itself reaps 0 in the workspace (verified via its own `reaped pids:`
line being empty). This reproduces exactly the mis-attribution mechanism
(some cause outside the reaper's own decision kills `fresh_pid`) without
depending on the unreproduced CI race:
- PRE-FIX: `if ! alive "$fresh_pid"` sees `fresh_pid` dead (killed
  externally) and FAILS with "fail-safe broken ... reaper output: reaped:
  0" — a demonstrable mis-attribution, since the reaper's own count says it
  reaped nothing.
- POST-FIX: the attribution assertion checks the reaper's `reaped pids:`
  line, which is empty (the reaper genuinely reaped 0), so `fresh_pid` is
  correctly judged NOT reaped by the reaper — the test PASSES despite
  `fresh_pid` being dead.

This is the row that behaviorally discriminates old code from new code (RED
before the fix, GREEN after), independent of whether the CI-Linux race ever
reproduces during this work.

### Seam analysis (step 6a)

The reaper's stdout is consumed by: (1) `test_018` and the sibling TEST-006/
013/015/016/017/021 (all via `grep -qiE "reaped: *[1-9]"` or
`grep -qxE "reaped: *0"` on the WHOLE captured output, not a fixed line
count) — verified these are per-line pattern matches, so an ADDITIONAL line
appended after `reaped: N` does not change what they match; (2)
`.aai/scripts/aai-run-tests.sh`, which invokes the reaper as a
defence-in-depth sweep but does not parse its stdout at all (verified: no
`grep`/`reaped` reference in that script beyond comments) — no seam risk
there. No other caller was found (`grep -rl aai-reap-tests.sh` over
non-test/non-doc paths returns only `aai-run-tests.sh` and the reaper
itself). This is confirmed, not assumed — see TEST-004 below, which re-runs
the existing consumers unmodified against the new reaper output.

## Companion obligations check (PLANNING step 3a)

Closed list, two entries, evaluated against this scope's actual file list
(`.aai/scripts/aai-reap-tests.sh`, `tests/skills/test-aai-run-tests.sh`, this
spec doc, the ISSUE-DRAFT intake doc):

1. Adds bytes to the prompt corpus (`.aai/*.prompt.md`, `.aai/AGENTS.md`)?
   **NO** — no prompt-corpus file is touched. Prompt-diet ledger true-up
   (`tests/skills/lib/prompt-diet-ledger.sh` + TEST-012 checkpoint bump) does
   **NOT** apply.
2. Adds a NEW `.aai/**` file? **NO** — `.aai/scripts/aai-reap-tests.sh`
   already exists and is edited in place; no new file is created under
   `.aai/`. PROFILES.yaml classification does **NOT** apply.

OUTCOME: neither companion obligation applies. No prompt-diet ledger
true-up, no PROFILES.yaml classification entry required. (Structurally
pinned by Spec-AC-05 / TEST-008 below.)

## Constitution deviations

None. (Article 5 "Additive first" is the design's own governing principle —
the reaper edit is a pure addition with zero removed/modified lines,
mechanically checked by TEST-005; Article 1 "Evidence before claims" governs
the Honesty requirements section above.)

## Acceptance Criteria Mapping

- Maps to: intake "Expected Behavior" + "Verification" sections.
- Spec-AC-01: `.aai/scripts/aai-reap-tests.sh` prints an ADDITIVE `reaped
  pids: <space-list>` line immediately after the existing, byte-unchanged
  `reaped: N` line — empty tail when nothing matched, exactly N
  space-separated pid tokens when N matched (derived from the same
  `MATCH_PIDS` accumulator the count already uses). POSIX-safe (sh/dash), no
  bashisms.
  - Verification: `bash tests/skills/test-aai-run-tests.sh 018` (new
    structural sub-assertions) + direct reaper invocation against controlled
    fixtures (TEST-001/002/003).
- Spec-AC-02: The reaper's match/age/kill DECISION logic is unchanged —
  proven both by a purely-additive diff (zero removed/modified lines in
  `.aai/scripts/aai-reap-tests.sh`) and by TEST-006/013/015/016/017 (the
  deterministic epoch/legacy tests) remaining green, unmodified.
  - Verification: `git diff <base>...HEAD -- .aai/scripts/aai-reap-tests.sh`
    contains zero `^-` (removal) lines (TEST-005); `bash
    tests/skills/test-aai-run-tests.sh 006 013 015 016 017` exits 0
    (TEST-004).
- Spec-AC-03: `test_018`'s spare-fresh assertion is ATTRIBUTABLE — it fails
  only when `fresh_pid` appears in the reaper's OWN reported reaped-pids
  list, never merely because `fresh_pid` is dead. Proven via the
  discriminating external-kill fixture: pre-fix the fixture FAILS
  (mis-attribution), post-fix it PASSES.
  - Verification: `bash tests/skills/test-aai-run-tests.sh 018` with the
    injected external-kill fixture (TEST-006).
- Spec-AC-04: On any `reaped > 0` observed by the spare-fresh direction, the
  test captures diagnostic evidence — the workspace-scoped `ps` snapshot plus
  each reported pid's parsed etime — to test output, so a Linux `ps etime`
  read race is captured with evidence if it recurs in CI.
  - Verification: stub-reaper-driven RED-proof + real invocation (TEST-007).
- Spec-AC-05: Companion obligations check (step 3a) run and recorded; neither
  companion applies to this scope's own file list.
  - Verification: `git diff --name-only` / `--name-status` contain no
    prompt-corpus path and no newly-added `.aai/**` path (TEST-008).
- Spec-AC-06 (deferred, CI-authoritative): the `skill-suite` CI job is green
  on Ubuntu across repeated runs post-fix, specifically watching for a
  recurrence of the spare-fresh case now being correctly attributed (not
  false-failing) — CI is the sole authoritative environment for this
  CI-Linux-only, load-dependent flake; a local pass alone is NOT sufficient
  evidence (same posture as SPEC-0072 Spec-AC-05).
  - Verification: `gh run list --workflow skill-suite.yml --branch
    fix/test-018-legacy-spare-attribution` / `gh run view <id>`, repeated
    (TEST-009).

## Acceptance Criteria Status

| Spec-AC    | Description                                                          | Status    | Evidence | Review-By  | Notes |
|------------|-----------------------------------------------------------------------|-----------|----------|------------|-------|
| Spec-AC-01 | Reaper prints additive `reaped pids: ...` line (empty/N-token correct) | done      | docs/ai/tdd/red-20260724T135656Z-test018-attribution.log; docs/ai/tdd/green-20260724T135656Z-test018-attribution.log (TEST-001/002/003 green) | — | Sourced from the existing `MATCH_PIDS` accumulator; no new match computation. `reaped pids: <p1> <p2>` for N matched, empty tail for 0; identical under dash. |
| Spec-AC-02 | Reaper match/age/kill decision logic unchanged (purely additive diff + regression pin) | done | git diff reaper: 0 removed/modified lines (TEST-005); pre/post reaper DECISION identical on same fixture; 006/013/015/016/017 green (TEST-004) | — | Purely additive diff; empirical pre-vs-post decision proof: old1=REAPED old2=REAPED other=SPARED both runs. |
| Spec-AC-03 | test_018 spare-fresh assertion is attribution-based, not a liveness proxy | done | docs/ai/tdd/red-20260724T135656Z-test018-discriminating.log (PRE-FIX FAIL); green-20260724T135656Z-test018-attribution.log (POST-FIX PASS) | — | Discriminating external-kill fixture: RED (mis-attribution, reaper output `reaped: 0`) -> GREEN (attribution, fresh_pid not in reaped-pids). |
| Spec-AC-04 | Evidence dump (ps snapshot + parsed etime) on any reaped>0 in spare-fresh | done | green-20260724T135656Z-test018-attribution.log (dump FIRES under stub reaped>0; ABSENT on normal path) | — | Fires only on the suspicious/failing path; silent otherwise. |
| Spec-AC-05 | Companion obligations check recorded; neither obligation applies       | done      | git status: only `.aai/scripts/aai-reap-tests.sh` + `tests/skills/test-aai-run-tests.sh` modified; no prompt-corpus path, no new `.aai/**` file (TEST-008) | — | No prompt-diet ledger true-up; no PROFILES.yaml entry. |
| Spec-AC-06 | CI skill-suite green on Ubuntu across repeated runs post-fix           | deferred  | —        | 2026-08-10 | CI-authoritative for this CI-Linux-only flake; local pass is not sufficient evidence (Honesty requirements section). Owned by Validation after push. |

## Implementation plan
- Components/modules affected: `.aai/scripts/aai-reap-tests.sh` (one new
  `echo` line, no other line touched); `tests/skills/test-aai-run-tests.sh`
  (`test_018` spare-fresh block rewritten + a small helper to parse the
  `reaped pids:` line and dump `ps`/etime evidence — reusing existing
  helpers `spawn_marked`/`alive`/`track` where possible).
- Data flows: none (no product code, no runtime state; test-infra + a
  diagnostic print only).
- Edge cases:
  - Zero matched pids: `reaped pids:` line must still appear with an empty
    tail (not omitted) so the test's parser has a stable line to match
    against every invocation.
  - Pid list with a single matched pid vs. multiple (Direction 1 of the SAME
    test case reaps `old_pid` earlier in the loop — the spare-fresh
    invocation's OWN reaper call must report an independent count for that
    invocation only, not cumulative across the two `reap_run` calls in one
    `for invalid in ...` iteration).
  - The evidence dump must not fire (no extra noise) on the normal
    `reaped: 0` path — only when `reaped > 0` is observed on the spare-fresh
    direction, per Spec-AC-04.

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected)                          | Description | Status |
|----------|------------|------|------------------------------------------------|--------------|--------|
| TEST-001 | Spec-AC-01 | int  | .aai/scripts/aai-reap-tests.sh                 | Structural/behavioral: direct reaper invocation against a fixture with 2 matched old procs (legacy MIN_AGE=1, workspace-scoped) reports `reaped: 2` AND a `reaped pids:` line containing exactly 2 numeric tokens matching the spawned pids. Cmd: run `sh .aai/scripts/aai-reap-tests.sh` against the fixture, grep the output for `^reaped pids:` and count tokens. Pre-fix value: NO `reaped pids:` line exists in the output at all — grep for `^reaped pids:` returns 0 matches (RED, the line does not exist today). Post-fix value: line present with exactly 2 tokens. | green |
| TEST-002 | Spec-AC-01 | int  | .aai/scripts/aai-reap-tests.sh                 | Zero-match case: fixture with only a fresh (~0s) proc, legacy MIN_AGE=60 (nothing eligible). Reaper reports `reaped: 0` (unchanged) AND `reaped pids:` with an empty tail (0 tokens). Cmd: same invocation pattern as TEST-001 against the zero-match fixture. Pre-fix value: `reaped pids:` line absent — grep returns 0 matches (RED). Post-fix value: line present, 0 tokens. | green |
| TEST-003 | Spec-AC-01 | int  | .aai/scripts/aai-reap-tests.sh                 | Portability: the new print uses only POSIX `sh`/`dash`-safe constructs (no bashisms, no arrays, no `[[ ]]`) — run the same fixture as TEST-001 explicitly under `dash` (mirrors the existing TEST-013 dash-portability idiom in this suite) and confirm identical `reaped pids:` output. Cmd: `dash .aai/scripts/aai-reap-tests.sh` (or `sh` pointed at dash) against the TEST-001 fixture. Pre-fix value: N/A — line does not exist (RED by absence). Post-fix value: identical 2-token output under dash. | green |
| TEST-004 | Spec-AC-02 | int  | tests/skills/test-aai-run-tests.sh             | Regression pin: the deterministic epoch/legacy reaper tests are unaffected by the additive change. Cmd: `bash tests/skills/test-aai-run-tests.sh 006 013 015 016 017`. Pre-fix value: baseline — all five already pass on the unmodified reaper. Post-fix value: all five still pass, unmodified, against the edited reaper (discriminates any accidental behavior change introduced alongside the diagnostic). | green |
| TEST-005 | Spec-AC-02 | int  | .aai/scripts/aai-reap-tests.sh (diff, not runtime) | Byte/behaviour pin: the reaper diff contains ZERO removed or modified lines — a purely additive diff proves the existing match/age/kill decision bytes are untouched (a modification shows as remove+add in `git diff`, so "no removals" is sufficient to prove no existing line changed). Cmd: `git diff <base>...HEAD -- .aai/scripts/aai-reap-tests.sh \| grep -E '^-' \| grep -v '^---' \| wc -l` expect `0`. Pre-fix value: N/A at plan time (no diff exists yet) — this is a scope-conformance guard; it fails FAST if implementation edits or removes any existing line instead of only adding the new one. Post-fix value: `0`. | green |
| TEST-006 | Spec-AC-03 | int  | tests/skills/test-aai-run-tests.sh (test_018)  | THE DISCRIMINATING ROW. test_018 spare-fresh direction, with an injected external kill of fresh_pid (`kill -9 "$fresh_pid"`) immediately after the reap_run call and immediately before the assertion, while the reaper's own reaped-pids line for this call is confirmed empty (reaper genuinely reaped 0 in the workspace). Cmd: `bash tests/skills/test-aai-run-tests.sh 018` with the external-kill line added to the spare-fresh block. Pre-fix value: the OLD liveness-based assertion (`if ! alive "$fresh_pid"`) sees fresh_pid dead and FAILS with "fail-safe broken ... reaper output: reaped: 0" — a demonstrable mis-attribution, captured by running this exact fixture against the file's current, unedited assertion before implementation. Post-fix value: the NEW attribution assertion checks the reaper's `reaped pids:` line (empty), correctly judges fresh_pid as not-reaped-by-the-reaper, and PASSES despite fresh_pid being dead. | green |
| TEST-007 | Spec-AC-04 | int  | tests/skills/test-aai-run-tests.sh (test_018)  | Evidence-dump path: point `AAI_REAP_SCRIPT` at a stub reaper (mirrors the existing stub-override pattern already used by TEST-001/005/016 in this suite) that deliberately reports `reaped: 1` plus a fabricated pid in `reaped pids:`, and confirm test_018's spare-fresh block emits the diagnostic dump (a `ps` snapshot scoped to the case workspace + the fabricated pid's parsed etime) to test output. Also confirm the dump is ABSENT on the normal `reaped: 0` real-reaper path (no added noise). Cmd: `AAI_REAP_SCRIPT=<stub path> bash tests/skills/test-aai-run-tests.sh 018` (grep test output for the dump markers) + `bash tests/skills/test-aai-run-tests.sh 018` (grep for absence on the normal path). Pre-fix value: no such dump code path exists — grep for the dump markers returns 0 matches under the stub scenario (RED, brand-new code path). Post-fix value: dump present under the stub scenario, absent on the normal green path. | green |
| TEST-008 | Spec-AC-05 | int  | (scope diff, not a test file)                  | Structural scope-guard for the companion-obligations outcome: the scope's own diff touches no prompt-corpus path (`.aai/*.prompt.md` or `.aai/AGENTS.md`) and adds no new path under `.aai/`. Cmd: `git diff --name-only <base>...HEAD` + `git diff --name-status <base>...HEAD`, confirm neither set contains a prompt-corpus path nor a newly-added `.aai/` entry. Pre-fix value: N/A (no diff exists at plan time) — fails FAST if a future edit strays into either companion's trigger paths. Post-fix value: no match in either set. | green |
| TEST-009 | Spec-AC-06 | e2e  | .github/workflows/skill-suite.yml (CI)         | AUTHORITATIVE evidence: `skill-suite` job green on Ubuntu across a REPEATED run (at least 2 consecutive runs on the branch, or one run re-run at least once), specifically with no recurrence of the spare-fresh mis-attribution failure. Cmd: `gh run list --workflow skill-suite.yml --branch fix/test-018-legacy-spare-attribution` + `gh run view <id>` (repeat). Pre-fix value: prior intermittent `reaped: 1` mis-attribution failures observed on PR #122/#127/#132; this row is the sole authoritative evidence that the attribution fix (not luck) holds under CI-Linux load — a local pass (TEST-001..008) is explicitly NOT substitutable for this row (Honesty requirements). | pending (CI — owned by Validation after push) |

Notes:
- Every Spec-AC has >=1 TEST-xxx. Test IDs are stable post-freeze.
- RED-proof obligation: TEST-001/002 RED-proof by absence (the `reaped
  pids:` line does not exist in the current, unedited reaper's output —
  directly reproducible today via `sh .aai/scripts/aai-reap-tests.sh` against
  any fixture). TEST-005 RED-proofs itself structurally (no diff exists yet,
  so the guard cannot pass vacuously — implementation must produce a diff
  with zero removals for it to go green). TEST-006 is the mandatory
  behavioral RED-proof: run the discriminating external-kill fixture against
  the file's CURRENT, unedited `test_018` before making any change, and
  observe the documented pre-fix FAIL; only then implement the attribution
  rewrite and re-run for GREEN. TEST-007 RED-proofs via the existing
  stub-reaper override convention (`AAI_REAP_SCRIPT`), proving the dump path
  is not tautological (it must trigger on a stub that reports a reap, and
  stay silent on the real, normally-passing path).
- TEST-004 and TEST-008 are regression/scope-conformance guards with no
  independently discriminating pre/post state of their own — they exist to
  catch an unintended side effect during implementation, not to prove the
  fix.
- CI (Ubuntu, under load) is the authoritative environment for the
  CI-Linux-only flake this scope addresses; a green local run (TEST-001..008)
  is necessary but never sufficient to claim the flake is de-flaked, and must
  not be reported as standalone evidence for Spec-AC-06.

## Verification
- Commands: the nine rows above (TEST-001..009).
- Evidence artifacts: RED/GREEN grep output for TEST-001/002/003; diff output
  for TEST-005; RED (pre-fix, documented FAIL) / GREEN (post-fix) run logs
  for TEST-006 (the discriminating row); stub-driven RED/GREEN logs for
  TEST-007; `git diff` output for TEST-008; `gh run` output/URLs for
  TEST-009.
- PASS criteria (local, non-CI rows): TEST-001..008 green AND all Spec-AC
  except Spec-AC-06 in status `done`. Spec-AC-06 stays `deferred` with
  Review-By 2026-08-10 until TEST-009's repeated-CI-green evidence arrives —
  per the Honesty requirements, this deferral is NOT itself a blocker for
  reporting the local fix, but a merge/PR-ready claim must not assert the
  flake is resolved until Spec-AC-06 is flipped to `done` with real CI
  evidence.

## Evidence contract
For each implementation / validation / TDD / code-review artifact record:
- ref_id: test-018-legacy-spare-attribution
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path
- commit SHA or diff range when available

## Implementation strategy
- Strategy: hybrid
- Rationale: TDD for the two rows that introduce genuinely NEW behavior with
  a meaningfully discriminating RED state — Spec-AC-01 (the reaper's
  `reaped pids:` line, a production-script change, RED-proofed by its
  current absence: TEST-001/002) and Spec-AC-03 (the attribution assertion
  rewrite, the core behavioral fix, RED-proofed by the external-kill fixture
  actually failing against today's unedited assertion: TEST-006) — both
  benefit from observing the documented failure BEFORE editing, not just
  asserting it would fail. `loop` for the remaining rows, which are
  structural regression/scope guards or a straightforward additive dump with
  no new decision logic of their own: Spec-AC-02 (a byte-diff purity check
  and an unmodified-test regression pin — nothing to iterate on), Spec-AC-04
  (the evidence dump, RED-proofed via the suite's existing stub-reaper
  override convention rather than a fresh RED-GREEN cycle), and Spec-AC-05
  (a git-diff scope-conformance guard). Full RED-GREEN-REFACTOR staging on
  every row would add process ceremony without added signal for TEST-004/005/
  007/008; TDD is reserved for the two rows where seeing the real failure
  first materially reduces risk.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: two non-protected files (one production script edited
  purely additively, one test file), small, reversible, single-surface
  change; already on its own dedicated branch
  `fix/test-018-legacy-spare-attribution` off `main` per the one-branch-per-
  work-item convention.
- User decision: undecided (Implementation Preparation gate; `not_needed`
  does not require a user decision before proceeding, per
  `.aai/AGENTS.md` worktree policy).
- Base ref: main
- Worktree branch/path: n/a (inline)
- Inline review scope: `.aai/scripts/aai-reap-tests.sh`,
  `tests/skills/test-aai-run-tests.sh`

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
- Required: true (production script + test-infra behavioral change).
- Scope: `.aai/scripts/aai-reap-tests.sh`, `tests/skills/test-aai-run-tests.sh`
  (inline diff scope, no worktree/PR base-ref yet).

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
Use plain Markdown headings and body text. Do not add emoji or decorative
icons unless there is a strong domain-specific reason.
