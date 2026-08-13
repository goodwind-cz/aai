# Code Review — CHANGE-0138 doctor/config honesty batch

- Date: 2026-08-13T13:41:07Z
- Reviewer: Code Review role (single dual-verdict pass, .aai/SKILL_CODE_REVIEW.prompt.md)
- Scope: `git diff 53b7e20..HEAD` (f923f0a, e17f511, e30bf61) on branch feat/doctor-honesty-batch
- Spec: docs/specs/SPEC-DRAFT-spec-doctor-honesty-batch.md (frozen at 53b7e20)
- Prior validation: docs/ai/validation/validation-20260813T133311Z-CHANGE-0138-doctor-honesty-batch.md (PASS)

```yaml
review:
  scope: 53b7e20..HEAD (f923f0a, e17f511, e30bf61)
  spec: docs/specs/SPEC-DRAFT-spec-doctor-honesty-batch.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/aai-doctor.mjs:573-591 parseCodexExecObservation; TEST-035 11-fixture battery (suite 38/38 PASS); reviewer probes P1-P8 all match D1" }
      - { ac: Spec-AC-02, call: compliant,
          citation: ".aai/scripts/aai-doctor.mjs:548-561 tri-state, stdout||stderr fallback deleted; TEST-036 + TEST-026 updated pins green" }
      - { ac: Spec-AC-03, call: compliant,
          citation: ".aai/scripts/aai-doctor.mjs:620-627 strict-equality tallies; TEST-037 byte-checks both line shapes; live run 3/3 clean tail" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "update-doctor-report.mjs:135 + update-check.mjs:148 byte-identical strip, both in e17f511; 0138-TEST-004/005 behavioral + structural pins green in both suites" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "update-doctor-report.mjs:117-127 ENOENT split, :192-215 prune budget; 0138-TEST-006/007 all arms assert 1 stdout line + exit 0" }
      - { ac: Spec-AC-06, call: compliant,
          citation: "check-test-registration exit 0; doctor/update/update-check/release suites exit 0; Pester 141/141; TEST-032 + 0138-TEST-009 doc pins; TEST-024 heading discipline PASS" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-doctor.sh, line: 1330,
          issue: "The D1 rule 'a blank line does NOT end the block' has no suite fixture: none of FX-01..FX-11 places the exec row AFTER a blank line inside a Commands: block",
          failure_scenario: "A future refactor that terminates blocks at the first blank line (a natural simplification) passes all 11 fixtures green while false-negativing any clap help that groups subcommands with blank lines inside the Commands: block; the regression ships invisibly. Reviewer probe P2 and validator probe H6 confirm today's behavior but neither is a committed regression test." }
  cannot_verify:
    - { claim: "Windows PATHEXT arm of resolveExecutable with the new tri-state (present:false reason wording on a real Windows PATH miss)",
        closes_with: "ps1-quality / skill-suite CI on a Windows runner (ci-full label per validation F-6)" }
    - { claim: "Behavior of downstream consumers of the embedded field-report JSON outside this repo when present === 'UNKNOWN' (RR-5 type widening)",
        closes_with: "nothing in-repo consumes clis.*.present besides the doctor itself (grep-verified); external consumers can only be closed by the documented contract — docs/product/aai-doctor.md now states 'treat any non-true value as not-present'" }
    - { claim: "A real hung codex --help (not --version) grandchild being reaped: spawnSync SIGTERMs the direct child only; a grandchild holding the pipe could in theory delay or outlive the probe",
        closes_with: "observed on this host: doctor returned in 5.7s at the 5s bound and the orphan sleep self-terminated; a hostile-grandchild arm would need a dedicated fixture; bounded risk, RR-4-adjacent" }
  overall: pass
```

## Focus-area walk (dispatch questions answered)

1. **Commands:-block parser.**
   - Bounding: block ends at the first NON-EMPTY column-0 line or EOF
     (`aai-doctor.mjs:581`). Block-as-last-thing with trailing
     whitespace-only lines: probe P1 (`Commands:\n   \n\t\n  exec  run\n   \n`)
     → `true`; whitespace-only lines pass `/^[ \t]/`, empty lines pass the
     `line !== ''` guard. Header at EOF with empty block → honest `false` (P3).
   - Anchors: header `/^(commands|subcommands):\s*$/i` applied per split line
     (no `m` flag ambiguity); `\s*$` correctly admits trailing spaces and a
     stray `\r` (P4 green). Row regex requires the token exactly `exec`
     (`execute`/`exechelper` rejected, P7/FX-11).
   - CRLF: `split(/\r?\n/)` in both the parser and the version first-line
     split; FX-08 is a committed CRLF fixture.
   - ReDoS: all three regexes are single-quantifier, no nesting. Timed on
     adversarial megabyte inputs (1M-space lines, 550k-line help):
     worst case 1.3 ms single-regex, 34 ms full parse. Linear; no
     catastrophic backtracking class present.
   - Help-on-stderr (clap prints help to stderr on error): still parsed —
     stdout+stderr concatenation preserved from the old code (P8).

2. **Tri-state consumers.** Repo-wide grep: the only consumers of
   `clis.<name>.present` are `probeCodexExecSubcommand` (now guarded
   `codexPresent !== true`, so an UNKNOWN codex never earns a second 5s hang)
   and the strict-equality tallies in `catAgentCliProbe`. The field-report
   embedder (`update-doctor-report.mjs`) embeds the doctor JSON verbatim and
   reads only `verdict`/categories count — no boolean check on `present`.
   The retired `unknown: true` flag has zero remaining readers. RR-5 is
   documented verbatim in docs/product/aai-doctor.md ("consumers must treat
   any non-`true` value as not-present"). Timeout path: measured 5.7s total
   with a sleeping fake; the orphaned grandchild self-terminated and none
   remained after the suites (`pgrep` clean) — no zombie accumulation.

3. **BOM twins.** Strip sits immediately after `readFileSync` and before the
   line split in BOTH parsers — i.e. before any `^`-anchored match can see
   index 0. The structural pin (test_019) grep-counts the exact statement
   (must be exactly 1 per file) AND byte-compares the two grep-extracted
   lines including indentation — replacing either side with a variant
   (e.g. `codePointAt`) drops the count to 0 and fails. Both strips landed in
   the single commit e17f511. Behavioral pins cover both parsers plus the
   negative controls (mid-file ZWNBSP is content; only index 0, exactly once).

4. **Degrade arms.** Every new arm in 0138-TEST-004/006/007 asserts
   `wc -l < out == 1` and `HELPER_RC == 0`; TEST-007 asserts exactly ONE
   stderr line in both the single-failure and two-failure arms ("and 1 more"
   pinned, single failure pinned to NOT claim more), and zero stderr on the
   writable arm; TEST-006 pins ENOENT-silent. No exit-code change anywhere
   in the diff; the doctor exit map is untouched (live runs: 0 on repo root,
   1 on empty scratch root, 2 on usage per validation F-7).

5. **Test quality.** All fixtures are PATH-injected fake CLIs driven through
   the REAL doctor via `node $DOCTOR --json` — no unit-mocked parser
   anywhere. Assertions feed node via here-strings (`<<<"$out"`), never
   `echo | node`; TEST-033's old `echo | node` pipe was converted in this
   diff. Could a subtly wrong parser pass? The battery discriminates
   block-bounding (FX-07), token-exactness (FX-11), separators (FX-03/04),
   header variants (FX-08), CRLF (FX-08) and no-header UNKNOWN (FX-01/10) —
   the one undiscriminated rule is blank-line-inside-block (NB-1 below).
   test-aai-doctor.sh runs `set -uo pipefail` (no `-e`), so doctor exit 1 on
   scratch roots is safe; the update suites' new arms wrap rc-capture in
   `set +e`/`set -e` correctly and guard `grep -c ... || true`. No .ps1
   touched (diffstat); Pester re-run by this reviewer: **141 passed / 0
   failed**. Emitted strings all ASCII (the em-dashes live only in .md/.sh
   comments, never in helper output).

6. **Governance.** CHANGELOG: exactly one `## [unreleased] — … (CHANGE-0138) [L1]`
   heading with body bullets under it (per-entry heading convention);
   test-aai-release.sh TEST-024 PASS (no merge-base heading deleted).
   Product docs match observed behavior claim-for-claim (each doc claim was
   cross-checked against a live probe in this review or the suite pins).
   Spec AC evidence rows cite real, present artifacts
   (docs/ai/tdd/red-…TEST-00{1,2,3,4,6,7}.log + green twins exist on disk).
   Ceremony 1 is appropriate: no new file, no protected path (L3 list
   checked — none in scope), additive-only, all ACs locally provable (D5
   held: zero planned/pending rows). Companion obligations vacuous and
   correctly recorded (no prompt bytes, no PROFILES/suite-map change owed).

## Commands run by this reviewer (all on HEAD e30bf61)

| Command | Result |
|---|---|
| bash tests/skills/test-aai-doctor.sh | exit 0, 38 PASS / 0 FAIL |
| bash tests/skills/test-aai-update.sh | exit 0, 24 PASS |
| bash tests/skills/test-aai-update-check.sh | exit 0 |
| bash tests/skills/test-aai-release.sh | exit 0 (TEST-024 PASS) |
| node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-DRAFT-spec-doctor-honesty-batch.md | exit 0, 0 findings |
| node .aai/scripts/check-test-registration.mjs | exit 0 |
| node .aai/scripts/aai-doctor.mjs --json (repo root) | exit 0; CAT-16 PASS, 3/3 present all versioned, exec true via real Commands: block |
| pwsh Invoke-Pester (aai-update + aai-win-dispatch) | 141 passed / 0 failed |
| ReDoS timing probe (adversarial megabyte help text) | linear, worst 34 ms |
| Parser edge probes P1–P8 through the real doctor | all match D1 contract |
| Timeout/orphan probe (sleeping fake gemini) | 5.7s return, UNKNOWN record, orphan self-terminated |

## Findings

### BLOCKING
None.

### NON-BLOCKING
- **NB-1** (tests/skills/test-aai-doctor.sh, battery in test_035): the D1
  rule "a blank line does NOT end the block" is unpinned by the committed
  battery — a blank-line-terminating parser would pass all 11 fixtures.
  Failure scenario: a future simplification of the inner loop to
  `if (line === '') break` ships green and false-negatives clap output that
  groups subcommands with blank lines. **Recommended disposition:
  remediate-in-tree** (one 12th fixture: `Commands:\n  run  x\n\n  exec  y\n`
  → true; ~6 lines) — or promote to a follow-up ref if the tree is frozen
  for PR.

### INFO (never gate)
- `resolveCliVersion` reason strings are mildly inconsistent: the timeout
  reason carries the CLI name (`${name} --version timed out`) while the
  no-stdout reason does not (`--version produced no stdout (exit …)`); a
  signal-killed child renders as `exit null`. Honest, just uneven.
- The timed-out probe orphans the hung CLI's grandchildren for their natural
  lifetime (spawnSync signals the direct child only). Bounded,
  self-terminating, consistent with RR-4; no action owed in this scope.

## Merge-gate statement

Both verdicts PASS; no BLOCKING finding. Per the H6 warnings policy the pass
is conditional on NB-1 receiving a disposition (remediate-in-tree
recommended, ~6-line fixture) recorded by the orchestrator. Independently of
this review, validation F-6 stands: the PR must be created with the
`ci-full` label already applied. With those two items handled, this scope is
merge-ready. Per the dispatch, this reviewer did not write STATE.yaml; the
orchestrator records the code_review block and the NB-1 disposition.
