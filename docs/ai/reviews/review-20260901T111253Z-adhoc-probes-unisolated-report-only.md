# Code Review — adhoc-probes-unisolated-report-only

```yaml
review:
  scope: "git diff main...HEAD (worktree fix/adhoc-probes-unisolated-report-only; 4 commits 569320d, 41df498, 5699eef, bd1efd2)"
  spec: docs/specs/SPEC-DRAFT-spec-adhoc-probes-unisolated-report-only.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/aai-run-tests.sh:763; TEST-301 green (own run); own fixture probe: exactly one `AAI-ADHOC: <root>` line on stderr" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "TEST-302 green (own run); the banner lives only inside the `dirty` arm at aai-run-tests.sh:752-771, and AAI_ISO_STATUS stays `not-applicable` for ad-hoc" }
      - { ac: Spec-AC-03, call: compliant,
          citation: ".aai/scripts/lib/repo-tripwire.sh:167 + :202; TEST-303 green. INDEPENDENTLY VERIFIED both byte-identical halves by running main's wrapper+library and HEAD's against the same fixture: suite leg diff empty, test-framework.sh leg diff empty" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "TEST-304 green; own control probe: flag unset, dirty ad-hoc exit 0 -> wrapper 0, exit 7 -> wrapper 7" }
      - { ac: Spec-AC-05, call: compliant,
          citation: ".aai/scripts/aai-run-tests.sh:769-771; TEST-305(a-d) green; own probe: framework run with the flag set and a dirtying command still exits 0 and prints the suite sentence (the clause TEST-305 does not cover)" }
      - { ac: Spec-AC-06, call: compliant,
          citation: ".aai/scripts/follow-ups.mjs:757-793 (extractHeadingClaims/extractInlineClaims); TEST-024 green" }
      - { ac: Spec-AC-07, call: compliant,
          citation: ".aai/scripts/follow-ups.mjs:764-780; TEST-025 four branches, exact set equality, green. See NON-BLOCKING N4/N5 for two shapes the branch rules silently mis-handle" }
      - { ac: Spec-AC-08, call: compliant,
          citation: ".aai/scripts/follow-ups.mjs:820-834; TEST-026 green (one MISS, one ATTRIBUTION, exit 0)" }
      - { ac: Spec-AC-09, call: compliant,
          citation: "TEST-027(a/b/c) green; own runs: report-only 0, --strict 1, missing --path 2. See NON-BLOCKING N1 — `--strict=<value>` is accepted and silently means report-only" }
      - { ac: Spec-AC-10, call: compliant,
          citation: ".aai/scripts/follow-ups.mjs:795-812; TEST-028 green; own real-corpus run: docs_scanned 410, silent docs contribute zero claims, exit 0" }
      - { ac: Spec-AC-11, call: compliant,
          citation: "tests/skills/test-aai-follow-ups.sh:1518-1522 (allowlist, exactly 3) + :1744-1775 (subset ratchet + its own negative control); own real-corpus run reports exactly those 3 as MISS. See NON-BLOCKING N2 — the arm has no lower bound and can pass over an empty scan" }
      - { ac: Spec-AC-12, call: compliant,
          citation: "tests/skills/suite-map.yaml:285-290; TEST-030 green; own run of select-suites.mjs on docs/specs/*.md and docs/issues/*.md both SELECT aai-follow-ups" }
      - { ac: Spec-AC-13, call: compliant,
          citation: "docs/ai/decisions.jsonl +2 lines, byte-prefix of main verified identical by cmp (456979 bytes); own fold: both ids `done`, resolved_by=adhoc-probes-unisolated-report-only; `git diff --name-only main...HEAD -- docs/specs/*.md` returns only this scope's own spec" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/aai-run-tests.sh, line: 770,
          issue: "Forcing STATUS=12 makes the pre-existing aai_capture_friction \"$STATUS\" deterministic_script_failure call at :805 fire for a wrapped command that exited 0, writing a factually false observation into docs/ai/friction/observations.jsonl. Directly contradicts the spec's own D6 (the friction spool is deliberately NOT a second sink). Every new test arm sets AAI_FRICTION_CAPTURE=0, so nothing in the scope can catch it.",
          failure_scenario: "Operator exports AAI_SHIPPING_WRITE_FATAL=1 (the scope's headline opt-in) and runs `bash .aai/scripts/aai-run-tests.sh node scripts/generate.mjs`; the generator writes into the repo and exits 0. Wrapper exits 12 AND appends {\"failure_class\":\"deterministic_script_failure\", ...} to the spool. aai-feedback-triage.mjs:182/232 clusters by failure_class and aai-feedback-upsert.mjs --publish --confirm can turn that cluster into an upstream GitHub issue about a script failure that never happened. Reproduced: rc=12 + one spool line written; control with the flag unset gives rc=0 and zero spool lines." }
      - { rank: NON-BLOCKING, file: .aai/scripts/follow-ups.mjs, line: 433,
          issue: "`--strict` is listed in FLAG_SPECS['verify-closures'] (the VALUE-flag table) while being consumed as a boolean at :490-495. The `--flag=value` escape hatch at :511-517 therefore accepts `--strict=1` and stores the STRING '1', which `opts.strict === true` at :735 rejects — the gate is silently off.",
          failure_scenario: "A CI step or operator writes `node .aai/scripts/follow-ups.mjs verify-closures --strict=1` (a spelling the CLI's own USAGE documents as general grammar). Reproduced against the live ledger: 3 MISSes printed, exit 0. Bare `--strict` on the same input exits 1." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-follow-ups.sh, line: 1746,
          issue: "TEST-029, the real-corpus ratchet, has no lower bound: it asserts only MISS-set ⊆ allowlist plus static facts about the allowlist array itself. An empty MISS set passes (misses_subset_of_allowlist \"\" returns 0 on the blank line), and so does a scan that found zero documents.",
          failure_scenario: "verify-closures resolves docs/specs and docs/issues against process.cwd() (follow-ups.mjs:807-810). Reproduced from a foreign cwd with an absolute --ledger: `docs=0 claims=0 miss=0`, exit 0 even under --strict. Any change that makes the walk return nothing (a cwd change in the harness, a docs-root rename, a regex regression in extractClaims) leaves TEST-029 green with the ratchet dead — the exact silent-guard failure mode this scope exists to close." }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-run-tests.sh, line: 578,
          issue: "The framework-kind block at :578-586 is a verbatim copy of the framework opt-out inside aai_iso_is_suite_run at :341-347 rather than a shared helper, and no automated arm pins the `framework` kind at all (round-2 NB-1's coverage gap). Two bypasses of that opt-out have already been closed in the original (see the comment at :326-338), so the original is a proven site of future edits.",
          failure_scenario: "A third opt-out bypass is closed in aai_iso_is_suite_run only. A real `bash tests/skills/test-framework.sh` run then classifies as ad-hoc: it prints the AAI-ADHOC banner and the ad-hoc remediation line instead of the byte-identical suite block (Spec-AC-03 breaks), and with AAI_SHIPPING_WRITE_FATAL=1 a framework run that succeeded exits 12 (Spec-AC-05 breaks). No suite goes red. NOTE: current behaviour is CORRECT — I hand-probed it from the repo root and from a subdirectory with a relative path; this is drift risk, not a live defect." }
      - { rank: NON-BLOCKING, file: .aai/scripts/follow-ups.mjs, line: 771,
          issue: "extractHeadingClaims scans only the segments AFTER each label match; every fu- id stated in the section body BEFORE the first label is silently dropped. RR-3 explicitly covers the false-MISS direction only; this is the opposite, a false OK.",
          failure_scenario: "A future spec writes its headline claim as prose above the label block ('This scope closes `fu-x` outright.' then 'CLOSED FULLY:' with a different id). Reproduced with a fixture: only the post-label id is reported; `fu-before-any-label` is never checked. The claim is then unverified with a green gate — `fu-spec-closes-claim-unverified` reintroduced in a narrower shape." }
      - { rank: NON-BLOCKING, file: .aai/scripts/follow-ups.mjs, line: 762,
          issue: "The section boundary is `rest.search(/\\n##[ \\t]+/)`, which does not match `###`, so a nested sub-section stays inside the claim body and every fu- id in it becomes a claim.",
          failure_scenario: "Reproduced: a `### An unrelated sub-section` under the claim heading contributed `fu-swallowed-by-subheading` as a claim. False-MISS direction, so the subset ratchet contains the blast radius (TEST-029 would red and the allowlist would need a reviewed update rather than a silent pass)." }
      - { rank: NON-BLOCKING, file: .aai/scripts/follow-ups.mjs, line: 452,
          issue: "usageError('unknown subcommand \"…\" (expected list, add or close)') was not updated when verify-closures was added.",
          failure_scenario: "A user types `verify-closure` (singular) and is told the tool expects 'list, add or close' — the error actively hides the subcommand they were reaching for. Confirmed by reading :450-453; the FLAG_SPECS table on the line above now has four keys." }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-run-tests.sh, line: 763,
          issue: "`echo \"AAI-ADHOC: $AAI_TW_ROOT …\"` in a `#!/bin/sh` script (shebang confirmed at :1). On a dash /bin/sh — the Debian/Ubuntu CI leg SPEC-0062 targets — `echo` interprets backslash escapes in the interpolated repository path.",
          failure_scenario: "A repository path containing a backslash renders a mangled banner on the Linux CI leg. Same shape as the pre-existing AAI-TRIPWIRE NOTE line at :793, and no realistic path on that leg carries one; `printf '%s\\n'` would be strictly safer." }
  cannot_verify:
    - { claim: "RR-1 — the ad-hoc banner and the AAI_SHIPPING_WRITE_FATAL opt-in on the Windows legs (aai-run-tests.ps1 -> WSL, and the Git-Bash degraded leg).",
        closes_with: "A run of TEST-301..305 on the WSL leg plus a field-verified Git-Bash capture, recorded in the SPEC-0046 platform matrix. All of my probes were macOS; `sh -n` and `dash -n` both pass, so the POSIX shape is sound, but no leg was executed." }
    - { claim: "That the close ceremony will restore correct per-AC Evidence atomically with the frontmatter flip. bd1efd2 reverted all 13 Status cells to `implementing` AND all 13 Evidence cells to `—`, so the AC table currently carries zero evidence citations; the evidence lives only in the two validation reports and commit 569320d.",
        closes_with: "The close-ceremony commit showing 13 `done` rows whose Evidence cells carry the TEST ids / RED-GREEN logs / commit SHA the validation reports name, together with the frontmatter status flip." }
    - { claim: "The aggregate CI cost of routing every docs/specs/** and docs/issues/** change through the aai-follow-ups suite (suite-map.yaml:285-290), whose TEST-029/TEST-031 arms hit the live repository.",
        closes_with: "A few sweeps' worth of selected-suite counts and wall-clock in docs/ai/tests/test-runs.jsonl compared against the pre-change baseline. Intended by Spec-AC-12; noted, not disputed." }
  overall: fail
```

## Scope and spec

- Scope: `git diff main...HEAD` inside the worktree
  `/Users/ales/Projects/aai-fix-adhoc-probes-unisolated-report-only`, branch
  `fix/adhoc-probes-unisolated-report-only`, base `main`, 4 commits
  (`569320d`, `41df498`, `5699eef`, `bd1efd2`). 14 files, +1373/−14.
- Preflight: `docs/ai/STATE.yaml` `worktree.user_decision: worktree`, confirmed
  by reading it. `git status --porcelain` shows exactly two modified files,
  `docs/ai/EVENTS.jsonl` (+1 `validation_verdict` line) and
  `docs/ai/tests/test-runs.jsonl` (+1 sweep row) — round-2 validation telemetry,
  append-only, no unrelated dirty change. One clean scope established.
- Spec: `docs/specs/SPEC-DRAFT-spec-adhoc-probes-unisolated-report-only.md`,
  SPEC-FROZEN: true, ceremony_level 2, 13 Spec-AC, 13 TEST ids, D1-D10,
  SEAM-1..4. Read in full.

### Dispatch-coaching note (anti-gaming contract)

The dispatch briefing named the AC-table `implementing` cells as deliberately
deferred and pre-characterised the round-2 `test-framework.sh` coverage gap as
"non-blocking" while asking me to assess it independently. I reviewed the full
diff and reached my own conclusions; the deferral note matched what I found in
`bd1efd2` on inspection, and I independently downgraded the `test-framework.sh`
item to a coverage gap only AFTER hand-probing the behaviour myself (below),
not on the briefing's word. The BLOCKING finding below is one the briefing did
not mention and that both validation rounds saw and dismissed.

## AC walk

All 13 rows are compliant. Every claimed TEST-xxx exists and passes — I ran both
owning suites through the canonical wrapper myself:

- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-follow-ups.sh`
  → "All aai-follow-ups tests passed", including TEST-024..031.
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-suite-isolation.sh`
  → "All tests passed!", including TEST-301..305.

Independent verification beyond the suites (the point of this pass — validation
checked behaviour through the tests; I checked the code and then probed what the
tests do not reach):

- **Spec-AC-03/05, the `test-framework.sh` clauses (round-2 NB-1's gap).** I
  built two fixture repos, one with `main`'s wrapper + library and one with
  HEAD's, ran a dirtying `bash tests/skills/test-framework.sh` through each, and
  diffed the captured stderr: **byte-identical**. Same for a degraded dirtying
  suite run. I also ran the framework leg with `AAI_SHIPPING_WRITE_FATAL=1`:
  exit 0, suite sentence, no `AAI-ADHOC` line — from the repo root and from a
  subdirectory with a relative path. The clauses are correct in fact; what is
  missing is only a pin (finding N3).
- **Spec-AC-13 / decisions.jsonl.** `cmp` of the first 456979 bytes of the
  branch's ledger against `main`'s: identical. `numstat` 2/0. A true append.
- **The cd-subshell-leak baseline (`5699eef`).** `--record` into a scratch file
  and `diff` against the committed TSV: **identical**, so the recorded numbers
  are the exact current counts, not an inflated suppression. The commit changes
  three rows, all three files this scope edits; every other row is untouched.
  `check-cd-subshell-leak.mjs` exits 0 with UNSAFE 0.
- **`bd1efd2`.** Reverts exactly the 13 AC Status/Evidence cells, plus a
  regenerated `docs/INDEX.md` and four appended telemetry rows. Nothing else in
  the spec, no implementation file, no test file. A clean, minimal revert.
- **Guardrails.** Zero `protected_paths_l3` paths touched (list read from
  `docs/ai/docs-audit.yaml:74-82`; none of the eight appears in the diff);
  `git diff --numstat main...HEAD -- '.aai/*.prompt.md' '.aai/**/*.prompt.md'`
  empty, so D10's zero-prompt-bytes claim holds and no diet-ledger entry is
  owed; `--diff-filter=A -- .aai/scripts` empty, so no new script file; the only
  added file in the whole branch is the spec.
- **Repo gates.** `node .aai/scripts/spec-lint.mjs` exit 0;
  `node .aai/scripts/docs-audit.mjs --check --strict --no-event` → **CLEAN**.

## Findings

### BLOCKING — B1: the opt-in exit code writes a false friction record, contradicting D6

`.aai/scripts/aai-run-tests.sh:769-771` sets `STATUS=12`. The pre-existing tail
of the script at `:804-806` then runs
`aai_capture_friction "$STATUS" deterministic_script_failure` because `STATUS`
is now non-zero. `aai_capture_friction` (`:176-197`) fires whenever
`AAI_FRICTION_CAPTURE != 0` and the spool directory exists —
`docs/ai/friction/` **does** exist in this repository — and appends a record
whose `failure_class` is `deterministic_script_failure` and whose
`observed_behavior` reads "wrapped command exited 12".

The wrapped command exited **0**. The record is false on both counts: the
command did not fail, and the class is wrong for what actually happened (a
shipping-repo write).

This contradicts the spec's own D6 verbatim: *"A durable record in
`docs/ai/friction` was designed and declined … a second sink for the same event
is unrequested surface (Constitution article 2) and would put a write on a path
this scope exists to keep quiet."* The implementation ships exactly the sink D6
declined, mislabelled.

Reproduced (fixture repo, spool redirected to scratch so the real spool stays
clean):

```
AAI_SHIPPING_WRITE_FATAL=1 AAI_FRICTION_SPOOL_DIR=$F/spool \
  bash .aai/scripts/aai-run-tests.sh sh -c 'printf x > stray.txt; exit 0'
# wrapper rc=12
# $F/spool/observations.jsonl:
# {"schema_version":2,...,"failure_class":"deterministic_script_failure",...}

# control, flag unset, same command:
# wrapper rc=0, spool files: 0
```

Why this is BLOCKING and not the "harmless, it's gitignored" note round-1 filed
as NB-6: gitignored is orthogonal to whether the record is true or whether
anything reads it. The spool is machine-consumed —
`aai-feedback-triage.mjs:182` validates `failure_class` against the taxonomy and
`:232` propagates it as the cluster's class, and
`aai-feedback-upsert.mjs --publish --confirm` turns a cluster into an upstream
GitHub issue. So the scope ships a path that manufactures false upstream
evidence of a script failure that never occurred. It bites on the feature's own
documented happy path, not an exotic edge, and every new test arm sets
`AAI_FRICTION_CAPTURE=0`, so no test in the scope can ever see it. H6 also names
"anything leaving a false record" as ineligible for the softest disposition —
this repository's own value system treats false records as serious.

Fix shape (small, local): capture the friction observation from the wrapped
command's REAL status before the escalation, or skip the capture on the
escalated path, or give it its own honest class. Any of the three keeps D6.

### NON-BLOCKING

- **N1 (P2) — `--strict=<value>` silently disables the gate.**
  `.aai/scripts/follow-ups.mjs:433` puts `--strict` in the value-flag table
  while `:490-495` consumes it as a boolean, so the `--flag=value` branch at
  `:511-517` accepts `--strict=1` and stores `'1'`, which `:735`
  (`opts.strict === true`) rejects. Reproduced against the live ledger:
  `--strict` → exit 1, `--strict=1` → exit 0 with 3 MISSes printed. It must
  stay in `knownTokens` (so `--path --strict` still errors) — the fix is to
  reject `--strict=` in the `=` branch, or to build `knownTokens` from a
  separate set. The identical shape exists pre-existing for `close --correct=1`
  and is worth folding into the same fix.
  **Disposition: (b) promote to a typed `decisions.jsonl` follow_up, P2.**
- **N2 (P2) — TEST-029 can pass over an empty scan.**
  `tests/skills/test-aai-follow-ups.sh:1744-1775` asserts only
  MISS ⊆ allowlist plus static facts about the allowlist array;
  `misses_subset_of_allowlist ""` returns 0. Reproduced: corpus mode from a
  foreign cwd prints `docs=0 claims=0 miss=0` and exits 0 **under `--strict`**.
  A one-line lower bound (`docs_scanned >= 1 && claims >= 1`, read from the same
  JSON the arm already parses) closes it.
  **Disposition: (a) remediate in tree.**
- **N3 (P2) — duplicated, unpinned framework detection.**
  `.aai/scripts/aai-run-tests.sh:578-586` duplicates `:341-347`. Current
  behaviour is correct (hand-probed, two ways); the risk is drift, and the
  consequence of drift is a silent Spec-AC-03 + Spec-AC-05 regression on the
  framework leg with no red test. Extract one
  `aai_iso_is_framework_script "$@"` helper used by both call sites, and add
  the TEST-306 arm round-2 NB-1 already named.
  **Disposition: (a) remediate in tree; (b) a P2 follow_up if the close is
  time-boxed.**
- **N4 (P3) — claim-parser false negative before the first label.**
  `.aai/scripts/follow-ups.mjs:771`. Reproduced. Leaves a real closure claim
  unverified with a green gate, which is the defect class this scope exists to
  close. Same family as round-1 NB-1/NB-2.
  **Disposition: (b) promote to a typed `decisions.jsonl` follow_up, P3** —
  not (d), because it leaves a class of claim silently unchecked.
- **N5 (P3) — `###` sub-headings do not close the claim body.**
  `.aai/scripts/follow-ups.mjs:762`. Reproduced. False-MISS direction, so the
  subset ratchet contains it and RR-3 already argues that containment.
  **Disposition: (d) accepted residual: P3 assurance-strength, no observed
  bite, blast radius bounded by the subset ratchet which reds rather than
  passes; fold into N4's follow-up if one is filed.**
- **N6 (P3) — stale usage message.**
  `.aai/scripts/follow-ups.mjs:452` still says "expected list, add or close".
  One string. Matches round-1 NB-5.
  **Disposition: (a) remediate in tree.**
- **N7 (P3) — `echo` under `#!/bin/sh`.** `.aai/scripts/aai-run-tests.sh:763`.
  Same shape as the pre-existing line at `:793`, no realistic trigger on any
  supported leg.
  **Disposition: (d) accepted residual: P3 maintenance, identical to an
  existing accepted line in the same file, no observed bite and no false record
  left anywhere.**

### INFO (never gates)

- `.aai/scripts/follow-ups.mjs:800/810/836` — the `seenPerDoc` map can never
  hold a pre-existing entry (docPaths are unique across the two disjoint roots,
  and `extractClaims` already returns a `Set`). Dead dedup machinery.
- `tests/skills/test-aai-follow-ups.sh:1728` and `:1746` capture `--json`
  output with `2>&1`. No stderr is produced today, so no bite; a future
  `loadRegistry` note would make `JSON.parse` throw and red the arm
  confusingly rather than reporting the note.
- `tests/skills/test-aai-follow-ups.sh:1826` re-invokes `test_002_query_path`
  inside TEST-030, so TEST-002 runs twice per suite. Deliberate (SEAM-3),
  cosmetic in the pass counts.

### Things I tried to break and could not

- Catastrophic backtracking in `CLAIM_ID_RE` — the inner group is anchored by a
  mandatory `-` that `[a-z0-9]+` cannot consume, so there is no ambiguity.
  80 000-character adversarial input matched in 0 ms.
- Regex `lastIndex` leakage across documents — `HEADING_RE` has no `g` flag,
  and both `g`-flagged regexes are copied with `new RegExp(...)` per call.
- Injection through document content — claim ids are constrained by the regex
  to `fu-[a-z0-9-]+` and everything reaches only `console.log`; no shell, no
  eval, no template execution.
- `exit()`-without-`return` in `cmdVerifyClosures` — `exit` throws an
  `ExitSignal` (`lib/cli-pipe-guard.mjs`), and no new `usageError` call sits
  inside a `try` block, so every usage path really does terminate at 2.
- POSIX conformance — `sh -n` and `dash -n` both clean on both edited shell
  files; the new code uses only `${5:-…}`, `${var##*/}`, `[ ]` and `$( )`.
- Watchdog/exit-code ordering — `TIMED_OUT` is checked before `STATUS`
  (`:800-807`), and a timed-out command's status is non-zero anyway, so 124
  outranks 12 on both counts.
- A vacuous byte-identity assertion in TEST-303(b) — I re-derived both
  byte-identity claims against `main`'s actual code rather than trusting the
  stored literal.

## Overall

**fail** — spec_compliance passes (13/13 compliant, all 13 TEST ids exist and
green, both byte-identity halves independently re-derived), code_quality fails
on one BLOCKING finding: the opt-in exit-12 path writes a false
`deterministic_script_failure` observation into a machine-consumed spool that
feeds upstream issue drafting, contradicting the scope's own D6.

Next steps: fix B1 with a RED-proofed regression arm (a fixture run with
`AAI_FRICTION_CAPTURE=1` and `AAI_FRICTION_SPOOL_DIR` pointed at the fixture,
asserting zero spool lines for an escalated ad-hoc dirty success); remediate N2,
N3 and N6 in tree; file N1 and N4 as typed follow-ups; N5 and N7 stand as
accepted residuals recorded above. Then re-review — same single pass.
