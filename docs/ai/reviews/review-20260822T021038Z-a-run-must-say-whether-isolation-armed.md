# Code Review — a-run-must-say-whether-isolation-armed

```yaml
review:
  scope: git diff 2d1d57c..efdb726 (branch feat/isolation-status-is-reported)
  spec: docs/specs/SPEC-DRAFT-spec-a-run-must-say-whether-isolation-armed.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "tests/skills/test-framework.sh:573-607 (single iso_status site); TEST-101..104 green (13/13, exit 0, my own run)" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "tests/skills/test-framework.sh:888 unconditional `log` outside any `if`; TEST-101 green" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "tests/skills/test-framework.sh:940; all 134 ledger lines JSON.parse clean, 3 carry the new fields, invariant holds on all 3; TEST-105 green" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "FAILED_TESTS written only at test-framework.sh:756,790 — both pre-existing, neither in the diff; TEST-106 green" }
      - { ac: Spec-AC-05, call: compliant,
          citation: ".aai/scripts/aai-run-tests.sh:418-427; all four reachable branches re-derived under /bin/dash with the exit contract intact; TEST-107 green" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-framework.sh, line: 536,
          issue: "The isolation increment is 66 lines and five external calls downstream of TOTAL_TESTS++, not adjacent to it. The invariant depends on every path that reaches 536 also reaching 602, and nothing at either site says so — the comment at 567-572 documents single-site-ness (no double count) and is silent about reach (no under-count).",
          failure_scenario: "A later editor adds an early `return` inside run_test between lines 537 and 601 (a per-suite filter, or a bail-out when the log file cannot be created). TOTAL_TESTS is already bumped, neither isolation counter is, and the summary line and the ledger record silently under-count while both stay well-formed: `80/81 suite(s) isolated; 0 degraded`. TEST-105 asserts isolated+degraded==total only for the shapes its fixtures exercise, so the new path is not caught unless it is fixtured." }
      - { rank: NON-BLOCKING, file: tests/skills/test-framework.sh, line: 257,
          issue: "iso_note_reason silently drops an empty reason. A degraded suite whose iso_status_why is empty is still counted, but contributes nothing to the reason set, and generate_summary then prints a WARN line ending `Reason(s): ` with nothing after it. No arm asserts that the reason set is non-empty when ISOLATION_DEGRADED > 0.",
          failure_scenario: "Measured, not read: with ISOLATION_WHY forced empty in a scratchpad copy under /bin/bash 3.2.57, a 1-suite run printed `Isolation: every suite runs degraded ()`, `Reason(s): ` (empty) and `Isolation: 0/1 suite(s) isolated; 1 degraded`, and the ledger record was correct. Reached in the field the first time a fourth degrade path assigns iso_status=degraded and forgets iso_status_why — the operator gets a count with no reason and is sent back to the scrollback this line exists to replace." }
  cannot_verify:
    - { claim: "Behavior on Linux and on Windows/Git-Bash — the whole review was run on darwin 25.6.0 (arm64).",
        closes_with: "The pre-merge CI run: select-suites.mjs returns FULL_RUN for this file list, so .github/workflows/skill-suite.yml runs mode=full on this PR." }
    - { claim: "That no downstream consumer outside this repository greps the wrapper's stderr and is broken by the new AAI-ISOLATION line on a previously-silent AAI_TEST_ISOLATION=0 suite run.",
        closes_with: "A vendored-consumer sweep, or the first aai-sync into a downstream project." }
    - { claim: "That the seeding-completeness axis (fu-seeding-completeness-uncounted) cannot mask a false-green run in practice — I confirmed the two cp steps are silent by reading, but did not force a cp failure end to end.",
        closes_with: "The sibling scope's own evidence; out of this scope's ACs." }
  overall: pass
```

## Scope and method

Base `2d1d57c`, head `efdb726`, branch `feat/isolation-status-is-reported`.
Reviewed files: `tests/skills/test-framework.sh`, `.aai/scripts/aai-run-tests.sh`,
`tests/skills/test-aai-suite-isolation.sh`, `tests/skills/README.md`, plus the
spec and intake docs.

Validation round 1
(`docs/ai/validation/validation-20260822T011021Z-...-round1.md`) was read first
and is NOT repeated. It forced degrade paths 2 and 3 on a real 81-suite clone,
ran the invariant against six interrupt/empty shapes and re-derived every
mutation bite. This review is the other half: the code as code, and the blast
radius of two files every one of the 83 suites enters through.

Working copies live under the session scratchpad. No restoring git command was
run; `git status --porcelain` is empty at the end; `docs/INDEX.md` was backed up
and is byte-identical to the backup.

## Verdict 1 — spec_compliance: pass

| Spec-AC | Call | Citation |
|---|---|---|
| Spec-AC-01 | compliant | `run_test` declares `iso_status="isolated"` once (`test-framework.sh:574`); the three degrade paths (`:586`, `:594`, `:599`) only ASSIGN it; exactly one read/increment pair at `:602-607`. `/usr/bin/grep -c 'ISOLATION_ISOLATED=\$((' ` and its twin each return 1. TEST-101..104 green in my own run. |
| Spec-AC-02 | compliant | `test-framework.sh:888` is a bare `log` at function-body level in `generate_summary`, outside every `if`. The only conditional is the WARN above it (`:886`). |
| Spec-AC-03 | compliant | `test-framework.sh:940`. Both interpolations are arithmetic-assigned integers, so the record cannot become invalid JSON from these fields. Verified: all 134 lines of `docs/ai/tests/test-runs.jsonl` `JSON.parse` clean, the 3 carrying the new fields all satisfy `suites_isolated + suites_degraded == total`. |
| Spec-AC-04 | compliant | `FAILED_TESTS` is assigned at exactly two sites (`:756`, `:790`), both pre-existing and neither in the diff; the exit is still `exit 1 iff FAILED_TESTS > 0` (`:990`). The new code uses only `log`/`log_warn`, which are pure `echo` (`log_warn` at the helper block). TEST-106 green. |
| Spec-AC-05 | compliant | `aai-run-tests.sh:418-427`, one `case` on `AAI_ISO_STATUS`, `not-applicable` printing nothing. TEST-107 green. |

TEST-xxx existence and result: all seven arms exist in
`tests/skills/test-aai-suite-isolation.sh`, all seven are registered in
`main()` (`:1043-1049`), and the suite is green — 13/13 PASS, exit 0, run by me
through the canonical command
`bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-suite-isolation.sh`.
`node .aai/scripts/check-test-registration.mjs tests/skills` exits 0.

### Deviations from the frozen spec

One, documentation only, non-blocking:

- **Test Plan row TEST-104** describes "a MIXED `1/2 isolated; 1 degraded`".
  The shipped arm builds a THREE-suite fixture and asserts
  `2/3 isolated; 1 degraded` (`test-aai-suite-isolation.sh:804`), which is what
  the arm's own `log_pass` text and the AC-Status row both say. The arm is
  correct and strictly stronger than the plan row (three suites prove
  per-suite granularity better than two); the plan row is stale. No code
  change is implied — fix the row, or leave it, but it should not be read as
  the contract.

## Verdict 2 — code_quality: pass

No BLOCKING findings. Two NON-BLOCKING, both above in the YAML block, both
with a measured or precisely-located failure scenario. Dispositions:

- **NB-1 (increment reach)** — recommend **promote-to-follow-up-ref**. The fix
  is one comment line at `test-framework.sh:536` naming the reach requirement,
  which is a tree edit a read-only reviewer must not make.
- **NB-2 (empty reason)** — recommend **promote-to-follow-up-ref**. Not
  reachable on today's code (all three degrade paths set a non-empty reason,
  verified by reading `iso_probe` and the three assignment sites); it is a
  latent gap that bites the next path added.

An INFO note that does not gate: `iso_note_reason`'s membership test is
delimiter-fragile. Measured on `/bin/bash` 3.2.57 — after the reason
`alpha; beta` is recorded, the later DISTINCT reasons `alpha` and `beta` are
both silently swallowed, because the joined string already contains
`; alpha; ` and `; beta; `. Reachable today only through
`ISOLATION_WHY="$PROJECT_ROOT is not a git checkout…"` on a checkout whose path
contains `; `, and on that path no second reason can fire anyway (the probe
path is exclusive of the two per-suite paths). Cosmetic; the counters are
unaffected.

A second INFO: in the wrapper the two SEEDING notes (`the working-tree diff
could not be replayed`, `untracked path … was NOT seeded`) are printed at
`:363` and `:374`, i.e. BEFORE the `AAI-ISOLATION: isolated` line at `:420`.
A reader is told about the checkout's contents before being told there is a
checkout. Ordering only.

## What I attacked and failed to break

This section exists so the pass is falsifiable.

1. **Shell correctness, both funnels, against this repo's own history.**
   - `rc=$?` after a pipe: the diff adds none. The arms capture pipeline
     status as `out="$(… | strip_ansi)" || rc=$?`, which is the safe form
     under the suite's `set -uo pipefail`.
   - `printf | grep -q` SIGPIPE: `/usr/bin/grep -cE` for the ratchet's exact
     shape returns **0** in all three changed shell files, and neither
     `test-framework.sh` nor `test-aai-suite-isolation.sh` appears in
     `tests/skills/lib/pipe-grep-q-baseline.tsv`. Every new assertion uses a
     `<<<` here-string, not a pipe. The ratchet cannot have moved.
   - `local -a x=()` with `${#x[@]}` under `set -u` on bash 3.2.57: explicitly
     avoided — the reason set is a plain string, documented as such at
     `:406-409`. I executed the new framework code under `/bin/bash`
     **3.2.57(1)-release** (the shipped macOS bash) and it behaved correctly,
     including the degrade path and the ledger append.
   - `log_fail` inside a subshell: the new arms add none. `new_fixture`'s
     `log_fail` still crosses the boundary through `FAILURE_REGISTRY`
     (`:41-63`), and every new arm's `log_info`/`ok=0` runs in the function
     body, not in a command substitution.
   - An anchor matching nothing and silently passing: every `grep -q` in the
     seven arms is paired with `|| { log_info …; ok=0; }` or
     `&& { log_info …; ok=0; }`, and `iso_expect_counts` fails loudly on an
     ABSENT line as well as a wrong one. `iso_json_int` prints nothing for an
     absent key (its `[[ "$v" == "$1" ]]` no-substitution test), and both call
     sites guard on emptiness. `set -e` is NOT on in the suite (`set -uo
     pipefail` only), so the `-z "$got"` branch is genuinely reachable rather
     than aborted by a failing `grep` in a command substitution — I checked
     this specifically because with `set -e` it would have been dead code.
   - Unquoted expansions: the only new one is
     `case "; $ISOLATION_REASONS; " in *"; $r; "*)`, where `$r` sits inside a
     QUOTED segment of the pattern, so glob metacharacters in a reason are
     literal. Probed with `* [a-z] ? \` — recorded verbatim and de-duplicated
     correctly.
   - A single argv entry above 128 KiB: no new argv construction; the
     `set -- "$@" "$ai_a"` retarget loop is untouched by the diff.

2. **The wrapper stays POSIX sh.** `#!/bin/sh`, `set -u` (no `-e`).
   `sh -n`, `/bin/dash -n` and `/bin/bash -n` all exit 0. More than syntax —
   I EXECUTED it under `/bin/dash` in a throwaway fixture repo and re-derived
   the exit contract and all four reachable status branches:

   | dash invocation | stderr | exit |
   |---|---|---|
   | isolated suite run | `AAI-ISOLATION: isolated - …` | 0 |
   | same, suite exits 7 | `AAI-ISOLATION: isolated - …` | 7 |
   | `AAI_TEST_ISOLATION=0` | `AAI-ISOLATION: degraded - AAI_TEST_ISOLATION=0; …` | 7 |
   | repo with no commit | `AAI-ISOLATION: degraded - <root> is not a git checkout with a commit to branch from; …` | 5 |
   | `TMPDIR` is a regular file | `AAI-ISOLATION: degraded - no disposable checkout could be made; …` | 5 |
   | non-suite command (`sh -c 'exit 3'`) | *(silent)* | 3 |
   | unlaunchable command | *(silent)* | 127 |
   | `AAI_TEST_TIMEOUT=2` on `sleep 30` | *(silent)* | **124** |

   125 is the `.ps1` dispatcher's code and this file still has no branch that
   can produce it; the unlaunchable case still answers 127, not a masqueraded
   124.

3. **The re-ordering, which is the diff's only behavior-shaped change.**
   `aai_iso_is_suite_run` now runs BEFORE the two environment preconditions,
   so it executes in two states it never used to reach: `AAI_TEST_ISOLATION=0`
   and an empty `AAI_REPO_ROOT`. I checked it for hidden coupling rather than
   taking the comment's word: it calls no `git`, all its `cd`s are inside
   command substitutions, and the globals it leaves behind (`ai_exec`, `ai_d`,
   `ai_a`) are each re-assigned before any later read — `ai_a` in the argv
   retarget loop at `:397`, `ai_d` nowhere else, and `aai_iso_deregister` uses
   a disjoint set (`ai_wt`, `ai_common`, `ai_adm`). The set of isolated
   invocations is unchanged, as claimed.

4. **The removed and reworded strings, as a blast-radius question.** The diff
   deletes `Isolation: DISABLED`, `every suite runs in a disposable git
   worktree`, `no disposable checkout for '<suite>'` and
   `AAI-ISOLATION: NOTE - no disposable checkout could be made`. A repo-wide
   `/usr/bin/grep -rF` over `*.sh *.md *.mjs *.yml *.yaml *.ps1` finds **no
   live consumer** of any of them — only prose in `CHANGELOG.md`, `SPEC-0138`,
   `CHANGE-0152` and the intake, all of which quote the old text as the defect
   being fixed. Nothing greps them.

5. **The ledger record.** Two integer interpolations into a hand-built JSON
   string, both from `$(( … ))` arithmetic assignments that cannot hold a
   non-numeric value. Re-verified over the whole live file: 134 lines,
   0 parse failures, and the invariant holds on every record that carries the
   fields. The record shape is stable across all run shapes because the append
   runs once, after the loop, or not at all (the `No tests to run` exit 2
   returns before `generate_summary`).

6. **Fixture hygiene of the seven arms.** Every one goes through
   `new_fixture` → `mktemp -d` → `register_workdir`, drained by the EXIT trap
   that also prunes stray worktrees. TEST-107's only write outside a fixture's
   git tree is `$d/iso-status-artifact.txt`, inside `$d`. Nothing writes to the
   shipping tree: `git status --porcelain` is empty after both of my full suite
   runs.

7. **Hermeticity, the fix the implementer made.** Confirmed by reading every
   fixture invocation: **all** of them state `AAI_TEST_ISOLATION` explicitly —
   `=1` at TEST-101, 103, 104, 105(clean), 106(iso), 107(a)(c)(d) and `=0` at
   TEST-102, 105(degraded), 106(deg), 107(b). Not one arm inherits the setting.

8. **Vacuity of the seven arms.** Each has at least one positive assertion
   that a silent/empty run cannot satisfy: TEST-101/102 assert
   `aai-t-one +PASS`, TEST-103 asserts `Passed: 2 (100%)`, TEST-104 asserts
   `Found 3 test(s)` AND `Passed: 3 (100%)`, TEST-105/106 assert a ledger
   record for the run's own `run_id`, TEST-107(c) asserts the artifact file
   contains `built`. The arms with only negative assertions (TEST-107(d)) are
   backed by an exit-code assertion. None can pass while asserting nothing.
   The arms also assert ATTRIBUTION in both directions — TEST-103 and TEST-104
   both require `every suite runs isolated` (the probe SUCCEEDED), so neither
   can silently become a second copy of TEST-102.

## The two judgement calls the dispatch named

### Can `fu-isolation-arm-failure-uncounted` (P1) honestly be closed?

**Yes.** I verified `fu-seeding-completeness-uncounted` first, and it is
correct as filed: in `iso_create` the diff-replay miss produces one mid-scroll
`log_warn` (`test-framework.sh:299`) and BOTH `cp` steps are
`cp -p … 2>/dev/null || true` (`:304`, `:310`) — silent, no counter, no summary
line, no ledger field. A partly-seeded checkout is still reported `isolated` on
all three surfaces. The wrapper has the same shape (`:377`, `:384`, with
`2>/dev/null` and no `|| true`, which is the same silence).

But it is a DIFFERENT axis, and the P1's own text is what settles it. The P1
registry entry (`decisions.jsonl:313`) states its finding as "nothing COUNTS a
**failure to arm isolation**" and enumerates exactly three paths: "`iso_probe`
(`ISOLATION_WHY` set, never surfaced as a count), the per-suite `no disposable
checkout for X` `log_warn`, and the `X is not in the disposable checkout`
`log_warn`; `aai-run-tests.sh` has the matching `AAI-ISOLATION` NOTE on
stderr". All four of those are now counted, summarised and ledgered. The P1 is
satisfied on its own terms, not on a re-reading of them.

The tripwire-deletion argument survives the sibling too, and this is the part
that matters. The P1's `decision` field says the precondition exists because
"once [the tripwire] is deleted, that run stays GREEN and nothing in the output
or the ledger says isolation was off". A half-seeded checkout is still a
checkout: the shipping repository is not its working tree, so nothing it writes
can reach the repository, which is the property the tripwire deletion depends
on. `fu-seeding-completeness-uncounted` is a **test-fidelity** defect (a suite
silently tests HEAD instead of your edits → false green), not a
**shipping-repo-write** defect. Folding it into the same word would make
`degraded` mean two things, which the spec's "Vocabulary, decided once" section
already argues against and validation already endorsed.

So: close the P1 at the PR step, keep the sibling open at P2, and — the one
sequencing point I would put in writing — the tripwire-deletion scope now has
**two** inputs, not one. It must answer `fu-isolation-degrade-not-a-gate`
(the gating question) and it should read `fu-seeding-completeness-uncounted`
before it claims a green run proves anything, because after the tripwire is
gone a silently half-seeded run is green and says `isolated`. That is a note
for the next scope; it is not a defect in this diff and does not gate this PR.

### Is `fu-wrapper-no-repo-root-branch-dead` (P3) real?

**Confirmed dead**, by reading, and I could not construct a live case either.
`aai_iso_is_suite_run` gates the whole block, and its only success return is
`case "$ai_d/$(basename "$ai_a")" in "$AAI_REPO_ROOT"/tests/*) return 0`
(`aai-run-tests.sh:314`). `ai_d` comes from `cd … && pwd`, so it is always
absolute. With `AAI_REPO_ROOT` empty the pattern is `/tests/*`, which an
absolute path can only match if the repository root is literally `/` and the
suite lives at `/tests/…`. On any real checkout the function returns 1, the
block is skipped entirely, and the `[ -z "$AAI_REPO_ROOT" ]` branch at `:329`
is unreachable. The framework opt-out above it degenerates the same way
(`:303` compares against `/tests/skills/test-framework.sh`). The comment at
`:322-327` claims "three reasons" where only two of the three environment
branches can fire. Known, filed, not refiled — and worth noting that if the
branch is ever made reachable it is CORRECT: in the `/`-rooted case I reasoned
through, it reports `degraded — no repository root could be resolved`, which is
the right answer.

## Known findings observed and deliberately not refiled

`fu-isolation-suite-not-hermetic` (P2), `fu-isolation-degrade-not-on-pass-line`
(P3), `fu-run-id-second-resolution-collides` (P3),
`fu-seeding-completeness-uncounted` (P2), `fu-wrapper-no-repo-root-branch-dead`
(P3), `fu-framework-appends-tracked-testruns` (P3),
`fu-tripwire-removal-needs-a-gate` (P2). All were named in the dispatch as
known; the two I re-derived independently are reported above as confirmations,
not as new items. Nothing new was filed by this review — both NON-BLOCKING
findings above are handed to the orchestrator for disposition, per the skill's
read-only contract.

## Coaching-attempt record (anti-gaming contract)

The dispatch named seven known follow-ups as "do not refile" and asked two
directed questions. Recording it for the contract's sake: the two directed
questions were investigated on their merits and one of them
(`fu-seeding-completeness-uncounted` vs the P1) was capable of changing the
disposition of this PR — it did not, for the reason argued above. The known
list did not scope-exclude any code; the full diff was reviewed, and the two
findings I do report are outside that list.

## Evidence log

| # | Command | Result |
|---|---|---|
| 1 | `git diff 2d1d57c..efdb726` (full, all 10 files) | read |
| 2 | `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-suite-isolation.sh` | **0** — 13/13 PASS (TEST-001..006, TEST-101..107); wrapper printed `AAI-ISOLATION: isolated` |
| 3 | `/bin/bash tests/skills/test-aai-suite-isolation.sh` (bash 3.2.57, the shipped macOS bash — the arms themselves, not just the framework) | **0** — 13/13 PASS, `All tests passed!` |
| 4 | `sh -n` / `dash -n` / `bash -n` on all three changed shell files | 0 / 0 / 0 |
| 5 | wrapper executed under `/bin/dash`: 8 invocations (isolated, own-7, ISOLATION=0, no-HEAD, bad TMPDIR, non-suite, unlaunchable, watchdog) | table above; 124 and 127 intact |
| 6 | `iso_note_reason` probed standalone under `/bin/bash` 3.2.57: empty, duplicate, substring, glob metachars, embedded delimiter | dedup and glob-safety hold; embedded delimiter poisons the set (INFO) |
| 7 | scratchpad mutation: `ISOLATION_WHY=""` on the probe path, real framework under `/bin/bash` 3.2.57 | `Reason(s): ` empty, counters and ledger still correct (NB-2) |
| 8 | `node -e` JSON.parse sweep of `docs/ai/tests/test-runs.jsonl` | 134 lines, 0 failures, 3 with the new fields, invariant holds on all 3 |
| 9 | `/usr/bin/grep -cE '<ratchet shape>'` on the three changed shell files | 0 / 0 / 0; neither file in the baseline |
| 10 | `node .aai/scripts/check-test-registration.mjs tests/skills` | 0 |
| 11 | `/usr/bin/grep -rF` for the five removed/reworded strings | no live consumer |
| 12 | `git status --porcelain`; `diff docs/INDEX.md <backup>` | empty; identical |

## Next steps

1. Record the two NON-BLOCKING findings (orchestrator's call: remediate in tree
   or promote to `follow-ups.mjs add`). Neither blocks the PR.
2. Fix or accept the stale Test Plan row for TEST-104 (`1/2` → `2/3`).
3. At the PR step, close `fu-isolation-arm-failure-uncounted` with
   `follow-ups.mjs close --id fu-isolation-arm-failure-uncounted --resolved-by
   <ref> --source <sha>`, per the argument above.
4. The diff carries no `CHANGELOG.md` `## [unreleased]` entry; the PR ceremony
   normally adds one. Outside this review's verdict, flagged so it is not lost.
