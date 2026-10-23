# Code Review — ci-node-24-baseline

```yaml
review:
  scope: c6d86ed8..78f75635 (branch change/ci-node-24; f4cf6476 is a test-runs ledger line only)
  spec: docs/specs/SPEC-DRAFT-spec-ci-node-24-baseline.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".github/workflows/close-gate.yml:32; docs-numbering.yml:51,76; skill-suite.yml:122,162,256,304,352,389,408,518 (11 x '24'), skill-suite.yml:528 ('22'); ci-select.mjs:30; TEST-2301 test_138 PASS" }
      - { ac: Spec-AC-02, call: compliant, citation: "skill-suite.yml:504-540 (name/needs/if/runs-on/timeout unchanged; smoke -> setup-node 22 -> compat step); TEST-2302 test_139 PASS" }
      - { ac: Spec-AC-03, call: compliant, citation: "docs/TECHNOLOGY.md:30-34 Runtime(s), :235 Version Matrix row, Open Questions UNKNOWN removed; TEST-2303 test_140 PASS" }
      - { ac: Spec-AC-04, call: compliant, citation: ".aai/scripts/aai-doctor.mjs:637-638 constants; TEST-2304 test_141 PASS" }
      - { ac: Spec-AC-05, call: compliant, citation: "aai-doctor.mjs:640-649 catNodeRuntime, :1106 runDoctor; TEST-2305 PASS (v20.11.1, v21.7.3)" }
      - { ac: Spec-AC-06, call: compliant, citation: "TEST-2306 PASS, TEST-2307 PASS; --strict assertion is weakly discriminating, see NB-1" }
      - { ac: Spec-AC-07, call: compliant, citation: "docs/rfc/RFC-0017-...md:309; TEST-2308 test_142 PASS" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-doctor.sh, line: 2741,
          issue: "TEST-2306 '--strict exits 1 at v20.11.1' cannot attribute the exit to CAT-20: this repo already carries 5 WARN categories at v22 (CAT-04/07/08/13/18), so --strict exits 1 with or without CAT-20.",
          failure_scenario: "A change that excludes CAT-20 from the --strict count (e.g. filtering c.id !== 'CAT-20' in the strict branch of aai-doctor.mjs:1129) keeps TEST-2306 green. Mitigation already present: the issues == hi+1 assert (line 2736) pins CAT-20 into warnOrFailCount, the same variable --strict reads today." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-hygiene-pack.sh, line: 6070,
          issue: "test_139 / test_138 pin workflow text beyond the floor fact: exact top-level job count 9 (6070), setup-node@v4 two lines above the 22 pin (6088), timeout-minutes 10 (6079), and any 'Node 20' text anywhere under .aai/scripts (6054). Spec-mandated (Spec-AC-01/02), but brittle.",
          failure_scenario: "A Dependabot bump of actions/setup-node to @v5, adding a 10th job to skill-suite.yml, or a future script comment that legitimately mentions 'Node 20' fails the hygiene pack on an unrelated PR. The failure message names the cause, so the cost is a one-line test edit, not a silent mis-pass." }
  cannot_verify:
    - { claim: "Every Node step on hosted CI resolves 24.x and the compat setup-node resolves 22.x; all suites (incl. the Windows native-worktree-seed Pester job, which spawns node check-state.mjs / the seeder) pass on Node 24.",
        closes_with: "Hosted check H1: PR-head skill-suite + docs-numbering + close-gate runs green, setup-node log lines per job." }
    - { claim: "The compat step cost stays within budget (job <= 120 s, step <= 90 s, off the critical path).",
        closes_with: "Hosted check H2: gh run view <id> --json jobs step timestamps." }
    - { claim: "The process.version preload behaves identically on real Node 24 (verified locally on Node 22.23.1 and 26.12.0 only).",
        closes_with: "H1 doctor-suite run on Node 24 (TEST-2305..2307 green)." }
    - { claim: "Node 22 floor means 22.0+: CI exercises only the latest 22.x that setup-node resolves; an API added in a later 22 minor would pass CI yet break 22.0-22.x downstream while CAT-20 stays silent. A grep for known late-minor APIs found none (only cpSync, available since 16.7).",
        closes_with: "Either pin node-version '22.0' in the compat step or narrow the published floor wording to a minor; out of this spec's frozen scope." }
    - { claim: "Required status-check names are unchanged in branch protection.",
        closes_with: "Job name byte-equal is proved by test_139; actual branch-protection binding is only observable on the hosted PR." }
  overall: pass
```

## Scope and spec

- Scope: `git diff c6d86ed8..78f75635` in worktree `/private/tmp/aai-ci-node-24`
  (branch `change/ci-node-24`). `f4cf6476` only appends one line to
  `docs/ai/tests/test-runs.jsonl`.
- Spec: `docs/specs/SPEC-DRAFT-spec-ci-node-24-baseline.md` (frozen, ceremony 2).
- Dispatch note: the dispatch named two validation findings (NB-1, NB-6) and
  focus areas. Recorded per the anti-gaming contract; the full scope was
  reviewed and both were judged independently below.

## Verdict 1 — spec_compliance: PASS

AC walk (each TEST re-run by the reviewer in the worktree, single-function dispatch, all PASS):

| Spec-AC | Call | Evidence |
|---|---|---|
| Spec-AC-01 | compliant | 11 `'24'` pins, one `'22'` in self-hosting-smoke; ci-select.mjs:30 comment fixed; test_138 PASS |
| Spec-AC-02 | compliant | skill-suite.yml:504-540; identity lines unchanged; order smoke -> setup-node 22 -> compat; `set -euo pipefail` first; `case` version assertion (no pipe); test_139 PASS |
| Spec-AC-03 | compliant | TECHNOLOGY.md Runtime(s), Version Matrix row, Open Questions; test_140 PASS |
| Spec-AC-04 | compliant | NODE_FLOOR_MAJOR/NODE_BASELINE_MAJOR agree with TECHNOLOGY.md and pins; test_141 PASS |
| Spec-AC-05 | compliant | CAT-20 WARN line and JSON detail at v20.11.1 and v21.7.3; TEST-2305 PASS |
| Spec-AC-06 | compliant | FAIL count and plain exit equal at v20/v22, --strict exits 1, silent at v22/v24/vX/real; TEST-2306, TEST-2307 PASS |
| Spec-AC-07 | compliant | RFC-0017 row 309; test_142 PASS |

Also run: `check-test-registration.mjs tests/skills` exit 0;
`mutation-gate.mjs --spec <spec>` GATE PASS, 8 rows, degraded=0.

Deviations from the frozen spec: none found. D2 asked the header comment's
"category list" to gain CAT-20; the header has no enumerated list, and the
FAIL-capability note (aai-doctor.mjs:23-25) was updated, which is the only
list-like text. D5 delivery docs (product doc, CHANGELOG) are post-LOOP and
not in this range, as the spec intends. `docs/ai/roadmap.yaml` (+capability
`ci-node-24-baseline: active`) is ceremony, outside the AC set.

## Verdict 2 — code_quality: PASS

Focus areas checked:

- **setup-node 22 placement.** It is after `Run self-hosting smoke test`, so
  every earlier step (identity check, primary smoke) runs on Node 24. The
  compat step is the last step of the job, so nothing runs on 22 afterward.
  The smoke script is hermetic (`mktemp -d`, `trap rm -rf`), so the second
  run on 22 is not affected by the first run's leftovers.
- **Required check name.** Job `name:` unchanged byte for byte (pinned by
  test_139); gate `needs` list unchanged.
- **Compat run block.** `set -euo pipefail`; `find -print0 | xargs -0 -n1
  node --check` fails the step on any syntax error (xargs 123); doctor exit
  captured with `|| doctor_rc=$?` so errexit does not fire, 0|1 accepted, 2
  (missing root, aai-doctor.mjs:1115) fails; JSON check via `node -e`.
- **Windows native-worktree-seed.** Only the pin changes. Its Pester tests
  spawn `node` directly; no `shell: true` / DEP0190 exposure under
  `.aai/scripts`, and the .cmd-spawn restriction predates Node 24.
- **CAT-20 parsing.** `/^v(\d+)\./` handles `v24.0.0-nightly...` (24 ->
  silent), `v20` without a dot (null -> silent), an undefined
  `process.version` (`String(undefined)` -> null). It reads
  `process.version` only, so missing `process.versions` is irrelevant. The
  default parameter is evaluated at call time, so the preload is seen.
  Never FAIL; `filter(Boolean)` drops null. Correct.
- **Node 22 compatibility of shipped code.** Grep for Node 23/24-only and
  late-22-minor APIs (RegExp.escape, Promise.try, Error.isError,
  Float16Array, registerHooks, getBuiltinModule, node:sqlite, URL.parse,
  fs.glob, partialDeepStrictEqual, mock.module, Object.groupBy, Set
  methods, explicit resource management) found nothing; only `cpSync`
  (16.7+). Validation ran the compat block under 22.23.1.

### NB-1 (NON-BLOCKING, P3) — TEST-2306 --strict assert is non-discriminating

tests/skills/test-aai-doctor.sh:2741. Confirmed independently: the doctor on
this repo at Node 22 reports 5 WARN categories, so `--strict` exits 1
regardless of CAT-20. A mutant that special-cases CAT-20 out of the strict
count survives. The adjacent `issues == hi + 1` assert (line 2736) does pin
CAT-20 into `warnOrFailCount`, which is the exact variable --strict uses
(aai-doctor.mjs:1120, 1129), so only a deliberate CAT-20 carve-out escapes.
Spec-AC-06 wording ("--strict SHALL exit 1") is literally met.

Disposition: (d) accepted residual: P3 assurance-strength gap in a test
assertion, no observed bite, no false record; the issue-count assert already
binds CAT-20 to the --strict counter.

### NB-2 (NON-BLOCKING, P3) — hygiene guards over-pin workflow text

tests/skills/test-aai-hygiene-pack.sh:6070 (job count 9), :6079
(timeout-minutes 10), :6088 (`setup-node@v4` exactly two lines above the 22
pin), :6054 (any `Node 20` text under `.aai/scripts`). All are spec-mandated
(Spec-AC-01/02 and the TEST-2302 description), so not a compliance defect,
but a Dependabot `setup-node@v5` bump, a new skill-suite job, or a script
comment legitimately mentioning Node 20 turns the hygiene pack red on an
unrelated PR. The failure messages name the cause precisely.

Disposition: (d) accepted residual: P3 maintenance cost, intentional
tripwires per the frozen spec, loud and self-explaining on trip, no false record.

### INFO (not gating)

- RFC-0017 row 309 labelled `order 4` sits in a Phase-numbered table where
  phase 4 is "not started" (validation NB-6). The label is mandated
  verbatim by spec D4 and the docs-audit Rollout Status reader
  (docs-audit-core.mjs:1662-1700) consumes only the status column, so no tool
  misreads it; a human reader may conflate it with phase 4. A later RFC edit
  could say "decision 1.4 step 4". No failure mode, INFO only.
- TEST-2306/2307 (test-aai-doctor.sh:2742, 2757) gate their PASS line on the
  suite-global `FAILED`, so an earlier failing test in the same run hides
  these PASS lines. Cosmetic; failures still print.

## cannot_verify

See the YAML block above: hosted H1 (Node 24 everywhere incl. Windows,
22 in compat), H2 (cost), preload on real Node 24, 22.0-vs-latest-22.x minor
coverage, and branch-protection binding of the unchanged job name.

## Warning dispositions (H6)

- NB-1: accepted residual: "P3 assurance-strength gap; issues == hi+1 already binds CAT-20 to the --strict counter."
- NB-2: accepted residual: "P3 maintenance cost; spec-mandated tripwires that fail loudly with a self-naming message."

## Next steps

Proceed to PR; run H1/H2 on the PR head before merge-readiness; D5 product
doc and CHANGELOG after LOOP COMPLETE.
