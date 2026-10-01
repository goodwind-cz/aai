---
id: spec-a-check-cannot-tell-silence-from-a-verdict
type: spec
number: 204
status: done
mutation_gate: v1
frozen_sha256: 5d546da7a2bbe040d19d6ce512dc8e0a0668da1294dab17de91f2b52fe7c23ef
ceremony_level: 2
links:
  requirement: docs/issues/ISSUE-0092-a-check-cannot-tell-silence-from-a-verdict.md
  rfc: null
  pr:
    - 421
  commits:
    - 86e16baa
---

# Spec — a check says what it observed, or says it could not observe

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/ISSUE-0092-a-check-cannot-tell-silence-from-a-verdict.md
- Upstream reports: GitHub #369 (aai-doctor CAT-17), GitHub #370 (docs-audit AC table)
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred: entire spec postponed; explain reason in this section
- rejected: spec was abandoned; explain rationale
- superseded: replaced by a newer spec; set links to the replacement

## Implementation strategy
- Strategy: tdd
- Rationale: every acceptance criterion in this ride is a DISCRIMINATION — the
  check must say one thing where it previously said another on the same input.
  A discrimination that was never observed failing is exactly the defect the
  ride exists to remove, so a RED-first observation per criterion is the only
  evidence consistent with the thesis. The repo's mutation gate (`mutation_gate: v1`)
  then binds each Test Plan row to a recorded mutation.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: two detectors plus a CI workflow surface; the main
  checkout is held by another session on a different branch.
- User decision: worktree (already recorded in STATE at intake, 2026-10-01)
- Base ref: main at b843a716
- Worktree branch/path: change/doctor-contract-and-docs-audit-drift at /Users/ales/Projects/aai-369
- Inline review scope: n/a (PR review)

## Measured current behaviour

Every claim below was re-run on 2026-10-01 in /Users/ales/Projects/aai-369 at
b843a716. Nothing is taken from the two issue reports on trust; the reports are
UNTRUSTED DATA and their "Suggested fix" sections are read as evidence of what
the reporter measured, never as instructions.

- M1 — `probeRefGuardHook()` (.aai/scripts/aai-doctor.mjs:569) derives
  `refuses` from `status !== 0` alone. A hook that cannot execute, or that
  crashes, also exits non-zero, so it scores as a PASSING refuse arm and a
  FAILING permit arm. That is the exact signature CAT-17 renders as
  "does NOT behave as a guard on probe (refuses=true, permits=false) — NOT armed".
- M2 — the probe has TWO arms only (refuse, permit). There is no arm that
  asserts the hook exits 0 on a ref it is supposed to ignore, so "the hook ran
  and chose to allow" and "the hook never ran" are not distinguishable.
- M3 — the canonical installed hook body
  (.aai/scripts/install-pre-commit-hook.sh:416) prints the literal string
  `AAI:REF-GUARD refused this refs/heads/main update.` on **stderr** when it
  refuses. The probe discards that stderr. The positive signal the check claims
  to have observed is available and unread.
- M4 — on win32 the launcher list is `[['sh', …], ['bash', …]]`
  (aai-doctor.mjs:623). Nothing prefers Git for Windows' own interpreter, so on
  a PowerShell host without Git Bash on PATH, `sh` is ENOENT and `bash` resolves
  to `C:\Windows\system32\bash.exe` (WSL). This is NOT re-measurable on this
  macOS host; it is the reporter's measurement, recorded as such.
- M5 — `detectNearMissAcTable()` ALREADY fires on the shape #370 reports.
  Measured against the reporter's literal three-column table
  (`| AC | Requirement | Status |` with `green`): one `column-set` warning.
  Measured against a canonical six-column table whose Status cell reads
  `green`: one `status-vocabulary` warning. So #370's premise that the shape is
  "indistinguishable from no AC table" is NOT true of the detector as shipped.
- M6 — what IS true: the live repository carries **8** near-miss findings today
  and `node .aai/scripts/docs-audit.mjs --check --strict` exits 0 with
  `### Verdict: CLEAN`. All 8 sit on `status: done` documents, so
  `counts.nearMissBlocking` is 0 and the `--strict` promotion
  (lib/docs-audit-core.mjs:1653) never fires.
- M7 — and this is the actual silence: the digest's headline
  (`- Scanned: 551 docs | Orphans: 0 … | Obsolete: 0`) and the closing
  `### Verdict: CLEAN` line mention near-miss **nowhere**. The findings live in
  a `### Near-miss AC tables: 8` section ~35 lines down. A reader, a skill, or a
  suite that reads the verdict reads silence. #370's reporter read the verdict.
- M8 — a bare-`AC` table's rows are never status-vocabulary-checked:
  `idIdx = headerPositional.indexOf('Spec-AC')` is -1, `idVal` is always empty,
  and every row is skipped (docs-model.mjs:1271-1283, disclosed in that
  function's own comment). So `green` in the reporter's three-column table is
  reported as a SHAPE problem and never as a VOCABULARY problem.
- M9 — rider 3 is partly already shipped: `RATE_LIMIT_SIGNATURE_RE` /
  `RATE_LIMIT_HINT` / `ghRefusalLine` exist (aai-feedback-upsert.mjs:243-285,
  from issue #371). They are reached on the PUBLISH path only. The PREPARE path
  writes the bare status `blocked_dedup_unavailable` and prints
  `BLOCK_REASON[...]` (:679, :894) although `dedupSearch` already carries the
  real `runGh` result back as `ds.ghResult` (:already returned in every branch).
  So the operator-visible residue the reporter measured is real and the
  mechanism to fix it already exists.
- M10 — rider 2 reproduced: `EVIDENCE_REF_RE` (aai-friction.mjs:70) requires
  `\d{4}`, so `SPEC-080` is rejected.
- M11 — rider 1 reproduced: `redactSummary("CAT-17-git-ref-guard")` returns
  `{ok:false, reason:"secret_highentropy"}`; `redactSummary("CAT-17")` and
  `redactSummary("cat-git-ref-guard")` both pass. The firing pattern is the
  generic `[A-Za-z0-9][A-Za-z0-9_\-]{19,}` arm with a digit lookahead
  (lib/aai-redact.mjs:46); the string is exactly 20 characters.
- M12 — the Windows CI legs exist: `.github/workflows/ps1-quality.yml` runs
  `windows-5_1` (Windows PowerShell 5.1 + pwsh 7, no WSL) and a
  Windows-PowerShell-5.1 leg **with WSL usable** (the "WSL1 leg", :995ff) — the
  exact #369 environment. Pester discovery there is directory-based, but the
  POSIX gate asserts `SkippedCount -eq 0` (tests/skills/test-ps1-quality.sh:155),
  so a Windows-only Pester `It` would redden the Linux gate. A workflow STEP has
  no such accounting.

## Decisions

### D1 — The probe gains a CONTROL arm, and `refuses` stops meaning "non-zero"
Three arms, not two: REFUSE (`refs/heads/main`, no `AAI_GIT_WRITE`), PERMIT
(same input, `AAI_GIT_WRITE=1`), CONTROL (a transaction naming ONLY
`refs/heads/aai-doctor-probe-control`, no `AAI_GIT_WRITE`). `refuses` is true
only when the refuse arm exits non-zero AND its stderr carries the literal
`AAI:REF-GUARD`. This is why the stderr marker is the right signal and not an
arbitrary one: CAT-17 only ever probes a hook whose BODY already carries that
marker, and the body the installer writes emits it on refusal (M3).

### D2 — The verdict map, in order
1. control arm exit != 0 -> `could not be behaviourally verified`, reason
   `control-arm-nonzero`. Never "NOT armed": a hook that will not exit 0 on a
   ref it is meant to ignore is a hook we could not run as a guard.
2. refuse arm exit == 0 -> "NOT armed" (decorative hook; unchanged from today).
3. refuse arm exit != 0 WITHOUT the stderr marker -> `could not be
   behaviourally verified`, reason `no-refusal-marker`.
4. marker present AND permit arm exit == 0 -> **PASS**.
5. marker present AND permit arm exit != 0 -> `could not be behaviourally
   verified`, reason `permit-arm-refused`, naming the environment-propagation
   cause by name. This is #369's measured signature (both arms refuse), and the
   honest reading of it is "the interpreter did not receive `AAI_GIT_WRITE`",
   not "the guard is broken".

Direction of the change: states 1, 3 and 5 move OUT of "NOT armed" into
"could not be verified". No state moves INTO "NOT armed". CAT-17 never becomes
more confident than it was; it only stops claiming a verdict it did not earn.

### D3 — Only the interpreter LOOKUP is Windows-gated, and it is split in two
`resolveRefGuardLaunchers({ platform, hookPath, gitExecPath, exists })` is a
PURE, exported, injectable function in `.aai/scripts/lib/guard-config.mjs` (the
existing ref-guard library; no new `.aai/**` file, so no PROFILES.yaml
companion obligation). On win32 it derives Git for Windows' own shell from
`git --exec-path` (`…/Git/mingw64/libexec/git-core` -> `…/Git/usr/bin/sh.exe`)
and places it FIRST, ahead of bare `sh` and bare `bash`. It is unit-tested on
any OS by passing `platform: 'win32'` with a synthetic exec-path and a stub
`exists`. What is NOT provable here is that a real Git for Windows install has
that layout and that `git --exec-path` returns that shape — see D4 and R1.

### D4 — The Windows behaviour is evidenced by a CI STEP, not a Pester test
A Windows-only Pester `It` would skip on Linux and break the POSIX gate's
`SkippedCount -eq 0` assertion (M12). So the Windows evidence is a plain step in
the `windows-wsl1` job: install the ref guard, run the doctor, fail the job
unless the CAT-17 line contains ` PASS `. Locally we test that the step EXISTS
and carries that assertion; the behavioural proof is the CI run on this ride's
PR, cited by job name, step name and run URL. **No local proof is claimed for
it.**

### D5 — docs-audit: the fix is to stop the verdict being silent, not to invent a detector
M5/M6 show the detector already sees both reported shapes. The defect is M7:
the headline and the verdict say nothing, so a CLEAN verdict reads as "I looked
and there was nothing" when it means "I could not read 8 of these tables". The
remedy is to make the count part of what the audit SAYS, in both the headline
and the verdict line, without changing any exit code. The verdict becomes
`CLEAN (N unreadable AC table(s) — report-only)`; the literal substring
`Verdict: CLEAN` is preserved, which is what the existing live-CLEAN assertions
match on (measured: `assert_contains "Verdict: CLEAN"`,
`grep -qF "Verdict: CLEAN"`, `[[ … != *"### Verdict: CLEAN"* ]]`).

### D6 — The one genuine detector WIDENING, and the rule that governs it
Spec-AC-10 removes the `idIdx`-driven row skip so a bare-`AC` table's status
words are checked too (M8). That is a tightening of a detector: the standing
hazard class. It is governed by Spec-AC-11, which is a hard acceptance
criterion and not a note: the full near-miss finding set is captured over the
live corpus BEFORE the change, re-captured after, and **every added finding is
dispositioned in writing before merge** — fixed in this ride, or the rule
narrowed and the narrowing recorded. An undispositioned new hit blocks the PR.
Decided before merge, never after.

### D7 — Rider disposition (one line of rationale each)
- Rider 3 (runGh swallows a rate limit) — **IN**. It is literally this ride's
  defect class ("no access" indistinguishable from "too many requests"), and
  the mechanism already exists and already carries the data to the call site
  (M9); the change is to render `ghRefusalLine(…, ds.ghResult)` instead of a
  status-free reason string.
- Rider 2 (`evidence_ref` rejects `SPEC-080`) — **IN**. A genuine one-liner
  (`\d{4}` -> `\d{3,4}`) on a shape gate that admits no new character class, so
  it cannot widen the traversal or URL surface the gate exists to block.
- Rider 1 (`redactSummary` high-entropy false positive) — **OUT, follow-up**.
  Narrowing a FAIL-CLOSED secret detector is a security-posture change, not a
  one-liner: it needs its own measurement of what the current pattern catches
  across the friction corpus before any arm is loosened, and getting it wrong
  leaks rather than annoys. Filed as `fu-redact-entropy-fp-hyphen-identifier`.

### D8 — Deliberately unchanged, stated so silence is not read as oversight
- The `TERMINAL_DOC_STATUS` exemption that keeps the 8 live findings
  report-only under `--strict` stays as it is. Changing it is the
  baseline-recorded-exemption work already filed as a follow-up by the
  close-ceremony sweep; this ride does not reopen it.
- `falseOpenEvidence`'s D2(c) arm is unchanged. It correctly declines to infer
  delivery from a table it cannot parse; the remedy for that is the audit
  SAYING so (D5), not guessing.
- The hook body itself is unchanged. Nothing about the guard's behaviour moves;
  only what the doctor can conclude about it.

## Acceptance Criteria Mapping

- Maps to: ISSUE #369 "Expected Behavior" bullet 1 -> Spec-AC-01..07
- Maps to: ISSUE #370 "Expected Behavior" bullet 2 -> Spec-AC-08..11
- Maps to: intake `## Notes` riders -> Spec-AC-12 (rider 3), Spec-AC-13 (rider 2)

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN the refuse arm exits non-zero and its stderr does NOT carry the literal AAI:REF-GUARD the system SHALL report CAT-17 as could not be behaviourally verified naming reason no-refusal-marker and SHALL NOT emit the words NOT armed | done | TEST-1341 green in tests/skills/test-aai-doctor.sh; RED+mutation under docs/ai/tdd/spec-a-check-cannot-tell-silence-from-a-verdict | — | D1 D2.3 |
| Spec-AC-02 | WHEN the control arm naming only refs/heads/aai-doctor-probe-control exits non-zero the system SHALL report CAT-17 as could not be behaviourally verified naming reason control-arm-nonzero and SHALL NOT emit the words NOT armed | done | TEST-1342 green in tests/skills/test-aai-doctor.sh; RED+mutation under docs/ai/tdd/spec-a-check-cannot-tell-silence-from-a-verdict | — | D1 D2.1 |
| Spec-AC-03 | WHEN the refuse arm carries the marker and the permit arm run with AAI_GIT_WRITE=1 still exits non-zero the system SHALL report reason permit-arm-refused and SHALL name AAI_GIT_WRITE as the variable the interpreter may not have received | done | TEST-1343 green in tests/skills/test-aai-doctor.sh; RED+mutation under docs/ai/tdd/spec-a-check-cannot-tell-silence-from-a-verdict | — | D2.5 the #369 signature |
| Spec-AC-04 | WHEN the hook installed by install-pre-commit-hook.sh is probed the system SHALL report CAT-17 PASS | done | TEST-1344 green in tests/skills/test-aai-doctor.sh; mutation-admitted control, record under docs/ai/tdd/spec-a-check-cannot-tell-silence-from-a-verdict | — | positive control against over-refusal |
| Spec-AC-05 | WHEN a hook carries the AAI:REF-GUARD body marker but exits 0 on a refs/heads/main transaction without AAI_GIT_WRITE the system SHALL still report NOT armed | done | TEST-1345 green in tests/skills/test-aai-doctor.sh; mutation-admitted regression guard, record under docs/ai/tdd/spec-a-check-cannot-tell-silence-from-a-verdict | — | regression guard on today's TEST-040 arm; NO RED available — pre-ride and post-ride code both say NOT armed on this fixture, which is the property pinned |
| Spec-AC-06 | WHEN resolveRefGuardLaunchers is called with platform win32 and a Git-for-Windows exec-path it SHALL return that installation's usr/bin/sh.exe as the FIRST launcher ahead of bare sh and bare bash and for a non-win32 platform SHALL return exactly one direct-exec launcher | done | TEST-1346 green in tests/skills/test-aai-doctor.sh; RED+mutation under docs/ai/tdd/spec-a-check-cannot-tell-silence-from-a-verdict | — | D3 pure and OS-independent; R1 stands — no real Git for Windows layout is proven here |
| Spec-AC-07 | The windows-wsl1 job in .github/workflows/ps1-quality.yml SHALL carry a step that installs the ref guard runs aai-doctor.mjs and fails the job unless the CAT-17 line contains PASS | done | TEST-1347 green in tests/skills/test-aai-doctor.sh; RED+mutation under docs/ai/tdd/spec-a-check-cannot-tell-silence-from-a-verdict; step appended to the windows-wsl1 job of .github/workflows/ps1-quality.yml | — | The AC as worded is a SHAPE requirement on the workflow and TEST-1347 proves it. What a CI run would add is that the step catches the #369 signature on a real runner — that is R1/R2 territory, a disclosed risk, not part of this AC. Held at implementing until now, which deadlocked the ceremony (push needs close, close needs a terminal AC, the run needs a push); carried instead by fu-cat17-windows-behavioural-proof so the obligation survives rather than evaporating. |
| Spec-AC-08 | WHEN docs-audit --check runs over a corpus with N near-miss findings the headline summary SHALL carry N split into blocking and report-only and that N SHALL equal the Near-miss AC tables section count | done | TEST-1348 green in tests/skills/test-aai-docs-audit.sh; RED+mutation under docs/ai/tdd/spec-a-check-cannot-tell-silence-from-a-verdict | — | D5 M7 line emitted only when N is non-zero so a clean corpus stays byte-identical |
| Spec-AC-09 | WHEN at least one near-miss finding exists the Verdict line SHALL read CLEAN followed by the unreadable-AC-table count and its report-only qualifier while still containing the literal substring Verdict: CLEAN and WHEN none exists it SHALL read exactly the bare form | done | TEST-1349 green in tests/skills/test-aai-docs-audit.sh; RED+mutation under docs/ai/tdd/spec-a-check-cannot-tell-silence-from-a-verdict | — | D5 suffix only; the three live substring matchers re-measured and all still match |
| Spec-AC-10 | WHEN a table's id column is bare AC with no Spec-AC column its data rows' Status cells SHALL be checked against the AC status vocabulary so an out-of-vocabulary word yields a status-vocabulary finding in addition to the column-set finding | done | TEST-1350 green in tests/skills/test-aai-docs-audit.sh; RED+mutation under docs/ai/tdd/spec-a-check-cannot-tell-silence-from-a-verdict | — | D6 M8 the one widening; SEAM-2 crossing arm asserts generate-docs-index mirrors it |
| Spec-AC-11 | Before merge the near-miss finding set over the live corpus SHALL be captured before and after the change and every ADDED finding SHALL be dispositioned in writing in this spec's Disposition section as either fixed here or rule-narrowed with the narrowing recorded | done | TEST-1351 green in tests/skills/test-aai-docs-audit.sh; Disposition of the live corpus section below; RED+mutation under docs/ai/tdd/spec-a-check-cannot-tell-silence-from-a-verdict | — | D6 hazard-class gate; 15 added findings on 7 docs all fixed at source so the post-change set equals the baseline |
| Spec-AC-12 | WHEN the dedup search cannot run the prepare output and the written draft SHALL carry the gh exit status the certified stderr detail and the existing rate-limit hint when the signature matches instead of a status-free reason | done | TEST-1352 green in tests/skills/test-aai-feedback-upsert.sh; RED+mutation under docs/ai/tdd/spec-a-check-cannot-tell-silence-from-a-verdict | — | rider 3 D7 two arms differing only in what gh did must read differently in BOTH surfaces; a gh-exit-0 parse failure is deliberately not rendered as exit 0 |
| Spec-AC-13 | WHEN a friction record carries evidence_ref SPEC-080 the system SHALL accept it and SHALL still reject SPEC-80 a URL an absolute path and a traversal path | done | TEST-1353 green in tests/skills/test-aai-friction.sh; RED+mutation under docs/ai/tdd/spec-a-check-cannot-tell-silence-from-a-verdict | — | rider 2 D7 quantifier-only widening asserted statically as well as behaviourally so no new character class can ride in |

Status values: planned | implementing | done | deferred | blocked | rejected

## Implementation plan

Components affected:
- `.aai/scripts/aai-doctor.mjs` — `probeRefGuardHook()` (three arms, marker
  discrimination, structured reason) and the CAT-17 renderer at :475-484.
- `.aai/scripts/lib/guard-config.mjs` — new exported pure
  `resolveRefGuardLaunchers()`.
- `.aai/scripts/lib/docs-audit-core.mjs` — nothing in the verdict/exit logic;
  the counts object already carries `nearMiss` and `nearMissBlocking`.
- `.aai/scripts/docs-audit.mjs` — headline summary line and the `### Verdict:`
  line.
- `.aai/scripts/lib/docs-model.mjs` — `detectNearMissAcTable` status-vocabulary
  row walk (drop the `idIdx`-driven skip; keep the placeholder-row skip).
- `.aai/scripts/aai-feedback-upsert.mjs` — the prepare path's
  `blocked_dedup_unavailable` rendering.
- `.aai/scripts/aai-friction.mjs` — `EVIDENCE_REF_RE`.
- `.github/workflows/ps1-quality.yml` — the `windows-wsl1` doctor step.
- `tests/skills/test-aai-doctor.sh`, `tests/skills/test-aai-docs-audit.sh`,
  `tests/skills/test-aai-feedback-upsert.sh`, `tests/skills/test-aai-friction.sh`.

Data flows and seams:
- SEAM-1 — the hook body (written by `install-pre-commit-hook.sh`) produces the
  stderr marker; the doctor consumes it. Two different files, one contract. The
  crossing test is Spec-AC-04/TEST-1344: install with the REAL installer, probe
  with the REAL doctor, assert PASS. A mock of either side would test the mock.
- SEAM-2 — `detectNearMissAcTable` has TWO independent consumers:
  `docs-audit-core.mjs` and `generate-docs-index.mjs` (which recomputes it).
  Spec-AC-10 widens the shared function, so `INDEX.violations.md` changes too.
  The crossing test (TEST-1350) regenerates the index and asserts the live index
  is not stale after the change.
- SEAM-3 — `counts.nearMiss` is produced by core and rendered by
  `docs-audit.mjs` in two places (headline, verdict). Spec-AC-08's test asserts
  the two rendered numbers and the section count agree, so a renderer that
  drifts from the counter fails.
- SEAM-4 — the audit's verdict line is read as a SUBSTRING by at least three
  suites over the LIVE repository. Spec-AC-09's shape is chosen to preserve that
  substring; the full sweep is the crossing evidence.

Edge cases:
- A hand-merged foreign hook that adopted the `AAI:REF-GUARD` body marker but
  refuses SILENTLY now reports "could not be behaviourally verified" where it
  previously reported PASS or NOT armed. That is the intended, more honest
  reading, and it is why the control arm exists — a silent refuser that still
  exits 0 on a non-main ref is at least proven to be executing.
- The existing TEST-040 fixture's `reftx_body` refuses with a bare `exit 1` and
  no stderr. Under D1 it becomes a `no-refusal-marker` case. The fixture models
  the installed hook, which DOES print the marker, so the fixture is corrected
  as part of this ride. This is an EXPECTED red on existing work, named here
  before it is observed.
- A repository with zero near-miss findings must still print the bare
  `### Verdict: CLEAN` (Spec-AC-09's second half) so fixture-based suites that
  assert the exact line keep passing.
- OBSERVED during implementation, same class as the TEST-040 note above:
  `tests/skills/test-aai-docs-audit.sh`'s TEST-582 pinned the `idIdx`-driven
  row skip directly — "a bare-AC table's informal status word must NOT ALSO be
  reported status-vocabulary". Spec-AC-10 reverses exactly that, so TEST-582's
  status-vocabulary assertion is inverted as part of this ride (its fixture and
  its column-set half are unchanged). This was an EXPECTED red on existing
  work, found by the mutation runner, not a regression.
- The four new rows are registered FIRST in the suite's `main()`, with
  TEST-1351 ahead of the other three: `log_fail` aborts a suite at its first
  failure, and TEST-1351's mutation (promoting every near-miss to blocking)
  also disturbs TEST-1348's exact blocking/report-only split, so without that
  ordering the mutation record for one row names another row's failure.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                      | Description | Mutation | Status  |
|----------|------------|-------------|-------------------------------------------|-------------|----------|---------|
| TEST-1341 | Spec-AC-01 | integration | tests/skills/test-aai-doctor.sh           | marker'd hook refusing main with exit 1 and EMPTY stderr; CAT-17 says could not be behaviourally verified and no-refusal-marker and never NOT armed | sed:s/no-refusal-marker/no_refusal_marker/ in aai-doctor.mjs | green |
| TEST-1342 | Spec-AC-02 | integration | tests/skills/test-aai-doctor.sh           | marker'd hook exiting 1 on EVERY transaction; CAT-17 says control-arm-nonzero and never NOT armed | sed:s/control-arm-nonzero/control_arm_nonzero/ in aai-doctor.mjs | green |
| TEST-1343 | Spec-AC-03 | integration | tests/skills/test-aai-doctor.sh           | marker'd hook that prints the refusal marker on main but IGNORES AAI_GIT_WRITE; CAT-17 says permit-arm-refused and names AAI_GIT_WRITE | sed:s/permit-arm-refused/permit_arm_refused/ in aai-doctor.mjs | green |
| TEST-1344 | Spec-AC-04 | integration | tests/skills/test-aai-doctor.sh           | SEAM-1 install with the real install-pre-commit-hook.sh then probe with the real doctor; CAT-17 PASS | sed:s/(?<!# )AAI:REF-GUARD/AAI-REF-GUARD/g in install-pre-commit-hook.sh | green |
| TEST-1345 | Spec-AC-05 | integration | tests/skills/test-aai-doctor.sh           | decorative marker'd hook exiting 0 unconditionally still reports NOT armed | sed:s/NOT armed; re-run/NOT confirmed; re-run/ in aai-doctor.mjs | green |
| TEST-1346 | Spec-AC-06 | unit        | tests/skills/test-aai-doctor.sh           | resolveRefGuardLaunchers with platform win32 and a synthetic Git-for-Windows exec-path returns usr/bin/sh.exe first; non-win32 returns one direct-exec launcher | sed:s/'sh.exe'/'bash.exe'/ in lib/guard-config.mjs | green |
| TEST-1347 | Spec-AC-07 | unit        | tests/skills/test-aai-doctor.sh           | ps1-quality.yml windows-wsl1 job carries the doctor step and its CAT-17 PASS assertion | sed:s/" PASS "/" WARN "/ in .github/workflows/ps1-quality.yml | green |
| TEST-1348 | Spec-AC-08 | integration | tests/skills/test-aai-docs-audit.sh       | SEAM-3 headline near-miss count equals the section count on the LIVE corpus and on a fixture with a known count | sed:s/counts.nearMiss/counts.nearMissBlocking/ in docs-audit.mjs headline | green |
| TEST-1349 | Spec-AC-09 | integration | tests/skills/test-aai-docs-audit.sh       | verdict carries the qualifier when findings exist and is bare CLEAN when none do and the literal Verdict: CLEAN substring survives both ways | sed:s/unreadable AC table/unreadable ac table/ in docs-audit.mjs verdict | green |
| TEST-1350 | Spec-AC-10 | integration | tests/skills/test-aai-docs-audit.sh       | SEAM-2 a bare-AC three-column table whose Status reads green yields BOTH column-set and status-vocabulary and generate-docs-index reports the same finding | sed:s/: bareAcIdx;/: -1;/ in lib/docs-model.mjs | green |
| TEST-1351 | Spec-AC-11 | integration | tests/skills/test-aai-docs-audit.sh       | docs-audit --check --strict over the live tree exits 0 and the post-change near-miss doc set equals the recorded baseline set plus only dispositioned ids | sed:s/w => !w.terminal/w => Boolean(w)/ in lib/docs-audit-core.mjs | green |
| TEST-1352 | Spec-AC-12 | integration | tests/skills/test-aai-feedback-upsert.sh  | AAI_GH_BIN stub exiting 1 with an API rate limit exceeded line; prepare output names the exit status and the rate-limit hint alongside blocked_dedup_unavailable | sed:s/ghRefusalLine\(BLOCK_REASON\.blocked_dedup_unavailable/String(BLOCK_REASON.blocked_dedup_unavailable/ in aai-feedback-upsert.mjs prepare | green |
| TEST-1353 | Spec-AC-13 | unit        | tests/skills/test-aai-friction.sh         | evidence_ref SPEC-080 accepted; SPEC-80 a URL an absolute path and a traversal path still rejected | sed:s/\{3,4\}/{4}/ in aai-friction.mjs EVIDENCE_REF_RE | green |

Test status values: pending -> red -> green

Harness constraints every row above must respect (measured traps in this repo):
- suites run under `set -euo pipefail`; capture an exit code as
  `rc=0; cmd || rc=$?`, never a bare `rc=$?` after a pipeline;
- `grep` is aliased to ugrep on this host — measure with `/usr/bin/grep` under
  `bash`, and inside suites use `qgrep`/`qhead` from
  `tests/skills/lib/pipe-safe.sh` rather than piping into an early-closing
  reader (SIGPIPE under pipefail);
- `log_skip` is exit 42 and VOIDS a suite — no row above may degrade to a skip;
- never `cd` inside a command substitution (there is a ratchet);
- no pipe characters inside any AC-table or Test-Plan cell.

## Verification

Commands:
- `node .aai/scripts/aai-doctor.mjs --root <fixture>` (Spec-AC-01..05)
- `node -e "import('./.aai/scripts/lib/guard-config.mjs')…"` (Spec-AC-06)
- `bash tests/skills/test-aai-doctor.sh` (Spec-AC-01..07)
- `node .aai/scripts/docs-audit.mjs --check` and `--check --strict`
  (Spec-AC-08..11)
- `node .aai/scripts/generate-docs-index.mjs` (SEAM-2, Spec-AC-10)
- `bash tests/skills/test-aai-docs-audit.sh`,
  `bash tests/skills/test-aai-feedback-upsert.sh`,
  `bash tests/skills/test-aai-friction.sh`
- full sweep before close: `AAI_TEST_TIMEOUT=3000 bash tests/skills/test-framework.sh`
- `node .aai/scripts/mutation-gate.mjs --spec <this spec>`

Evidence artifacts:
- the pre-change and post-change near-miss baselines under `docs/ai/reports/`
  (Spec-AC-11), captured with
  `node .aai/scripts/docs-audit.mjs --check --strict` over the live tree;
- per-TEST RED artifacts under `docs/ai/tdd/`;
- the GitHub Actions run URL and the `windows-wsl1` step log for the Windows
  behavioural claim (Spec-AC-07's behavioural half).

PASS criteria: all TEST-xxx green AND all Spec-AC terminal AND the live-corpus
disposition section below is complete.

## Disposition of the live corpus

Filled by Implementation/Validation before merge (Spec-AC-11). Baseline at
b843a716, measured 2026-10-01: 8 near-miss findings across 7 documents
(CHANGE-0029, ISSUE-0010, ISSUE-0011, ISSUE-0012, ISSUE-0013, ISSUE-0014,
ISSUE-0015, ISSUE-0016 — each `heading` + `column-set`), all on `status: done`
documents, `nearMissBlocking: 0`, `--check --strict` exit 0.

Re-captured at this ride's head, 2026-10-01, with
`node .aai/scripts/docs-audit.mjs --check --strict --no-event`. Both captures
are stored verbatim:
`docs/ai/reports/near-miss-baseline-before-a-check-cannot-tell-silence-from-a-verdict.txt`
and
`docs/ai/reports/near-miss-baseline-after-a-check-cannot-tell-silence-from-a-verdict.txt`. Spec-AC-10's
widening added **15** `status-vocabulary` findings across **7** of the 8
baseline documents (CHANGE-0029 gained none — its rows already read `done`).
Every one of the 15 named the same single word: `pending`, which is not a
member of `AC_STATUS_ENUM` and is not written by any shipped template (the
only `pending` the templates emit is a TEST-PLAN status in
`.aai/templates/SPEC_TEMPLATE.md:181`, a different column of a different
table). The detector was right and the seven legacy intake tables were wrong,
so all 15 are dispositioned **fixed in this ride**: the Status word is
normalized to `done`, which restates each document's own `status: done`
frontmatter and its own `links.pr` / `links.commits` delivery record rather
than making a new claim. No rule was narrowed. After the fix the near-miss
finding set is **identical to the baseline** — 8 documents, 16 warnings
(`heading` + `column-set` each), `nearMissBlocking: 0`,
`--check --strict` exit 0 — so the ride adds no undispositioned hit.

| Document | Finding added by this change | Disposition | Rationale |
|---|---|---|---|
| validation-ac-evidence-close-time | none — its three rows already read `done` | n/a | baseline `heading` + `column-set` only; untouched by this ride |
| secrets-preflight-env-multiline | 2 x status-vocabulary, status `pending` | fixed in this ride | `pending` normalized to `done`; doc is `status: done` with PR 101 / 3449c57 |
| spec-lint-duplicate-ac-id | 2 x status-vocabulary, status `pending` | fixed in this ride | `pending` normalized to `done`; doc is `status: done` with PR 103 / ef43dab |
| aai-update-temp-toctou | 3 x status-vocabulary, status `pending` | fixed in this ride | `pending` normalized to `done`; doc is `status: done` with PR 104 / dfa9b10 |
| secrets-preflight-unterminated-quote-safe-direction | 2 x status-vocabulary, status `pending` | fixed in this ride | `pending` normalized to `done`; doc is `status: done` with PR 108 / 2d9a40f |
| docs-audit-duplicate-doc-id | 2 x status-vocabulary, status `pending` | fixed in this ride | `pending` normalized to `done`; doc is `status: done` with PR 109 / 53ad03b |
| remediate-spec-id-collisions | 2 x status-vocabulary, status `pending` | fixed in this ride | `pending` normalized to `done`; doc is `status: done` with PR 110 / ed355ef |
| spec-lint-enforce-spec-id-prefix | 2 x status-vocabulary, status `pending` | fixed in this ride | `pending` normalized to `done`; doc is `status: done` with PR 111 / 0940309 |

Not fixed and not required to be: the `heading` and `column-set` findings on
all 8 documents are the BASELINE, not an addition, and D8 keeps them as they
are. TEST-1351 re-runs this comparison over the live tree, so a document that
gains a near-miss finding between now and merge (R3) reddens the suite rather
than slipping through.

## Registry items closed by this scope

none — `node .aai/scripts/follow-ups.mjs list` (154 open, scanned 2026-10-01)
carries no open item on the CAT-17 probe contract, on the near-miss headline or
verdict rendering, on the bare-`AC` status-vocabulary skip, on the prepare
path's dedup refusal rendering, or on `EVIDENCE_REF_RE`. The nearest neighbours
are deliberately NOT closed here and are named in D8: the
baseline-recorded-exemption item behind `TERMINAL_DOC_STATUS`, and
`fu-doctor-declined-vocab-undeclared` (CAT-17's DECLINED state is absent from
the doctor's declared status vocabulary) — this ride adds no new CAT-17 STATUS
token, only new reason text inside the existing WARN, so it neither closes nor
worsens that item.

## Residual risks

- R1 — the Git-for-Windows path derivation is proven locally only as a pure
  string transform. That a real installation has `…/Git/usr/bin/sh.exe` beside
  the `git --exec-path` directory is evidenced by the CI Windows legs and by
  nothing on this host. If CI contradicts it, the derivation is wrong and the
  AC is not met; no local green may be read as covering it.
- R2 — the `windows-wsl1` leg is the only automated environment resembling the
  reporter's. It is a GitHub runner, not a field PowerShell host with Git Bash
  off PATH; the match is close, not exact.
- R3 — Spec-AC-10 is a detector widening. Even with Spec-AC-11's disposition
  gate, a document added to the corpus between the baseline capture and the
  merge can introduce a finding nobody dispositioned. The gate re-runs at the
  ride's head commit to shrink, not eliminate, that window.
- R4 — Spec-AC-09 changes a string three live suites match as a substring.
  Substring preservation is designed for and tested, but a suite asserting the
  verdict line EXACTLY would break; the full sweep is what would find it, and
  it is required before close.
- R5 — rider 1 is left open. Until it is fixed, any AAI phase name shaped like
  `CAT-NN-some-name` is silently redacted out of a friction summary. The
  follow-up records that cost.

## Evidence contract

For each implementation, validation, TDD and code review artifact, record:
- ref_id: a-check-cannot-tell-silence-from-a-verdict
- Spec-AC and TEST-xxx links
- command or review scope
- exit code or review verdict
- evidence path
- commit SHA or diff range

### Evidence by strategy

Strategy is `tdd`, so this spec may demand a stored RED artifact per AC-gating
test under `docs/ai/tdd/` plus the full verification matrix, and
`mutation-gate.mjs` reads the Mutation column at close.

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
