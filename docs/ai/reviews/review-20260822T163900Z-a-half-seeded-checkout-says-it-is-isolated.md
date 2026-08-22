# Code Review — a-half-seeded-checkout-says-it-is-isolated

```yaml
review:
  scope: "4988771..f77b62b (tests/skills/test-framework.sh, .aai/scripts/aai-run-tests.sh, tests/skills/test-aai-suite-isolation.sh, spec + intake docs)"
  spec: docs/specs/SPEC-DRAFT-spec-a-half-seeded-checkout-says-it-is-isolated.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "tests/skills/test-framework.sh:344-388 (three steps, four named branches); .aai/scripts/aai-run-tests.sh:393-443; TEST-108..111 green at HEAD in my own run test-20260822-162209 under /bin/bash 3.2.57" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "iso_seed_fail (test-framework.sh:289-292) touches only ISO_LAST_SEED; run_test:708-722 keeps the two increment sites independent; TEST-109/110/111 assert both lines on one run" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "test-framework.sh:1029 unconditional summary line, :1030-1032 invariant check, :1092 ledger fields; my run printed 'Seeding: 1/1 suite(s) fully seeded; 0 partial; 0 skipped'" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "no added path touches FAILED_TESTS (read-verified over the whole diff; only log/log_warn calls added); TEST-112 both outcomes green" }
      - { ac: Spec-AC-05, call: compliant,
          citation: ".aai/scripts/aai-run-tests.sh:495-507 gated on AAI_ISO_STATUS != not-applicable; TEST-113(a)-(e) green" }
      - { ac: "AC-status evidence freshness", call: cannot-verify,
          citation: "every AC row cites commit ccba52c and run test-20260822-065708; the shipped head is f77b62b, which changed three arms of the evidencing suite — see NON-BLOCKING finding 2" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-framework.sh, line: 366,
          issue: "Seeding step 2 has a third failure mode neither funnel can see: `git ls-files --others --exclude-standard` exits 0 with only a stderr warning when it cannot read a directory, and both funnels send that stderr to /dev/null. Files under such a directory are never enumerated, so n_untracked_fail stays 0 and the run claims a complete seed.",
          failure_scenario: "A working tree containing a directory the runner cannot read (root-owned bind-mount dir from a container, a stray chmod 000). Measured in a scratch repo: `chmod 000 sub` -> `warning: could not open directory 'sub/': Permission denied`, rc=0, and sub/test-aai-newthing.sh absent from the listing. The framework then prints `Seeding: N/N suite(s) fully seeded` and the wrapper prints `AAI-SEEDING: seeded - every seeding step completed; the disposable checkout carries your working tree` while untracked content did not arrive. Same class as .aai/scripts/aai-run-tests.sh:410." }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-DRAFT-spec-a-half-seeded-checkout-says-it-is-isolated.md, line: 306,
          issue: "All five AC Status rows cite commit ccba52c and run test-20260822-065708 as evidence, but f77b62b (the shipped head) edited three arms of the suite those rows are evidenced by. The cited run predates the shipped test code.",
          failure_scenario: "A later reader (or the docs audit at close) resolves the AC evidence to ccba52c, diffs it against head, and finds the evidencing file changed after the cited run — the row cannot be re-derived from what it names. The claim itself still holds: I re-ran the suite at head and got 19/19 (run test-20260822-162209)." }
  cannot_verify:
    - { claim: "Behaviour as root, where chmod denies nothing and the three NOT COVERED branches fire.",
        closes_with: "One run of tests/skills/test-aai-suite-isolation.sh as uid 0 (or in a root container), reading that TEST-110/111/112 print the NOT COVERED pass and the suite still exits 0." }
    - { claim: "An unwritable $AAI_ISO_BASE after mktemp succeeded (the marker files themselves unwritable).",
        closes_with: "A read-only-tmpfs probe; reasoned below to be self-covering, not measured." }
    - { claim: "The 81-suite full run at head. Not re-run per dispatch; the implementer's test-20260822-061705 (81/81) stands and validation re-read its ledger record.",
        closes_with: "CI's full-framework job on this PR, which select-suites.mjs already forces to mode=full." }
  overall: pass
```

## Scope and method

Combined diff `4988771..f77b62b` (two commits: `ccba52c` the feature, `f77b62b`
the verdict fix), read in full, not just the last commit. Validation round 1
(`docs/ai/validation/validation-20260822T065601Z-...-round1.md`) was read first
and is NOT repeated: it built ten fixtures, re-derived the construction, ran
four mutations in a clone and probed the wrapper thirteen ways. This review
judges the code as code and the blast radius, and adds only measurements
validation did not take.

New measurements taken here:

| measurement | result |
|---|---|
| `/bin/bash tests/skills/test-framework.sh --skill aai-suite-isolation` under **bash 3.2.57** (the shipped macOS bash), run alone | rc 0, suite PASS, **19/19 arms PASS** including TEST-108..113, tripwire clean, run `test-20260822-162209` |
| same, run **concurrently** with the hygiene pack | suite FAIL — but on the TRIPWIRE (`M docs/ai/tests/test-runs.jsonl`), caused by the other run's framework append. My own concurrency error, not a defect; re-run alone is green. Named here rather than omitted. |
| `/bin/bash tests/skills/test-framework.sh --skill aai-hygiene-pack` (carries the `printf \| grep -q` ratchet at `tests/skills/lib/pipe-grep-q-ratchet.sh`) | rc 0, PASS — the diff adds no new occurrence |
| `git ls-files --others --exclude-standard` with a mode-000 directory, scratch repo | `warning: could not open directory 'sub/': Permission denied`, **rc 0**, file absent from the listing → finding 1 |
| Consumers of `docs/ai/tests/test-runs.jsonl` | `orchestration-dispatch.mjs` uses it only as a member of `TREE_HASH_EXCLUDE_PATHS` (no schema parse); `test-aai-repo-tripwire.sh` and the two funnels. **No consumer can break on three new JSON keys.** |
| Consumers of the summary lines outside the three changed files | none (`grep` over `tests/`, `.aai/`, `.github/`). `skill-suite.yml` reads exit codes only. |

## Verdict 1 — spec_compliance: pass

The AC-table walk is in the YAML block. Every Spec-AC is compliant and every
TEST-xxx it names exists and passes at head, verified by my own run rather than
by citation. One row-level caveat (evidence freshness) is a NON-BLOCKING finding,
not an AC failure.

Deviations from the frozen spec: **none found.** Three spec claims that could
have drifted were checked against the code line by line:

- "every `return 1` path in `iso_create` is BEFORE the first seeding step" —
  true: returns at `test-framework.sh:314, 315, 326, 327, 331`, first seeding
  step at `:345`. So a recorded reason cannot orphan onto an uncounted suite.
- "Exactly ONE site reads `seed_status` and increments exactly one of three
  counters" — true (`:718-722`), and there is no `return` between
  `TOTAL_TESTS=$((TOTAL_TESTS + 1))` at `:625` and that site, so every counted
  suite is classified exactly once. A suite failing two steps still increments
  once, because `iso_seed_fail` counts nothing.
- "The script is `#!/bin/sh` under `set -u` … every new variable is initialised
  before first read" — true: `set -u` at `aai-run-tests.sh:67`;
  `AAI_SEED_STATUS`/`AAI_SEED_WHY` at `:225-226`, `ai_seedfail`/`ai_seedfirst`
  at `:430-431` before the loop that reads them.

## Verdict 2 — code_quality: pass

### What I attacked and could not break

**Shell correctness, both funnels, under bash 3.2.57.**
No bare `rc=$?` after a pipe was added: every added `rc=$?` is
`out="$(seed_run "$d")" || rc=$?`, and `seed_run`'s internal pipe is disambiguated
by the suite's own `set -uo pipefail` (`test-aai-suite-isolation.sh:29`), which is
what makes `rc` the framework's exit code and not `strip_ansi`'s — TEST-112's
0-vs-1 assertion is the live proof. No `local -a x=()` was added (the
`; `-joined string form is used for `SEEDING_REASONS`, matching the
3.2.57-driven precedent). No `local a=1 b=$a` chain exists in any added `local`
line — I enumerated all 22 of them; none references a name declared on the same
line. All new numeric tests are quoted (`[[ "$n_untracked_fail" -gt 0 ]]`). The
only unquoted expansion is `for f in $ISOLATION_SEED_PATHS`, which is the
pre-existing deliberate word-split.

**`log_fail` in a subshell.** The new arms use `d="$(new_fixture)" || return`,
which *looks* like the verdictless pattern f77b62b just fixed. It is not:
`new_fixture` calls `log_fail` before returning 1, and `log_fail`
(`:81`) appends to `$FAILURE_REGISTRY`, a FILE, which crosses the command
substitution's subshell boundary, and `main` (`:1492`) fails the suite on a
non-empty registry. So those paths carry a verdict.

**The wrapper's marker files.** Read as code, against the four hypotheticals:
- *cannot be written / base unwritable* — self-covering. The base is a fresh
  `mktemp -d` whose first use is `git diff HEAD --binary > "$AAI_ISO_BASE/wt.patch"`;
  if the base is unwritable that redirect fails, step 1's `! git … ` branch fires
  and the axis is already `partial`. The residual is an under-named reason on a
  run that is already reporting partial, not a false `seeded`.
- *two markers collide* — the two names are distinct literal constants
  (`seedfail-quoted`, `seedfail-untracked`), the quoted branch `continue`s so one
  path can never land in both, and the base is fresh per invocation, so no marker
  can survive into a second run (validation measured this; I confirmed the
  mechanism).
- *a glob character in the name* — the marker NAMES are constants; only their
  CONTENT is attacker-controlled, and it is consumed by `wc -l <` and `head -n 1`
  inside double quotes. No glob expansion is reachable.
- *the count* — `printf '%s\n'` per entry against `wc -l` is exact.

**The three-token accounting.** `iso_seed_fail` is the only writer of
`ISO_LAST_SEED` after initialisation, `run_test:682` is the only reader, and the
capture at `:682` happens BEFORE the `iso_destroy` on the suite-missing degrade
path at `:695` — which is what keeps the `degraded` + `partial` cell reachable and
correctly reported rather than lost with the destroyed checkout.

**The verdict fix in f77b62b is complete for the class it names.** All three
`seed_make_unreadable … || return` sites became branches that emit a pass naming
the non-coverage, and I found no other arm in the file that can exit
verdictless. The NOT COVERED text is unambiguous to a human ("the arm did not
run"). Two residuals I judge acceptable rather than filings: TEST-112's
NOT COVERED `return` sits inside the `for outcome in pass fail` loop, so it
reports once and skips the second outcome (which is equally uncoverable), and no
machine-readable "N arms not covered" tally exists — but that is the file's
established idiom (TEST-004(d)) and strictly better than the vanishing it
replaces.

**Blast radius.** Contained. The ledger's three new keys have no schema
consumer; the three summary lines have no consumer outside the changed files;
CI reads exit codes only. Cumulative risk from the third change to both funnels
in twelve hours is real but structural rather than behavioural: the isolation
and seeding axes are now two near-identical increment machines side by side
(already filed as `fu-isolation-seeding-duplicated`, P3), and `iso_create` has
grown to ~80 lines. Nothing in this diff can change which suites run, in what
order, or with what exit code.

### Finding 1 (NON-BLOCKING) — step 2's enumeration failure is invisible

`tests/skills/test-framework.sh:366` and `.aai/scripts/aai-run-tests.sh:410`.
See the YAML block for the measurement and the failure scenario. In short: the
axis names two distinct failures for step 1 (captured / applied) but only one for
step 2 (copied), and git's "could not enumerate" is neither an error exit nor a
visible warning once stderr is discarded — so the run answers "fully seeded" for
a checkout that is not.

Why this is not a blocker: the change is additive reporting and this state was
equally silent before it, so nothing regresses; and the safety-relevant
consequence is still covered one axis over — a suite that never arrives is
reported `degraded` by `run_test:688-694`, which is the state a repository-safety
gate would read.

Recommended disposition: **promote to follow-up ref** — filed as
`fu-seed-step2-enumeration-silent` (P3), read back from the ledger and confirmed
open (see "Filed" below).

### Finding 2 (NON-BLOCKING) — AC evidence cites the pre-fix commit

See the YAML block. Recommended disposition: **remediate in tree** — one edit to
the Evidence column of the five AC rows, adding `f77b62b` and a run taken at head
(mine, `test-20260822-162209`, 19/19), before the close ceremony.

### INFO (never gates)

- `aai-run-tests.sh:501` prints `partial - $AAI_SEED_WHY; …` with no guard for an
  empty reason, while the framework's twin (`test-framework.sh:1024-1025`) has an
  explicit "(none recorded — … a defect in the framework)" fallback. No call site
  passes an empty reason today, so the asymmetry is latent.
- The paired comment at `test-framework.sh:626-633` still says "bump the
  **isolation** counters first"; it now guards three counters more than it names.
- `log_warn` is `echo -e`, so a `\`-bearing path in `first: $first_untracked_fail`
  would print its escape rather than itself. Pre-existing to this helper.

## Judgement — AC-004's forward answer, checked end to end

The spec answers **No** to "should this gate when the tripwire is deleted",
the opposite of SPEC-0144's answer. Validation called that sound but "one
sentence too absolute". I checked the reasoning rather than the sentence, and
**the two gates together leave no reachable write-capable state uncovered**:

- The only mechanism by which a suite's writes land in the shipping repository is
  `run_test:685` failing the `[[ -f "$ISO_LAST_WT/$iso_rel" ]]` test, which sets
  `iso_status=degraded` at `:692` and destroys the checkout. Every cause of that
  — including a step-2 failure that removed a brand-new suite — arrives at the
  same branch, so `degraded` is a complete cover of the write-capable set.
- A `partial` seed that is NOT `degraded` means the suite file DID arrive: the
  suite runs inside the disposable checkout and its writes land there. Content it
  reads may be missing (stale HEAD copy of a tracked file, an absent seed path),
  which makes the run test LESS than it claims — a coverage defect, not a
  repository-safety one.
- So a `grep degraded` gate is sufficient for safety, and a second gate on
  `partial` would add zero safety coverage while firing on the harmless majority.

The spec's literal sentence "A partial seed cannot write anywhere" remains one
notch stronger than the mechanism supports (a partial seed can CAUSE the state
that can write), but the paragraph's conclusion is load-bearing and correct, and
the spec says the true version explicitly in "The interaction that decides the
denominator" and in its cross-axis table. Not a blocker, and not worth a filing
on top of the existing `fu-tripwire-removal-needs-a-gate` (P2).

## Judgement — cumulative readability of the summary block

Measured from my own run:

    Tripwire: 1/1 suite(s) attested clean; 0 not attested (skipped, failed, allowlisted, or unguarded)
    Isolation: 1/1 suite(s) isolated; 0 degraded
    Seeding: 1/1 suite(s) fully seeded; 0 partial; 0 skipped

Three lines, parallel in shape, each naming its own axis first. The block still
reads. The one ambiguous token is `skipped`, already filed as
`fu-seeding-skipped-token-collides` (P3) — I agree with the P3 and with the
reasoning that machine readability is unharmed. I add one observation: the block
now has THREE distinct `Seeding: ` line shapes in a failing run (the per-suite
NOTE, the PARTLY SEEDED warning, the accounting line). The spec's stated grep key
(prefix plus ` fully seeded; `) disambiguates them, so this is prose density, not
a defect.

## Known findings — not refiled

`fu-seed-loss-turns-an-arm-into-a-skip` (P2), `fu-seeding-skipped-token-collides`
(P3), `fu-seed-arms-vanish-when-lever-dead` (P3 — **the fix in f77b62b is
complete**; recommend closing it against f77b62b),
`fu-isolation-seeding-duplicated` (P3), `fu-isolation-suite-not-hermetic` (P2),
`fu-tripwire-removal-needs-a-gate` (P2), `fu-framework-appends-tracked-testruns`
(P3 — reproduced incidentally by my concurrent run, which is precisely its bite),
`fu-run-id-second-resolution-collides` (P3).

## Filed

- `fu-seed-step2-enumeration-silent` (P3, ref
  `spec-a-half-seeded-checkout-says-it-is-isolated`). **Read back from the
  ledger** after filing: id, severity P3, status open, ts 2026-08-22T16:25:56Z,
  `id_malformed: false`. 32 characters, matches `^fu-[a-z0-9]+(-[a-z0-9]+)*$`.

## Blockers

None.

## Next steps

1. Remediate finding 2 in tree (AC Evidence column cites f77b62b and a run at
   head) before the close ceremony.
2. Close `fu-seed-arms-vanish-when-lever-dead` against f77b62b.
3. `fu-seed-step2-enumeration-silent` is an input to whichever scope owns the
   coverage question, beside `fu-seed-loss-turns-an-arm-into-a-skip`.
4. PR step: run the close ceremony BEFORE CI, per validation's handoff — the
   terminal AC table on a still-`implementing` doc trips docs-audit's false-open
   arm until the frontmatter flips.
