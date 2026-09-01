# Code Review (round 2) — adhoc-probes-unisolated-report-only

```yaml
review:
  scope: "git diff main...HEAD (worktree /Users/ales/Projects/aai-fix-adhoc-probes-unisolated-report-only, branch fix/adhoc-probes-unisolated-report-only; 6 commits 569320d, 41df498, 5699eef, bd1efd2, de3fec6, 393e32a)"
  spec: docs/specs/SPEC-DRAFT-spec-adhoc-probes-unisolated-report-only.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/aai-run-tests.sh:778 (the single `echo \"AAI-ADHOC: $AAI_TW_ROOT ...\"`, reachable only from the `dirty` + `ad-hoc` arm at :766-786); TEST-301 at tests/skills/test-aai-suite-isolation.sh:2200. OWN PROBE in a scratch fixture repo: exactly one `AAI-ADHOC: <fixture root>` stderr line, exit 0." }
      - { ac: Spec-AC-02, call: compliant,
          citation: "the banner and the escalation are both inside `case dirty` (aai-run-tests.sh:766-786) so a clean run reaches neither; AAI_ISO_STATUS stays `not-applicable` for a non-suite invocation (:223) and nothing is printed for that value. TEST-302 at test-aai-suite-isolation.sh:2228. OWN PROBE: clean ad-hoc run emitted zero AAI-ADHOC and zero AAI-ISOLATION lines." }
      - { ac: Spec-AC-03, call: compliant,
          citation: ".aai/scripts/lib/repo-tripwire.sh:167 (`tw_remediation=\"${5:-A suite must run against a fixture, never against PROJECT_ROOT.}\"`) + :202 (`printf '%s   %s\\n'`). INDEPENDENTLY PROVED byte-identity at the library level, not just by test: I ran `main`'s aai_tripwire_report and HEAD's over the same before/after snapshot pair with 4 args and `cmp` reports the outputs identical. All three external callers pass exactly 4 args (tests/skills/test-framework.sh:1274, :1605; tests/skills/test-aai-repo-tripwire.sh:409), so EVERY non-ad-hoc caller takes the default path by construction. TEST-303(b) pins the suite leg end-to-end; TEST-306(a) (new this round) pins the framework leg." }
      - { ac: Spec-AC-04, call: compliant,
          citation: "aai-run-tests.sh:784 gates the escalation on `${AAI_SHIPPING_WRITE_FATAL:-0}` = 1, so unset changes nothing; TEST-304 at test-aai-suite-isolation.sh:2290. OWN PROBES: flag unset, dirty ad-hoc exiting 0 -> wrapper 0; exiting 7 -> wrapper 7." }
      - { ac: Spec-AC-05, call: compliant,
          citation: "aai-run-tests.sh:784-786 (`STATUS=12` only when the wrapped status is 0); TEST-305(a-d) at :2310 and TEST-306(a)/(b) at :2370 for the `or of test-framework.sh` clause that had no arm in round 1. OWN PROBES: flag set + dirty + 0 -> 12; flag set + dirty + 7 -> 7; flag set + clean -> 0." }
      - { ac: Spec-AC-06, call: compliant,
          citation: ".aai/scripts/follow-ups.mjs:733 extractHeadingClaims, :775 extractInlineClaims, :812 extractClaims (union, deduplicated); TEST-024 at tests/skills/test-aai-follow-ups.sh:1547." }
      - { ac: Spec-AC-07, call: compliant,
          citation: "follow-ups.mjs:745-765 — labelled segments, the `none` sentinel short-circuit at :751, the any-other-unlabelled fallthrough at :752. TEST-025 asserts the four branches by EXACT set, not count. Two shapes outside the AC's own four-branch wording are mishandled (N2, N3 below); neither contradicts the AC as written." }
      - { ac: Spec-AC-08, call: compliant,
          citation: "follow-ups.mjs:902-918 (MISS for absent/non-done, ATTRIBUTION for done-but-unrelated) and :940 (only MISS, and only under --strict, moves the exit code); TEST-026. OWN real-corpus run: 10 ATTRIBUTION notes present, exit 0." }
      - { ac: Spec-AC-09, call: compliant,
          citation: "OWN RUNS against the live ledger: report-only with 3 MISSes -> exit 0; `--strict` -> exit 1; `--path` at a nonexistent file -> exit 2. TEST-027. The `--strict=<value>` spelling silently means report-only (N1 below), a usage-error form this AC does not enumerate." }
      - { ac: Spec-AC-10, call: compliant,
          citation: "follow-ups.mjs:872-876 (union of docs/specs and docs/issues) and :884-887 (an unreadable doc contributes zero claims, never an error); TEST-028. OWN real-corpus run: docs_scanned=410, claims=33, exit 0; both roots are flat (no archive subtree) so the recursive walk adds nothing today." }
      - { ac: Spec-AC-11, call: compliant,
          citation: "allowlist at tests/skills/test-aai-follow-ups.sh:1523 (exactly three entries, pinned by name at :1782-1785), the NEW lower-bound floor at :1755-1761, the subset check at :1777, and the negative control at :1786-1791. OWN real-corpus run reports exactly the three declared ids as MISS." }
      - { ac: Spec-AC-12, call: compliant,
          citation: "tests/skills/suite-map.yaml:289-290; TEST-030. OWN RUNS: select-suites.mjs over docs/specs/SPEC-9999-x.md and over docs/issues/CHANGE-9999-x.md each print SELECTED aai-follow-ups." }
      - { ac: Spec-AC-13, call: compliant,
          citation: "docs/ai/decisions.jsonl +2 follow_up_status lines, both `done`, resolved_by=adhoc-probes-unisolated-report-only, source=569320d; `git diff --name-only main...HEAD -- docs/specs/*.md` returns only this scope's own spec, and `--name-status` over all 6 commits shows no other scope's frozen document. The AC's own condition is MET by the delivery; the arm that encodes its second half is defective as written — see BLOCKING B1." }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: tests/skills/test-aai-follow-ups.sh, line: 1849,
          issue: "TEST-031's delivery-diff guard is written as a branch-agnostic, permanent assertion instead of a check on THIS delivery. It runs `git diff --name-only \"$BASE_REF\"...HEAD -- 'docs/specs/*.md'`, filters out only this one scope's own spec filename by literal grep -v (:1850), and calls log_fail on anything left (:1852). log_fail is `echo ...; exit 1` (:71), so the WHOLE aai-follow-ups suite hard-fails. Because the same scope adds `docs/specs/**` to that suite's suite-map row (suite-map.yaml:289), a docs-only diff now selects this suite too — so the arm is not merely present in the full sweep, it is deliberately routed to.",
          failure_scenario: "The very next ceremony-2 scope branches off main and authors docs/specs/SPEC-DRAFT-spec-<anything>.md. `git diff origin/main...HEAD -- docs/specs/*.md` returns that file, grep -v does not match it, other_specs is non-empty, log_fail fires: `FAIL: TEST-031: this scope's diff touches another frozen spec document, which Spec-AC-13 forbids`. PROVED, not reasoned: I cloned this worktree, branched off the scope branch, added one unrelated spec file, and ran `bash tests/skills/test-aai-follow-ups.sh` — EXIT=1 with exactly that message. Every future spec-authoring branch reds this shared suite in every full sweep and in every test-impact-selected CI run, and main itself stays green so nothing catches it before merge." }
      - { rank: NON-BLOCKING, file: .aai/scripts/follow-ups.mjs, line: 433,
          issue: "`--strict` is listed in FLAG_SPECS['verify-closures'] (the VALUE-flag table) while being consumed as a boolean at :492-496. The `--flag=value` escape hatch at :500-506 therefore accepts `--strict=1`, stores the STRING '1', and `opts.strict === true` at :927 rejects it — the gate is silently off. CARRIED from round 1 (N1), already filed.",
          failure_scenario: "A CI step writes `node .aai/scripts/follow-ups.mjs verify-closures --strict=1`, a spelling the CLI's own USAGE documents as general grammar. REPRODUCED against the live ledger this round: `--strict=1` exits 0 with 3 MISSes printed; bare `--strict` on the same input exits 1." }
      - { rank: NON-BLOCKING, file: .aai/scripts/follow-ups.mjs, line: 762,
          issue: "extractHeadingClaims scans only the segments AFTER each label match (`body.slice(labels[i].end, segEnd)`); every fu- id stated in the section body BEFORE the first label is silently dropped. CARRIED from round 1 (N4), already filed.",
          failure_scenario: "REPRODUCED with a fixture this round: a section reading `This scope closes \\`fu-before-any-label\\` outright.` above a `CLOSED FULLY:` block reports only `fu-after-the-label`. The headline claim is then unverified behind a green gate — fu-spec-closes-claim-unverified reintroduced in a narrower shape." }
      - { rank: NON-BLOCKING, file: .aai/scripts/follow-ups.mjs, line: 872,
          issue: "Corpus mode resolves both roots against `process.cwd()` (`path.resolve(process.cwd(), 'docs/specs')`) and says nothing when BOTH resolve to nothing — it prints `docs=0 claims=0 miss=0` and exits 0 even under `--strict`. NEW this round at the TOOL level: round 1 named this cwd behaviour only inside N2's failure scenario, and the N2 remediation put the floor in TEST-029 (the test), leaving the CLI itself unchanged.",
          failure_scenario: "REPRODUCED: from an empty scratch directory, `node <repo>/.aai/scripts/follow-ups.mjs verify-closures --ledger <repo>/docs/ai/decisions.jsonl --strict` prints `verify-closures: docs=0 claims=0 miss=0 attribution=0 ok=0` and exits 0. An operator or a future CI step that invokes the documented `--strict` form from anywhere other than the repository root gets a live-looking gate that can never fail. The in-repo ratchet is safe (TEST-029 cds to PROJECT_ROOT and now floors docs>100), so this is the operator-facing surface only." }
      - { rank: NON-BLOCKING, file: .aai/scripts/follow-ups.mjs, line: 739,
          issue: "The claim-section boundary is `rest.search(/\\n##[ \\t]+/)`, which does not match `###`, so a nested sub-section stays inside the claim body and every fu- id in it becomes a claim. CARRIED from round 1 (N5), accepted residual there.",
          failure_scenario: "REPRODUCED this round: a `### An unrelated sub-section` under the claim heading contributed `fu-swallowed-by-subheading` as a claim alongside the real one. False-MISS direction, so Spec-AC-11's subset ratchet contains the blast radius — TEST-029 would red and force a reviewed allowlist update rather than pass silently." }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-run-tests.sh, line: 778,
          issue: "`echo \"AAI-ADHOC: $AAI_TW_ROOT ...\"` in a `#!/bin/sh` script. On a dash /bin/sh — the Debian/Ubuntu CI leg SPEC-0062 targets — `echo` interprets backslash escapes in the interpolated repository path. CARRIED from round 1 (N7), accepted residual there.",
          failure_scenario: "A repository path containing a backslash renders a mangled banner on the Linux CI leg. Identical shape to the pre-existing AAI-TRIPWIRE NOTE line at :808, and no realistic path on that leg carries one; `printf '%s\\n'` would be strictly safer." }
  cannot_verify:
    - { claim: "RR-1 — the ad-hoc banner and the AAI_SHIPPING_WRITE_FATAL opt-in on the Windows legs (aai-run-tests.ps1 -> WSL, and the Git-Bash degraded leg). Also unverified: whether the new AAI-ADHOC stderr line displaces `AAI-BRANCH: WSL` across the WSL1 boundary the way the tripwire NOTE line once did (aai-run-tests.sh:802-806 records that exact history).",
        closes_with: "A run of TEST-301..306 on the WSL leg plus a field-verified Git-Bash capture, recorded in the SPEC-0046 platform matrix. Every probe I ran was macOS." }
    - { claim: "That the close ceremony will restore correct per-AC Evidence atomically with the frontmatter flip. bd1efd2 reverted all 13 Status cells to `implementing` AND all 13 Evidence cells to `—` (deliberately, to keep docs-audit CLEAN per VALIDATION step 8a), so the AC table currently carries zero evidence citations; the evidence lives only in the two validation reports, this report, and commit 41df498's reverted text.",
        closes_with: "The close-ceremony commit showing 13 `done` rows whose Evidence cells carry the TEST ids, the RED/GREEN log paths and the commit SHA, together with the frontmatter status flip." }
    - { claim: "The aggregate CI cost of routing every docs/specs/** and docs/issues/** change through the aai-follow-ups suite (suite-map.yaml:289-290), whose TEST-029 and TEST-031 arms both hit the live repository.",
        closes_with: "A few sweeps' worth of selected-suite counts and wall-clock in docs/ai/tests/test-runs.jsonl compared against the pre-change baseline. Intended by Spec-AC-12; noted, not disputed." }
    - { claim: "That TEST-029's real-corpus ratchet will not red during the ordinary window between a future scope's spec freeze and its ledger close step. By D10's own design a NEW unverified claim reds, and a spec states its `CLOSED FULLY` claim before `follow-ups.mjs close` runs — so the suite is expected to be red for part of every future scope's implementation phase.",
        closes_with: "One future scope run end to end, with the sweep results recorded at spec-freeze time and again after the close step. Spec-intended behaviour (Spec-AC-11 + D10), so recorded as a named gap rather than a finding." }
    - { claim: "Stability of the full-sweep result. This round measured 84 total / 84 passed / 0 failed, but a single sweep cannot distinguish a stable 84/84 from a run that happened to miss the known test-aai-run-tests TEST-005 reaper flake. The same run's RUN-LEVEL exit was 1 because I wrote this report into the worktree while the sweep was in flight and tripped the concurrency tripwire — self-inflicted, but it means the run was not a pristine one.",
        closes_with: "Two or three consecutive sweeps at the same head with nothing else writing to the worktree." }
  overall: fail
```

## Scope and spec

- Diff scope: `git diff main...HEAD` inside the worktree
  `/Users/ales/Projects/aai-fix-adhoc-probes-unisolated-report-only`,
  branch `fix/adhoc-probes-unisolated-report-only`, 6 commits
  (569320d, 41df498, 5699eef, bd1efd2, de3fec6, 393e32a).
- Preflight: I read `docs/ai/STATE.yaml` myself — `worktree.user_decision:
  worktree`, base ref `main`. `git status --porcelain` is EMPTY at review
  time and again after every probe I ran (all fixtures were built in a
  scratch directory, never in the worktree). Exactly one scope, no unrelated
  dirty changes.
- Spec: `docs/specs/SPEC-DRAFT-spec-adhoc-probes-unisolated-report-only.md`,
  SPEC-FROZEN: true, ceremony_level 2, read in full.
- 15 files changed, +1804/-22.

## Dispatch note (ANTI-GAMING CONTRACT)

The dispatch briefing named round 1's BLOCKING finding and all seven of its
NON-BLOCKING findings by id, restated their agreed dispositions, and stated an
expected sweep outcome ("ideally 84/84/0"). That is closer to characterizing
expected findings than the contract allows, even though the same briefing
explicitly told me to review the full scope fresh and to say so if I felt
coached. Recording it here as required. I re-derived every carried finding
from the code myself (each one is marked REPRODUCED above with the command I
ran), reviewed the whole diff rather than the delta, and the BLOCKING finding
this report raises is one the briefing did not anticipate and round 1 did not
find.

## Round-1 remediation: verified, not trusted

### Round 1's BLOCKING finding — GENUINELY FIXED

`aai-run-tests.sh:722` now captures `AAI_CMD_REAL_STATUS=$STATUS` immediately
after `wait "$CMD_PID"; STATUS=$?` (:714-715), before the only line in the
script that can overwrite `$STATUS` (the escalation at :785). The friction
call at :819-820 reads `AAI_CMD_REAL_STATUS`, never `$STATUS`. `set -u` is
active (:76) and the new variable is assigned on the only path that reaches
its reader, so there is no unset-variable hazard; it is not exported, so a
wrapped command cannot see or collide with it.

I did not take that on the diff's word. I built a scratch fixture repo
carrying byte copies of the wrapper, `lib/repo-tripwire.sh`,
`aai-friction.mjs` and `lib/aai-redact.mjs`, and ran the exact TEST-305(e)
scenario:

| wrapper | scenario | wrapper exit | spool lines |
|---|---|---|---|
| HEAD (fixed) | flag set, ad-hoc dirty, wrapped exits 0 | 12 | **0** |
| B1 wiring reverted (pre-fix) | same | 12 | **1** — `"failure_class":"deterministic_script_failure"` |

The pre-fix record is exactly the false observation round 1 described. So
TEST-305(e) (test-aai-suite-isolation.sh:2339-2364) is a genuine RED-proofed
regression test, not a test written to pass.

I also checked the fix did not break the case it must preserve:

| scenario | wrapper exit | spool lines |
|---|---|---|
| flag set, ad-hoc dirty, wrapped exits 7 | 7 | 1 (correct — it really failed) |
| flag unset, ad-hoc clean, wrapped exits 7 | 7 | 1 (correct, unchanged baseline) |
| flag unset, ad-hoc dirty, wrapped exits 0 | 0 | 0 |

No var-scoping issue, no race (both assignments are in the same shell, no
subshell), and the watchdog path is untouched — `TIMED_OUT` is still checked
before `STATUS` at :815, so 124 still outranks 12.

### N2 (vacuous ratchet) — FIXED, and the floor is real

`test-aai-follow-ups.sh:1755-1761` adds `docs_scanned > 100 && counts.claims
> 10` before the subset check. Measured against the real repository this
round: `docs_scanned=410, claims=33`. The floor is a genuine lower bound
(a scan that finds nothing now fails loudly) and is not flake-prone — the
corpus would have to shrink by 76% (docs) or 70% (claims) to trip it. Not
itself vacuous: I confirmed the two guarded quantities are the ones the
failure mode zeroes.

### N3 (duplicated framework predicate) — FIXED, with a real new arm

`aai_iso_is_framework_script()` is a genuinely extracted helper
(aai-run-tests.sh:331-341), called from `aai_iso_is_suite_run` (:358) and
from the kind classification (:592). The two former copies are gone; the dead
`ai_exec`/`ai_d` locals from the old inline copy are removed and nothing else
reads them. The classification call is correctly guarded by
`[ "$AAI_INVOCATION_KIND" != 'suite' ]`, which matters: `set -- "$@" "$ai_a"`
at :576 retargets `"$@"`, and that loop is nested three `fi`s deep inside the
`aai_iso_is_suite_run` branch, so a non-suite invocation reaches :592 with
`"$@"` unmodified. TEST-306 (test-aai-suite-isolation.sh:2370) is a real new
arm with two legs (dirty framework run keeps its own exit 1 and the suite
sentence with no AAI-ADHOC; clean framework run under the flag stays at 0,
never 12). Every helper it calls exists in the file.

### N6 (stale usage message) — FIXED

`follow-ups.mjs:452`. Verified by running it: `verify-closure` (singular)
now prints `unknown subcommand "verify-closure" (expected list, add, close or
verify-closures)` — all four subcommands.

### The two filed follow-ups — clean and correctly formed

`docs/ai/decisions.jsonl` gains exactly two `type: follow_up` lines, both
`ref_id: adhoc-probes-unisolated-report-only`, both
`source: docs/ai/reviews/review-20260901T111253Z-adhoc-probes-unisolated-report-only.md`:
`fu-verify-closures-strict-value-off` (P2) and
`fu-verify-closures-claim-before-label` (P3). Not duplicated, not malformed
(the ledger folds them and `verify-closures` runs over the same file at exit
0). Neither appears in the `verify-closures` corpus report, which is correct
and answers the dispatch's question: `verify-closures` reports ids CLAIMED by
a document, and no document claims these two. The MISS set is still exactly
the three measured entries.

## New this round — BLOCKING B1

`tests/skills/test-aai-follow-ups.sh:1842-1855`. TEST-031's second half is
meant to assert something about THIS scope's delivery diff (Spec-AC-13: "the
delivery diff SHALL contain no other scope frozen document"). It is written
as a permanent, branch-agnostic comparison against whatever `BASE_REF...HEAD`
happens to be, with only this scope's own spec filename filtered out by a
literal `grep -v`.

Proof, not inference. In a clone of this worktree I branched off the scope
branch, added one unrelated spec file, and ran the suite standalone:

```
$ bash tests/skills/test-aai-follow-ups.sh
...
FAIL: TEST-031: this scope's diff touches another frozen spec document,
which Spec-AC-13 forbids: docs/specs/SPEC-DRAFT-spec-a-future-unrelated-scope.md
EXIT=1
```

`log_fail` is `echo ...; exit 1` (:71), so this is a hard failure of the whole
`aai-follow-ups` suite, not a soft note. The same scope adds `docs/specs/**`
and `docs/issues/**` to that suite's `suite-map.yaml` row (:289-290), so the
suite is now selected for exactly the diffs that trip it.

Why nothing catches it before merge: on `main`, `BASE_REF...HEAD` is empty, so
main stays green; on THIS branch the only spec in the range is the one the
`grep -v` removes, so this round's own sweep is green. The failure lands on
the next scope's branch.

The AC itself is satisfied by the delivery — I checked
`git diff --name-only main...HEAD -- docs/specs/*.md` and `--name-status`
across all six commits, and no other scope's document is touched. This is a
defect in how the assertion is encoded, not a compliance gap, which is why
spec_compliance passes and code_quality fails.

## Guardrail re-check (all 6 commits)

- `protected_paths_l3` (docs/ai/docs-audit.yaml: state.mjs, lib/state-engine.mjs,
  lib/state-core.mjs, allocate-doc-number.mjs, pre-commit-checks.sh/.ps1,
  .aai/workflow/WORKFLOW.md, docs/CONSTITUTION.md): **zero touched**.
- `.aai/*.prompt.md`: **zero files changed**, so zero byte growth (D10's
  "spends zero prompt-corpus bytes" holds).
- New file under `.aai/scripts/`: **none** (`--diff-filter=A` over
  `.aai/scripts/*` is empty). Both new files in the diff are
  `docs/ai/reviews/review-20260901T111253Z-...md` and the spec.
- Scope creep across the two remediation commits: de3fec6 touches only
  aai-run-tests.sh, test-aai-suite-isolation.sh and the leak baseline;
  393e32a touches only follow-ups.mjs (one line), test-aai-follow-ups.sh
  (14 lines), and ledger/telemetry/report/INDEX bookkeeping. No creep.
- No new gitignored runtime sidecar; `verify-closures` is read-only and adds
  no load/write/stale/claim/GC surface (SIDECAR LIFECYCLE rule N/A).
- `check-cd-subshell-leak.mjs`: exit 0, UNSAFE 0, baseline current.

## Verification I ran myself

| Command | Result |
|---|---|
| `node .aai/scripts/follow-ups.mjs verify-closures --json` | exit 0; docs_scanned=410, claims=33, miss=3, attribution=10, ok=20; MISS set exactly the three declared entries |
| `node .aai/scripts/docs-audit.mjs --check --strict --no-event` | exit 0, **Verdict: CLEAN** |
| `node .aai/scripts/spec-lint.mjs` | exit 0 |
| `node .aai/scripts/check-cd-subshell-leak.mjs` | exit 0, UNSAFE 0 |
| `select-suites.mjs` over `docs/specs/*.md` and `docs/issues/*.md` | both SELECT aai-follow-ups |
| library byte-identity: `main` vs HEAD `aai_tripwire_report`, 4 args | `cmp` identical |
| TEST-305(e) scenario, HEAD wrapper vs B1-reverted wrapper | 0 spool lines vs 1 — RED proved |
| TEST-031 on a simulated future spec-authoring branch | **EXIT 1** (BLOCKING B1) |
| `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-suite-isolation.sh` | exit 0, all passed, TEST-301..306 all PASS |
| `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-follow-ups.sh` | exit 0, all passed, TEST-024..031 all PASS |
| `AAI_TEST_TIMEOUT=3600 bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh` | **84 total, 84 passed, 0 failed**, 84/84 isolated, 84/84 seeded (run_id test-20260901-123526). Run-level exit 1 — see below |

Full-sweep suite verdicts are **84/84/0**, better than main's own baseline
(84/78/6, run test-20260831-212557) and better than round-2 Validation's
84/83/1. Every one of the 84 suites passed, including
`test-aai-run-tests` — the pre-existing TEST-005 reaper flake did not appear.

The RUN's exit code was nonetheless 1, and the reason is mine, not the
scope's: the framework's concurrency tripwire reported the shipping
repository dirty during one 8-wide wave, discarded that wave and re-ran it
serially, and the violation block names exactly the two files I created while
the sweep was in flight —

```
AAI-TRIPWIRE   now:  M docs/ai/tests/test-runs.jsonl
AAI-TRIPWIRE   now: ?? docs/ai/reviews/review-20260901T124922Z-adhoc-probes-unisolated-report-only-round2.md
```

— this report file, written into the worktree mid-run. Reviewer error; no
suite reproduced the change alone because no suite made it. The 84 serial
verdicts above are the ones the framework itself says it reports. Recorded
rather than hidden, and it is why the `cannot_verify` list carries a
sweep-stability entry.

Note on the sweep command: the spec's own Verification section lists
`bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh`
without a timeout override. Run exactly as written it dies at the wrapper's
300s default watchdog (`TIMEOUT="${AAI_TEST_TIMEOUT:-300}"`,
aai-run-tests.sh:78) with exit 124 about 8 suites in — I reproduced that
before re-running with `AAI_TEST_TIMEOUT=3600`, the same value round-2
Validation used. Pre-existing operator-side ergonomics, not this scope's
defect, and not raised as a finding.

## WARNINGS POLICY dispositions (H6)

| # | Finding | Disposition | Artifact |
|---|---|---|---|
| N1 | `--strict=<value>` silently report-only | (b) typed follow_up — ALREADY FILED | decision id `fu-verify-closures-strict-value-off` (P2) |
| N2 | claim stated before the first label is dropped | (b) typed follow_up — ALREADY FILED | decision id `fu-verify-closures-claim-before-label` (P3) |
| N3 | corpus mode is silent from a foreign cwd (NEW) | (b) promote to a typed follow_up, P3 — recommended id `fu-verify-closures-corpus-cwd-silent` | to be filed by the orchestrator (I am read-only on the ledger) |
| N4 | `###` sub-section swallowed into the claim body | (d) accepted residual: P3 assurance-strength only — the false-MISS direction is contained by Spec-AC-11's subset ratchet, which reds and forces a reviewed allowlist update rather than passing silently; no bite observed, no false record left anywhere | this report |
| N5 | `echo` instead of `printf` in a `#!/bin/sh` script | (d) accepted residual: P3 maintenance only — identical shape to the pre-existing AAI-TRIPWIRE NOTE line at :808, needs a backslash in the repository path to bite, and no realistic Linux CI path carries one | this report |

## Next steps

1. Fix BLOCKING B1. The assertion needs to be pinned to this delivery rather
   than to "whatever the current branch is" — for example by comparing a
   fixed commit range, by scoping the check to the branch/ref this scope owns,
   or by moving the one-shot delivery check out of a permanent suite arm and
   into the validation record. Whatever shape it takes, it must be RED-proved
   on the simulated future-branch scenario above (add one unrelated spec on a
   branch, run the suite, observe it stay green) before it is called fixed.
2. File N3 as a typed follow_up.
3. Re-review after remediation, then close out.
