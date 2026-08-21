# Code Review — assertions-must-not-die-on-their-own-payload

```yaml
review:
  scope: git diff 67b9580..5a30648 (branch fix/assertions-survive-large-payloads)
  spec: docs/specs/SPEC-DRAFT-spec-assertions-must-not-die-on-their-own-payload.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "spec:78-110 census + at-risk set EMPTY; corroborated by validation round 1 over 43% of the baselined occurrences; TEST-006 (test-aai-hygiene-pack.sh:1388)" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "tests/skills/lib/assert-payload.sh:42-100; TEST-001/002 green (test_100/test_101), 212011 B payload: old idiom 141, helper 0" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "tests/skills/lib/pipe-grep-q-ratchet.sh:103-127; TEST-003/005 green; both honest limits now stated in spec:145-166" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "pipe-grep-q-ratchet.sh:159-179; TEST-004 green; I independently re-rendered the baseline and it is BYTE-IDENTICAL to the committed file" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "test-aai-docs-audit.sh exit 0, 156 PASS; needle pins at test-aai-hygiene-pack.sh:1382-1386 (3 of 4 sites — see NB-5)" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: tests/skills/test-aai-hygiene-pack.sh, line: 1428,
          issue: "test_105's unbounded-payload sweep greps for the single literal spelling `got: $out\"`. That string occurs 0 times in test-aai-docs-audit.sh, so the arm logs `no unbounded payload dump` while the same file still dumps the SAME findings payloads at 8 sites spelled `: $out\"`.",
          failure_scenario: "test-aai-docs-audit.sh:2246 fails -> log_fail prints the whole index_posix_findings payload (the 46 KB blob this scope exists for) into the CI log; test_105 has already certified the file clean of exactly that." }
      - { rank: NON-BLOCKING, file: tests/skills/lib/assert-payload.sh, line: 87,
          issue: "the NEEDLE is interpolated unbounded into the message the helper exists to bound; only the payload goes through payload_preview.",
          failure_scenario: "measured: a 5000 B needle produces a 5040 B failure message. test_100(c) varies only the payload, so the bound is unproven in the needle direction." }
      - { rank: NON-BLOCKING, file: tests/skills/lib/pipe-grep-q-ratchet.sh, line: 86,
          issue: "pgq_lookup exits at the FIRST matching baseline row; a duplicated row with a higher count masks a real rise as a SHRINK NOTE. Nothing validates baseline shape.",
          failure_scenario: "measured: baseline rows `9<TAB>test-a.sh` then `3<TAB>test-a.sh`, real rise 3->5, verdict `SHRINK test-a.sh 9 5` = NOTE, arm passes. Reachable via a .tsv merge conflict resolved by keeping both sides." }
      - { rank: NON-BLOCKING, file: tests/skills/lib/pipe-grep-q-ratchet.sh, line: 56,
          issue: "`2>/dev/null` on the scan grep turns a per-file measurement ERROR into a count of 0; the file drops out of the scan and the ratchet reports it as an improvement.",
          failure_scenario: "measured: chmod 000 on a baselined file -> scan omits it -> `GONE test-a.sh 3 0` = NOTE -> arm passes. Violates AGENTS.md's degrade-with-a-NOTE rule. Same at pgq_read_baseline:131." }
      - { rank: NON-BLOCKING, file: .github/workflows/skill-suite.yml, line: 15,
          issue: "the workflow header still documents the always-on core set as `(check-state, docs-audit, spec-lint)` after this diff added a fourth entry.",
          failure_scenario: "the next engineer costing a selected-mode PR reads the workflow's own header and under-counts the always-on set; the promotion's rationale lives only in suite-map.yaml." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-hygiene-pack.sh, line: 1382,
          issue: "PGQ_CONVERTED pins 3 of the 4 converted assert_payload_contains sites; docs-audit:2338 (`\"$out\" \"$victim\"`) is unpinned while the arm claims `every converted site ... keeps its needle`.",
          failure_scenario: "delete test-aai-docs-audit.sh:2338 and both suites stay green; the coverage the pin exists to protect is gone unobserved." }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-DRAFT-spec-assertions-must-not-die-on-their-own-payload.md, line: 82,
          issue: "the distribution table does not sum to its own stated total: 23+2307+561+10195+3+0 = 13089, the prose says 13091.",
          failure_scenario: "a reader auditing Spec-AC-01's sole evidence artifact adds the column, gets a different number, and cannot tell whether the missing 2 are the filtered fixture rows or a reporting error. Validation round 1 flagged this qualitatively; the follow-up commit did not address it." }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-DRAFT-spec-assertions-must-not-die-on-their-own-payload.md, line: 282,
          issue: "Test Plan row TEST-004 describes `baseline is byte-identical to a fresh --record`, which test_103 does not assert — and which would CONTRADICT TEST-005/Spec-AC-03 (a SHRINK must be a NOTE, not a failure).",
          failure_scenario: "a maintainer implements the tabled description and turns every deliberate conversion into a red suite." }
  cannot_verify:
    - { claim: "the full-framework census aggregates (13091 calls, 81 suites, the 10195-call 4-16 KiB cluster)",
        closes_with: "a second independent full-framework run under a differently-implemented shim; validation re-derived 43% of the baselined occurrences and I did not re-derive any of it" }
    - { claim: "test_101 CONTROL A's hard `rc == 141` requirement holds on ubuntu-latest",
        closes_with: "one CI run of the now-always-on suite on Linux; every measurement here and in validation is darwin, and the core: promotion makes this arm gate EVERY selected-mode PR" }
    - { claim: "the marginal CI cost of the core: promotion",
        closes_with: "a CI timing of `test-framework.sh --skill aai-hygiene-pack` on the runner; locally measured 5.97 s real, which matches the suite-map comment's 6 s claim, but the disposable-worktree add is not in that number" }
    - { claim: "whether the PR will carry ci-full / trip a fail-open trigger",
        closes_with: "the PR itself; carried forward unchanged from validation round 1" }
  overall: fail
```

## Scope and method

Base `67b9580`, head `5a30648`, working tree clean, HEAD unchanged at `5a30648`
throughout. Validation round 1
(`docs/ai/validation/validation-20260821T173510Z-...-round1.md`) was read first
and is NOT repeated: its census re-derivation, locale verification, D1 sweep and
M9 reproduction are taken as given. This pass judged the code as code, with a
bias toward the newest and least-examined change (the `core:` promotion) and
toward the shell-correctness classes this repo has been burned by.

Every measurement used `/usr/bin/grep` absolutely, ran loops under `/bin/bash`,
and no measurement's stderr went to `/dev/null`. Probe scripts live under the
scratchpad; no tracked file was edited.

## BLOCKING — the unbounded-dump guard certifies a file that still dumps

`tests/skills/test-aai-hygiene-pack.sh:1426-1434` adds, in this diff:

```
unbounded="$(grep -nF -- 'got: $out"' "$suite" 2>/dev/null)" || unbounded=""
```

and, when it finds nothing, the arm logs
`no unbounded payload dump (TEST-006)`. The spec's Test Plan row TEST-006 makes
the same claim: *"every converted site sources the helper, keeps its needle, and
dumps no unbounded payload"*.

Measured on the shipped head:

- `grep -cF 'got: $out"' tests/skills/test-aai-docs-audit.sh` -> **0**. The sweep
  is satisfied.
- `grep -cE 'log_(fail|info) ".*: \$out"' tests/skills/test-aai-docs-audit.sh` ->
  **12**, of which **8 print the output of `index_posix_findings` or
  `index_stale_findings`** — the exact two producers whose OTHER call sites this
  diff bounded with `payload_preview` at 2308 and 2357, because their payloads
  measured past 46 KB:

  | line | statement |
  |---|---|
  | 2246 | `log_fail "an earlier-day index must still pass the POSIX-path arm: $out"` |
  | 2249 | `log_fail "an earlier-day index must still pass the staleness arm: $out"` |
  | 2274 | `log_fail "committed docs/INDEX.md must carry forward-slash paths only: $out"` |
  | 2275 | `log_info "  committed index: $out"` |
  | 2278 | `log_fail "a fresh regeneration must carry forward-slash paths only: $out"` |
  | 2323 | `log_fail "committed docs/INDEX.md is stale: $out"` |
  | 2427 | `log_fail "the POSIX-path arm must stay clean across the boundary ($snap): $out"` |
  | 2430 | `log_fail "the staleness arm must stay clean across the boundary ($snap): $out"` |

The anchor is a spelling, not the hazard. `got: ` is not what makes a dump
unbounded; `$out` unwrapped by `payload_preview` is. Line 2308 was rewritten in
this very diff from `got: $out"` to `got: $(payload_preview "$out")"` — the
sweep sees only the sites the author had already thought about.

Why I rank this BLOCKING rather than filing it:

1. The SKILL_CODE_REVIEW contract is explicit: *"A test whose NAME claims a
   universal negative ... while asserting only a subset of paths is likewise
   BLOCKING — rename it or prove the negative (corpus sweep / mutation)."* This
   is that, verbatim, and the guard is a product of this diff, not inherited
   debt.
2. It is a false negative TODAY, not prospectively.
3. Validation itself argued (on `fu-framework-appends-tracked-testruns`) that
   *"a guard that reports clean while its own harness writes is a correctness
   bug in the guard's contract"*. The same standard applied here reaches the
   same verdict, and this instance is inside the shipped diff.

Honest sizing, because a blocker must be proportionate: the residual exposure is
CI-log noise on a red run, not a false CI red — the eight sites are `[[ ]]`
comparisons and are not themselves subject to the SIGPIPE defect. **Either fix
is one edit**: widen the sweep to `: \$out"` in a `log_(fail|info)` line and
wrap the eight sites (they are already inside the suite that owns
`payload_preview`), or rename the claim to what it actually checks. What is not
acceptable is shipping the attestation as written.

## The `core:` promotion — attacked hardest, survived

This is the part of the diff validation never saw. Everything below is my own
measurement.

- **Selector correctness.** A diff touching only `tests/skills/test-aai-doctor.sh`
  now returns `CORE aai-check-state / aai-docs-audit / aai-spec-lint /
  aai-hygiene-pack`, `SELECTED aai-doctor`, `DROPPED 76`. The gap
  `fu-ratchet-not-selected-on-rise` names is closed for PRs.
- **The parser.** `suite-map.yaml` is read by a hand-rolled line parser, and this
  diff inserts eight `#` comment lines INSIDE the `core:` block at 2-space
  indentation — a shape the file had never carried there. `select-suites.mjs:118`
  skips `/^\s*#/` before any section dispatch, so the comments cannot be parsed
  as core entries. Verified by running the selector, not by reading.
- **`DROPPED` arithmetic.** `Object.keys(suites).length - core.length -
  selected.size` (line 305) stays correct only because core suites are excluded
  from `selected` at line 295. They are. 76 is right.
- **The fail-open triad and the ghost-core guard.** Unchanged; `select-suites.mjs:242`
  still refuses a core entry with no `suites:` row by degrading to
  `FULL_RUN reason=internal-error`, and `aai-hygiene-pack` has one (line 331).
  `test-aai-suite-select.sh` TEST-019 covers this and the suite is green.
- **The hygiene pin.** The pin requires one `suites:` row per `test-aai-*.sh`;
  `core:` membership is orthogonal and the row is present. `test-aai-hygiene-pack.sh`
  green.
- **Cost.** The suite-map comment claims "6 s". Measured 5.97 s real / 4.23 user.
  `skills-selected` runs suites serially in one job at `timeout-minutes: 15`, and
  `aai-docs-audit` (129 s) is already core, so the marginal risk is nil.
- **Is `core:` the right mechanism?** Yes for this suite, with a caveat I am not
  turning into a finding. The alternative the comment dismisses — widening the
  globs — was available in a non-drifting form (`tests/skills/**`, and
  `tests/skills/lib/**` is already used at suite-map.yaml:783 by
  `aai-win-fallback`), so "hoping the glob keeps up" slightly overstates the
  case. But core is strictly stronger and the 6 s is real, so the choice is
  sound. What it does NOT fix is the class: any suite that guards a CORPUS
  rather than a component has the same selection gap, and this is the second
  ratchet in the repo (the known-offender ratchet in `test-framework.sh` is the
  first). That is a note for the next ratchet, not a defect in this one.
- **One consequence the diff did not cost.** `test_101` CONTROL A hard-asserts
  `rc == 141` from a real SIGPIPE, and the promotion makes that arm gate EVERY
  selected-mode PR. Every observation of that 141 — the intake's, validation's
  and mine — is darwin. The mechanism should hold on Linux (65536 B buffer, a
  212 KB payload, an early needle), but it is now on the critical path for all
  PRs and has never been observed there. Recorded under `cannot_verify`, not as
  a finding.

## Shell correctness — what I attacked and failed to break

- **The fix does not contain the defect it fixes.** Every `grep` in the new
  library code either reads to EOF (`-Eo | grep -c ''`, `grep -E`, `grep -c`) or
  targets a FILE. There is no `printf | grep -q` in `assert-payload.sh`,
  `pipe-grep-q-ratchet.sh`, or the six new arms. `pgq_scan`'s pipeline survives
  the caller's `pipefail` because `grep -c` on empty input exits 1 and the
  `|| _pgq_n=0` catches it — the comment at lines 46-51 is accurate.
- **`local x=$(...)` masking.** Not present. `local` is declared bare at the top
  of each function and the command substitutions are separate statements, so
  `|| _pgq_n=0` reads the pipeline's status and not `local`'s.
- **`log_fail` reachability.** `log_fail` in both suites is
  `echo ... >&2; exit 1`, so `_assert_payload_report`'s delegation terminates the
  suite exactly as the old `|| log_fail` did. No `set -e` semantic change at the
  six converted sites, and no `log_fail` inside a subshell or command
  substitution in the new code.
- **`${BASH_SOURCE[0]} = ${0}` on `--record`.** Correct and load-bearing:
  `test_102`/`103`/`104` source the library from INSIDE a function, and without
  that half `${1:-}` would be the function's first argument.
- **`set -u` + empty array on bash 3.2.57 (the shipped macOS bash).** Measured
  harmless on this patchlevel: `ARR=(); echo ${#ARR[@]}` -> `0`, no abort. The
  `test_105` vacuity guard is safe.
- **`LC_ALL=C` scoping.** Does not leak. Under an exported `en_US.UTF-8`, the
  caller's `${#cz}` is 6 before and after `payload_preview`. Confirms validation.
- **Preview boundary.** Exact, no off-by-one: a 512 B payload yields a 541 B
  message and is NOT labelled truncated; 513 B yields 580 B and is.
- **Hostile payloads and needles.** `%s`, `\n`, `\t`, `*`, `?` are all literal:
  the payload goes through `printf '%s'` and the needle is quoted inside the
  `case` pattern. No accidental format or glob semantics.
- **Arity under `set -u`.** `assert_payload_contains` with ZERO arguments is
  refused cleanly (`$#` is tested before `$2`), not aborted.
- **Baseline data format, fail-closed cases.** A malformed count -> `NEW` (FAIL,
  because awk coerces to 0). An empty baseline -> every file `NEW` (FAIL), and
  `test_102` additionally guards `[[ -n "$base" ]]` and `[[ -f "$baseline" ]]`. A
  baseline row for a vanished file -> `GONE` NOTE, no crash. A row with no tab ->
  skipped. Only the duplicate-row case (NB-3) and the unreadable-file case (NB-4)
  fail open.
- **Basename keying.** Unreachable today: `pgq_scan` globs ONE non-recursive
  directory, so basenames are unique by construction, and the committed baseline
  has no duplicate basenames (`uniq -d` empty). It becomes a real hazard the day
  the glob is made recursive — which is the fix direction
  `fu-pgq-scan-evadable-shapes` points at, so the two are coupled.
- **Provenance.** I re-rendered the baseline to the scratchpad with the real
  `--record` against `tests/skills` and it is **byte-identical** to the committed
  file (389 occurrences, 38 files). Nothing has drifted since the recording.
- **Sourcing and blast radius.** `iso_create` (test-framework.sh:259-299) does a
  full `git worktree add HEAD` plus a working-tree patch replay plus a copy of
  every untracked-not-ignored file, so `tests/skills/lib/` is present in every
  disposable checkout — tracked now, untracked before the commit, either way
  seeded. `--skill <name>` takes the identical path. The self-hosting smoke works
  off `tests/fixtures/target-project` and never touches `tests/skills/`. Both
  library files are mode 100644 and are only ever `bash`-invoked or sourced.
  `check-test-registration.mjs tests/skills` is clean.
- **Self-reference (D7/D9/D10).** `test-aai-hygiene-pack.sh` carries 0
  occurrences and is ABSENT from the baseline, which is the STRICT case: a real
  site added there compares as `NEW ... 0 n` = FAIL. The `PGQ_BAR`
  parameterisation can only hide a site written deliberately through `$PGQ_BAR`.
  Prose comments counting as occurrences is deliberate (D7, and the header of the
  library says the scanner "does not care that an occurrence is a comment, and it
  should not"). Cannot mask a real site.

## Is the negative result presented honestly?

**Substantially yes, with one arithmetic defect.**

In its favour, and this is the part that matters: the intake itself pre-authorised
the outcome — *"If the measurement says the at-risk set is empty except the four
already fixed, say so and ship the helper and the ratchet alone"*
(CHANGE-DRAFT, Constraints). The spec says it plainly at line 91
(**"The at-risk set is EMPTY"**) and again at 102 (*"no site was converted for
AC-001, and that is the honest answer"*), states the census's blind spot
explicitly at 106-110, and — new in the fix commit — states two honest limits on
the ratchet at 145-166 including the one validation left unfixed. A reader who
was not here CAN reach the right verdict on Spec-AC-01.

What still needs reconciling by the reader, and should not:

- The distribution table's rows sum to **13089**; the prose above it says
  **13091**. The difference is exactly the two filtered fixture rows, but the
  artifact never says so — the `<- ... over REPOSITORY call sites` annotation is
  attached to one row while the total is unfiltered.
- The sentence *"The two rows at or above the floor are both this scope's own
  `test_101` CONTROL A fixture"* uses "rows" for census RECORDS while the table
  immediately above uses "rows" for BUCKETS, and the bucket at that position
  reads `0`. Validation flagged this and recommended fixing it in the write-up;
  the follow-up commit amended Spec-AC-03 and left this untouched.

**Is the vacuity recorded?** Yes. The AC Status table's Spec-AC-01 Evidence cell
reads *"at-risk set EMPTY"* and its Notes cell names the nearest miss and its
follow-up id. The spec does not read as if conversion work was done. Note that
Spec-AC-01 narrows the intake's AC-001 from *"every site whose payload CAN
exceed 32 KiB"* to *"every site the census RECORDED at or above 32768 B"* — a
prospective claim becoming a point-in-time one. That narrowing is authorised by
the intake's own Verification section, and the standing-re-census gap it leaves
is already carried by `fu-ceremony-levels-nearest-miss-30kb`. Not a finding.

All five AC rows remain `implementing` (`docs-audit --gate` exits 1). Per
validation this is the precedented deferred-to-close state on DRAFT specs;
the close ceremony must flip all five and populate Evidence.

## Warning dispositions (H6)

I am read-only on the registry per the SKILL_CODE_REVIEW anti-gaming contract, so
I did **not** file anything. Recommended dispositions for the orchestrator, with
ids verified against `^fu-[a-z0-9]+(-[a-z0-9]+)*$` and the 40-character limit:

| finding | disposition | proposed id (chars) | severity |
|---|---|---|---|
| BLOCKING sweep anchor | remediate-in-tree | — | — |
| unbounded needle | follow-up | `fu-payload-needle-unbounded-in-message` (38) | P3 |
| duplicate baseline row | follow-up | `fu-pgq-baseline-duplicate-row-masks-rise` (40) | P3 |
| scan silent on grep error | follow-up | `fu-pgq-scan-silent-on-grep-error` (32) | P3 |
| stale workflow core comment | remediate-in-tree (one line) | — | — |
| unpinned 4th converted needle | remediate-in-tree (one array entry) | — | — |
| table does not sum | remediate-in-tree (spec) | — | — |
| TEST-004 Test Plan row drift | remediate-in-tree (spec) | — | — |

Known and deliberately NOT refiled: `fu-drain-pipe-grep-q-ratchet`,
`fu-ceremony-levels-nearest-miss-30kb`, `fu-pipe-into-head-sigpipe-class`,
`fu-framework-appends-tracked-testruns`, `fu-ratchet-not-selected-on-rise`
(fixed in this diff and verified above), `fu-pgq-scan-evadable-shapes`.

## INFO (never gates)

- `payload_preview` has no arity guard; a bare call under `set -u` aborts the
  suite (`assert-payload.sh:44: $1: unbound variable`) where both sibling helpers
  refuse gracefully.
- `$(payload_preview ...)` strips the payload's trailing newlines, so a payload
  of `abc\n\n\n` renders as `got: abc` and a whitespace-only payload renders as
  nothing at all.
- Three different corpus counts ship in one change: 387 (intake), 389 (baseline,
  arm and spec), 390 (`test-aai-hygiene-pack.sh:1143`, "the corpus's 390 sites").
- `test_103` and `test_105` call bare `grep` while the same file defines
  `PGQ_GREP_BIN` precisely because `grep` may resolve to a ugrep shell function.
- spec:210 documents the marker as `... [<N> bytes total, truncated]`; the code
  emits `... [<N> bytes total, truncated to 512]`. spec:280 says the TEST-002
  fixture is 216000 B; the arm measures 212011 B (spec:129 has it right).

## Test evidence

| Command | Exit | Notes |
|---|---|---|
| `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-hygiene-pack.sh` | 0 | TEST-001..006 PASS; live gate 389/38, superset 635; `test_105: 3 converted needle(s)` |
| `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-suite-select.sh` | 0 | the suite that parses suite-map.yaml; TEST-018/019 green |
| `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-docs-audit.sh` | 0 | 156 PASS; owns all six converted sites |
| `node .aai/scripts/select-suites.mjs --files-from <one unrelated suite>` | 0 | `CORE aai-hygiene-pack reason=core` + 3 CORE + 1 SELECTED + DROPPED 76 |
| `node .aai/scripts/check-test-registration.mjs tests/skills` | 0 | new arms registered in `main()` |
| `bash tests/skills/lib/pipe-grep-q-ratchet.sh --record <scratch> <tests/skills>` | 0 | `diff` vs the committed baseline: byte-identical |
| `/usr/bin/time -p bash tests/skills/test-aai-hygiene-pack.sh` | 0 | real 5.97 s — the suite-map "6 s" claim holds |
| scratchpad probes p1 (helper edges) / p2 (baseline format) | — | boundary, needle, locale, printf-safety, duplicate/malformed/empty/missing/unreadable |

## Repo hygiene and disclosures

- `git status --porcelain` empty at start and at end. HEAD `5a30648` unchanged.
- `docs/INDEX.md` byte-identical to the backup taken before the suite runs
  (`cmp` clean).
- No tracked file was edited at any point; every experiment ran on copies under
  the scratchpad. No restoring git command was issued.
- **Protocol slip, disclosed:** the `/usr/bin/time` measurement of
  `test-aai-hygiene-pack.sh` was taken directly (not through
  `aai-run-tests.sh`) and overlapped the tail of the backgrounded
  `test-aai-docs-audit.sh` run, breaking the serial-suites rule. Both exited 0
  and neither writes to the shipping tree, and `test-aai-hygiene-pack.sh` had
  already been run cleanly and serially through the canonical dispatcher before
  that; the timing number is the only result that came from the overlapping run.

## Verdict

**changes_requested.** One BLOCKING finding: a guard added by this diff attests
that the converted suite dumps no unbounded payload, and the converted suite
dumps eight of them. The substance of the change — the negative result, the
helper, the ratchet, the `core:` promotion — I attacked across the surfaces
listed above and could not break.
